"""Аккаунты Sonar: регистрация, вход, привязка Telegram, токен интеграции, рефералка, сводки.

Без HTTP и без бота — их зовут и бот, и (потом) роутеры API.
"""
from __future__ import annotations

import hashlib
import re
import secrets
import sqlite3
import time
from collections import defaultdict, deque
from dataclasses import dataclass

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError
from cryptography.fernet import Fernet, InvalidToken

from .db import now_ms

LOGIN_RE = re.compile(r"^[a-z0-9_.]{3,24}$")
PASSWORD_MIN = 8
NUMBER_START = 100001
REF_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
TOKEN_PREFIX = "snr_"
TOKEN_LIKE = re.compile(r"^(y0_[\w-]{20,}|AQAAAA[\w-]{20,}|2-\d{5,}-\d+-\w{10,}|[A-Za-z0-9_-]{32,})$")

_ph = PasswordHasher()  # argon2id по умолчанию


class AccountError(Exception):
    """Понятная пользователю причина: code — ключ текста в боте."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


@dataclass
class User:
    id: str
    number: int
    login: str
    username: str
    display_name: str
    has_password: bool
    tg_id: int | None
    referral_code: str | None
    created_at: int

    @classmethod
    def of(cls, r: sqlite3.Row | None) -> "User | None":
        if r is None:
            return None
        return cls(r["id"], r["number"], r["login"], r["username"], r["display_name"], bool(r["password_hash"]),
                   r["tg_id"], r["referral_code"], r["created_at"])


def looks_like_token(text: str) -> bool:
    """Токен сервиса, который прислали боту вместо приложения (TZ §4.15)."""
    t = text.strip()
    return " " not in t and bool(TOKEN_LIKE.match(t)) and not LOGIN_RE.match(t)


# ---- лимиты входа (в памяти, как SPEC §3.4): 5 попыток за 15 минут на ключ ----

class RateLimit:
    def __init__(self, limit: int = 5, window_s: int = 15 * 60):
        self.limit, self.window = limit, window_s
        self.hits: dict[str, deque[float]] = defaultdict(deque)

    def blocked(self, *keys: str) -> bool:
        t = time.monotonic()
        for k in keys:
            q = self.hits[k]
            while q and t - q[0] > self.window:
                q.popleft()
            if len(q) >= self.limit:
                return True
        return False

    def hit(self, *keys: str) -> None:
        for k in keys:
            self.hits[k].append(time.monotonic())

    def reset(self, *keys: str) -> None:
        for k in keys:
            self.hits.pop(k, None)


class Accounts:
    def __init__(self, con: sqlite3.Connection, fernet_key: str):
        self.con = con
        self.fernet = Fernet(fernet_key.encode())
        self.login_limit = RateLimit()

    # ---- поиск ----

    def by_id(self, user_id: str) -> User | None:
        return User.of(self.con.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone())

    def by_login(self, login: str) -> User | None:
        return User.of(self.con.execute("SELECT * FROM users WHERE login = ? AND banned = 0", (login.strip().lstrip("@"),)).fetchone())

    def by_tg(self, tg_id: int) -> User | None:
        return User.of(self.con.execute("SELECT * FROM users WHERE tg_id = ? AND banned = 0", (tg_id,)).fetchone())

    def login_free(self, login: str) -> bool:
        r = self.con.execute("SELECT 1 FROM users WHERE login = ? OR username = ?", (login, login)).fetchone()
        return r is None

    # ---- регистрация и вход ----

    def check_login(self, login: str) -> str:
        login = login.strip().lstrip("@").lower()
        if not LOGIN_RE.match(login):
            raise AccountError("login_format")
        if not self.login_free(login):
            raise AccountError("login_taken")
        return login

    def register(self, login: str, password: str, tg_id: int | None = None, tg_username: str | None = None,
                 referred_code: str | None = None) -> User:
        login = self.check_login(login)
        if len(password) < PASSWORD_MIN:
            raise AccountError("password_short")
        if tg_id is not None and self.by_tg(tg_id):
            raise AccountError("tg_taken")
        ref = self.by_referral(referred_code) if referred_code else None
        uid = "u_" + secrets.token_hex(8)
        with self.con:
            n = self.con.execute("SELECT COALESCE(MAX(number), ?) + 1 AS n FROM users", (NUMBER_START - 1,)).fetchone()["n"]
            self.con.execute(
                "INSERT INTO users (id, number, login, username, display_name, password_hash, tg_id, tg_username,"
                " referral_code, referred_by, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                (uid, n, login, login, login, _ph.hash(password), tg_id, tg_username, self._new_ref_code(),
                 ref.id if ref else None, now_ms()),
            )
        return self.by_id(uid)

    def verify(self, login: str, password: str, tg_id: int | None = None) -> User:
        """Вход логином и паролем; AccountError('no_user' | 'bad_password' | 'too_many')."""
        keys = [f"login:{login.lower()}"] + ([f"tg:{tg_id}"] if tg_id else [])
        if self.login_limit.blocked(*keys):
            raise AccountError("too_many")
        r = self.con.execute("SELECT * FROM users WHERE login = ? AND banned = 0", (login.strip().lstrip("@"),)).fetchone()
        if r is None:
            self.login_limit.hit(*keys)
            raise AccountError("no_user")
        try:
            _ph.verify(r["password_hash"] or "", password)
        except (VerifyMismatchError, InvalidHashError):
            self.login_limit.hit(*keys)
            raise AccountError("bad_password")
        self.login_limit.reset(*keys)
        return User.of(r)

    def link_tg(self, user: User, tg_id: int, tg_username: str | None) -> User:
        with self.con:
            # Telegram может быть привязан только к одному аккаунту — отвязываем от прежнего.
            self.con.execute("UPDATE users SET tg_id = NULL WHERE tg_id = ? AND id != ?", (tg_id, user.id))
            self.con.execute("UPDATE users SET tg_id = ?, tg_username = ? WHERE id = ?", (tg_id, tg_username, user.id))
        return self.by_id(user.id)

    def unlink_tg(self, user: User) -> None:
        if not user.has_password:
            raise AccountError("no_password")
        self.con.execute("UPDATE users SET tg_id = NULL WHERE id = ?", (user.id,))

    # ---- рефералка ----

    def _new_ref_code(self) -> str:
        while True:
            code = "".join(secrets.choice(REF_ALPHABET) for _ in range(6))
            if not self.con.execute("SELECT 1 FROM users WHERE referral_code = ?", (code,)).fetchone():
                return code

    def by_referral(self, code: str) -> User | None:
        return User.of(self.con.execute("SELECT * FROM users WHERE referral_code = ?", (code.upper(),)).fetchone())

    def referral_count(self, user: User) -> int:
        return self.con.execute("SELECT COUNT(*) AS n FROM users WHERE referred_by = ?", (user.id,)).fetchone()["n"]

    # ---- токен интеграции: виден всегда (BOT.md §2.6а), поэтому хэш + Fernet ----

    def token(self, user: User) -> str | None:
        r = self.con.execute("SELECT key_enc FROM api_keys WHERE user_id = ?", (user.id,)).fetchone()
        if not r:
            return None
        try:
            return self.fernet.decrypt(r["key_enc"].encode()).decode()
        except InvalidToken:
            return None

    def new_token(self, user: User) -> str:
        tok = TOKEN_PREFIX + secrets.token_hex(16)
        h = hashlib.sha256(tok.encode()).hexdigest()
        enc = self.fernet.encrypt(tok.encode()).decode()
        self.con.execute(
            "INSERT INTO api_keys (user_id, key_hash, key_enc, created_at) VALUES (?,?,?,?)"
            " ON CONFLICT(user_id) DO UPDATE SET key_hash = excluded.key_hash, key_enc = excluded.key_enc,"
            " created_at = excluded.created_at",
            (user.id, h, enc, now_ms()),
        )
        return tok

    def revoke_token(self, user: User) -> None:
        self.con.execute("DELETE FROM api_keys WHERE user_id = ?", (user.id,))

    def user_by_token(self, token: str) -> User | None:
        h = hashlib.sha256(token.encode()).hexdigest()
        r = self.con.execute("SELECT u.* FROM users u JOIN api_keys k ON k.user_id = u.id WHERE k.key_hash = ?", (h,)).fetchone()
        return User.of(r)

    # ---- сводки для профиля и статистики ----

    def services(self, user: User) -> dict[str, bool]:
        rows = self.con.execute("SELECT service FROM service_accounts WHERE user_id = ?", (user.id,)).fetchall()
        have = {r["service"] for r in rows}
        lastfm = self.con.execute("SELECT 1 FROM lastfm WHERE user_id = ?", (user.id,)).fetchone() is not None
        return {"soundcloud": "soundcloud" in have, "yandex": "yandex" in have, "lastfm": lastfm}

    def totals(self, user: User, since_ms: int, until_ms: int | None = None) -> tuple[int, int]:
        """(минуты, треки) за период."""
        until_ms = until_ms or now_ms()
        r = self.con.execute(
            "SELECT COALESCE(SUM(listened_ms), 0) AS ms, COUNT(*) AS n FROM plays WHERE user_id = ? AND played_at >= ? AND played_at < ?",
            (user.id, since_ms, until_ms),
        ).fetchone()
        return r["ms"] // 60000, r["n"]

    def stats(self, user: User, days: int) -> dict:
        now = now_ms()
        span = days * 86400_000
        mins, n = self.totals(user, now - span, now)
        prev_mins, _ = self.totals(user, now - 2 * span, now - span)
        q = lambda sql: self.con.execute(sql, (user.id, now - span)).fetchall()  # noqa: E731
        artists = [r["artist"] for r in q(
            "SELECT artist, SUM(listened_ms) AS ms FROM plays WHERE user_id = ? AND played_at >= ? GROUP BY artist ORDER BY ms DESC LIMIT 3")]
        tracks = [f"{r['artist']} — {r['title']}" if r["title"] else r["ref"] for r in q(
            "SELECT p.ref, p.artist, t.title, COUNT(*) AS c FROM plays p LEFT JOIN tracks t ON t.ref = p.ref"
            " WHERE p.user_id = ? AND p.played_at >= ? GROUP BY p.ref ORDER BY c DESC LIMIT 3")]
        day = q("SELECT strftime('%w', played_at / 1000, 'unixepoch', 'localtime') AS d, SUM(listened_ms) AS ms FROM plays"
                " WHERE user_id = ? AND played_at >= ? GROUP BY d ORDER BY ms DESC LIMIT 1")
        hour = q("SELECT strftime('%H', played_at / 1000, 'unixepoch', 'localtime') AS h, SUM(listened_ms) AS ms FROM plays"
                 " WHERE user_id = ? AND played_at >= ? GROUP BY h ORDER BY ms DESC LIMIT 1")
        delta = None if not prev_mins else round((mins - prev_mins) * 100 / prev_mins)
        return {"minutes": mins, "tracks": n, "delta": delta, "artists": artists, "top_tracks": tracks,
                "day": int(day[0]["d"]) if day else None, "hour": int(hour[0]["h"]) if hour else None}

    def users_count(self) -> int:
        return self.con.execute("SELECT COUNT(*) AS n FROM users WHERE banned = 0").fetchone()["n"]

    def listening_now(self) -> int:
        return self.con.execute("SELECT COUNT(*) AS n FROM player_state WHERE is_playing = 1 AND heartbeat_at > ?",
                                (now_ms() - 90_000,)).fetchone()["n"]
