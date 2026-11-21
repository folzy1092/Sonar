"""Дашборд админки: всё в уникальных пользователях, считается запросами по индексам `events(kind, day, user_id)`.

«Открыл плеер» — любое событие за день (включил трек — значит, и открыл), «слушал» — хотя бы один play.
Пустая база даёт нули и пустые списки — шаблон показывает «нет данных», ничего не выдумываем.
"""
from __future__ import annotations

import sqlite3
from datetime import date, datetime, time, timedelta

from ..db import now_ms
from ..events import day_of, tz
from ..subs import DAY_MS, PLAN_ORDER

SERVICE_ORDER = ["soundcloud", "yandex", "youtube", "vk", "spotify", "local"]



def today(now: int | None = None) -> str:
    return day_of(now or now_ms())


def shift(day: str, n: int) -> str:
    return (date.fromisoformat(day) + timedelta(days=n)).isoformat()


def days_between(start: str, end: str) -> list[str]:
    a, b = date.fromisoformat(start), date.fromisoformat(end)
    return [(a + timedelta(days=i)).isoformat() for i in range((b - a).days + 1)]


def day_start_ms(day: str) -> int:
    return int(datetime.combine(date.fromisoformat(day), time(), tz()).timestamp() * 1000)


def _one(con, sql, args=()) -> int:
    return con.execute(sql, args).fetchone()[0] or 0


# ---- активность ----

def summary(con: sqlite3.Connection, start: str, end: str) -> dict:
    a = (start, end)
    openers = _one(con, "SELECT COUNT(DISTINCT user_id) FROM events WHERE day BETWEEN ? AND ?", a)
    listeners = _one(con, "SELECT COUNT(DISTINCT user_id) FROM events WHERE kind = 'play' AND day BETWEEN ? AND ?", a)
    plays = _one(con, "SELECT COUNT(*) FROM events WHERE kind = 'play' AND day BETWEEN ? AND ?", a)
    regs = _one(con, "SELECT COUNT(*) FROM users WHERE created_at >= ? AND created_at < ?",
                (day_start_ms(start), day_start_ms(shift(end, 1))))
    return {"openers": openers, "listeners": listeners, "idle": openers - listeners, "plays": plays,
            "per_listener": round(plays / listeners, 1) if listeners else None,
            "listen_share": round(listeners * 100 / openers) if openers else None, "registrations": regs}


def active(con: sqlite3.Connection, end: str) -> dict:
    q = "SELECT COUNT(DISTINCT user_id) FROM events WHERE day BETWEEN ? AND ?"
    dau, wau, mau = (_one(con, q, (shift(end, 1 - n), end)) for n in (1, 7, 30))
    return {"dau": dau, "wau": wau, "mau": mau, "stickiness": round(dau * 100 / mau) if mau else None}


def by_service(con: sqlite3.Connection, start: str, end: str) -> list[dict]:
    rows = {r["service"]: r for r in con.execute(
        "SELECT service, COUNT(DISTINCT user_id) AS users, COUNT(*) AS plays FROM events"
        " WHERE kind = 'play' AND day BETWEEN ? AND ? GROUP BY service", (start, end))}
    keys = SERVICE_ORDER + sorted(k for k in rows if k not in SERVICE_ORDER and k)
    out = [{"key": k, "users": rows[k]["users"] if k in rows else 0, "plays": rows[k]["plays"] if k in rows else 0}
           for k in keys if k != "local" or k in rows]
    if None in rows:
        out.append({"key": None, "users": rows[None]["users"], "plays": rows[None]["plays"]})
    return out


def by_platform(con: sqlite3.Connection, start: str, end: str) -> list[dict]:
    rows = {r["platform"]: r for r in con.execute(
        "SELECT platform, COUNT(DISTINCT user_id) AS users,"
        " COUNT(DISTINCT CASE WHEN kind = 'play' THEN user_id END) AS listeners,"
        " SUM(kind = 'play') AS plays FROM events WHERE day BETWEEN ? AND ? GROUP BY platform", (start, end))}
    keys = ["windows", "ios"] + sorted(k for k in rows if k not in ("windows", "ios"))
    out = []
    for k in keys:
        r = rows.get(k)
        out.append({"key": k, "users": r["users"] if r else 0, "listeners": r["listeners"] if r else 0,
                    "plays": r["plays"] if r else 0})
    return out


def series(con: sqlite3.Connection, start: str, end: str) -> list[dict]:
    """По дням: открыли, слушали, треков, регистраций, новых подписок. Пустые дни — нули."""
    days = days_between(start, end)
    out = {d: {"day": d, "openers": 0, "listeners": 0, "plays": 0, "registrations": 0, "subs": 0} for d in days}
    for r in con.execute(
            "SELECT day, COUNT(DISTINCT user_id) AS o, COUNT(DISTINCT CASE WHEN kind = 'play' THEN user_id END) AS l,"
            " SUM(kind = 'play') AS p FROM events WHERE day BETWEEN ? AND ? GROUP BY day", (start, end)):
        out[r["day"]].update(openers=r["o"], listeners=r["l"], plays=r["p"] or 0)
    lo, hi = day_start_ms(start), day_start_ms(shift(end, 1))
    # Регистраций и подписок — единицы в день, день по местному поясу считаем здесь (SQLite не знает переходов на летнее время).
    for r in con.execute("SELECT created_at FROM users WHERE created_at >= ? AND created_at < ?", (lo, hi)):
        d = day_of(r["created_at"])
        if d in out:
            out[d]["registrations"] += 1
    for r in con.execute("SELECT created_at FROM subscriptions WHERE created_at >= ? AND created_at < ?", (lo, hi)):
        d = day_of(r["created_at"])
        if d in out:
            out[d]["subs"] += 1
    return list(out.values())


def top_tracks(con: sqlite3.Connection, start: str, end: str, n: int = 10) -> list[dict]:
    return [dict(r) for r in con.execute(
        "SELECT ref, MAX(title) AS title, MAX(artist) AS artist, service, COUNT(DISTINCT user_id) AS users, COUNT(*) AS plays"
        " FROM events WHERE kind = 'play' AND day BETWEEN ? AND ? GROUP BY ref ORDER BY users DESC, plays DESC LIMIT ?",
        (start, end, n))]


def top_artists(con: sqlite3.Connection, start: str, end: str, n: int = 10) -> list[dict]:
    return [dict(r) for r in con.execute(
        "SELECT MAX(artist) AS artist, COUNT(DISTINCT user_id) AS users, COUNT(*) AS plays FROM events"
        " WHERE kind = 'play' AND day BETWEEN ? AND ? AND artist IS NOT NULL GROUP BY lower(artist)"
        " ORDER BY users DESC, plays DESC LIMIT ?", (start, end, n))]


# ---- подписки ----

def subscriptions(con: sqlite3.Connection, start: str, end: str, now: int | None = None) -> dict:
    now = now or now_ms()
    lo, hi = day_start_ms(start), day_start_ms(shift(end, 1))
    plans = {r["plan"]: r["n"] for r in con.execute(
        "SELECT plan, COUNT(DISTINCT user_id) AS n FROM subscriptions WHERE started_at <= ? AND ends_at > ? GROUP BY plan",
        (now, now))}
    kinds = {r["kind"]: r["n"] for r in con.execute(
        "SELECT kind, COUNT(DISTINCT user_id) AS n FROM subscriptions WHERE created_at >= ? AND created_at < ? GROUP BY kind",
        (lo, hi))}
    revenue = {r["currency"]: r["s"] for r in con.execute(
        "SELECT currency, SUM(amount) AS s FROM subscriptions WHERE created_at >= ? AND created_at < ? AND amount > 0"
        " GROUP BY currency", (lo, hi))}
    return {"active": sum(plans.values()), "by_plan": [{"plan": p, "users": plans.get(p, 0)} for p in PLAN_ORDER],
            "new": kinds.get("new", 0), "renew": kinds.get("renew", 0), "expiring_7d": expiring(con, 7, now),
            "revenue": revenue}


def expiring(con: sqlite3.Connection, days: int, now: int | None = None) -> int:
    """Сколько человек с действующей подпиской, у которых она кончится в ближайшие N дней (без уже оплаченного продления)."""
    now = now or now_ms()
    return _one(con, "SELECT COUNT(*) FROM (SELECT user_id, MAX(ends_at) AS e FROM subscriptions WHERE ends_at > ?"
                     " GROUP BY user_id HAVING e <= ?)", (now, now + days * DAY_MS))


def renew_rate(con: sqlite3.Connection, now: int | None = None, window_days: int = 90, grace_days: int = 7) -> tuple[int, int]:
    """(продлили, решали) за окно: период кончился за последние 90 дней, продление — новый период в течение 7 дней
    после конца. Кончившиеся меньше 7 дней назад и ещё не продлённые не считаем — человек ещё может продлить."""
    now = now or now_ms()
    grace = grace_days * DAY_MS
    r = con.execute(
        "SELECT SUM(renewed) AS renewed, COUNT(*) AS due FROM ("
        " SELECT s.ends_at, EXISTS (SELECT 1 FROM subscriptions n WHERE n.user_id = s.user_id AND n.id != s.id"
        "   AND n.started_at >= s.ends_at AND n.started_at <= s.ends_at + ?) AS renewed"
        " FROM subscriptions s WHERE s.ends_at >= ? AND s.ends_at < ?)"
        " WHERE renewed = 1 OR ends_at <= ?",
        (grace, now - window_days * DAY_MS, now, now - grace)).fetchone()
    return r["renewed"] or 0, r["due"] or 0


def forecast(con: sqlite3.Connection, now: int | None = None, horizon_days: int = 30) -> dict | None:
    """Оценка числа действующих подписок через 30 дней.

    оценка = (действуют сейчас − кончатся за 30 дней) + кончатся × доля продлений + новые за 30 дней.
    Новые — линейный тренд двух последних 30-дневок: 2·последние − прошлые (не меньше 0). Доля продлений —
    из прошлых 90 дней; если решать ещё было некому, берём 50 % и показываем вилку 0–100 %. None — данных нет.
    """
    now = now or now_ms()
    a = _one(con, "SELECT COUNT(DISTINCT user_id) FROM subscriptions WHERE started_at <= ? AND ends_at > ?", (now, now))
    e = expiring(con, horizon_days, now)
    span = horizon_days * DAY_MS
    q = "SELECT COUNT(DISTINCT user_id) FROM subscriptions WHERE kind = 'new' AND created_at >= ? AND created_at < ?"
    last, prev = _one(con, q, (now - span, now)), _one(con, q, (now - 2 * span, now - span))
    if a + last + prev == 0:
        return None
    renewed, due = renew_rate(con, now)
    rate = renewed / due if due else None
    new_next = max(0, 2 * last - prev)
    new_lo, new_hi = min(last, new_next), max(last, new_next)
    stay = a - e

    def est(r: float, new: float) -> int:
        return max(0, round(stay + e * r + new))

    if rate is None:
        estimate, low, high = est(0.5, new_next), est(0.0, new_lo), est(1.0, new_hi)
    else:
        estimate, low, high = est(rate, new_next), est(max(0.0, rate - 0.15), new_lo), est(min(1.0, rate + 0.15), new_hi)
    avg = con.execute("SELECT AVG(amount) AS a FROM subscriptions WHERE amount > 0 AND created_at >= ?",
                      (now - 90 * DAY_MS,)).fetchone()["a"]
    paying = e * (rate if rate is not None else 0.5) + new_next
    return {"active": a, "expiring": e, "renewed": renewed, "due": due,
            "renew_rate": round(rate * 100) if rate is not None else None, "new_last": last, "new_prev": prev,
            "new_next": new_next, "estimate": estimate, "low": low, "high": high, "horizon_days": horizon_days,
            "revenue": round(paying * avg) if avg else None}


def build(con: sqlite3.Connection, start: str, end: str, now: int | None = None) -> dict:
    now = now or now_ms()
    day = today(now)
    return {"start": start, "end": end, "today": day, "days": len(days_between(start, end)),
            "today_summary": summary(con, day, day), "period": summary(con, start, end), "active": active(con, end),
            "services": by_service(con, start, end), "platforms": by_platform(con, start, end),
            "series": series(con, start, end), "top_tracks": top_tracks(con, day, day),
            "top_artists": top_artists(con, day, day), "period_tracks": top_tracks(con, start, end),
            "subs": subscriptions(con, start, end, now), "forecast": forecast(con, now),
            "has_events": con.execute("SELECT 1 FROM events LIMIT 1").fetchone() is not None}
