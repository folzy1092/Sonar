"""Аккаунты Sonar: регистрация, вход, привязка Telegram, токен интеграции, рефералка, сводки.

Без HTTP и без бота — их зовут и бот, и (потом) роутеры API.
"""
from __future__ import annotations

import asyncio
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

from . import bans
from .db import now_ms, tx

LOGIN_RE = re.compile(r"^[a-z0-9_.]{3,24}$")
PASSWORD_MIN = 8
DISPLAY_NAME_MAX = 48
NUMBER_START = 1  # владелец — #1, дальше по порядку (решение 2026-11-15)
REF_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
TOKEN_PREFIX = "snr_"
TOKEN_LIKE = re.compile(r"^(y0_[\w-]{20,}|AQAAAA[\w-]{20,}|2-\d{5,}-\d+-\w{10,}|[A-Za-z0-9_-]{32,})$")

# argon2id в минимуме OWASP (19 МБ, 2 прохода, 1 поток). Умолчание библиотеки (64 МБ, 3 прохода, 4 потока) на контейнере с
# 25 % vCPU и 512 МБ держит один вход 1,5–2,5 секунды, а несколько подряд (повторы телефона) дают таймауты и скачок памяти.
# Старые хэши проверяются по своим параметрам и тихо переписываются при ближайшем входе (`Accounts.verify`).
_ph = PasswordHasher(time_cost=2, memory_cost=19456, parallelism=1)
_DUMMY_HASH = _ph.hash("not-a-password")
_cpu = asyncio.Semaphore(2)   # не больше двух хэшей одновременно: память и процессор — четверть ядра


async def hash_password(password: str) -> str:
    async with _cpu:
        return await asyncio.to_thread(_ph.hash, password)


async def check_password(password_hash: str, password: str) -> bool:
    async with _cpu:
        return await asyncio.to_thread(password_ok, password_hash, password)


def password_ok(password_hash: str, password: str) -> bool:
    """Проверка argon2 без исключений. Медленная (~50 мс) — из async-кода звать через `asyncio.to_thread`."""
    try:
        return _ph.verify(password_hash, password)
    except (VerifyMismatchError, InvalidHashError):
        return False


class AccountError(Exception):
    """Понятная пользователю причина: code — ключ текста в боте."""

    def __init__(self, code: str, ban=None):
        super().__init__(code)
        self.code = code
        self.ban = ban      # bans.Ban у кода «banned»


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

IP_LOGIN_TRIES = 30   # попыток входа за 15 минут с одного IP (на логин — 5)


class RateLimit:
    def __init__(self, limit: int = 5, window_s: int = 15 * 60):
        self.limit, self.window = limit, window_s
        self.hits: dict[str, deque[float]] = defaultdict(deque)

    def blocked(self, *keys: str) -> bool:
        t = time.monotonic()
        for k in keys:
            # `get`, а не `self.hits[k]`: проверка не должна заводить запись на каждый новый логин или IP
            q = self.hits.get(k)
            if q is None:
                continue
            while q and t - q[0] > self.window:
                q.popleft()
            if not q:
                del self.hits[k]
                continue
            if len(q) >= self.limit:
                return True
        return False

    def hit(self, *keys: str) -> None:
        for k in keys:
            self.hits[k].append(time.monotonic())

    def reset(self, *keys: str) -> None:
        for k in keys:
            self.hits.pop(k, None)


def users_count(con: sqlite3.Connection) -> int:
    return con.execute("SELECT COUNT(*) AS n FROM users WHERE banned = 0").fetchone()["n"]


def listeners_24h(con: sqlite3.Connection) -> int:
    """Сколько разных аккаунтов слушали за последние 24 часа: один аккаунт — один слушатель.

    Скользящее окно, а не «с полуночи»: слушатели во всех часовых поясах (решение владельца 2026-11-18).
    """
    since = now_ms() - 86400_000
    return con.execute(
        "SELECT COUNT(*) AS n FROM (SELECT user_id FROM plays WHERE played_at >= ?"
        " UNION SELECT user_id FROM player_state WHERE is_playing = 1 AND heartbeat_at >= ?)",
        (since, since)).fetchone()["n"]


def listening_now(con: sqlite3.Connection) -> int:
    """Играют сейчас: heartbeat моложе 90 с (API.md §9)."""
    return con.execute("SELECT COUNT(*) AS n FROM player_state WHERE is_playing = 1 AND heartbeat_at > ?",
                       (now_ms() - 90_000,)).fetchone()["n"]


class Accounts:
    def __init__(self, con: sqlite3.Connection, fernet_key: str):
        self.con = con
        self.fernet = Fernet(fernet_key.encode())
        self.login_limit = RateLimit()                      # 5 попыток за 15 минут на логин и на Telegram
        # IP считается отдельно и мягче: у мобильного оператора и у общего nginx хостинга за одним адресом сидят многие, а
        # перебор пароля и так упирается в лимит на логин. 5 на IP хватало, чтобы пара опечаток заперла вход всем.
        self.ip_limit = RateLimit(limit=IP_LOGIN_TRIES)

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

    async def register(self, login: str, password: str, tg_id: int | None = None, tg_username: str | None = None,
                       referred_code: str | None = None) -> User:
        login = self.check_login(login)
        if len(password) < PASSWORD_MIN:
            raise AccountError("password_short")
        if tg_id is not None and self.by_tg(tg_id):
            raise AccountError("tg_taken")
        ref = self.by_referral(referred_code) if referred_code else None
        uid = "u_" + secrets.token_hex(8)
        # Хэш — в потоке: бот и админка живут в одном цикле событий, argon2 не должен его держать.
        password_hash = await hash_password(password)
        with tx(self.con):
            if not self.login_free(login):  # пока считался хэш, логин мог занять другой
                raise AccountError("login_taken")
            n = self.con.execute("SELECT COALESCE(MAX(number), ?) + 1 AS n FROM users", (NUMBER_START - 1,)).fetchone()["n"]
            self.con.execute(
                "INSERT INTO users (id, number, login, username, display_name, password_hash, tg_id, tg_username,"
                " referral_code, referred_by, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                (uid, n, login, login, login, password_hash, tg_id, tg_username, self._new_ref_code(),
                 ref.id if ref else None, now_ms()),
            )
        return self.by_id(uid)

    async def verify(self, login: str, password: str, tg_id: int | None = None, ip: str | None = None) -> User:
        """Вход логином и паролем; AccountError('no_user' | 'bad_password' | 'too_many').

        Лимит — 5 попыток за 15 минут на логин и на Telegram (бот), 30 — на IP (API).
        """
        keys = [f"login:{login.strip().lstrip('@').lower()[:64]}"] + ([f"tg:{tg_id}"] if tg_id else [])
        ip_key = f"ip:{ip}" if ip else None
        if self.login_limit.blocked(*keys) or (ip_key and self.ip_limit.blocked(ip_key)):
            raise AccountError("too_many")
        # Попытка считается до проверки: пока argon2 считает в потоке, параллельные попытки тоже упрутся в лимит.
        self.login_limit.hit(*keys)
        if ip_key:
            self.ip_limit.hit(ip_key)
        bans.expire(self.con)
        r = self.con.execute("SELECT * FROM users WHERE login = ?", (login.strip().lstrip("@"),)).fetchone()
        if r is None:
            # Та же работа argon2, что и с настоящим логином: по времени ответа не понять, есть ли такой аккаунт.
            await check_password(_DUMMY_HASH, password)
            raise AccountError("no_user")
        if not await check_password(r["password_hash"] or _DUMMY_HASH, password):
            raise AccountError("bad_password")
        if r["password_hash"] and _ph.check_needs_rehash(r["password_hash"]):
            # вход подтверждён — переписываем старый тяжёлый хэш на облегчённый (один раз на пользователя)
            self.con.execute("UPDATE users SET password_hash = ? WHERE id = ?", (await hash_password(password), r["id"]))
        if r["banned"]:
            # О бане говорим только тому, кто знает пароль: чужому это не раскрывает, что такой аккаунт есть.
            raise AccountError("banned", bans.Ban(r["ban_reason"], r["ban_until"], r["banned_at"]))
        self.login_limit.reset(*keys)      # IP не сбрасываем: иначе вход под своим аккаунтом обнулял бы счётчик перебора
        return User.of(r)

    def link_tg(self, user: User, tg_id: int, tg_username: str | None) -> User:
        with tx(self.con):
            # Telegram может быть привязан только к одному аккаунту — отвязываем от прежнего.
            self.con.execute("UPDATE users SET tg_id = NULL WHERE tg_id = ? AND id != ?", (tg_id, user.id))
            self.con.execute("UPDATE users SET tg_id = ?, tg_username = ? WHERE id = ?", (tg_id, tg_username, user.id))
        return self.by_id(user.id)

    def unlink_tg(self, user: User) -> None:
        if not user.has_password:
            raise AccountError("no_password")
        self.con.execute("UPDATE users SET tg_id = NULL WHERE id = ?", (user.id,))

    # ---- профиль и пароль (API `PATCH /me`, `PUT /me/password`) ----

    async def set_password(self, user: User, new_password: str, old_password: str | None = None) -> None:
        """AccountError('password_short' | 'bad_password'). Старый нужен, только если пароль уже был."""
        if len(new_password) < PASSWORD_MIN:
            raise AccountError("password_short")
        if user.has_password:
            r = self.con.execute("SELECT password_hash FROM users WHERE id = ?", (user.id,)).fetchone()
            if not old_password or not await check_password(r["password_hash"] or _DUMMY_HASH, old_password):
                raise AccountError("bad_password")
        h = await hash_password(new_password)
        self.con.execute("UPDATE users SET password_hash = ? WHERE id = ?", (h, user.id))

    def update_profile(self, user: User, username: str | None = None, display_name: str | None = None) -> User:
        """@username — по правилам логина, свободный (среди чужих логинов и ников); имя — 1…48 символов.

        AccountError('login_format' | 'login_taken' | 'name_format'). Логин не меняется (только админ).
        """
        with tx(self.con):
            if username is not None:
                username = username.strip().lstrip("@").lower()
                if not LOGIN_RE.match(username):
                    raise AccountError("login_format")
                if self.con.execute("SELECT 1 FROM users WHERE (login = ? OR username = ?) AND id != ?",
                                    (username, username, user.id)).fetchone():
                    raise AccountError("login_taken")
                try:
                    self.con.execute("UPDATE users SET username = ? WHERE id = ?", (username, user.id))
                except sqlite3.IntegrityError:  # заняли между проверкой и записью
                    raise AccountError("login_taken") from None
            if display_name is not None:
                display_name = " ".join(display_name.split())
                if not 1 <= len(display_name) <= DISPLAY_NAME_MAX:
                    raise AccountError("name_format")
                self.con.execute("UPDATE users SET display_name = ? WHERE id = ?", (display_name, user.id))
        return self.by_id(user.id)

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
        return users_count(self.con)

    def listeners_24h(self) -> int:
        return listeners_24h(self.con)

    def listening_now(self) -> int:
        return listening_now(self.con)
