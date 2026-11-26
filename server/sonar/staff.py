"""Помощники владельца: права на админку, обновление сервера и модерацию (ADMIN.md «Доступ», BOT.md §2.12з).

Права выдаёт только владелец (заводской админ `folzy` в админке) по аккаунту Sonar, хранятся в `staff`:
    panel       вход в админку: дашборд, пользователи, журнал; вход — логин аккаунта, пароль одноразовый
    server      `/update` в боте и страница «Сервер»
    moderation  `/who /ban /unban /rban /runban /banned` в боте и бан, обращения, выход с устройств в админке
Владелец (`SONAR_OWNER_TG_ID` в боте, админ без `user_id` в админке) может всё. Заблокированный помощник прав не имеет.
"""
from __future__ import annotations

import sqlite3

from . import bans
from .admin.users import audit
from .db import now_ms, tx

PERMS = ("panel", "server", "moderation")
PERM_NAMES = {"panel": "Админка", "server": "Сервер", "moderation": "Модерация"}
OWNER = "owner"                     # не выдаётся: только у владельца
OWNER_PERMS = frozenset(PERMS) | {OWNER}
NONE: frozenset[str] = frozenset()


class StaffError(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def _parse(text: str | None) -> frozenset[str]:
    return frozenset(p for p in (text or "").split(",") if p in PERMS)


def _pack(perms) -> str:
    return ",".join(p for p in PERMS if p in perms)


def stored_perms(con: sqlite3.Connection, user_id: str) -> frozenset[str]:
    """Что записано в `staff`, без учёта бана — для правки прав."""
    r = con.execute("SELECT perms FROM staff WHERE user_id = ?", (user_id,)).fetchone()
    return _parse(r["perms"]) if r else NONE


def perms_of_user(con: sqlite3.Connection, user_id: str) -> frozenset[str]:
    """Действующие права: заблокированный помощник не может ничего."""
    perms = stored_perms(con, user_id)
    return perms if perms and bans.of_user(con, user_id) is None else NONE


def perms_by_tg(con: sqlite3.Connection, tg_id: int) -> frozenset[str]:
    r = con.execute("SELECT id FROM users WHERE tg_id = ?", (tg_id,)).fetchone()
    return perms_of_user(con, r["id"]) if r else NONE


def admin_perms(con: sqlite3.Connection, user_id: str | None) -> frozenset[str]:
    """Права админа по его `admins.user_id`: NULL — владелец (заводской или созданный из консоли)."""
    if user_id is None:
        return OWNER_PERMS
    perms = perms_of_user(con, user_id)
    return perms if "panel" in perms else NONE


def allowed(ctx, tg_id: int, perm: str) -> bool:
    """Бот: владелец может всё, помощник — то, что ему выдали (по привязанному Telegram)."""
    return ctx.is_owner(tg_id) or perm in perms_by_tg(ctx.accounts.con, tg_id)


def find(con: sqlite3.Connection, query: str) -> sqlite3.Row | None:
    """Пользователь по id аккаунта (`u_…`), `#номеру`, логину, `@username` или Telegram ID."""
    q = (query or "").strip()[:64]
    return con.execute("SELECT * FROM users WHERE id = ?", (q,)).fetchone() or bans.find(con, q)


def listing(con: sqlite3.Connection) -> list[dict]:
    rows = con.execute("SELECT s.*, u.login, u.number, u.display_name, u.tg_id, u.banned, a.login AS admin_login"
                       " FROM staff s JOIN users u ON u.id = s.user_id LEFT JOIN admins a ON a.user_id = s.user_id"
                       " ORDER BY s.granted_at DESC").fetchall()
    return [dict(r, perms=_parse(r["perms"])) for r in rows]


def grant(con: sqlite3.Connection, auth, who: str, user: sqlite3.Row, perms, owner_tg_id: int | None) -> str | None:
    """Поставить помощнику ровно эти права (пусто — забрать всё). `auth` — AdminAuth: заводит и удаляет вход в админку.
    → одноразовый пароль, если вход в админку только что создан (показать владельцу один раз), иначе None.
    StaffError: owner — это аккаунт владельца, admin_login_taken — логин занят другим админом."""
    new = frozenset(p for p in perms if p in PERMS)
    if owner_tg_id and user["tg_id"] == owner_tg_id:
        raise StaffError("owner")
    old = stored_perms(con, user["id"])
    if new == old:
        raise StaffError("no_change")
    taken = con.execute("SELECT user_id FROM admins WHERE login = ?", (user["login"],)).fetchone()
    if "panel" in new and taken is not None and taken["user_id"] != user["id"]:
        raise StaffError("admin_login_taken")
    if not new:
        revoke(con, auth, who, user)
        return None
    password = None
    with tx(con):
        con.execute("INSERT INTO staff (user_id, perms, granted_at, granted_by) VALUES (?,?,?,?)"
                    " ON CONFLICT(user_id) DO UPDATE SET perms = excluded.perms, granted_at = excluded.granted_at,"
                    " granted_by = excluded.granted_by", (user["id"], _pack(new), now_ms(), who))
        if "panel" in new and "panel" not in old:
            password = auth.add_staff(user["login"], user["id"])
        elif "panel" in old and "panel" not in new:
            auth.drop_staff(user["id"])
        audit(con, who, "grant_staff", user["id"], login=user["login"], before=_pack(old), after=_pack(new))
    return password


def revoke(con: sqlite3.Connection, auth, who: str, user: sqlite3.Row) -> None:
    old = stored_perms(con, user["id"])
    if not old:
        raise StaffError("no_change")
    with tx(con):
        con.execute("DELETE FROM staff WHERE user_id = ?", (user["id"],))
        auth.drop_staff(user["id"])
        audit(con, who, "revoke_staff", user["id"], login=user["login"], before=_pack(old))
