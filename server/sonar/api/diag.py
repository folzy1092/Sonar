"""`GET /diag` и `GET /diag/payload` — диагностика доступности (docs/SERVER_DIAG_PROMPT.md, API.md «Диагностика»).

Оба публичные: в ответах нет ни секретов, ни чьих-либо адресов. Тело `payload` — до 2 МБ, поэтому у него свой лимит на IP
поверх общего: страница `/diag` за один прогон делает 30 запросов, перебор — нет."""
from __future__ import annotations

import asyncio

from fastapi import APIRouter, Query, Request
from fastapi.responses import JSONResponse, Response

from .. import diag
from ..updater import short
from .deps import WINDOW_S, Limiter, client_ip
from .errors import ApiError

router = APIRouter()
PAYLOAD_PER_IP = 90          # три прогона страницы /diag в минуту
NO_STORE = {"Cache-Control": "no-store"}
payload_limit = Limiter(limit=PAYLOAD_PER_IP, window_s=WINDOW_S)
_version: str | None = None


async def _server_version(request: Request) -> str:
    """Коммит кода на диске (sync.py). Не меняется до перезапуска процесса — читаем один раз и не в event loop."""
    global _version
    if _version is None:
        current = await asyncio.to_thread(request.app.state.updater.current)
        _version = short(current["sha"])
    return _version


@router.get("/diag")
async def server_diag(request: Request):
    return JSONResponse({"version": await _server_version(request), "uptime_s": diag.uptime_s(),
                         "loop_lag": diag.MONITOR.stats(), "rss_mb": diag.rss_mb(),
                         "requests_per_min": diag.REQUESTS.per_minute()}, headers=NO_STORE)


@router.get("/diag/payload")
async def diag_payload(request: Request, kb: int = Query(1, ge=0, le=diag.PAYLOAD_MAX_KB)):
    if not payload_limit.take(client_ip(request)):
        raise ApiError(429, "too_many", "Слишком много проверок, попробуй через минуту", headers={"Retry-After": str(WINDOW_S)})
    return Response(diag.payload(kb), media_type="text/plain; charset=utf-8", headers=NO_STORE)
