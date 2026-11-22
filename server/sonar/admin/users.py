"""Пользователи в админке: список с поиском и фильтрами, карточка, действия (бан, логин, подписка)."""
from __future__ import annotations

import csv
import io
import json
import sqlite3

from ..accounts import LOGIN_RE
from ..db import now_ms
from .. import subs

PAGE = 50
AUDIT_PAGE = 100
SORTS = {"new": "u.created_at DESC", "old": "u.created_at ASC", "seen": "last_seen DESC", "number": "u.number ASC"}
FILTERS = {"all", "banned", "subscribed", "no_sub", "tg", "no_tg", "active7"}


class UserError(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def audit(con: sqlite3.Connection, admin: str, action: str, target: str | None = None, **detail) -> None:
    con.execute("INSERT INTO admin_audit (at, admin, action, target, detail) VALUES (?,?,?,?,?)",
                (now_ms(), admin, action, target, json.dumps(detail, ensure_ascii=False) if detail else None))


FAILED_LOGIN_CAP = 200  # записей о неудачных входах за час — дальше не пишем, чтобы перебор не раздул базу
HOUR_MS = 60 * 60 * 1000


def login_failed(con: sqlite3.Connection, login: str, ip: str, reason: str, now: int | None = None) -> bool:
    """Записать неудачный или заблокированный вход в журнал. → False, если за час их уже слишком много."""
    now = now or now_ms()
    recent = con.execute("SELECT COUNT(*) FROM admin_audit WHERE action = 'login_failed' AND at >= ?",
                         (now - HOUR_MS,)).fetchone()[0]
    if recent >= FAILED_LOGIN_CAP:
        return False
    audit(con, "—", "login_failed", None, login=login.strip()[:64], ip=ip, reason=reason)
    return True


def listing(con: sqlite3.Connection, q: str = "", flt: str = "all", sort: str = "new", page: int = 1,
            now: int | None = None) -> tuple[list[dict], int]:
    """→ (строки страницы, всего найдено). Поиск — логин, @username, #номер, Telegram (id или ник)."""
    now = now or now_ms()
    where, args = ["1"], []
    q = q.strip()
    if q:
        if q.startswith("#") and q[1:].isdigit():
            where.append("u.number = ?")
            args.append(int(q[1:]))
        elif q.lstrip("-").isdigit():
            where.append("(u.tg_id = ? OR u.number = ?)")
            args += [int(q), int(q)]
        else:
            like = "%" + q.lstrip("@").replace("%", r"\%").replace("_", r"\_") + "%"
            where.append(r"(u.login LIKE ? ESCAPE '\' OR u.username LIKE ? ESCAPE '\' OR u.tg_username LIKE ? ESCAPE '\'"
                         r" OR u.display_name LIKE ? ESCAPE '\')")
            args += [like] * 4
    if flt == "banned":
        where.append("u.banned = 1")
    elif flt == "tg":
        where.append("u.tg_id IS NOT NULL")
    elif flt == "no_tg":
        where.append("u.tg_id IS NULL")
    elif flt == "subscribed":
        where.append("sub_end IS NOT NULL")
    elif flt == "no_sub":
        where.append("sub_end IS NULL")
    elif flt == "active7":
        where.append("last_seen >= ?")
        args.append(now - 7 * subs.DAY_MS)
    base = (
        "SELECT u.id, u.number, u.login, u.username, u.display_name, u.tg_id, u.tg_username, u.banned, u.created_at,"
        " MAX(COALESCE((SELECT MAX(at) FROM events e WHERE e.user_id = u.id), 0),"
        "     COALESCE((SELECT MAX(last_seen_at) FROM sessions s WHERE s.user_id = u.id), 0)) AS last_seen,"
        " (SELECT MAX(ends_at) FROM subscriptions b WHERE b.user_id = u.id AND b.ends_at > :now"
        "   AND EXISTS (SELECT 1 FROM subscriptions c WHERE c.user_id = u.id AND c.started_at <= :now AND c.ends_at > :now)) AS sub_end,"
        " (SELECT plan FROM subscriptions c WHERE c.user_id = u.id AND c.started_at <= :now AND c.ends_at > :now"
        "   ORDER BY c.started_at DESC LIMIT 1) AS sub_plan"
        " FROM users u")
    # Подзапросы с именованным :now и позиционные ? не смешать — подставляем now числом (это наше значение, не ввод).
    base = base.replace(":now", str(int(now)))
    sql = f"SELECT * FROM ({base}) u WHERE {' AND '.join(where)}"
    total = con.execute(f"SELECT COUNT(*) FROM ({sql})", args).fetchone()[0]
    order = SORTS.get(sort, SORTS["new"]).replace("u.", "")
    rows = con.execute(f"{sql} ORDER BY {order} LIMIT ? OFFSET ?", args + [PAGE, (max(page, 1) - 1) * PAGE]).fetchall()
    return [dict(r) for r in rows], total


def card(con: sqlite3.Connection, user_id: str, now: int | None = None) -> dict | None:
    now = now or now_ms()
    u = con.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    if u is None:
        return None
    one = lambda sql, *a: con.execute(sql, a).fetchone()  # noqa: E731
    month = now - 30 * subs.DAY_MS
    stats = {
        "plays_total": one("SELECT COUNT(*) AS n FROM events WHERE user_id = ? AND kind = 'play'", user_id)["n"],
        "plays_30d": one("SELECT COUNT(*) AS n FROM events WHERE user_id = ? AND kind = 'play' AND at >= ?", user_id, month)["n"],
        "days_30d": one("SELECT COUNT(DISTINCT day) AS n FROM events WHERE user_id = ? AND at >= ?", user_id, month)["n"],
        "listen_days_30d": one("SELECT COUNT(DISTINCT day) AS n FROM events WHERE user_id = ? AND kind = 'play' AND at >= ?",
                               user_id, month)["n"],
        "minutes_total": one("SELECT COALESCE(SUM(listened_ms), 0) / 60000 AS n FROM plays WHERE user_id = ?", user_id)["n"],
        "first_at": one("SELECT MIN(at) AS n FROM events WHERE user_id = ?", user_id)["n"],
        "last_at": one("SELECT MAX(at) AS n FROM events WHERE user_id = ?", user_id)["n"],
    }
    services = [dict(r) for r in con.execute(
        "SELECT service, COUNT(*) AS plays FROM events WHERE user_id = ? AND kind = 'play' GROUP BY service ORDER BY plays DESC",
        (user_id,))]
    artists = [dict(r) for r in con.execute(
        "SELECT MAX(artist) AS artist, COUNT(*) AS plays FROM events WHERE user_id = ? AND kind = 'play' AND artist IS NOT NULL"
        " GROUP BY lower(artist) ORDER BY plays DESC LIMIT 5", (user_id,))]
    devices = [dict(r) for r in con.execute(
        "SELECT device_id, device_name, platform, os, app_version, build, created_at, last_seen_at FROM sessions"
        " WHERE user_id = ? ORDER BY last_seen_at DESC", (user_id,))]
    known = {d["device_id"] for d in devices}
    # Устройства, что слали события, но сессии уже нет (вышли) — тоже показываем, без имени.
    for r in con.execute("SELECT device_id, platform, MAX(at) AS last FROM events WHERE user_id = ? GROUP BY device_id",
                         (user_id,)):
        if r["device_id"] not in known:
            devices.append({"device_id": r["device_id"], "device_name": None, "platform": r["platform"], "os": None,
                            "app_version": None, "build": None, "created_at": None, "last_seen_at": r["last"]})
    linked = [dict(r) for r in con.execute("SELECT service, ext_name, connected_at FROM service_accounts WHERE user_id = ?",
                                            (user_id,))]
    journal = [dict(r) for r in con.execute(
        "SELECT at, admin, action, detail FROM admin_audit WHERE target = ? ORDER BY at DESC LIMIT 30", (user_id,))]
    return {"user": dict(u), "stats": stats, "services": services, "artists": artists, "devices": devices,
            "linked": linked, "sub": subs.active(con, user_id, now), "history": [dict(r) for r in subs.history(con, user_id)],
            "journal": journal}


def ban(con: sqlite3.Connection, admin: str, user_id: str, reason: str) -> None:
    reason = reason.strip()[:200] or None
    with con:
        n = con.execute("UPDATE users SET banned = 1, ban_reason = ?, banned_at = ? WHERE id = ? AND banned = 0",
                        (reason, now_ms(), user_id)).rowcount
        if not n:
            raise UserError("no_change")
        con.execute("DELETE FROM sessions WHERE user_id = ?", (user_id,))  # бан выкидывает со всех устройств
        audit(con, admin, "ban", user_id, reason=reason)


def unban(con: sqlite3.Connection, admin: str, user_id: str) -> None:
    with con:
        if not con.execute("UPDATE users SET banned = 0, ban_reason = NULL, banned_at = NULL WHERE id = ? AND banned = 1",
                           (user_id,)).rowcount:
            raise UserError("no_change")
        audit(con, admin, "unban", user_id)


def set_login(con: sqlite3.Connection, admin: str, user_id: str, login: str) -> None:
    """Сменить логин может только админ (TZ §4.16). @username не трогаем."""
    login = login.strip().lstrip("@").lower()
    if not LOGIN_RE.match(login):
        raise UserError("login_format")
    old = con.execute("SELECT login FROM users WHERE id = ?", (user_id,)).fetchone()
    if old is None:
        raise UserError("no_user")
    if old["login"].lower() == login:
        raise UserError("no_change")
    if con.execute("SELECT 1 FROM users WHERE (login = ? OR username = ?) AND id != ?", (login, login, user_id)).fetchone():
        raise UserError("login_taken")
    with con:
        con.execute("UPDATE users SET login = ? WHERE id = ?", (login, user_id))
        audit(con, admin, "set_login", user_id, old=old["login"], new=login)


def grant_sub(con: sqlite3.Connection, admin: str, user_id: str, plan: str, days: int, amount: int, note: str) -> None:
    if con.execute("SELECT 1 FROM users WHERE id = ?", (user_id,)).fetchone() is None:
        raise UserError("no_user")
    try:
        with con:
            subs.grant(con, user_id, plan, days, amount, note=note.strip()[:200] or None)
            audit(con, admin, "grant_sub", user_id, plan=plan, days=days, amount=amount)
    except subs.SubError as e:
        raise UserError(e.code) from None


def end_device(con: sqlite3.Connection, admin: str, user_id: str, device_id: str) -> None:
    """Завершить сессию одного устройства (ADMIN.md §4): там нужно войти заново, остальные не трогаем."""
    with con:
        if not con.execute("DELETE FROM sessions WHERE user_id = ? AND device_id = ?", (user_id, device_id)).rowcount:
            raise UserError("no_change")
        audit(con, admin, "end_device", user_id, device=device_id[:64])


def logout_all(con: sqlite3.Connection, admin: str, user_id: str) -> None:
    """Выйти на всех устройствах без бана (ADMIN.md §3) — например, если у человека увели телефон."""
    with con:
        n = con.execute("DELETE FROM sessions WHERE user_id = ?", (user_id,)).rowcount
        if not n:
            raise UserError("no_change")
        audit(con, admin, "logout_all", user_id, sessions=n)


def audit_page(con: sqlite3.Connection, action: str | None, page: int) -> tuple[list[dict], int]:
    """Журнал админки страницами, по желанию — одно действие. → (строки, всего)."""
    where, args = ("WHERE a.action = ?", [action]) if action else ("", [])
    total = con.execute(f"SELECT COUNT(*) FROM admin_audit a {where}", args).fetchone()[0]
    rows = con.execute(
        f"SELECT a.*, u.login AS user_login FROM admin_audit a LEFT JOIN users u ON u.id = a.target {where}"
        " ORDER BY a.at DESC, a.id DESC LIMIT ? OFFSET ?", args + [AUDIT_PAGE, (max(page, 1) - 1) * AUDIT_PAGE]).fetchall()
    return [dict(r) for r in rows], total


AUDIT_CSV_MAX = 50_000
CSV_HEADER = ("at", "admin", "action", "user_id", "user_login", "detail")


def csv_cell(value) -> str:
    """Ячейка CSV без формул: Excel и Таблицы исполняют «=…», «+…», «-…», «@…» — прячем апострофом."""
    text = "" if value is None else str(value)
    return "'" + text if text[:1] in ("=", "+", "-", "@", "\t", "\r") else text


def audit_csv(con: sqlite3.Connection, action: str | None, fmt_at) -> str:
    """Журнал целиком (до AUDIT_CSV_MAX строк, новые сверху) одной строкой CSV."""
    where, args = ("WHERE a.action = ?", [action]) if action else ("", [])
    rows = con.execute(
        f"SELECT a.at, a.admin, a.action, a.target, u.login AS user_login, a.detail FROM admin_audit a"
        f" LEFT JOIN users u ON u.id = a.target {where} ORDER BY a.at DESC, a.id DESC LIMIT ?",
        args + [AUDIT_CSV_MAX]).fetchall()
    out = io.StringIO()
    w = csv.writer(out)
    w.writerow(CSV_HEADER)
    for r in rows:
        w.writerow([csv_cell(fmt_at(r["at"])), csv_cell(r["admin"]), csv_cell(r["action"]), csv_cell(r["target"]),
                    csv_cell(r["user_login"]), csv_cell(r["detail"])])
    return out.getvalue()
