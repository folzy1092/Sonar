"""Статус сервиса (SPEC §3.11): проверки раз в 5 минут, история в status_checks, сводка для /status."""
from __future__ import annotations

import asyncio
import shutil
import sqlite3
import time
from dataclasses import dataclass

import aiohttp

from .db import now_ms

OK, PARTIAL, DOWN = "ok", "partial", "down"
SLOW_MS = 2000
TIMEOUT = aiohttp.ClientTimeout(total=5)
UA = {"User-Agent": "Sonar/0.1 (+https://sonar.folzy.ru)"}
MIN_FREE_BYTES = 100 * 1024 * 1024


@dataclass
class Item:
    key: str
    state: str
    ms: int | None = None
    note: str = ""


async def _http(session: aiohttp.ClientSession, url: str, **params) -> int:
    t = time.monotonic()
    async with session.get(url, params=params or None, headers=UA, timeout=TIMEOUT) as r:
        await r.read()
        if r.status >= 500 or r.status in (403, 429):
            raise RuntimeError(f"HTTP {r.status}")
    return int((time.monotonic() - t) * 1000)


class Status:
    def __init__(self, con: sqlite3.Connection, data_dir, settings, bot=None):
        self.con, self.data_dir, self.settings, self.bot = con, data_dir, settings, bot
        self.last: dict[str, Item] = {}
        self.checked_at = 0.0

    # ---- проверки ----

    def _main(self) -> Item:
        t = time.monotonic()
        self.con.execute("SELECT 1").fetchone()
        return Item("main", OK, int((time.monotonic() - t) * 1000))

    def _storage(self) -> Item:
        self.con.execute("INSERT INTO kv (key, value) VALUES ('status:probe', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                         (str(now_ms()),))
        free = shutil.disk_usage(self.data_dir).free
        return Item("storage", OK if free > MIN_FREE_BYTES else PARTIAL, note=f"{free / 1024 ** 3:.1f} ГБ свободно")

    async def _remote(self, session, key, url, **params) -> Item:
        try:
            ms = await _http(session, url, **params)
            return Item(key, OK if ms < SLOW_MS else PARTIAL, ms)
        except Exception:  # noqa: BLE001 — любая ошибка сети = сервис недоступен
            return Item(key, DOWN)

    async def _telegram(self) -> Item:
        if not self.bot:
            return Item("telegram", DOWN)
        t = time.monotonic()
        try:
            await self.bot.get_me()
            return Item("telegram", OK, int((time.monotonic() - t) * 1000))
        except Exception:  # noqa: BLE001
            return Item("telegram", DOWN)

    async def check(self) -> dict[str, Item]:
        items = [self._main(), self._storage(), Item("bot", OK if self.bot else DOWN)]
        async with aiohttp.ClientSession() as s:
            jobs = [
                self._remote(s, "soundcloud", "https://soundcloud.com/"),
                self._remote(s, "yandex", "https://api.music.yandex.net/search", text="sonar", type="track", page=0),
                self._remote(s, "lrclib", "https://lrclib.net/api/search", q="sonar"),
                self._remote(s, "genius", "https://genius.com/api/search/multi", q="sonar"),
                self._remote(s, "site", self.settings.site_url),
                self._telegram(),
            ]
            if self.settings.lastfm_api_key:
                jobs.append(self._remote(s, "lastfm", "https://ws.audioscrobbler.com/2.0/", method="chart.gettoptracks",
                                         api_key=self.settings.lastfm_api_key, format="json", limit=1))
            if self.settings.public_url:
                jobs.append(self._remote(s, "proxy", f"{self.settings.public_url}/health"))
            items += await asyncio.gather(*jobs)
        # Медиа = выдаём ссылки на поток: живы ли оба сервиса.
        sc, ym = next(i for i in items if i.key == "soundcloud"), next(i for i in items if i.key == "yandex")
        media = OK if sc.state == ym.state == OK else (DOWN if sc.state == ym.state == DOWN else PARTIAL)
        items.append(Item("media", media, max(sc.ms or 0, ym.ms or 0) or None))
        ts = now_ms()
        self.con.executemany("INSERT INTO status_checks (ts, item, state, ms) VALUES (?,?,?,?)",
                             [(ts, i.key, i.state, i.ms) for i in items])
        self.con.execute("DELETE FROM status_checks WHERE ts < ?", (ts - 30 * 86400_000,))
        self.last = {i.key: self._smooth(i) for i in items}
        self.checked_at = time.monotonic()
        return self.last

    def _smooth(self, item: Item) -> Item:
        """⚠️ — если упала 1–2 из последних 3, ❌ — если 3 подряд (SPEC §3.11)."""
        rows = self.con.execute("SELECT state FROM status_checks WHERE item = ? ORDER BY ts DESC LIMIT 3", (item.key,)).fetchall()
        downs = sum(r["state"] == DOWN for r in rows)  # текущая проверка уже записана
        state = DOWN if downs >= 3 else PARTIAL if downs else item.state
        return Item(item.key, state, item.ms, item.note)

    async def current(self, max_age_s: int = 60) -> dict[str, Item]:
        if not self.last or time.monotonic() - self.checked_at > max_age_s:
            await self.check()
        return self.last

    def uptime(self) -> float | None:
        r = self.con.execute("SELECT COUNT(*) AS n, SUM(state = 'ok') AS ok FROM status_checks WHERE item = 'main' AND ts > ?",
                             (now_ms() - 30 * 86400_000,)).fetchone()
        return None if not r["n"] else r["ok"] * 100 / r["n"]

    async def loop(self, every_s: int = 300) -> None:
        while True:
            try:
                await self.check()
            except Exception:  # noqa: BLE001 — проверка не должна ронять бота
                pass
            await asyncio.sleep(every_s)
