"""`GET /health`, `GET /config`, `POST /events` — первые методы API (до /api жили в корне, там остались алиасы)."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from .. import events
from ..admin import prefs
from ..events import Device
from .deps import client_ip, device
from .errors import ApiError

router = APIRouter()


@router.get("/health")
async def health():
    return {"ok": True}


@router.get("/whoami")
async def whoami(request: Request):
    """Какой адрес клиента видит сервер за nginx хостинга и что именно передал прокси (`remote` — кто подключился,
    `forwarded_for` / `real_ip` — что он сказал про клиента). Лимиты входа, регистрации и запросов считаются по `ip`: если у
    разных людей он один и тот же (адрес прокси), лимит общий. Свои же данные запроса, секрета тут нет."""
    h = request.headers
    return JSONResponse({"ip": client_ip(request), "remote": request.client.host if request.client else None,
                         "forwarded_for": h.get("x-forwarded-for", ""), "real_ip": h.get("x-real-ip", ""),
                         "proto": h.get("x-forwarded-proto", "")}, headers={"Cache-Control": "no-store"})


@router.get("/config")
async def get_config(request: Request):
    return prefs.public_config(request.app.state.con)


@router.post("/events")
async def post_events(request: Request, dev: Device = Depends(device)):
    try:
        body = await request.json()
    except ValueError:
        raise ApiError(400, "bad_json", "Тело — JSON") from None
    items = body.get("events") if isinstance(body, dict) else None
    if not isinstance(items, list):
        raise ApiError(400, "bad_events", "Нужно поле events — список")
    if len(items) > events.BATCH_MAX:
        raise ApiError(400, "too_many", f"Не больше {events.BATCH_MAX} событий за раз")
    return {"accepted": events.record(request.app.state.con, dev, items)}
