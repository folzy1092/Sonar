"""Подписка Sonar Deep на сервере: периоды, выдача и продление (вручную из админки, потом — платёжкой).

Тарифы и цены — зеркало `windows/src/lib/subscription.ts` (помесячно, ₽). Один период — одна строка
`subscriptions`; продление начинается с конца текущего периода, поэтому дни не теряются.
"""
from __future__ import annotations

import sqlite3
from dataclasses import dataclass

from .db import now_ms

DAY_MS = 86400_000
MONTH_DAYS = 30
PLANS = {"ping": ("Ping", 1, 100), "echo": ("Echo", 2, 190), "pod": ("Pod", 3, 285), "fleet": ("Fleet", 4, 380)}
PLAN_ORDER = list(PLANS)


class SubError(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


@dataclass
class Active:
    plan: str
    ends_at: int


def active(con: sqlite3.Connection, user_id: str, now: int | None = None) -> Active | None:
    """Действующая подписка: тариф — у периода, что идёт сейчас, конец — у последнего подряд идущего."""
    now = now or now_ms()
    cur = con.execute("SELECT plan, ends_at FROM subscriptions WHERE user_id = ? AND started_at <= ? AND ends_at > ?"
                      " ORDER BY started_at DESC LIMIT 1", (user_id, now, now)).fetchone()
    if cur is None:
        return None
    end = con.execute("SELECT MAX(ends_at) AS e FROM subscriptions WHERE user_id = ? AND ends_at > ?",
                      (user_id, now)).fetchone()["e"]
    return Active(cur["plan"], end)


def grant(con: sqlite3.Connection, user_id: str, plan: str, days: int, amount: int = 0, source: str = "manual",
          note: str | None = None, now: int | None = None) -> int:
    """Выдать или продлить. kind: new — первая подписка у человека, renew — была раньше. Вернёт id строки."""
    if plan not in PLANS:
        raise SubError("bad_plan")
    if not 1 <= days <= 3660:
        raise SubError("bad_days")
    if amount < 0:
        raise SubError("bad_amount")
    now = now or now_ms()
    last = con.execute("SELECT MAX(ends_at) AS e, COUNT(*) AS n FROM subscriptions WHERE user_id = ?", (user_id,)).fetchone()
    start = max(now, last["e"] or 0)
    kind = "renew" if last["n"] else "new"
    cur = con.execute("INSERT INTO subscriptions (user_id, plan, kind, source, started_at, ends_at, amount, note, created_at)"
                      " VALUES (?,?,?,?,?,?,?,?,?)",
                      (user_id, plan, kind, source, start, start + days * DAY_MS, amount, note, now))
    return cur.lastrowid


def history(con: sqlite3.Connection, user_id: str) -> list[sqlite3.Row]:
    return con.execute("SELECT * FROM subscriptions WHERE user_id = ? ORDER BY started_at DESC", (user_id,)).fetchall()
