"""Публичный профиль `/@username` (API.md §1 `PublicProfile`): что гость видит на сайте.

Гость — не друг, поэтому раздел виден только при `privacy.<раздел> = everyone` (нет настройки — по умолчанию
`everyone`, как в SETTINGS.md). Скрытый раздел — `null` и его имя в `private`; пустой (ничего не прослушано, лайков
нет) — тоже `null`, но без `private`: сайт прячет блок, а не рисует нули. Сервер ничего не спрашивает у сервисов —
только то, что устройства уже прислали синком, `POST /plays` и `PUT /player/state`.
"""
from __future__ import annotations

import json
import sqlite3
from collections import defaultdict

from .api.integrations import now_json

SECTIONS = ("now_playing", "stats", "likes", "playlists")
LIKES_MAX = 8
PLAYLISTS_MAX = 12
COVERS_MAX = 4
TOP_ARTISTS = 6
SHOWCASE_MAX = 6
DAY_MS = 86400_000


def _settings(con: sqlite3.Connection, user_id: str) -> dict:
    rows = con.execute("SELECT key, value_json FROM sync_rows WHERE user_id = ? AND type = 'setting'"
                       " AND (key LIKE 'privacy.%' OR key = 'profile.showcase') AND value_json IS NOT NULL",
                       (user_id,))
    out = {}
    for r in rows:
        try:
            out[r["key"]] = json.loads(r["value_json"])
        except ValueError:
            continue
    return out


def _open(settings: dict, section: str) -> bool:
    return settings.get(f"privacy.{section}", "everyone") == "everyone"


def _text(v) -> str:
    return v.strip() if isinstance(v, str) else ""


def _int(v) -> int:
    return int(v) if isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0 else 0


def public_track(card, ref: str | None = None) -> dict | None:
    """Карточка `Track` клиента → `PublicTrack`; без названия — не показываем."""
    if not isinstance(card, dict):
        return None
    title = _text(card.get("title"))
    if not title:
        return None
    return {"ref": ref or _text(card.get("ref")), "title": title, "artist": _text(card.get("artist")),
            "cover_url": _text(card.get("cover_url")) or None, "duration_ms": _int(card.get("duration_ms")) or None}


def _rows(con: sqlite3.Connection, user_id: str, kind: str):
    for r in con.execute("SELECT key, value_json FROM sync_rows WHERE user_id = ? AND type = ? AND value_json IS NOT NULL",
                         (user_id, kind)):
        try:
            value = json.loads(r["value_json"])
        except ValueError:
            continue
        if isinstance(value, dict):
            yield r["key"], value


def now_playing(con: sqlite3.Connection, user_id: str, now: int) -> dict | None:
    r = con.execute("SELECT state_json, heartbeat_at FROM player_state WHERE user_id = ?", (user_id,)).fetchone()
    if r is None or not r["state_json"]:
        return None
    try:
        state = json.loads(r["state_json"])
    except ValueError:
        return None
    if not isinstance(state, dict):
        return None
    if not now_json(state, r["heartbeat_at"], now)["is_playing"]:
        return None
    return public_track(state.get("track"), state.get("ref"))


def _streak(days: set[int], today: int) -> int:
    """Дней подряд с прослушиваниями, считая сегодня или вчера (вечером ещё не слушал — серия не сгорает)."""
    day = today if today in days else today - 1
    n = 0
    while day in days:
        n += 1
        day -= 1
    return n


def stats(con: sqlite3.Connection, user_id: str, now: int) -> tuple[dict | None, list[dict]]:
    r = con.execute("SELECT COUNT(*) n, COALESCE(SUM(listened_ms), 0) ms, COUNT(DISTINCT ref) tracks,"
                    " COUNT(DISTINCT artist) artists FROM plays WHERE user_id = ?", (user_id,)).fetchone()
    if not r["n"]:
        return None, []
    days = {row[0] for row in con.execute("SELECT DISTINCT played_at / ? FROM plays WHERE user_id = ?", (DAY_MS, user_id))}
    top = [{"name": a["artist"], "plays": a["n"], "avatar_url": None, "ref": None} for a in con.execute(
        "SELECT artist, COUNT(*) n FROM plays WHERE user_id = ? AND artist != '' GROUP BY artist"
        " ORDER BY n DESC, artist LIMIT ?", (user_id, TOP_ARTISTS))]
    return ({"plays": r["n"], "total_ms": r["ms"], "tracks": r["tracks"], "artists": r["artists"],
             "streak_days": _streak(days, now // DAY_MS)}, top)


def likes(con: sqlite3.Connection, user_id: str) -> dict | None:
    liked = [(_int(v.get("added_at")), ref, v.get("track")) for ref, v in _rows(con, user_id, "like")
             if v.get("kind", "track") == "track"]
    if not liked:
        return None
    liked.sort(key=lambda x: x[0], reverse=True)
    tracks = [t for _, ref, card in liked if (t := public_track(card, ref))][:LIKES_MAX]
    return {"count": len(liked), "tracks": tracks}


def _position(item: dict) -> float:
    p = item.get("position")
    return p if isinstance(p, (int, float)) else 0


def playlists(con: sqlite3.Connection, user_id: str, hidden_ids) -> tuple[list[dict] | None, int]:
    hidden = set(hidden_ids) if isinstance(hidden_ids, list) else set()
    lists = {pid: v for pid, v in _rows(con, user_id, "playlist") if not v.get("hidden") and pid not in hidden}
    if not lists:
        return None, 0
    items = defaultdict(list)
    for _, v in _rows(con, user_id, "playlist_item"):
        if v.get("playlist_id") in lists:
            items[v["playlist_id"]].append(v)
    out = []
    for pid, v in lists.items():
        rows = sorted(items[pid], key=_position)
        cards = [it["track"] for it in rows if isinstance(it.get("track"), dict)]
        covers = list(dict.fromkeys(c for card in cards if (c := _text(card.get("cover_url")))))[:COVERS_MAX]
        out.append({"id": pid, "name": _text(v.get("name")) or "Плейлист", "track_count": len(rows),
                    "duration_ms": sum(_int(card.get("duration_ms")) for card in cards), "covers": covers,
                    "_at": _int(v.get("updated_at"))})
    out.sort(key=lambda p: (-p["_at"], p["name"]))
    return [{k: p[k] for k in p if k != "_at"} for p in out[:PLAYLISTS_MAX]], len(out)


def showcase(settings: dict) -> list[dict]:
    raw = settings.get("profile.showcase")
    if not isinstance(raw, list):
        return []
    hidden_ids = settings.get("privacy.hidden_playlists")
    hidden = set(hidden_ids) if isinstance(hidden_ids, list) else set()
    out = []
    for s in raw:
        if not isinstance(s, dict) or not _text(s.get("title")) or s.get("ref") in hidden:
            continue
        if s.get("kind") == "playlist" and not _open(settings, "playlists"):
            continue
        out.append({"kind": _text(s.get("kind")), "ref": _text(s.get("ref")), "title": _text(s.get("title")),
                    "subtitle": _text(s.get("subtitle")), "cover_url": _text(s.get("cover_url")) or None})
    return out[:SHOWCASE_MAX]


def build(con: sqlite3.Connection, user: sqlite3.Row, now: int) -> dict:
    uid = user["id"]
    settings = _settings(con, uid)
    private = [s for s in SECTIONS if not _open(settings, s)]
    stat, top = stats(con, uid, now) if "stats" not in private else (None, [])
    pls, pl_count = (playlists(con, uid, settings.get("privacy.hidden_playlists"))
                     if "playlists" not in private else (None, 0))
    return {
        "username": user["username"], "display_name": user["display_name"], "number": user["number"],
        "avatar_url": None, "created_at": user["created_at"],
        "now_playing": None if "now_playing" in private else now_playing(con, uid, now),
        "stats": stat, "top_artists": top,
        "likes": None if "likes" in private else likes(con, uid),
        "playlists": pls, "playlist_count": pl_count,
        "showcase": showcase(settings),
        "private": private,
    }
