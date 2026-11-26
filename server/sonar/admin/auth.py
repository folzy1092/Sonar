"""Вход в админку: свой админ (не аккаунт Sonar), сессии в базе, смена заводского пароля.

Заводской админ `folzy` создаётся при первом запуске со случайным паролем: он печатается один раз в журнал
запуска, в базе — только хэш argon2id. Репо публичное, поэтому ни пароля, ни хэша в коде нет; флаг
must_change не пускает дальше формы смены пароля.
"""
from __future__ import annotations

import asyncio
import hashlib
import secrets
import sqlite3
from dataclasses import dataclass

from argon2 import PasswordHasher

from ..accounts import RateLimit, password_ok
from ..db import now_ms, tx

FACTORY_LOGIN = "folzy"
# 18 случайных байт → 24 символа base64url: заводской пароль живёт до первого входа.
FACTORY_PASSWORD_BYTES = 18
SESSION_TTL_MS = 12 * 3600_000      # ADMIN.md §1: сессия админки короткая
PASSWORD_MIN = 10
# Длиннее логина не бывает — обрезаем до проверки, чтобы мусорный ввод не раздувал ключи лимита входа.
LOGIN_MAX = 64
LOGIN_WINDOW_S = 15 * 60
LOGIN_TRIES_PER_IP = 5
# Логин считается со всех адресов, но мягко: чужой с одного IP не запрёт владельца, а перебор с сотни IP упрётся сюда.
LOGIN_TRIES_PER_LOGIN = 50

_ph = PasswordHasher()
# Ложная проверка для несуществующего логина — чтобы время ответа не выдавало, есть ли такой админ.
_DUMMY = _ph.hash("not-a-password")


class AuthError(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


@dataclass
class Admin:
    id: int
    login: str
    must_change: bool
    user_id: str | None = None      # помощник владельца (staff.py); None — владелец


@dataclass
class Session:
    admin: Admin
    csrf: str
    token_hash: str


def _h(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


class AdminAuth:
    def __init__(self, con: sqlite3.Connection):
        self.con = con
        self.ip_limit = RateLimit(limit=LOGIN_TRIES_PER_IP, window_s=LOGIN_WINDOW_S)
        self.login_limit = RateLimit(limit=LOGIN_TRIES_PER_LOGIN, window_s=LOGIN_WINDOW_S)

    def ensure_factory(self) -> str | None:
        """Нет ни одного админа — создать заводского со случайным паролем. → этот пароль (показать один раз) или None."""
        if self.con.execute("SELECT 1 FROM admins LIMIT 1").fetchone():
            return None
        password = secrets.token_urlsafe(FACTORY_PASSWORD_BYTES)
        self.con.execute("INSERT INTO admins (login, password_hash, must_change, created_at) VALUES (?,?,1,?)",
                         (FACTORY_LOGIN, _ph.hash(password), now_ms()))
        return password

    def _admin(self, r) -> Admin:
        return Admin(r["id"], r["login"], bool(r["must_change"]), r["user_id"])

    async def login(self, login: str, password: str, ip: str, user_agent: str = "") -> tuple[str, Session]:
        """→ (токен для cookie, сессия). AuthError('too_many' | 'bad')."""
        login = login.strip().lower()[:LOGIN_MAX]
        ip_key, login_key = f"ip:{ip}", f"login:{login}"
        if self.ip_limit.blocked(ip_key) or self.login_limit.blocked(login_key):
            raise AuthError("too_many")
        # Попытка считается до проверки: пока argon2 считает в потоке, параллельные попытки тоже упрутся в лимит.
        self.ip_limit.hit(ip_key)
        self.login_limit.hit(login_key)
        r = self.con.execute("SELECT * FROM admins WHERE login = ?", (login,)).fetchone()
        ok = await asyncio.to_thread(password_ok, r["password_hash"] if r else _DUMMY, password)
        if not ok or r is None:
            raise AuthError("bad")
        self.ip_limit.reset(ip_key)
        return self._new_session(self._admin(r), ip, user_agent)

    def _new_session(self, admin: Admin, ip: str, user_agent: str) -> tuple[str, Session]:
        token, csrf = secrets.token_urlsafe(32), secrets.token_urlsafe(24)
        now = now_ms()
        self.con.execute("DELETE FROM admin_sessions WHERE expires_at <= ?", (now,))
        self.con.execute("INSERT INTO admin_sessions (token_hash, admin_id, csrf, ip, user_agent, created_at, expires_at)"
                         " VALUES (?,?,?,?,?,?,?)", (_h(token), admin.id, csrf, ip, user_agent[:200], now, now + SESSION_TTL_MS))
        return token, Session(admin, csrf, _h(token))

    def session(self, token: str | None) -> Session | None:
        if not token:
            return None
        r = self.con.execute("SELECT s.csrf, s.token_hash, a.* FROM admin_sessions s JOIN admins a ON a.id = s.admin_id"
                             " WHERE s.token_hash = ? AND s.expires_at > ?", (_h(token), now_ms())).fetchone()
        return Session(self._admin(r), r["csrf"], r["token_hash"]) if r else None

    def sessions(self, s: Session) -> list[dict]:
        """Открытые сессии этого админа, текущая — первой (`current`)."""
        rows = self.con.execute("SELECT token_hash, ip, user_agent, created_at FROM admin_sessions"
                                " WHERE admin_id = ? AND expires_at > ? ORDER BY created_at DESC", (s.admin.id, now_ms()))
        out = [{"ip": r["ip"], "user_agent": r["user_agent"], "created_at": r["created_at"],
                "current": r["token_hash"] == s.token_hash} for r in rows]
        return sorted(out, key=lambda r: not r["current"])

    def close_others(self, s: Session) -> int:
        """Закрыть все сессии админа, кроме текущей. → сколько закрыто."""
        return self.con.execute("DELETE FROM admin_sessions WHERE admin_id = ? AND token_hash != ?",
                                (s.admin.id, s.token_hash)).rowcount

    def logout(self, s: Session) -> None:
        self.con.execute("DELETE FROM admin_sessions WHERE token_hash = ?", (s.token_hash,))

    async def change_password(self, s: Session, old: str, new: str, again: str, ip: str,
                              user_agent: str = "") -> tuple[str, Session]:
        """Сменить пароль; все сессии этого админа закрываются, выдаётся новая. AuthError с кодом причины."""
        r = self.con.execute("SELECT * FROM admins WHERE id = ?", (s.admin.id,)).fetchone()
        if not await asyncio.to_thread(password_ok, r["password_hash"], old):
            raise AuthError("bad_old")
        if new != again:
            raise AuthError("mismatch")
        if len(new) < PASSWORD_MIN:
            raise AuthError("short")
        if new == old or new.lower() in {r["login"].lower(), FACTORY_LOGIN}:
            raise AuthError("weak")
        self._store_password(r["id"], await asyncio.to_thread(_ph.hash, new))
        return self._new_session(Admin(r["id"], r["login"], False, r["user_id"]), ip, user_agent)

    def set_password(self, login: str, new: str) -> None:
        """Новый пароль без старого (CLI `python -m sonar.admin passwd`): сессии закрываются."""
        r = self.con.execute("SELECT id FROM admins WHERE login = ?", (login,)).fetchone()
        if r is None:
            raise AuthError("no_admin")
        self._store_password(r["id"], _ph.hash(new))

    def reset_password(self, login: str = FACTORY_LOGIN) -> str:
        """Новый случайный пароль без старого (бот, `/admin`: владелец забыл заводской). Сессии закрываются, а при
        входе сразу откроется форма смены (`must_change`). Админа нет — создаётся заводской. → пароль, показать один раз."""
        self.ensure_factory()
        r = self.con.execute("SELECT id FROM admins WHERE login = ?", (login,)).fetchone()
        if r is None:
            raise AuthError("no_admin")
        password = secrets.token_urlsafe(FACTORY_PASSWORD_BYTES)
        self._store_password(r["id"], _ph.hash(password), must_change=True)
        return password

    def add_staff(self, login: str, user_id: str) -> str:
        """Вход в админку помощнику (право panel, staff.py): логин — его логин Sonar, пароль случайный и одноразовый
        (`must_change`). → пароль, показать владельцу один раз."""
        password = secrets.token_urlsafe(FACTORY_PASSWORD_BYTES)
        with tx(self.con):
            self.con.execute("DELETE FROM admins WHERE user_id = ?", (user_id,))
            self.con.execute("INSERT INTO admins (login, password_hash, must_change, created_at, user_id) VALUES (?,?,1,?,?)",
                             (login, _ph.hash(password), now_ms(), user_id))
        return password

    def drop_staff(self, user_id: str) -> None:
        """Забрать вход в админку у помощника: строка админа и все его сессии."""
        with tx(self.con):
            self.con.execute("DELETE FROM admin_sessions WHERE admin_id IN (SELECT id FROM admins WHERE user_id = ?)",
                             (user_id,))
            self.con.execute("DELETE FROM admins WHERE user_id = ?", (user_id,))

    def _store_password(self, admin_id: int, password_hash: str, must_change: bool = False) -> None:
        with tx(self.con):
            self.con.execute("UPDATE admins SET password_hash = ?, must_change = ?, changed_at = ? WHERE id = ?",
                             (password_hash, int(must_change), now_ms(), admin_id))
            self.con.execute("DELETE FROM admin_sessions WHERE admin_id = ?", (admin_id,))
