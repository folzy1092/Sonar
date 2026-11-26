"""Сборки, выпущенные из админки (SERVER_PROMPT этап 7, ADMIN.md «Сборки»).

CI собирает релизы `windows-v*` и `ios-build-*` на GitHub; владелец в админке выбирает сборку, канал и описание,
и сервер сам скачивает её файлы в `data/builds/<канал>/<платформа>/<тег>/` — так не упираемся в лимит загрузки у
прокси хостера. Клиенты потом берут обновления и файлы у нас (`api/updates.py`), GitHub — запасной путь.

Безопасность: тег проверяется регуляркой, имя файла на диске — своё (`FILES`), качаем только с хостов GitHub и
токен шлём только самому GitHub, а не на CDN, куда он перенаправляет.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import secrets
import shutil
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urljoin, urlsplit

import aiohttp

from .db import now_ms, tx

REPO = "folzy1092/Sonar"
API = f"https://api.github.com/repos/{REPO}"
CHANNELS = ("release", "beta")
FILES = {"windows": "Sonar-setup.exe", "ios": "Sonar.ipa"}
# Пока ничего не выпущено из админки — постоянные адреса последней сборки на GitHub.
FALLBACK = {"windows": f"https://github.com/{REPO}/releases/latest/download/Sonar-setup.exe",
            "ios": f"https://github.com/{REPO}/releases/download/ios-latest/Sonar.ipa"}
TAG_RE = re.compile(r"^(?:windows-v\d+\.\d+\.\d+[0-9A-Za-z.+-]{0,32}|ios-build-\d{1,9})$")
IOS_TITLE = re.compile(r"^Sonar (\S{1,32}) \((\d{1,9})\)")
KEEP = 3  # сборок на (платформу, канал); старше — удаляются с диском
MAX_BYTES = 200 * 1024 * 1024
SIG_MAX_BYTES = 64 * 1024
LANGS = ("ru", "en", "uk", "es", "de", "pl")
REQUIRED_LANGS = ("ru", "en")
NOTES_MAX = 4000
MAX_REDIRECTS = 5
TIMEOUT_S = 300
# GitHub отдаёт файлы релизов через свои CDN; release-assets — новый адрес вместо objects (с 2025 года).
DOWNLOAD_HOSTS = {"github.com", "api.github.com", "objects.githubusercontent.com",
                  "release-assets.githubusercontent.com", "raw.githubusercontent.com"}
TOKEN_HOSTS = {"github.com", "api.github.com", "raw.githubusercontent.com"}
FEED_MAX_BYTES = 256 * 1024     # latest.json и ios-update.json — десятки строк, больше — это не они
# Бета-канал — сборки CI прямо с GitHub (только для владельца, `api/updates.py`): последний релиз Windows и объявление iOS.
BETA_FEEDS = {"windows": f"https://github.com/{REPO}/releases/download/windows-latest/latest.json",
              "ios": f"https://raw.githubusercontent.com/{REPO}/main/updates/ios-update.json"}


class BuildError(Exception):
    """`code` — ключ сообщения в админке (`admin/web.py` MESSAGES)."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


@dataclass(frozen=True)
class Build:
    id: int
    platform: str
    channel: str
    tag: str
    version: str
    build: int | None
    notes: dict
    signature: str | None
    file: str
    size: int
    sha256: str
    published_at: int
    published_by: str
    revoked: bool

    def notes_for(self, lang: str) -> str:
        """Описание на языке клиента; нет такого — английское, потом русское."""
        lang = (lang or "").lower()[:2]
        return self.notes.get(lang) or self.notes.get("en") or self.notes.get("ru", "")


@dataclass(frozen=True)
class Plan:
    """Что качать из релиза GitHub: файл сборки, подпись (только Windows), версия."""
    platform: str
    version: str
    build: int | None
    url: str
    size: int
    sig_url: str | None


def channel_of(name: str | None) -> str | None:
    """`stable` — прежнее имя релизного канала в настройках клиентов (`update.channel`)."""
    name = (name or "").strip().lower()
    if name == "stable":
        return "release"
    return name if name in CHANNELS else None


def platform_of(tag: str) -> str:
    if not TAG_RE.match(tag or ""):
        raise BuildError("bad_tag")
    return "windows" if tag.startswith("windows-") else "ios"


def allowed(url: str) -> bool:
    parts = urlsplit(url)
    return parts.scheme == "https" and parts.hostname in DOWNLOAD_HOSTS


def clean_notes(raw: dict[str, str]) -> dict[str, str]:
    notes = {lang: (raw.get(lang) or "").strip() for lang in LANGS}
    if any(not notes[lang] for lang in REQUIRED_LANGS):
        raise BuildError("no_notes")
    if any(len(text) > NOTES_MAX for text in notes.values()):
        raise BuildError("too_long")
    return {lang: text for lang, text in notes.items() if text}


def plan(release: dict) -> Plan:
    """Разбор релиза GitHub. Ассет берём по его API-адресу: так работает и с приватным репо (с токеном)."""
    tag = release.get("tag_name", "")
    platform = platform_of(tag)
    assets = {a.get("name"): a for a in release.get("assets") or [] if isinstance(a, dict)}
    if platform == "windows":
        sig = next((a for name, a in assets.items() if name and name.endswith("-setup.exe.sig")), None)
        exe = assets.get(sig["name"].removesuffix(".sig")) if sig else None
        if not sig or not exe:
            raise BuildError("no_assets")  # без подписи tauri-plugin-updater обновление не поставит
        return Plan("windows", tag.removeprefix("windows-v"), None, exe["url"], int(exe.get("size") or 0), sig["url"])
    ipa = assets.get(FILES["ios"])
    title = IOS_TITLE.match(release.get("name") or "")
    if not ipa:
        raise BuildError("no_assets")
    if not title:
        raise BuildError("no_version")
    return Plan("ios", title.group(1), int(tag.removeprefix("ios-build-")), ipa["url"], int(ipa.get("size") or 0), None)


class GitHub:
    """Релизы репо Sonar. Токен необязателен (репо публичное), нужен для приватного репо и лимита 5000/ч."""

    def __init__(self, token: str | None = None):
        self.token = (token or "").strip() or None

    def _headers(self, url: str, accept: str = "application/vnd.github+json") -> dict[str, str]:
        headers = {"Accept": accept, "User-Agent": "sonar-server", "X-GitHub-Api-Version": "2022-11-28"}
        if self.token and urlsplit(url).hostname in TOKEN_HOSTS:
            headers["Authorization"] = f"Bearer {self.token}"
        return headers

    def _session(self) -> aiohttp.ClientSession:
        return aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=TIMEOUT_S))

    async def _json(self, url: str):
        try:
            async with self._session() as s, s.get(url, headers=self._headers(url)) as r:
                if r.status == 404:
                    raise BuildError("no_release")
                if r.status != 200:
                    raise BuildError("github")
                return await r.json()
        except (aiohttp.ClientError, TimeoutError) as err:
            raise BuildError("github") from err

    async def json_file(self, url: str, limit: int = FEED_MAX_BYTES):
        """Маленький JSON с GitHub (latest.json Windows, ios-update.json). Редиректы — вручную: каждый адрес проходит
        проверку хоста, токен уходит только самому GitHub. Не вышло — BuildError."""
        try:
            async with self._session() as s:
                for _ in range(MAX_REDIRECTS + 1):
                    if not allowed(url):
                        raise BuildError("bad_host")
                    async with s.get(url, headers=self._headers(url, "application/json"), allow_redirects=False) as r:
                        if r.status in (301, 302, 303, 307, 308):
                            url = urljoin(url, r.headers.get("Location", ""))
                            continue
                        if r.status != 200:
                            raise BuildError("github")
                        raw = await r.content.read(limit + 1)
                        if len(raw) > limit:
                            raise BuildError("too_big")
                        return json.loads(raw)
                raise BuildError("github")
        except (aiohttp.ClientError, TimeoutError, ValueError) as err:
            raise BuildError("github") from err

    async def releases(self) -> list[dict]:
        data = await self._json(f"{API}/releases?per_page=30")
        return [r for r in data if isinstance(r, dict) and not r.get("draft") and TAG_RE.match(r.get("tag_name", ""))]

    async def release(self, tag: str) -> dict:
        platform_of(tag)
        return await self._json(f"{API}/releases/tags/{tag}")

    async def download(self, url: str, dest: Path, limit: int = MAX_BYTES) -> tuple[int, str]:
        """Качает в `dest` через временный файл рядом; возвращает (размер, sha256). Редиректы — вручную,
        чтобы каждый адрес прошёл проверку хоста и токен не ушёл на CDN."""
        part = dest.with_name(f".{dest.name}.{secrets.token_hex(4)}.part")
        try:
            async with self._session() as s:
                for _ in range(MAX_REDIRECTS + 1):
                    if not allowed(url):
                        raise BuildError("bad_host")
                    headers = self._headers(url, "application/octet-stream")
                    async with s.get(url, headers=headers, allow_redirects=False) as r:
                        if r.status in (301, 302, 303, 307, 308):
                            url = urljoin(url, r.headers.get("Location", ""))
                            continue
                        if r.status != 200:
                            raise BuildError("github")
                        size, digest = 0, hashlib.sha256()
                        with part.open("wb") as f:
                            async for chunk in r.content.iter_chunked(64 * 1024):
                                size += len(chunk)
                                if size > limit:
                                    raise BuildError("too_big")
                                digest.update(chunk)
                                f.write(chunk)
                    os.replace(part, dest)
                    return size, digest.hexdigest()
                raise BuildError("github")
        except (aiohttp.ClientError, TimeoutError) as err:
            raise BuildError("github") from err
        finally:
            part.unlink(missing_ok=True)


# ---- база и диск ----

def root(data_dir: Path) -> Path:
    return data_dir / "builds"


def build_dir(data_dir: Path, channel: str, platform: str, tag: str) -> Path:
    base = root(data_dir).resolve()
    if channel not in CHANNELS or platform not in FILES or not TAG_RE.match(tag):
        raise BuildError("bad_tag")
    d = (base / channel / platform / tag).resolve()
    if base not in d.parents:
        raise BuildError("bad_tag")
    return d


def file_path(data_dir: Path, b: Build) -> Path:
    return build_dir(data_dir, b.channel, b.platform, b.tag) / FILES[b.platform]


def _row(r: sqlite3.Row | tuple) -> Build:
    (id_, platform, channel, tag, version, build, notes_json, signature, file, size, sha256, published_at,
     published_by, revoked) = r
    return Build(id_, platform, channel, tag, version, build, json.loads(notes_json), signature, file, size, sha256,
                 published_at, published_by, bool(revoked))


COLUMNS = ("id, platform, channel, tag, version, build, notes_json, signature, file, size, sha256, published_at, "
           "published_by, revoked")


def listing(con: sqlite3.Connection) -> list[Build]:
    rows = con.execute(f"SELECT {COLUMNS} FROM builds ORDER BY published_at DESC, id DESC").fetchall()
    return [_row(r) for r in rows]


def get(con: sqlite3.Connection, build_id: int) -> Build | None:
    r = con.execute(f"SELECT {COLUMNS} FROM builds WHERE id = ?", (build_id,)).fetchone()
    return _row(r) if r else None


def _latest(con: sqlite3.Connection, platform: str, channel: str) -> Build | None:
    r = con.execute(f"SELECT {COLUMNS} FROM builds WHERE platform = ? AND channel = ? AND revoked = 0 "
                    "ORDER BY published_at DESC, id DESC LIMIT 1", (platform, channel)).fetchone()
    return _row(r) if r else None


def _version_key(b: Build) -> tuple[int, ...]:
    """iPhone сравниваем по номеру сборки, Windows — по числам версии (`0.3.12` → (0, 3, 12))."""
    if b.build is not None:
        return (b.build,)
    return tuple(int(n) for n in re.findall(r"\d+", b.version)[:3])


def current(con: sqlite3.Connection, platform: str, channel: str) -> Build | None:
    """Текущая сборка канала. Бета видит и релизы: берём ту, у которой версия выше, — хотфикс релиза
    не перебивает более новую бету."""
    release = _latest(con, platform, "release")
    if channel != "beta":
        return release
    beta = _latest(con, platform, "beta")
    if release is None or beta is None:
        return beta or release
    return release if _version_key(release) > _version_key(beta) else beta


def pinned(con: sqlite3.Connection, platform: str, channel: str, tag: str, any_state: bool = False) -> Build | None:
    revoked = "" if any_state else " AND revoked = 0"
    r = con.execute(f"SELECT {COLUMNS} FROM builds WHERE platform = ? AND channel = ? AND tag = ?{revoked}",
                    (platform, channel, tag)).fetchone()
    return _row(r) if r else None


def prune(con: sqlite3.Connection, data_dir: Path, platform: str, channel: str, keep: int = KEEP) -> list[str]:
    old = con.execute("SELECT id, tag FROM builds WHERE platform = ? AND channel = ? "
                      "ORDER BY published_at DESC, id DESC LIMIT -1 OFFSET ?", (platform, channel, keep)).fetchall()
    with tx(con):
        con.executemany("DELETE FROM builds WHERE id = ?", [(id_,) for id_, _ in old])
    for _, tag in old:
        shutil.rmtree(build_dir(data_dir, channel, platform, tag), ignore_errors=True)
    return [tag for _, tag in old]


async def publish(con: sqlite3.Connection, data_dir: Path, gh: GitHub, tag: str, channel: str,
                  notes: dict[str, str], admin: str) -> Build:
    """Скачать сборку `tag` с GitHub и выпустить в канал. Повторный выпуск того же тега обновляет описание,
    перекачивает файлы и снимает отзыв; дата выпуска не меняется — старая сборка не становится «текущей»."""
    chan = channel_of(channel)
    if chan is None:
        raise BuildError("bad_channel")
    platform_of(tag)
    clean = clean_notes(notes)
    p = plan(await gh.release(tag))
    d = build_dir(data_dir, chan, p.platform, tag)
    fresh = pinned(con, p.platform, chan, tag, any_state=True) is None
    d.mkdir(parents=True, exist_ok=True)
    name = FILES[p.platform]
    try:
        size, sha256 = await gh.download(p.url, d / name)
        if p.size and size != p.size:
            raise BuildError("github")
        signature = None
        if p.sig_url:
            await gh.download(p.sig_url, d / f"{name}.sig", limit=SIG_MAX_BYTES)
            signature = (d / f"{name}.sig").read_text("utf-8").strip() or None
            if not signature:
                raise BuildError("no_assets")
    except BuildError:
        if fresh:  # строки в базе нет — prune эту папку никогда не найдёт
            shutil.rmtree(d, ignore_errors=True)
        raise
    rel = f"{chan}/{p.platform}/{tag}/{name}"
    with tx(con):
        con.execute(
            "INSERT INTO builds (platform, channel, tag, version, build, notes_json, signature, file, size, sha256, "
            "published_at, published_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
            "ON CONFLICT (platform, channel, tag) DO UPDATE SET version = excluded.version, build = excluded.build, "
            "notes_json = excluded.notes_json, signature = excluded.signature, file = excluded.file, "
            "size = excluded.size, sha256 = excluded.sha256, published_by = excluded.published_by, revoked = 0",
            (p.platform, chan, tag, p.version, p.build, json.dumps(clean, ensure_ascii=False), signature, rel, size,
             sha256, now_ms(), admin))
    prune(con, data_dir, p.platform, chan)
    b = pinned(con, p.platform, chan, tag)
    assert b is not None
    return b


def set_revoked(con: sqlite3.Connection, build_id: int, revoked: bool) -> Build:
    """Отозвать (клиенты перестают её видеть, файлы остаются) или вернуть."""
    with tx(con):
        cur = con.execute("UPDATE builds SET revoked = ? WHERE id = ?", (int(revoked), build_id))
    if cur.rowcount == 0:
        raise BuildError("no_build")
    b = get(con, build_id)
    assert b is not None
    return b
