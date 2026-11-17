"""Проверенные версии (BOT.md §2.12): владелец закрепляет в боте ссылку на сборку для платформы и решает,
кому она видна — всем, только списку аккаунтов или всем, кроме списка. Пользователь в «Скачать» видит
самую новую закреплённую версию, доступную ему; нет такой — общую ссылку из настроек (Windows —
releases/latest, iPhone — ios-latest/Sonar.ipa). Алерт — сообщение ботом каждому, кому версия видна.

Аккаунт в списке записывается как `@username`, логин, `#номер` или Telegram id (число от 5 цифр).
"""
from __future__ import annotations

import json
import re
import sqlite3
from dataclasses import dataclass, field

from .accounts import User
from .db import now_ms

PLATFORMS = {"windows": "Windows", "ios": "iPhone"}
AUDIENCES = {"all": "Всем", "only": "Только списку", "except": "Всем, кроме списка"}

SCHEMA = """
CREATE TABLE IF NOT EXISTS releases (
  id          INTEGER PRIMARY KEY,
  platform    TEXT NOT NULL,
  version     TEXT NOT NULL,
  url         TEXT NOT NULL,
  notes       TEXT NOT NULL DEFAULT '',
  audience    TEXT NOT NULL DEFAULT 'all',
  targets     TEXT NOT NULL DEFAULT '[]',
  active      INTEGER NOT NULL DEFAULT 1,
  created_at  INTEGER NOT NULL,
  alerted_at  INTEGER
);
CREATE INDEX IF NOT EXISTS releases_platform ON releases(platform, created_at);
"""

URL_RE = re.compile(r"^https://[^\s/]+\.[^\s/]+/\S*$")
TAG_RE = re.compile(r"/releases/(?:download|tag)/([^/?#]+)")


class ReleaseError(Exception):
    def __init__(self, text: str):
        super().__init__(text)
        self.text = text


@dataclass
class Release:
    id: int
    platform: str
    version: str
    url: str
    notes: str
    audience: str
    targets: list[str] = field(default_factory=list)
    active: bool = True
    created_at: int = 0
    alerted_at: int | None = None

    @classmethod
    def of(cls, r: sqlite3.Row | None) -> "Release | None":
        if r is None:
            return None
        return cls(r["id"], r["platform"], r["version"], r["url"], r["notes"], r["audience"], json.loads(r["targets"] or "[]"),
                   bool(r["active"]), r["created_at"], r["alerted_at"])

    @property
    def platform_name(self) -> str:
        return PLATFORMS.get(self.platform, self.platform)


def check_url(text: str) -> str:
    url = text.strip()
    if not URL_RE.match(url):
        raise ReleaseError("Нужна ссылка https://… на сборку или страницу релиза")
    return url


def version_from_url(url: str) -> str | None:
    """`…/releases/download/windows-v0.1.42/Sonar-setup.exe` → `windows-v0.1.42`."""
    m = TAG_RE.search(url)
    return m.group(1) if m and m.group(1) not in ("latest", "ios-latest") else None


def parse_targets(text: str) -> list[str]:
    """Список аккаунтов из сообщения: через пробел, запятую или с новой строки. Ключи нормализованы:
    `u:<username>`, `n:<номер>`, `tg:<id>`, `l:<логин>` (без регистра)."""
    out: list[str] = []
    for raw in re.split(r"[\s,;]+", text.strip()):
        t = raw.strip()
        if not t:
            continue
        if t.startswith("@") and len(t) > 1:
            key = f"u:{t[1:].lower()}"
        elif t.startswith("#") and t[1:].isdigit():
            key = f"n:{int(t[1:])}"
        elif t.isdigit() and len(t) >= 5:
            key = f"tg:{int(t)}"
        else:
            key = f"l:{t.lower()}"
        if key not in out:
            out.append(key)
    return out


def target_label(key: str) -> str:
    kind, _, value = key.partition(":")
    return {"u": f"@{value}", "n": f"#{value}", "tg": f"tg {value}"}.get(kind, value)


def user_keys(user: User) -> set[str]:
    keys = {f"u:{user.username.lower()}", f"n:{user.number}", f"l:{user.login.lower()}"}
    if user.tg_id:
        keys.add(f"tg:{user.tg_id}")
    return keys


def visible_to(rel: Release, user: User | None) -> bool:
    if not rel.active:
        return False
    if rel.audience == "all":
        return True
    hit = user is not None and bool(user_keys(user) & set(rel.targets))
    return hit if rel.audience == "only" else not hit


class Releases:
    def __init__(self, con: sqlite3.Connection):
        self.con = con
        con.executescript(SCHEMA)

    def add(self, platform: str, version: str, url: str, notes: str = "", audience: str = "all",
            targets: list[str] | None = None) -> Release:
        if platform not in PLATFORMS:
            raise ReleaseError("Неизвестная платформа")
        if audience not in AUDIENCES:
            raise ReleaseError("Неизвестная аудитория")
        if audience != "all" and not targets:
            raise ReleaseError("Список аккаунтов пуст")
        url = check_url(url)
        version = version.strip() or version_from_url(url) or "без номера"
        cur = self.con.execute(
            "INSERT INTO releases (platform, version, url, notes, audience, targets, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (platform, version[:60], url, notes.strip()[:1500], audience, json.dumps(targets or []), now_ms()),
        )
        return self.get(cur.lastrowid)

    def get(self, rid: int) -> Release | None:
        return Release.of(self.con.execute("SELECT * FROM releases WHERE id = ?", (rid,)).fetchone())

    def history(self, platform: str, limit: int = 6) -> list[Release]:
        rows = self.con.execute("SELECT * FROM releases WHERE platform = ? ORDER BY created_at DESC, id DESC LIMIT ?",
                                (platform, limit)).fetchall()
        return [Release.of(r) for r in rows]

    def current(self, platform: str, user: User | None) -> Release | None:
        """Самая новая закреплённая версия платформы, которую этому пользователю можно видеть."""
        for r in self.con.execute("SELECT * FROM releases WHERE platform = ? AND active = 1 ORDER BY created_at DESC, id DESC",
                                  (platform,)):
            rel = Release.of(r)
            if visible_to(rel, user):
                return rel
        return None

    def set_active(self, rid: int, active: bool) -> Release | None:
        self.con.execute("UPDATE releases SET active = ? WHERE id = ?", (int(active), rid))
        return self.get(rid)

    def mark_alerted(self, rid: int) -> None:
        self.con.execute("UPDATE releases SET alerted_at = ? WHERE id = ?", (now_ms(), rid))

    def recipients(self, rel: Release) -> list[User]:
        """Кому слать алерт: у кого привязан Telegram, кто не забанен и кому версия видна."""
        rows = self.con.execute("SELECT * FROM users WHERE tg_id IS NOT NULL AND banned = 0 ORDER BY number").fetchall()
        return [u for u in (User.of(r) for r in rows) if u and visible_to(rel, u)]
