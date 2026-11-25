"""Свой аккаунт и устройства (API.md §1): `/me`, пароль, список устройств, правило 24 ч."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Request, Response

from .. import sessions
from ..accounts import AccountError
from ..db import now_ms
from ..sessions import REVOKE_DELAY_MS, Session
from .auth import account_error, body, device_of
from .deps import session
from .errors import ApiError

router = APIRouter(prefix="/me")


def _user(request: Request, s: Session):
    user = request.app.state.accounts.by_id(s.user_id)
    if user is None:
        raise ApiError(401, "unauthorized", "Нет или неверная сессия")
    return user


@router.get("")
async def me(request: Request, s: Session = Depends(session)):
    return sessions.user_json(request.app.state.con, _user(request, s))


@router.patch("")
async def patch_me(request: Request, s: Session = Depends(session)):
    st = request.app.state
    data = await body(request)
    username, name = data.get("username"), data.get("display_name")
    if (username is not None and not isinstance(username, str)) or (name is not None and not isinstance(name, str)):
        raise ApiError(400, "bad_request", "username и display_name — строки")
    if "avatar" in data:
        raise ApiError(400, "bad_request", "Аватар — PUT /me/avatar (пока нет)")
    try:
        user = st.accounts.update_profile(_user(request, s), username=username, display_name=name)
    except AccountError as err:
        raise account_error(err) from None
    return sessions.user_json(st.con, user)


@router.put("/password", status_code=204)
async def put_password(request: Request, s: Session = Depends(session)):
    data = await body(request)
    new, old = data.get("new_password"), data.get("old_password")
    if not isinstance(new, str) or (old is not None and not isinstance(old, str)):
        raise ApiError(400, "bad_request", "new_password — строка")
    try:
        await request.app.state.accounts.set_password(_user(request, s), new[:256], old[:256] if old else None)
    except AccountError as err:
        if err.code == "bad_password":
            raise ApiError(403, "bad_password", "Старый пароль не подходит") from None
        raise account_error(err) from None
    # Решение владельца 2026-11-25: сменил пароль — все остальные устройства выходят (если пароль утёк).
    sessions.drop_others(request.app.state.con, s)
    return Response(status_code=204)


@router.get("/devices")
async def devices(request: Request, s: Session = Depends(session)):
    return sessions.devices(request.app.state.con, s)


@router.put("/device")
async def put_device(request: Request, s: Session = Depends(session)):
    """При каждом запуске клиента: имя, ОС, версия. id устройства — из сессии, не из тела."""
    con = request.app.state.con
    dev = device_of(await body(request))
    sessions.report(con, s, dev)
    return sessions.device_json(sessions.device_row(con, s.user_id, s.device_id), s.id)


def _device_or_404(request: Request, s: Session, device_id: str):
    r = sessions.device_row(request.app.state.con, s.user_id, device_id)
    if r is None:
        raise ApiError(404, "not_found", "Устройство не найдено")
    return r


@router.patch("/devices/{device_id}")
async def rename_device(request: Request, device_id: str, s: Session = Depends(session)):
    con = request.app.state.con
    r = _device_or_404(request, s, device_id)
    name = (await body(request)).get("name")
    if not isinstance(name, str) or not name.strip() or len(name.strip()) > sessions.NAME_MAX:
        raise ApiError(400, "bad_request", "name — от 1 до 48 символов")
    con.execute("UPDATE sessions SET device_name = ? WHERE id = ?", (name.strip(), r["id"]))
    return sessions.device_json(sessions.device_row(con, s.user_id, device_id), s.id)


@router.delete("/devices/{device_id}", status_code=204)
async def revoke_device(request: Request, device_id: str, s: Session = Depends(session)):
    r = _device_or_404(request, s, device_id)
    if r["id"] != s.id and now_ms() - s.created_at < REVOKE_DELAY_MS:
        raise ApiError(403, "session_too_new", "Вход был недавно — завершать другие сессии можно через 24 часа")
    sessions.drop(request.app.state.con, r["id"])
    return Response(status_code=204)
