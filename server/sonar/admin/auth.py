"""Вход в админку: свой админ (не аккаунт Sonar), сессии в базе, смена заводского пароля.

Заводской админ `folzy` создаётся при первом запуске со случайным паролем: он печатается один раз в журнал
запуска, в базе — только хэш argon2id. Репо публичное, поэтому ни пароля, ни хэша в коде нет; флаг
must_change не пускает дальше формы смены пароля.
"""
from __future__ import annotations

import hashlib
import secrets
import sqlite3
from dataclasses import dataclass

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError

from ..accounts import RateLimit
from ..db import now_ms

FACTORY_LOGIN = "folzy"
# 18 случайных байт → 24 символа base64url: заводской пароль живёт до первого входа.
FACTORY_PASSWORD_BYTES = 18
SESSION_TTL_MS = 12 * 3600_000      # ADMIN.md §1: сессия админки короткая
PASSWORD_MIN = 10
# Длиннее логина не бывает — обрезаем до проверки, чтобы мусорный ввод не раздувал ключи лимита входа.
LOGIN_MAX = 64

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
        self.limit = RateLimit(limit=5, window_s=15 * 60)

    def ensure_factory(self) -> str | None:
        """Нет ни одного админа — создать заводского со случайным паролем. → этот пароль (показать один раз) или None."""
        if self.con.execute("SELECT 1 FROM admins LIMIT 1").fetchone():
            return None
        password = secrets.token_urlsafe(FACTORY_PASSWORD_BYTES)
        self.con.execute("INSERT INTO admins (login, password_hash, must_change, created_at) VALUES (?,?,1,?)",
                         (FACTORY_LOGIN, _ph.hash(password), now_ms()))
        return password

    def _admin(self, r) -> Admin:
        return Admin(r["id"], r["login"], bool(r["must_change"]))

    def login(self, login: str, password: str, ip: str, user_agent: str = "") -> tuple[str, Session]:
        """→ (токен для cookie, сессия). AuthError('too_many' | 'bad')."""
        login = login.strip().lower()[:LOGIN_MAX]
        keys = (f"ip:{ip}", f"login:{login}")
        if self.limit.blocked(*keys):
            raise AuthError("too_many")
        r = self.con.execute("SELECT * FROM admins WHERE login = ?", (login,)).fetchone()
        try:
            _ph.verify(r["password_hash"] if r else _DUMMY, password)
            if r is None:
                raise VerifyMismatchError
        except (VerifyMismatchError, InvalidHashError):
            self.limit.hit(*keys)
            raise AuthError("bad") from None
        self.limit.reset(*keys)
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

    def change_password(self, s: Session, old: str, new: str, again: str, ip: str, user_agent: str = "") -> tuple[str, Session]:
        """Сменить пароль; все сессии этого админа закрываются, выдаётся новая. AuthError с кодом причины."""
        r = self.con.execute("SELECT * FROM admins WHERE id = ?", (s.admin.id,)).fetchone()
        try:
            _ph.verify(r["password_hash"], old)
        except (VerifyMismatchError, InvalidHashError):
            raise AuthError("bad_old") from None
        if new != again:
            raise AuthError("mismatch")
        if len(new) < PASSWORD_MIN:
            raise AuthError("short")
        if new == old or new.lower() in {r["login"].lower(), FACTORY_LOGIN}:
            raise AuthError("weak")
        self.set_password(r["login"], new)
        return self._new_session(Admin(r["id"], r["login"], False), ip, user_agent)

    def set_password(self, login: str, new: str) -> None:
        """Новый пароль без старого (CLI `python -m sonar.admin passwd`): сессии закрываются."""
        r = self.con.execute("SELECT id FROM admins WHERE login = ?", (login,)).fetchone()
        if r is None:
            raise AuthError("no_admin")
        with self.con:
            self.con.execute("UPDATE admins SET password_hash = ?, must_change = 0, changed_at = ? WHERE id = ?",
                             (_ph.hash(new), now_ms(), r["id"]))
            self.con.execute("DELETE FROM admin_sessions WHERE admin_id = ?", (r["id"],))
