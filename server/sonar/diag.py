"""Диагностика доступности сервера (docs/SERVER_DIAG_PROMPT.md): отставание event loop, запросы в минуту, ОЗУ, тело для
проверки обрывов на размере ответа. Всё в памяти процесса, без сети и без адресов клиентов — `/api/diag` публичный.

Один event loop крутит и бота, и HTTP: если его что-то блокирует (синхронный DNS, тяжёлый SQL), снаружи это выглядит как
«сайт открылся, а потом ничего не отвечает». Монитор раз в секунду проверяет, насколько позже срока сработал таймер."""
from __future__ import annotations

import asyncio
import base64
import functools
import logging
import math
import os
import random
import time
from collections import deque
from collections.abc import Callable

log = logging.getLogger("sonar.diag")

STARTED = time.monotonic()
TICK_S = 1.0
WARN_LAG_MS = 200
WINDOW_S = 300                 # max и p95 — за последние 5 минут
PAYLOAD_MAX_KB = 2048
_PAYLOAD_SEED = 1092           # тело одинаковое от запуска к запуску: можно сверять байты
_LINE = 64                     # строка тела: 63 знака base64 + перевод строки


def p95(values: list[float]) -> float:
    """95-й перцентиль методом ближайшего ранга; пустой список → 0."""
    if not values:
        return 0.0
    ordered = sorted(values)
    return ordered[max(0, math.ceil(0.95 * len(ordered)) - 1)]


class LoopMonitor:
    """Таймер раз в `tick_s`: насколько позже срока он сработал — столько loop был занят чем-то другим."""

    def __init__(self, tick_s: float = TICK_S, warn_ms: float = WARN_LAG_MS, window_s: float = WINDOW_S,
                 clock: Callable[[], float] = time.monotonic):
        self.tick_s, self.warn_ms, self.window_s, self.clock = tick_s, warn_ms, window_s, clock
        self.samples: deque[tuple[float, float]] = deque(maxlen=int(window_s / tick_s) + 5)   # (когда, отставание мс)
        self._loop: asyncio.AbstractEventLoop | None = None
        self._due = 0.0

    def start(self, loop: asyncio.AbstractEventLoop) -> None:
        """Повторный старт на том же loop ничего не делает: HTTP перезапускается из бота, а процесс и loop те же."""
        if self._loop is loop:
            return
        self._loop = loop
        self._schedule()

    def _schedule(self) -> None:
        self._due = self.clock() + self.tick_s
        self._loop.call_later(self.tick_s, self._tick)

    def _tick(self) -> None:
        self.record(max(0.0, (self.clock() - self._due) * 1000))
        self._schedule()

    def record(self, lag_ms: float) -> None:
        self.samples.append((self.clock(), lag_ms))
        if lag_ms > self.warn_ms:
            log.warning("event loop отстал на %d мс: что-то синхронное держит и бота, и HTTP", lag_ms)

    def stats(self) -> dict:
        since = self.clock() - self.window_s
        lags = [lag for at, lag in self.samples if at >= since]
        return {"max_ms": round(max(lags, default=0.0)), "p95_ms": round(p95(lags)), "samples": len(lags)}


class RequestRate:
    """Сколько запросов пришло за последние 60 с: счётчики по секундам, не больше 60 корзин."""

    def __init__(self, clock: Callable[[], float] = time.monotonic):
        self.clock = clock
        self.buckets: deque[list[int]] = deque()    # [секунда, сколько]

    def hit(self) -> None:
        second = int(self.clock())
        if self.buckets and self.buckets[-1][0] == second:
            self.buckets[-1][1] += 1
        else:
            self.buckets.append([second, 1])
        self._drop(second)

    def _drop(self, second: int) -> None:
        while self.buckets and self.buckets[0][0] <= second - 60:
            self.buckets.popleft()

    def per_minute(self) -> int:
        self._drop(int(self.clock()))
        return sum(n for _, n in self.buckets)


def rss_mb() -> float | None:
    """ОЗУ процесса сейчас (Linux, /proc). На другой системе — None: это про сервер, локально не важно."""
    try:
        with open("/proc/self/statm") as f:
            pages = int(f.read().split()[1])
        return round(pages * os.sysconf("SC_PAGE_SIZE") / 2**20, 1)
    except (OSError, ValueError, IndexError):
        return None


@functools.cache
def _payload_block() -> bytes:
    """2 МБ псевдослучайного base64 строками по 64 байта: прокси не сожмёт его в ноль, и проверка размера честная."""
    rnd = random.Random(_PAYLOAD_SEED)
    size = PAYLOAD_MAX_KB * 1024
    raw = base64.b64encode(rnd.randbytes(size))
    step = _LINE - 1
    return b"".join(raw[i * step:(i + 1) * step] + b"\n" for i in range(size // _LINE))


def payload(kb: int) -> bytes:
    """Ровно `kb` КБ детерминированного текста (0 ≤ kb ≤ 2048)."""
    if not 0 <= kb <= PAYLOAD_MAX_KB:
        raise ValueError(f"kb от 0 до {PAYLOAD_MAX_KB}")
    return _payload_block()[:kb * 1024]


MONITOR = LoopMonitor()
REQUESTS = RequestRate()


def uptime_s() -> int:
    return int(time.monotonic() - STARTED)
