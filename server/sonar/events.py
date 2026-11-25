"""События клиентов для дашборда админки: «открыл плеер» и «включил трек» (API.md «POST /events»).

Клиент шлёт пачку, сервер сам берёт пользователя, устройство и платформу из сессии (телу не верим),
сервис — из префикса ref. День (`day`) считается в часовом поясе админки, чтобы «сегодня» совпадало
с днём владельца, и хранится в строке — дашборд группирует по индексу, без вычислений в памяти.
"""
from __future__ import annotations

import hashlib
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone

from .db import now_ms, tx

KINDS = {"open", "play"}
# Префикс ref → сервис (API.md §2 «Префиксы ref»); local — локальные файлы ПК.
SERVICES = {"sc": "soundcloud", "ym": "yandex", "yt": "youtube", "vk": "vk", "sp": "spotify", "local": "local"}
PLATFORMS = {"windows", "ios", "android"}
BATCH_MAX = 200
PAST_MAX_MS = 7 * 86400_000     # офлайн-очередь клиента — не старше недели
FUTURE_MAX_MS = 5 * 60_000      # часы устройства могут спешить
TEXT_MAX = 200


def tz():
    """Часовой пояс дней дашборда: SONAR_ADMIN_TZ, по умолчанию Europe/Riga (владелец в Латвии)."""
    import os
    name = os.getenv("SONAR_ADMIN_TZ", "Europe/Riga")
    try:
        from zoneinfo import ZoneInfo
        return ZoneInfo(name)
    except Exception:  # нет базы поясов (Windows без tzdata) — UTC, но не падаем
        return timezone.utc


def day_of(ms: int) -> str:
    return datetime.fromtimestamp(ms / 1000, tz()).strftime("%Y-%m-%d")


def service_of(ref: str | None) -> str | None:
    if not ref or ":" not in ref:
        return None
    return SERVICES.get(ref.split(":", 1)[0])


@dataclass
class Device:
    user_id: str
    device_id: str
    platform: str


def session_device(con: sqlite3.Connection, token: str) -> Device | None:
    """Сессия клиента (Bearer) → пользователь и устройство; забаненным — None (сверка — `sessions.by_token`)."""
    from . import sessions
    s = sessions.by_token(con, token)
    if s is None:
        return None
    sessions.seen(con, s)
    return Device(s.user_id, s.device_id, s.platform)


def _text(v) -> str | None:
    if not isinstance(v, str) or not v.strip():
        return None
    return v.strip()[:TEXT_MAX]


def record(con: sqlite3.Connection, dev: Device, events: list[dict], now: int | None = None) -> int:
    """Принять пачку событий; вернуть, сколько записано. Повтор той же пачки не удваивает счёт."""
    now = now or now_ms()
    rows = []
    for ev in events[:BATCH_MAX]:
        if not isinstance(ev, dict):
            continue
        kind, at = ev.get("kind"), ev.get("at")
        if kind not in KINDS or not isinstance(at, int) or isinstance(at, bool):
            continue
        if at < now - PAST_MAX_MS or at > now + FUTURE_MAX_MS:
            continue
        ref = _text(ev.get("ref")) if kind == "play" else None
        if kind == "play" and not ref:
            continue
        rows.append((dev.user_id, dev.device_id, dev.platform if dev.platform in PLATFORMS else "other", kind,
                     service_of(ref), ref, _text(ev.get("artist")) if ref else None,
                     _text(ev.get("title")) if ref else None, at, day_of(at)))
    if not rows:
        return 0
    before = con.total_changes
    with tx(con):
        con.executemany("INSERT OR IGNORE INTO events (user_id, device_id, platform, kind, service, ref, artist, title, at, day)"
                        " VALUES (?,?,?,?,?,?,?,?,?,?)", rows)
    return con.total_changes - before
