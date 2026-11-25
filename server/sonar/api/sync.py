"""Синк, прослушивания и состояние плеера (API.md §5, §6). Логика — `sonar/sync.py`."""
from __future__ import annotations

import json

from fastapi import APIRouter, Depends, Request, Response

from .. import sync
from ..sessions import Session
from .auth import body as small_body
from .deps import session
from .errors import ApiError

router = APIRouter()


# Пачка синка — до 500 строк, обычно десятки КБ; больше 4 МБ (как у синка по Wi‑Fi) — не принимаем.
BODY_MAX = 4 * 1024 * 1024


async def body(request: Request) -> dict:
    if int(request.headers.get("content-length") or 0) > BODY_MAX:
        raise ApiError(413, "too_large", "Пачка больше 4 МБ — отправь частями")
    raw = await request.body()
    if len(raw) > BODY_MAX:
        raise ApiError(413, "too_large", "Пачка больше 4 МБ — отправь частями")
    try:
        data = json.loads(raw)
    except ValueError:
        raise ApiError(400, "bad_json", "Тело — JSON") from None
    if not isinstance(data, dict):
        raise ApiError(400, "bad_json", "Тело — JSON-объект")
    return data


def _bad(err: sync.SyncError) -> ApiError:
    return ApiError(400, "bad_request", str(err))


@router.get("/sync/pull")
async def pull(request: Request, since: int = 0, s: Session = Depends(session)):
    p = sync.pull(request.app.state.con, s.user_id, max(0, since))
    return {"rev": p.rev, "changes": p.changes, "more": p.more}


@router.post("/sync/push")
async def push(request: Request, s: Session = Depends(session)):
    try:
        ops = sync.parse_ops(await body(request))
    except sync.SyncError as err:
        raise _bad(err) from None
    rev, applied = sync.push(request.app.state.con, s.user_id, ops)
    return {"rev": rev, "applied": applied}


@router.get("/sync/snapshot")
async def snapshot(request: Request, s: Session = Depends(session)):
    return sync.snapshot(request.app.state.con, s.user_id)


@router.post("/sync/replace")
async def replace(request: Request, s: Session = Depends(session)):
    """Тело — как у push (`{ops}`), но это весь снимок: чего нет — удаляется. op_id не проверяются."""
    try:
        ops = sync.parse_ops(await body(request))
    except sync.SyncError as err:
        raise _bad(err) from None
    return {"rev": sync.replace(request.app.state.con, s.user_id, ops)}


@router.post("/plays")
async def plays(request: Request, s: Session = Depends(session)):
    try:
        n = sync.add_plays(request.app.state.con, s.user_id, (await body(request)).get("plays"))
    except sync.SyncError as err:
        raise _bad(err) from None
    return {"accepted": n}


@router.put("/player/state", status_code=204)
async def put_state(request: Request, s: Session = Depends(session)):
    try:
        sync.put_player_state(request.app.state.con, s.user_id, s.device_id, await small_body(request))
    except sync.SyncError as err:
        raise _bad(err) from None
    return Response(status_code=204)


@router.get("/player/state")
async def get_state(request: Request, s: Session = Depends(session)):
    state = sync.get_player_state(request.app.state.con, s.user_id)
    if state is None:
        raise ApiError(404, "not_found", "Ещё ничего не играло")
    return state
