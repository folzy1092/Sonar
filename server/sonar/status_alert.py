"""Сообщение в лог-группу о смене статуса пункта: что сломалось, почему, сколько длится, что проверяли."""
from __future__ import annotations

import json
import sqlite3
from html import escape

from .db import kv_get, kv_set
from .status import DOWN, OK, Change

MARKS = {OK: "✅", "partial": "⚠️", DOWN: "❌"}
NAMES = {"main": "Основной", "media": "Медиа", "proxy": "Прокси", "bot": "Бот", "site": "Сайт", "storage": "Хранилище",
         "soundcloud": "SoundCloud", "yandex": "Яндекс Музыка", "lrclib": "lrclib", "genius": "Genius",
         "lastfm": "Last.fm", "telegram": "Telegram", "youtube": "YouTube Music", "vk": "VK", "spotify": "Spotify",
         "apple": "Apple Music"}


def span(seconds: float) -> str:
    """Длительность по-человечески: «40 с», «15 мин», «1 ч 5 мин», «2 дн 3 ч»."""
    s = int(seconds)
    if s < 60:
        return f"{s} с"
    m = s // 60
    if m < 60:
        return f"{m} мин"
    h, m = divmod(m, 60)
    if h < 24:
        return f"{h} ч {m} мин" if m else f"{h} ч"
    d, h = divmod(h, 24)
    return f"{d} дн {h} ч" if h else f"{d} дн"


def _reason(c: Change) -> str:
    issue = escape(c.last_issue)
    if c.new == OK:
        took = f" · сбой длился {span(c.bad_for_s)}" if c.bad_for_s is not None else ""
        return f"Снова работает{took}" + (f"\nБыло: {issue}" if issue else "")
    if c.now.state == OK:
        # Сглаживание: проверка прошла, но недавние ещё падали — объяснить, откуда ⚠️ при живом сервисе.
        downs = sum(s == DOWN for s in c.recent)
        return f"Сейчас отвечает, но упали {downs} из {len(c.recent)} последних проверок" + (f"\nБыло: {issue}" if issue else "")
    going = f"\nСбой идёт {span(c.bad_for_s)}" if c.bad_for_s is not None else ""
    return f"Причина: {escape(c.now.note) or issue or 'не указана'}{going}"


def alert_lines(c: Change) -> list[str]:
    lines = [f"{MARKS[c.old]} → {MARKS[c.new]}", _reason(c)]
    if c.now.target or c.now.ms is not None:
        took = f"{c.now.ms} мс" if c.now.ms is not None else ""
        lines.append("Проверка: " + " · ".join(x for x in (escape(c.now.target), took) if x))
    if c.recent:
        lines.append("Последние проверки: " + " ".join(MARKS[s] for s in reversed(c.recent)) + " (новая — справа)")
    return lines


def alert_title(c: Change) -> str:
    return f"Статус: {NAMES.get(c.key, c.key)}"


# Об этих пунктах пишем в лог-группу. Остальное (lrclib, Genius, SoundCloud, Яндекс, YouTube, Spotify, Apple, «Медиа») — чужие
# сервисы, к которым ходит само устройство со своего IP, а тексты песен ищет приложение: что с ними видит сервер в Германии,
# пользователям неважно (lrclib вечно отвечает дольше 5 с), поэтому в логе молчим; в `/status` и на странице статуса они видны.
OWN = frozenset({"main", "bot", "site", "storage", "proxy", "telegram"})


class AlertGate:
    """Какие смены статуса идут в лог-группу. Раньше — каждая: одиночный таймаут lrclib на 5 секунд давал ⚠️, а следующая
    нормальная проверка — ✅, то есть два сообщения на пустяк. Теперь: пишем, только когда сбой подтверждён (❌ — три
    проверки подряд, около 15 минут), и один раз — когда после такого сбоя всё снова работает. ⚠️ и «упала одна проверка»
    молчат (на странице статуса и в `/status` они по-прежнему видны). Что уже сообщили, помним в базе: после рестарта
    сервера «снова работает» всё равно придёт."""

    KEY = "status:alerted_down"

    def __init__(self, con: sqlite3.Connection):
        self.con = con
        try:
            self.down: set[str] = set(json.loads(kv_get(con, self.KEY) or "[]"))
        except ValueError:
            self.down = set()

    def allow(self, change: Change) -> bool:
        if change.key not in OWN:
            return False
        if change.new == DOWN:
            self.down.add(change.key)
        elif change.new == OK and change.key in self.down:
            self.down.discard(change.key)
        else:
            return False
        kv_set(self.con, self.KEY, json.dumps(sorted(self.down)))
        return True
