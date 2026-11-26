"""Блокировки: аккаунта (на срок или навсегда) и обращений «Баг / Идея» — одно место для бота, админки и API.

Бан аккаунта — `users.banned` + `ban_reason` + `banned_at` + `ban_until` (NULL — навсегда). Сессии при бане **не стираются**:
API отвечает на них `403 account_banned` с причиной и сроком, и приложение выходит само и показывает «учётная запись
заблокирована» (раньше сессии удалялись, и клиент видел обычный 401). Временный бан снимает `expire()` — раз в минуту и
при входе, потому что остальной код смотрит просто на `banned = 0`.

Блок обращений — таблица `support_blocks (tg_id, reason, until)`, по Telegram ID: репорты принимает бот, и писать могут
и те, кто без аккаунта. Срок: NULL / 0 — навсегда.
"""
from __future__ import annotations

import json
import re
import sqlite3
from dataclasses import dataclass
from datetime import datetime

from .db import now_ms, tx

MINUTE, HOUR, DAY = 60_000, 3_600_000, 86_400_000
FOREVER = {"perm", "forever", "inf", "навсегда", "вечно", "насовсем"}
# Единица — только слово из списка: иначе «7д» + «спамит» склеилось бы в «7дспамит» и съело слово причины.
DURATION_RE = re.compile(r"^(\d{1,5})\s*(m|min|mins|minute|minutes|м|мин|минута|минуты|минут|h|hr|hrs|hour|hours|ч|час|часа|часов|"
                         r"d|day|days|д|дн|день|дня|дней|w|wk|week|weeks|н|нед|неделя|недели|недель)$")
# Единица по первой букве: m / м — минуты, h / ч — часы, d / д — дни, w / н — недели («мин», «час», «дн», «нед» тоже).
UNIT_MS = {"m": MINUTE, "м": MINUTE, "h": HOUR, "ч": HOUR, "d": DAY, "д": DAY, "w": 7 * DAY, "н": 7 * DAY}
REASON_MAX = 200


class ModerationError(Exception):
    """`code` — ключ короткого текста для бота и админки."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


@dataclass(frozen=True)
class Ban:
    reason: str | None
    until: int | None      # мс; None — навсегда
    since: int | None

    @property
    def forever(self) -> bool:
        return self.until is None


def parse_duration(token: str) -> tuple[bool, int | None]:
    """«30m» «2ч» «3д» «1w» «навсегда» → (True, длительность мс или None для «навсегда»); не срок — (False, None)."""
    t = token.strip().lower()
    if t in FOREVER:
        return True, None
    m = DURATION_RE.match(t)
    if not m:
        return False, None
    ms = int(m.group(1)) * UNIT_MS[m.group(2)[0]]
    return (True, ms) if ms > 0 else (False, None)


def split_args(text: str | None) -> tuple[str, int | None, str]:
    """«кто [срок] [причина…]» → (кто, длительность мс или None, причина). Срок не указан — навсегда.
    Срок бывает одним словом («7д», «навсегда») или двумя («7 дней»): иначе «7 дней спам» стало бы вечным баном."""
    parts = (text or "").split()
    if not parts:
        return "", None, ""
    who, rest = parts[0], parts[1:]
    for take in (2, 1):
        if len(rest) >= take:
            ok, ms = parse_duration("".join(rest[:take]))
            if ok:
                return who, ms, " ".join(rest[take:])[:REASON_MAX].strip()
    return who, None, " ".join(rest)[:REASON_MAX].strip()


def until_from(duration_ms: int | None, now: int | None = None) -> int | None:
    return None if duration_ms is None else (now or now_ms()) + duration_ms


def describe(until: int | None, tz=None) -> str:
    """«навсегда» или «до 27.11.2026 14:05»."""
    if until is None:
        return "навсегда"
    return "до " + datetime.fromtimestamp(until / 1000, tz).strftime("%d.%m.%Y %H:%M")


def message(b: Ban, tz=None) -> str:
    """Текст для API и клиентов; приложение показывает свой перевод, а причину и срок берёт из полей ответа."""
    text = "Учётная запись заблокирована " + describe(b.until, tz)
    return text + (f". Причина: {b.reason}" if b.reason else "")


# ---- аккаунт ----

def expire(con: sqlite3.Connection, now: int | None = None) -> list[str]:
    """Снять бан, срок которого вышел. → id разбаненных."""
    now = now or now_ms()
    ids = [r["id"] for r in con.execute("SELECT id FROM users WHERE banned = 1 AND ban_until IS NOT NULL AND ban_until <= ?",
                                        (now,))]
    for uid in ids:
        con.execute("UPDATE users SET banned = 0, ban_reason = NULL, banned_at = NULL, ban_until = NULL WHERE id = ?", (uid,))
        con.execute("INSERT INTO admin_audit (at, admin, action, target) VALUES (?,?,?,?)", (now, "system", "ban_expired", uid))
    return ids


def _ban(row: sqlite3.Row | None) -> Ban | None:
    if row is None or not row["banned"]:
        return None
    return Ban(row["ban_reason"], row["ban_until"], row["banned_at"])


def of_user(con: sqlite3.Connection, user_id: str) -> Ban | None:
    expire(con)
    return _ban(con.execute("SELECT banned, ban_reason, ban_until, banned_at FROM users WHERE id = ?", (user_id,)).fetchone())


def of_tg(con: sqlite3.Connection, tg_id: int) -> Ban | None:
    expire(con)
    return _ban(con.execute("SELECT banned, ban_reason, ban_until, banned_at FROM users WHERE tg_id = ?", (tg_id,)).fetchone())


def of_token(con: sqlite3.Connection, token_hash: str) -> Ban | None:
    """Сессия есть, а аккаунт заблокирован → причина и срок (`sessions._h(token)`)."""
    expire(con)
    return _ban(con.execute("SELECT u.banned, u.ban_reason, u.ban_until, u.banned_at FROM sessions s JOIN users u"
                            " ON u.id = s.user_id WHERE s.token_hash = ?", (token_hash,)).fetchone())


def of_device(con: sqlite3.Connection, device_id: str) -> Ban | None:
    """Устройство, с которого входил заблокированный: с него нельзя заводить новые аккаунты в обход бана."""
    expire(con)
    return _ban(con.execute("SELECT u.banned, u.ban_reason, u.ban_until, u.banned_at FROM sessions s JOIN users u"
                            " ON u.id = s.user_id WHERE s.device_id = ? AND u.banned = 1 LIMIT 1", (device_id,)).fetchone())


def ban(con: sqlite3.Connection, admin: str, user_id: str, reason: str = "", until: int | None = None) -> None:
    """Заблокировать. Сессии остаются — приложение получит `account_banned` и выйдет с объяснением."""
    reason = (reason or "").strip()[:REASON_MAX] or None
    with tx(con):
        row = con.execute("SELECT banned FROM users WHERE id = ?", (user_id,)).fetchone()
        if row is None:
            raise ModerationError("no_user")
        # Повторный бан меняет срок и причину: «навсегда» вместо «на день» — обычное дело.
        con.execute("UPDATE users SET banned = 1, ban_reason = ?, banned_at = ?, ban_until = ? WHERE id = ?",
                    (reason, now_ms(), until, user_id))
        con.execute("INSERT INTO admin_audit (at, admin, action, target, detail) VALUES (?,?,?,?,?)",
                    (now_ms(), admin, "ban", user_id, _detail(reason, until)))


def unban(con: sqlite3.Connection, admin: str, user_id: str) -> None:
    with tx(con):
        if not con.execute("UPDATE users SET banned = 0, ban_reason = NULL, banned_at = NULL, ban_until = NULL"
                           " WHERE id = ? AND banned = 1", (user_id,)).rowcount:
            raise ModerationError("no_change")
        con.execute("INSERT INTO admin_audit (at, admin, action, target) VALUES (?,?,?,?)",
                    (now_ms(), admin, "unban", user_id))


def _detail(reason: str | None, until: int | None) -> str:
    return json.dumps({"reason": reason, "until": until}, ensure_ascii=False)


# ---- обращения (баг / идея) ----

def report_block_of(con: sqlite3.Connection, tg_id: int) -> Ban | None:
    r = con.execute("SELECT reason, until FROM support_blocks WHERE tg_id = ?", (tg_id,)).fetchone()
    if r is None:
        return None
    until = r["until"] or None          # 0 и NULL — навсегда
    if until is not None and until <= now_ms():
        con.execute("DELETE FROM support_blocks WHERE tg_id = ?", (tg_id,))
        return None
    return Ban(r["reason"], until, None)


def report_block(con: sqlite3.Connection, admin: str, tg_id: int, reason: str = "", until: int | None = None) -> None:
    reason = (reason or "").strip()[:REASON_MAX] or None
    with tx(con):
        con.execute("INSERT INTO support_blocks (tg_id, reason, until) VALUES (?,?,?)"
                    " ON CONFLICT(tg_id) DO UPDATE SET reason = excluded.reason, until = excluded.until",
                    (tg_id, reason, until))
        con.execute("INSERT INTO admin_audit (at, admin, action, target, detail) VALUES (?,?,?,?,?)",
                    (now_ms(), admin, "report_block", str(tg_id), _detail(reason, until)))


def report_unblock(con: sqlite3.Connection, admin: str, tg_id: int) -> None:
    with tx(con):
        if not con.execute("DELETE FROM support_blocks WHERE tg_id = ?", (tg_id,)).rowcount:
            raise ModerationError("no_change")
        con.execute("INSERT INTO admin_audit (at, admin, action, target) VALUES (?,?,?,?)",
                    (now_ms(), admin, "report_unblock", str(tg_id)))


# ---- поиск ----

def find(con: sqlite3.Connection, query: str) -> sqlite3.Row | None:
    """Пользователь по логину, `@username`, `#номеру` или Telegram ID (в том числе заблокированный)."""
    q = (query or "").strip()
    if not q:
        return None
    if q.startswith("@"):
        return con.execute("SELECT * FROM users WHERE username = ?", (q[1:],)).fetchone()
    if q.startswith("#") and q[1:].isdigit():
        return con.execute("SELECT * FROM users WHERE number = ?", (int(q[1:]),)).fetchone()
    if q.isdigit():
        return (con.execute("SELECT * FROM users WHERE tg_id = ?", (int(q),)).fetchone()
                or con.execute("SELECT * FROM users WHERE number = ?", (int(q),)).fetchone())
    return (con.execute("SELECT * FROM users WHERE login = ?", (q.lower(),)).fetchone()
            or con.execute("SELECT * FROM users WHERE username = ?", (q,)).fetchone())


def banned_list(con: sqlite3.Connection, limit: int = 30) -> list[sqlite3.Row]:
    expire(con)
    return con.execute("SELECT id, login, username, tg_id, ban_reason, ban_until, banned_at FROM users WHERE banned = 1"
                       " ORDER BY banned_at DESC LIMIT ?", (limit,)).fetchall()


def report_blocks(con: sqlite3.Connection, limit: int = 30) -> list[sqlite3.Row]:
    now = now_ms()
    con.execute("DELETE FROM support_blocks WHERE until IS NOT NULL AND until > 0 AND until <= ?", (now,))
    return con.execute("SELECT b.tg_id, b.reason, b.until, u.login FROM support_blocks b LEFT JOIN users u ON u.tg_id = b.tg_id"
                       " ORDER BY b.rowid DESC LIMIT ?", (limit,)).fetchall()
