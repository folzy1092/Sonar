"""Обновления и файлы сборок с сервера (API.md §8, SERVER_PROMPT этап 7).

- `GET /api/updates/windows/<канал>.json` — формат `tauri-plugin-updater`. Канал из пути, а заголовок
  `X-Sonar-Channel` его перекрывает: адрес в `tauri.conf.json` один, канал выбирают в настройках.
- **Релиз** — только то, что владелец выпустил в админке («Сборки»), и только с нашего сайта. **Бета** — сборки CI прямо с
  GitHub (`latest.json` Windows, `ios-update.json`), и только логинам из `SONAR_BETA_USERS` (по умолчанию `folzy`) по
  `Authorization: Bearer`; всем остальным запрос беты отвечает как релиз.
- `GET /api/updates/ios/<канал>.json` — формат прежнего `updates/ios-update.json`.
- `GET /api/updates/manifest.plist` — манифест `itms-services` с теми же параметрами, что у `api.palera.in/genPlist`.
- `/downloads/<канал>/<файл>` — текущая сборка, `/downloads/<канал>/<тег>/<файл>` — конкретная (её адрес
  уходит в манифесты обновлений: подпись и файл всегда от одной сборки). Range и ETag — у `FileResponse`.

Нет сборки — JSON отвечает 404 (а не 204: на 404 tauri идёт к запасному адресу на GitHub), файлы — 302 на GitHub.
"""
from __future__ import annotations

import logging
import os
import re
import time
from datetime import UTC, datetime
from urllib.parse import urlsplit
from xml.sax.saxutils import escape

from fastapi import APIRouter, Request
from fastapi.responses import FileResponse, JSONResponse, RedirectResponse, Response

from .. import builds, sessions
from ..builds import FILES, Build, BuildError
from .deps import bearer
from .errors import ApiError

log = logging.getLogger("sonar.updates")

router = APIRouter(prefix="/updates", tags=["updates"])
downloads = APIRouter(prefix="/downloads", include_in_schema=False)

NO_CACHE = {"Cache-Control": "no-cache"}
PLATFORM_BY_FILE = {name: platform for platform, name in FILES.items()}
BUNDLE_RE = re.compile(r"^[A-Za-z0-9.-]{1,100}$")
NAME_MAX = 64
VERSION_RE = re.compile(r"^[0-9A-Za-z.+-]{1,32}$")


BETA_CACHE_S = 300      # сборка CI на GitHub выходит на каждый пуш; раз в 5 минут для одного владельца достаточно


def beta_users() -> set[str]:
    """Логины, которым доступна бета (`SONAR_BETA_USERS`, через запятую; по умолчанию — владелец `folzy`)."""
    raw = os.environ.get("SONAR_BETA_USERS", "folzy")
    return {x.strip().lower() for x in raw.split(",") if x.strip()}


def _beta_ok(request: Request) -> bool:
    """Запрос с сессией (`Authorization: Bearer`) пользователя из списка беты. Забаненный и чужой — нет."""
    token = bearer(request)
    st = request.app.state
    s = sessions.by_token(st.con, token) if token else None
    user = st.accounts.by_id(s.user_id) if s else None
    return user is not None and user.login.lower() in beta_users()


def _channel(request: Request, path_channel: str) -> str:
    """Канал из заголовка или пути. Бета — только своим: остальным (в том числе старым клиентам с включённым «Бета»)
    отвечаем как на релиз, а не 404 — они продолжают получать обычные обновления."""
    chan = builds.channel_of(request.headers.get("x-sonar-channel")) or builds.channel_of(path_channel)
    if chan is None:
        raise ApiError(404, "not_found", "Нет такого канала")
    return "release" if chan == "beta" and not _beta_ok(request) else chan


def _feed_ok(platform: str, data) -> bool:
    if not isinstance(data, dict):
        return False
    if platform == "windows":
        win = (data.get("platforms") or {}).get("windows-x86_64")
        return isinstance(data.get("version"), str) and isinstance(win, dict) and bool(win.get("url")) and bool(win.get("signature"))
    return isinstance(data.get("build"), int) and isinstance(data.get("ipa_url"), str)


async def _github_feed(request: Request, platform: str) -> dict | None:
    """Бета с GitHub: `latest.json` Windows и `ios-update.json` как есть (CI публикует их сам), кэш на 5 минут.
    GitHub не ответил или ответ не тот — None (дальше пробуем сборки из админки)."""
    st = request.app.state
    cache = getattr(st, "beta_cache", None)
    if cache is None:
        cache = st.beta_cache = {}
    hit = cache.get(platform)
    if hit and time.monotonic() - hit[0] < BETA_CACHE_S:
        return hit[1]
    try:
        data = await st.github.json_file(builds.BETA_FEEDS[platform])
    except BuildError as err:
        log.warning("бета %s: GitHub не отдал %s", platform, err.code)
        return hit[1] if hit else None            # старый ответ лучше, чем «обновлений нет»
    if not _feed_ok(platform, data):
        log.warning("бета %s: на GitHub не тот формат", platform)
        return hit[1] if hit else None
    cache[platform] = (time.monotonic(), data)
    return data


def _lang(request: Request) -> str:
    return request.query_params.get("lang") or request.headers.get("x-sonar-lang") or ""


def _current(request: Request, platform: str, chan: str) -> Build:
    b = builds.current(request.app.state.con, platform, chan)
    if b is None:
        raise ApiError(404, "not_found", "Сборок в этом канале пока нет")
    return b


def file_url(request: Request, b: Build) -> str:
    return f"{request.app.state.settings.site_url}/downloads/{b.channel}/{b.tag}/{FILES[b.platform]}"


def _iso(ms: int) -> str:
    return datetime.fromtimestamp(ms / 1000, UTC).isoformat(timespec="seconds").replace("+00:00", "Z")


@router.get("/windows/{channel}.json")
async def windows_update(request: Request, channel: str):
    chan = _channel(request, channel)
    if chan == "beta" and (feed := await _github_feed(request, "windows")):
        return JSONResponse(feed, headers=NO_CACHE)
    b = _current(request, "windows", chan)
    body = {"version": b.version, "notes": b.notes_for(_lang(request)), "pub_date": _iso(b.published_at),
            "platforms": {"windows-x86_64": {"signature": b.signature, "url": file_url(request, b)}}}
    return JSONResponse(body, headers=NO_CACHE)


@router.get("/ios/{channel}.json")
async def ios_update(request: Request, channel: str):
    chan = _channel(request, channel)
    if chan == "beta" and (feed := await _github_feed(request, "ios")):
        return JSONResponse(feed, headers=NO_CACHE)
    b = _current(request, "ios", chan)
    site = request.app.state.settings.site_url
    body = {"enabled": True, "build": b.build, "version": b.version, "minimum_build": 0,
            "title": f"Sonar {b.version}", "notes": b.notes_for(_lang(request)), "ipa_url": file_url(request, b),
            "url": f"{site}/#download"}
    return JSONResponse(body, headers=NO_CACHE)


def _manifest_ipa_ok(request: Request, url: str) -> bool:
    """Ставим только своё: ipa с локального сервера приложения (установка после переподписи) или наш /downloads."""
    parts = urlsplit(url)
    if parts.scheme == "http" and parts.hostname == "127.0.0.1" and parts.port:
        return True
    site = urlsplit(request.app.state.settings.site_url)
    return (parts.scheme == "https" and parts.netloc == site.netloc and parts.path.startswith("/downloads/")
            and not parts.query and ".." not in parts.path)


@router.get("/manifest.plist")
async def manifest(request: Request, fetchurl: str = "", bundleid: str = "com.folzy.sonar", name: str = "Sonar",
                   version: str = "0"):
    if not _manifest_ipa_ok(request, fetchurl):
        raise ApiError(400, "bad_request", "fetchurl: только 127.0.0.1 или /downloads этого сервера")
    if not BUNDLE_RE.match(bundleid) or not VERSION_RE.match(version) or not 0 < len(name) <= NAME_MAX:
        raise ApiError(400, "bad_request", "Неверные bundleid, version или name")
    e = lambda v: escape(v, {'"': "&quot;"})  # noqa: E731
    body = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>items</key><array><dict>
<key>assets</key><array><dict><key>kind</key><string>software-package</string><key>url</key><string>{e(fetchurl)}</string></dict></array>
<key>metadata</key><dict><key>bundle-identifier</key><string>{e(bundleid)}</string><key>bundle-version</key><string>{e(version)}</string><key>kind</key><string>software</string><key>title</key><string>{e(name)}</string></dict>
</dict></array></dict></plist>
"""
    return Response(body, media_type="application/xml", headers={"Cache-Control": "no-store"})


# ---- файлы ----

def _send(request: Request, b: Build) -> Response:
    path = builds.file_path(request.app.state.settings.data_dir, b)
    if not path.is_file():
        return Response(status_code=404)
    return FileResponse(path, media_type="application/octet-stream", filename=FILES[b.platform],
                        headers={"Cache-Control": "no-cache"})


def _platform(name: str) -> str:
    platform = PLATFORM_BY_FILE.get(name)
    if platform is None:
        raise ApiError(404, "not_found", "Нет такого файла")
    return platform


@downloads.api_route("/{channel}/{name}", methods=["GET", "HEAD"])
async def download_current(request: Request, channel: str, name: str):
    platform, chan = _platform(name), builds.channel_of(channel)
    if chan is None:
        return Response(status_code=404)
    b = builds.current(request.app.state.con, platform, chan)
    if b is None:
        return RedirectResponse(builds.FALLBACK[platform], status_code=302, headers=NO_CACHE)
    return _send(request, b)


@downloads.api_route("/{channel}/{tag}/{name}", methods=["GET", "HEAD"])
async def download_pinned(request: Request, channel: str, tag: str, name: str):
    platform, chan = _platform(name), builds.channel_of(channel)
    b = builds.pinned(request.app.state.con, platform, chan, tag) if chan and builds.TAG_RE.match(tag) else None
    return _send(request, b) if b else Response(status_code=404)
