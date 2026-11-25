"""Общие зависимости API: IP клиента за прокси, лимит запросов, сессия `Bearer`."""
from __future__ import annotations

import time

from fastapi import Request

from ..accounts import RateLimit
from ..admin.web import _ip
from .. import sessions
from ..events import Device, session_device
from .errors import ApiError

# Все запросы к /api с одного IP за минуту и отдельно, строже, — к /api/auth/* (перебор паролей и регистраций).
WINDOW_S = 60
API_PER_IP = 300
AUTH_PER_IP = 20
# Сколько IP держать в памяти, прежде чем вычистить тех, кто давно не заходил (≤150 МБ на процесс, SPEC §3.2).
PRUNE_AT = 5000


class Limiter(RateLimit):
    """`RateLimit` из accounts.py, который сам себя чистит: на открытом порту адресов может быть сколько угодно."""

    def take(self, key: str) -> bool:
        """Учесть запрос; → False, если лимит уже исчерпан (тогда запрос не считается)."""
        if self.blocked(key):
            return False
        if len(self.hits) >= PRUNE_AT:
            self.prune()
        self.hit(key)
        return True

    def prune(self) -> None:
        t = time.monotonic()
        for k in [k for k, q in self.hits.items() if not q or t - q[-1] > self.window]:
            del self.hits[k]


def client_ip(request: Request) -> str:
    """IP клиента: заголовкам прокси верим только от SONAR_TRUSTED_PROXIES (admin/web.py `_ip`)."""
    return _ip(request)


def bearer(request: Request) -> str | None:
    auth = request.headers.get("authorization", "")
    if not auth.lower().startswith("bearer "):
        return None
    return auth[7:].strip() or None


def device(request: Request) -> Device:
    """Зависимость FastAPI: сессия клиента → пользователь и устройство, иначе 401."""
    token = bearer(request)
    dev = session_device(request.app.state.con, token) if token else None
    if dev is None:
        raise ApiError(401, "unauthorized", "Нет или неверная сессия")
    return dev



def session(request: Request) -> sessions.Session:
    """Зависимость FastAPI: сессия клиента целиком (id, создана когда) — для /me и устройств; иначе 401."""
    token = bearer(request)
    con = request.app.state.con
    s = sessions.by_token(con, token) if token else None
    if s is None:
        raise ApiError(401, "unauthorized", "Нет или неверная сессия")
    sessions.seen(con, s)
    return s
