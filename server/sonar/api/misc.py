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
    """Какой адрес клиента видит сервер за nginx хостинга. Лимиты входа и регистрации считаются по нему: если у разных людей здесь
    один и тот же адрес (адрес прокси), лимит общий и надо настроить SONAR_TRUSTED_PROXIES. Свой адрес не секрет."""
    return JSONResponse({"ip": client_ip(request)}, headers={"Cache-Control": "no-store"})


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
