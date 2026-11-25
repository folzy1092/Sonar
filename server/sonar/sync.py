"""Синхронизация устройств одного аккаунта (API.md §6). Та же логика, что у хаба ПК (`store/hub.rs`) и
`MemoryServer` (`sync.rs`): глобальный `rev`, повтор `op_id` не применяется дважды, настройки — «побеждает
позднее» по `client_ts` (проигравшая подтверждается, а победитель получает новый `rev` и приходит в `pull`
заново), остальное — последняя запись.

Сервер значения не разбирает: строка — `(тип, ключ) → JSON`, `null` — удалено. Так новые типы клиентов не
требуют правок сервера. Исключения — `/dotify` (пишет лайки сам) и прослушивания (`plays`, своя таблица).
"""
from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass, field

from .db import now_ms, tx

TYPES = frozenset({"like", "playlist", "playlist_item", "setting", "player_state", "track_pref", "dislike", "wave_event"})
PUSH_MAX = 500
VALUE_MAX = 64 * 1024        # одна строка; карточка трека с артистами — ~1 КБ
PULL_BUDGET = 1024 * 1024    # байт изменений за один pull, дальше — `more`
CHANGE_OVERHEAD = 64
OPS_TTL_MS = 30 * 86400_000  # op_id помним месяц: повтор после сбоя сети приходит за секунды, не за недели


class SyncError(ValueError):
    pass


@dataclass
class Op:
    op_id: str
    type: str
    key: str
    value: object
    client_ts: int


@dataclass
class Pull:
    rev: int
    changes: list[dict] = field(default_factory=list)
    more: bool = False


def parse_ops(raw) -> list[Op]:
    """Тело `POST /sync/push` → операции. SyncError — текст для 400."""
    ops = raw.get("ops") if isinstance(raw, dict) else None
    if not isinstance(ops, list):
        raise SyncError("Нужно поле ops — список")
    if len(ops) > PUSH_MAX:
        raise SyncError(f"Не больше {PUSH_MAX} операций за раз")
    out = []
    for o in ops:
        if not isinstance(o, dict):
            raise SyncError("Операция — объект")
        op_id, kind, key, ts = o.get("op_id"), o.get("type"), o.get("key"), o.get("client_ts")
        if not isinstance(op_id, str) or not 1 <= len(op_id) <= 200:
            raise SyncError("op_id — строка до 200 символов")
        if kind not in TYPES:
            raise SyncError(f"Неизвестный type: {str(kind)[:40]}")
        if not isinstance(key, str) or not 1 <= len(key) <= 200:
            raise SyncError("key — строка до 200 символов")
        if not isinstance(ts, int) or isinstance(ts, bool):
            raise SyncError("client_ts — целое (мс)")
        value = o.get("value")
        if value is not None and len(json.dumps(value, ensure_ascii=False)) > VALUE_MAX:
            raise SyncError(f"Значение {kind}:{key[:40]} больше 64 КБ")
        out.append(Op(op_id, kind, key, value, ts))
    return out


def next_rev(con: sqlite3.Connection) -> int:
    return con.execute("UPDATE sync_rev SET value = value + 1 WHERE id = 1 RETURNING value").fetchone()[0]


def current_rev(con: sqlite3.Connection) -> int:
    return con.execute("SELECT value FROM sync_rev WHERE id = 1").fetchone()[0]


def put(con: sqlite3.Connection, user_id: str, kind: str, key: str, value, client_ts: int) -> int:
    """Записать строку с новым rev (без проверки op_id) — для серверных записей (`/dotify`)."""
    rev = next_rev(con)
    con.execute("INSERT INTO sync_rows (user_id, type, key, value_json, rev, client_ts) VALUES (?,?,?,?,?,?)"
                " ON CONFLICT(user_id, type, key) DO UPDATE SET value_json = excluded.value_json, rev = excluded.rev,"
                " client_ts = excluded.client_ts",
                (user_id, kind, key, None if value is None else json.dumps(value, ensure_ascii=False), rev, client_ts))
    return rev


def push(con: sqlite3.Connection, user_id: str, ops: list[Op]) -> tuple[int, list[str]]:
    """→ (rev, applied): подтверждаются все op_id — и новые, и повторы, и проигравшие настройки."""
    applied = []
    now = now_ms()
    with tx(con):
        for o in ops:
            fresh = con.execute("INSERT OR IGNORE INTO sync_ops (user_id, op_id, at) VALUES (?,?,?)",
                                (user_id, o.op_id, now)).rowcount == 1
            if fresh:
                row = con.execute("SELECT client_ts FROM sync_rows WHERE user_id = ? AND type = ? AND key = ?",
                                  (user_id, o.type, o.key)).fetchone()
                if o.type == "setting" and row is not None and row["client_ts"] > o.client_ts:
                    # проигравший мог уже забрать победителя раньше — поднимаем rev, чтобы пришёл заново
                    con.execute("UPDATE sync_rows SET rev = ? WHERE user_id = ? AND type = ? AND key = ?",
                                (next_rev(con), user_id, o.type, o.key))
                else:
                    put(con, user_id, o.type, o.key, o.value, o.client_ts)
            applied.append(o.op_id)
        con.execute("DELETE FROM sync_ops WHERE user_id = ? AND at < ?", (user_id, now - OPS_TTL_MS))
    return current_rev(con), applied


def pull(con: sqlite3.Connection, user_id: str, since: int, budget: int = PULL_BUDGET) -> Pull:
    """Изменения после since по возрастанию rev, пока влезают в budget (хотя бы одно). `more` — просить ещё."""
    out = Pull(rev=since)
    used = 0
    for r in con.execute("SELECT type, key, value_json, rev FROM sync_rows WHERE user_id = ? AND rev > ? ORDER BY rev",
                         (user_id, since)):
        size = len(r["value_json"] or "null") + CHANGE_OVERHEAD
        if out.changes and used + size > budget:
            out.more = True
            break
        used += size
        out.changes.append({"type": r["type"], "key": r["key"],
                            "value": None if r["value_json"] is None else json.loads(r["value_json"]), "rev": r["rev"]})
        out.rev = r["rev"]
    if not out.more:
        out.rev = max(out.rev, current_rev(con))
    return out


def snapshot(con: sqlite3.Connection, user_id: str) -> dict:
    """Всё живое (без удалённых) — для нового устройства одним ответом."""
    rows = con.execute("SELECT type, key, value_json, rev FROM sync_rows WHERE user_id = ? AND value_json IS NOT NULL"
                       " ORDER BY rev", (user_id,)).fetchall()
    return {"rev": current_rev(con),
            "changes": [{"type": r["type"], "key": r["key"], "value": json.loads(r["value_json"]), "rev": r["rev"]}
                        for r in rows]}


def replace(con: sqlite3.Connection, user_id: str, items: list[Op]) -> int:
    """Полный снимок с клиента: чего в нём нет — удалено (tombstone), остальное — как прислано."""
    keep = {(o.type, o.key) for o in items}
    with tx(con):
        for r in con.execute("SELECT type, key FROM sync_rows WHERE user_id = ? AND value_json IS NOT NULL",
                             (user_id,)).fetchall():
            if (r["type"], r["key"]) not in keep:
                put(con, user_id, r["type"], r["key"], None, now_ms())
        for o in items:
            put(con, user_id, o.type, o.key, o.value, o.client_ts)
    return current_rev(con)


# ---- прослушивания ----

PLAYS_MAX = 500


def _artist(con: sqlite3.Connection, user_id: str, ref: str) -> str:
    """Исполнитель для статистики бота: клиенты шлют только ref — берём из карточки трека."""
    r = con.execute("SELECT artist FROM tracks WHERE ref = ?", (ref,)).fetchone()
    if r and r["artist"]:
        return r["artist"]
    for kind in ("like", "playlist_item"):
        for row in con.execute("SELECT value_json FROM sync_rows WHERE user_id = ? AND type = ? AND value_json LIKE ?"
                               " LIMIT 5", (user_id, kind, f'%"{ref}"%')):
            track = (json.loads(row["value_json"]) or {}).get("track") or {}
            if track.get("ref") == ref and track.get("artist"):
                return str(track["artist"])[:300]
    return ""


def add_plays(con: sqlite3.Connection, user_id: str, plays) -> int:
    """`POST /plays`: повтор той же пачки не удваивает (UNIQUE user+ref+played_at). → сколько записано новых."""
    if not isinstance(plays, list):
        raise SyncError("Нужно поле plays — список")
    if len(plays) > PLAYS_MAX:
        raise SyncError(f"Не больше {PLAYS_MAX} прослушиваний за раз")
    now = now_ms()
    n = 0
    with tx(con):
        for p in plays:
            if not isinstance(p, dict):
                continue
            ref, at, ms = p.get("ref"), p.get("played_at"), p.get("listened_ms")
            if not (isinstance(ref, str) and 1 <= len(ref) <= 200 and isinstance(at, int) and isinstance(ms, int)):
                continue
            if not (1_577_836_800_000 <= at <= now + 86400_000) or not 0 <= ms <= 6 * 3600_000:
                continue  # до 2020 или из будущего, прослушивание дольше 6 ч — мусор
            ctx = p.get("context") if isinstance(p.get("context"), str) else None
            artist = p.get("artist") if isinstance(p.get("artist"), str) and p.get("artist") else _artist(con, user_id, ref)
            n += con.execute("INSERT OR IGNORE INTO plays (user_id, ref, artist, context, played_at, listened_ms)"
                             " VALUES (?,?,?,?,?,?)", (user_id, ref, artist[:300], (ctx or "")[:200] or None, at, ms)).rowcount
    return n


# ---- состояние плеера ----

STATE_MAX = 64 * 1024


def put_player_state(con: sqlite3.Connection, user_id: str, device_id: str, state) -> None:
    if not isinstance(state, dict):
        raise SyncError("PlayerState — объект")
    raw = json.dumps(state, ensure_ascii=False)
    if len(raw) > STATE_MAX:
        raise SyncError("PlayerState больше 64 КБ")
    now = now_ms()
    con.execute("INSERT INTO player_state (user_id, is_playing, heartbeat_at, device_id, state_json) VALUES (?,?,?,?,?)"
                " ON CONFLICT(user_id) DO UPDATE SET is_playing = excluded.is_playing, heartbeat_at = excluded.heartbeat_at,"
                " device_id = excluded.device_id, state_json = excluded.state_json",
                (user_id, int(bool(state.get("is_playing"))), now, device_id, raw))


def get_player_state(con: sqlite3.Connection, user_id: str) -> dict | None:
    r = con.execute("SELECT state_json FROM player_state WHERE user_id = ?", (user_id,)).fetchone()
    return json.loads(r["state_json"]) if r and r["state_json"] else None
