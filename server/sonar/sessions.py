"""Сессии устройств и запросы входа (API.md §1, BOT.md §3, §6). Без HTTP — их зовут роутеры API и бот.

Сессия = случайный токен, в базе только SHA-256 (`sessions.token_hash`). Один пользователь — одна сессия на
устройство: повторный вход с того же `device_id` заменяет прежнюю (UNIQUE (user_id, device_id)).

Запрос входа — строка `auth_links` (код живёт 5 минут, в базе только хэш). Виды (`for_kind`):
- `device` — новое устройство просит вход (`POST /auth/link`, `POST /auth/telegram/start` с `purpose: login`);
  разрешает уже вошедший — в приложении или в боте; сессию забирает опрос, один раз (`status` → `done`).
- `telegram` — бот просит привязать Telegram (быстрая ссылка из бота); разрешают в приложении.
- `tg_link` — вошедший в приложении привязывает Telegram (`purpose: link`); завершает бот по `?start=tg_<код>`.
"""
from __future__ import annotations

import hashlib
import json
import secrets
import sqlite3
import time
from dataclasses import dataclass

from .accounts import User
from .db import now_ms, tx

LINK_TTL_MS = 5 * 60_000
# Завершать другие сессии можно, только если своя старше суток: защита от того, кто только что вошёл чужим паролем.
REVOKE_DELAY_MS = 24 * 3600_000
PLATFORMS = ("ios", "windows", "android")
NAME_MAX = 48
TEXT_MAX = 64


class DeviceError(ValueError):
    pass


@dataclass
class DeviceInfo:
    id: str
    name: str
    platform: str
    os: str | None = None
    app_version: str | None = None
    build: int | None = None

    @classmethod
    def parse(cls, raw) -> "DeviceInfo":
        """`device` из тела запроса → проверенный DeviceInfo; DeviceError с текстом для 400."""
        if not isinstance(raw, dict):
            raise DeviceError("Нужно поле device")
        did, name, platform = raw.get("id"), raw.get("name"), raw.get("platform")
        if not isinstance(did, str) or not did.strip() or len(did) > TEXT_MAX:
            raise DeviceError("device.id — строка до 64 символов")
        if not isinstance(name, str) or not name.strip():
            raise DeviceError("device.name — непустая строка")
        if platform not in PLATFORMS:
            raise DeviceError("device.platform — ios, windows или android")

        def text(v) -> str | None:
            return v.strip()[:TEXT_MAX] or None if isinstance(v, str) else None

        build = raw.get("build")
        if not isinstance(build, int) or isinstance(build, bool) or build < 0:
            build = None
        return cls(did.strip(), name.strip()[:NAME_MAX], platform, text(raw.get("os")), text(raw.get("app_version")), build)

    def label(self) -> str:
        """«iPhone 15 Pro · Sonar 1.0» — для окна подтверждения и бота."""
        return f"{self.name} · Sonar {self.app_version}" if self.app_version else self.name


@dataclass
class Session:
    id: str
    user_id: str
    device_id: str
    platform: str
    created_at: int


def _h(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


# ---- сессии ----

def create(con: sqlite3.Connection, user_id: str, dev: DeviceInfo) -> str:
    """Новая сессия устройства (прежняя этого устройства — заменяется). → токен, показывается один раз."""
    token = secrets.token_urlsafe(32)
    now = now_ms()
    with tx(con):
        con.execute("DELETE FROM sessions WHERE user_id = ? AND device_id = ?", (user_id, dev.id))
        con.execute("INSERT INTO sessions (id, user_id, token_hash, device_id, device_name, platform, os, app_version,"
                    " build, created_at, last_seen_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                    ("d_" + secrets.token_hex(8), user_id, _h(token), dev.id, dev.name, dev.platform, dev.os,
                     dev.app_version, dev.build, now, now))
    return token


def by_token(con: sqlite3.Connection, token: str) -> Session | None:
    """Сессия по токену (Bearer); у забаненного — None. Единственное место, где сверяется токен сессии."""
    r = con.execute("SELECT s.id, s.user_id, s.device_id, s.platform, s.created_at FROM sessions s JOIN users u"
                    " ON u.id = s.user_id WHERE s.token_hash = ? AND u.banned = 0", (_h(token),)).fetchone()
    return Session(r["id"], r["user_id"], r["device_id"], r["platform"], r["created_at"]) if r else None


# last_seen_at пишем не чаще раза в 5 минут (SPEC §3.4): опрос и синк не должны писать в базу на каждый запрос.
SEEN_EVERY_MS = 5 * 60_000


def seen(con: sqlite3.Connection, s: Session) -> None:
    now = now_ms()
    con.execute("UPDATE sessions SET last_seen_at = ? WHERE id = ? AND last_seen_at < ?", (now, s.id, now - SEEN_EVERY_MS))


def drop_others(con: sqlite3.Connection, s: Session) -> int:
    """Выйти на всех устройствах, кроме этого (после смены пароля)."""
    return con.execute("DELETE FROM sessions WHERE user_id = ? AND id != ?", (s.user_id, s.id)).rowcount


def drop(con: sqlite3.Connection, session_id: str) -> None:
    con.execute("DELETE FROM sessions WHERE id = ?", (session_id,))


def report(con: sqlite3.Connection, s: Session, dev: DeviceInfo) -> None:
    """`PUT /me/device`: устройство при запуске сообщает имя, ОС, версию. id устройства у сессии не меняется."""
    con.execute("UPDATE sessions SET device_name = ?, platform = ?, os = ?, app_version = ?, build = ?, last_seen_at = ?"
                " WHERE id = ?", (dev.name, dev.platform, dev.os, dev.app_version, dev.build, now_ms(), s.id))


def device_json(r: sqlite3.Row, current_id: str | None) -> dict:
    return {"id": r["device_id"], "name": r["device_name"], "platform": r["platform"], "os": r["os"],
            "app_version": r["app_version"], "build": r["build"], "created_at": r["created_at"],
            "last_seen_at": r["last_seen_at"], "current": r["id"] == current_id}


def devices(con: sqlite3.Connection, s: Session) -> list[dict]:
    rows = con.execute("SELECT * FROM sessions WHERE user_id = ? ORDER BY id = ? DESC, last_seen_at DESC",
                       (s.user_id, s.id)).fetchall()
    return [device_json(r, s.id) for r in rows]


def device_row(con: sqlite3.Connection, user_id: str, device_id: str):
    return con.execute("SELECT * FROM sessions WHERE user_id = ? AND device_id = ?", (user_id, device_id)).fetchone()


def user_json(con: sqlite3.Connection, user: User) -> dict:
    """`User` из API.md §1. Аватара пока нет (загрузка — отдельным этапом)."""
    r = con.execute("SELECT tg_id, tg_username FROM users WHERE id = ?", (user.id,)).fetchone()
    have = {row["service"]: row for row in
            con.execute("SELECT service, ext_name FROM service_accounts WHERE user_id = ?", (user.id,)).fetchall()}
    services = {k: ({"connected": True, "name": have[k]["ext_name"], "premium": None} if k in have else {"connected": False})
                for k in ("soundcloud", "yandex")}
    return {"id": user.id, "login": user.login, "username": user.username, "display_name": user.display_name,
            "number": user.number, "avatar_url": None, "created_at": user.created_at,
            "telegram": {"id": r["tg_id"], "username": r["tg_username"]} if r and r["tg_id"] else None,
            "has_password": user.has_password, "services": services}


# ---- запросы входа ----

@dataclass
class Link:
    code_hash: str
    kind: str
    data: dict
    user_id: str | None
    status: str
    created_at: int
    expires_at: int


def new_link(con: sqlite3.Connection, kind: str, data: dict, user_id: str | None = None) -> tuple[str, Link]:
    """→ (код для ссылки, запрос). Код виден только создателю, в базе — хэш."""
    code = secrets.token_urlsafe(24)
    now = now_ms()
    link = Link(_h(code), kind, data, user_id, "pending", now, now + LINK_TTL_MS)
    con.execute("INSERT INTO auth_links (code_hash, for_kind, for_json, user_id, status, created_at, expires_at)"
                " VALUES (?,?,?,?,?,?,?)", (link.code_hash, kind, json.dumps(data, ensure_ascii=False), user_id,
                                            "pending", now, link.expires_at))
    return code, link


def get_link(con: sqlite3.Connection, code: str) -> Link | None:
    """Запрос по коду; просроченный ожидающий сам становится `expired`."""
    if not code or len(code) > 128:
        return None
    r = con.execute("SELECT * FROM auth_links WHERE code_hash = ?", (_h(code),)).fetchone()
    if r is None:
        return None
    link = Link(r["code_hash"], r["for_kind"], json.loads(r["for_json"]), r["user_id"], r["status"], r["created_at"],
                r["expires_at"])
    if link.status == "pending" and now_ms() >= link.expires_at:
        con.execute("UPDATE auth_links SET status = 'expired' WHERE code_hash = ?", (link.code_hash,))
        link.status = "expired"
    return link


def decide(con: sqlite3.Connection, link: Link, status: str, user_id: str | None = None) -> bool:
    """pending → approved / rejected. False — уже решён или истёк (второе нажатие ничего не меняет)."""
    cur = con.execute("UPDATE auth_links SET status = ?, user_id = COALESCE(?, user_id) WHERE code_hash = ?"
                      " AND status = 'pending' AND expires_at > ?", (status, user_id, link.code_hash, now_ms()))
    if cur.rowcount:
        link.status = status
        link.user_id = user_id or link.user_id
    return bool(cur.rowcount)


# Токен сессии в базе лежит только хэшем, поэтому повторно выдать его можно лишь из памяти. Ответ с сессией по мобильной сети
# теряется (обрыв, таймаут): раньше повторный опрос отвечал «expired», бот писал «Вход разрешён», а телефон оставался без
# аккаунта. Теперь тому, кто знает код (секрет на 32 байта), токен отдаётся повторно ещё CLAIM_GRACE_S секунд. Рестарт
# сервера в эти две минуты забывает токен — человек просто запросит новую ссылку.
CLAIM_GRACE_S = 120
_claimed: dict[str, tuple[str, float]] = {}


def _regrant(code_hash: str) -> str | None:
    now = time.monotonic()
    for key in [k for k, (_, until) in _claimed.items() if until <= now]:
        del _claimed[key]
    hit = _claimed.get(code_hash)
    return hit[0] if hit else None


def claim(con: sqlite3.Connection, link: Link) -> str | None:
    """Опрос `device`-запроса: разрешён → сессия для нового устройства. Создаётся один раз (approved → done), но тот же
    токен повторяется на повторных опросах в течение CLAIM_GRACE_S — на случай потерянного ответа."""
    if link.kind != "device" or not link.user_id or link.status not in ("approved", "done"):
        return None
    if link.status == "done":
        return _regrant(link.code_hash)
    if not con.execute("UPDATE auth_links SET status = 'done' WHERE code_hash = ? AND status = 'approved'",
                       (link.code_hash,)).rowcount:
        return _regrant(link.code_hash)           # параллельный опрос уже забрал — отдаём ему же выданное
    token = create(con, link.user_id, DeviceInfo.parse(link.data))
    _claimed[link.code_hash] = (token, time.monotonic() + CLAIM_GRACE_S)
    return token


def purge(con: sqlite3.Connection) -> None:
    """Старые запросы не копим: сутки после истечения — удалить."""
    con.execute("DELETE FROM auth_links WHERE expires_at < ?", (now_ms() - 86400_000,))
