"""Перенос «Любимых» из Dotify (файл `.dotifyplaylist`) в лайки аккаунта Sonar — скрытая команда бота `/dotify`.

Файл — JSON: `{"title", "tracks": [{"id", "title", "artist", "duration", "cover_art", "source", "url", "added_at",
"artists": [{"id", "name", "avatar", "source"}]}]}`, треки от новых к старым, `duration` — секунды, `added_at` — мс.
`source: soundcloud` → `sc:<id>` (артисты `sca:`), `yandex` → `ym:<id>` (`yma:`), остальное — пропуск со счётом.

Лайки пишутся в `likes` сервера (схема DB.md) с `rev` из `sync_rev` — синк (API.md §6) развезёт их по устройствам.
Уже стоящий лайк не трогаем, снятый вручную (`deleted = 1`) не возвращаем, метаданные трека, которые уже есть, не
перетираем. Всё — одной транзакцией: либо весь файл, либо ничего.
"""
from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass, field

from .db import now_ms, tx

PREFIX = {"soundcloud": ("sc", "sca"), "yandex": ("ym", "yma")}
FILE_MAX = 5 * 1024 * 1024
TRACKS_MAX = 20_000
TEXT_MAX = 300


class DotifyError(ValueError):
    pass


@dataclass
class Item:
    ref: str
    title: str
    artist: str
    artists_json: str
    duration_ms: int | None
    cover_url: str | None
    url: str | None
    added_at: int


@dataclass
class Parsed:
    title: str
    items: list[Item] = field(default_factory=list)
    unknown: int = 0          # неизвестный сервис или битая строка


@dataclass
class Counts:
    new: int = 0              # будут добавлены
    have: int = 0             # лайк уже стоит
    removed: int = 0          # сняты в Sonar вручную — не возвращаем
    unknown: int = 0


def _text(v, limit: int = TEXT_MAX) -> str | None:
    return v.strip()[:limit] or None if isinstance(v, str) else None


def _https(v) -> str | None:
    s = _text(v, 1000)
    return s if s and s.startswith("https://") else None


def _int(v) -> int | None:
    return int(v) if isinstance(v, (int, float)) and not isinstance(v, bool) and v >= 0 else None


def _id(v) -> str | None:
    s = str(v).strip() if isinstance(v, (str, int)) and not isinstance(v, bool) else ""
    return s if s and len(s) <= 64 and all(c.isalnum() or c in "_-" for c in s) else None


def parse(raw: bytes) -> Parsed:
    """Байты файла → треки. DotifyError — файл не тот (текст для пользователя)."""
    if len(raw) > FILE_MAX:
        raise DotifyError("Файл больше 5 МБ — это не плейлист Dotify")
    try:
        data = json.loads(raw.decode("utf-8-sig"))
    except (UnicodeDecodeError, ValueError):
        raise DotifyError("Это не файл .dotifyplaylist: внутри не JSON") from None
    tracks = data.get("tracks") if isinstance(data, dict) else None
    if not isinstance(tracks, list):
        raise DotifyError("В файле нет списка треков")
    if len(tracks) > TRACKS_MAX:
        raise DotifyError(f"Больше {TRACKS_MAX} треков за раз не переношу")
    out = Parsed(_text(data.get("title"), 100) or "Любимые")
    now = now_ms()
    seen: set[str] = set()
    for t in tracks:
        pfx = PREFIX.get(t.get("source")) if isinstance(t, dict) else None
        tid = _id(t.get("id")) if pfx else None
        title, artist = (_text(t.get("title")), _text(t.get("artist"))) if pfx else (None, None)
        if not (pfx and tid and title):
            out.unknown += 1
            continue
        ref = f"{pfx[0]}:{tid}"
        if ref in seen:  # дубль внутри файла — первый (самый свежий) выигрывает
            continue
        seen.add(ref)
        artists = []
        for a in t.get("artists") or []:
            aid = _id(a.get("id")) if isinstance(a, dict) else None
            if aid and _text(a.get("name")):
                artists.append({"ref": f"{pfx[1]}:{aid}", "name": _text(a.get("name")), "avatar_url": _https(a.get("avatar"))})
        added = _int(t.get("added_at"))
        dur = _int(t.get("duration"))
        out.items.append(Item(ref, title, artist or "", json.dumps(artists, ensure_ascii=False),
                              dur * 1000 if dur else None, _https(t.get("cover_art")), _https(t.get("url")),
                              added if added and added <= now else now))
    return out


def _states(con: sqlite3.Connection, user_id: str) -> dict[str, int]:
    return {r["ref"]: r["deleted"] for r in con.execute("SELECT ref, deleted FROM likes WHERE user_id = ?", (user_id,))}


def preview(con: sqlite3.Connection, user_id: str, p: Parsed) -> Counts:
    states = _states(con, user_id)
    c = Counts(unknown=p.unknown)
    for it in p.items:
        st = states.get(it.ref)
        if st is None:
            c.new += 1
        elif st:
            c.removed += 1
        else:
            c.have += 1
    return c


def apply(con: sqlite3.Connection, user_id: str, p: Parsed) -> Counts:
    """Записать лайки. Повтор того же файла ничего не удваивает (новых будет 0)."""
    c = Counts(unknown=p.unknown)
    now = now_ms()
    with tx(con):
        states = _states(con, user_id)
        for it in p.items:
            con.execute("INSERT OR IGNORE INTO tracks (ref, title, artist, artists_json, duration_ms, artwork_url, url,"
                        " updated_at) VALUES (?,?,?,?,?,?,?,?)",
                        (it.ref, it.title, it.artist, it.artists_json, it.duration_ms, it.cover_url, it.url, now))
            st = states.get(it.ref)
            if st is not None:
                if st:
                    c.removed += 1
                else:
                    c.have += 1
                continue
            rev = con.execute("UPDATE sync_rev SET value = value + 1 WHERE id = 1 RETURNING value").fetchone()[0]
            con.execute("INSERT INTO likes (user_id, ref, kind, added_at, deleted, rev) VALUES (?, ?, 'track', ?, 0, ?)",
                        (user_id, it.ref, it.added_at, rev))
            c.new += 1
    return c
