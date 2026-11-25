"""Входы в сервисы на всех устройствах (SERVER_PROMPT этап 4, API.md «Сервисы»).

Ключи лежат в `service_accounts.credentials` зашифрованными Fernet (`Accounts.fernet`), отдаются только владельцу
сессии. Значения ключей не попадают ни в ошибки, ни в журнал: в сообщениях — только имена сервисов и полей.
"""
from __future__ import annotations

import json
import logging

from cryptography.fernet import InvalidToken
from fastapi import APIRouter, Depends, Request, Response

from ..db import now_ms, tx
from ..events import Device
from .auth import body
from .deps import device
from .errors import ApiError

router = APIRouter(prefix="/services")
log = logging.getLogger(__name__)

# Сервис → (обязательные поля, необязательные). Имена полей — как у `Creds` клиентов (ПК `providers/*`).
FIELDS: dict[str, tuple[frozenset[str], frozenset[str]]] = {
    "soundcloud": (frozenset({"client_id"}), frozenset({"oauth_token"})),
    "yandex": (frozenset({"token"}), frozenset()),
    "youtube": (frozenset({"cookie"}), frozenset()),
    "spotify": (frozenset({"sp_dc"}), frozenset()),
}
ALIASES = {"sc": "soundcloud", "ym": "yandex", "yt": "youtube", "sp": "spotify"}
# Cookie YouTube — самое длинное (несколько КБ); 16 КБ с запасом, больше — не ключ, а мусор.
MAX_VALUE = 16 * 1024
MAX_NAME = 200


def service_key(raw: str) -> str:
    key = ALIASES.get(raw, raw)
    if key not in FIELDS:
        raise ApiError(404, "unknown_service", "Такого сервиса нет")
    return key


def _clean(service: str, value: object) -> dict[str, str]:
    """Поля одного сервиса → только известные непустые строки. Значения в ошибку не идут — только имена полей."""
    if not isinstance(value, dict):
        raise ApiError(400, "bad_request", f"{service}: ожидается объект")
    required, optional = FIELDS[service]
    unknown = set(value) - required - optional - {"name"}
    if unknown:
        raise ApiError(400, "bad_request", f"{service}: лишние поля {', '.join(sorted(map(str, unknown)))[:200]}")
    out: dict[str, str] = {}
    for field in sorted(required | optional):
        v = value.get(field)
        if not isinstance(v, (str, type(None))) or (isinstance(v, str) and len(v) > MAX_VALUE):
            raise ApiError(400, "bad_request", f"{service}.{field}: строка до {MAX_VALUE} символов")
        v = (v or "").strip()
        if not v:
            if field in required:
                raise ApiError(400, "bad_request", f"{service}: нет поля {field}")
            continue
        out[field] = v
    return out


def _name(value: dict) -> str | None:
    name = value.get("name")
    return name.strip()[:MAX_NAME] if isinstance(name, str) and name.strip() else None


@router.get("/credentials")
async def get_credentials(request: Request, dev: Device = Depends(device)):
    st = request.app.state
    rows = st.con.execute("SELECT service, credentials FROM service_accounts WHERE user_id = ?", (dev.user_id,)).fetchall()
    out: dict[str, dict[str, str]] = {}
    for r in rows:
        if r["service"] not in FIELDS:
            continue  # убранные (vk) и будущие — не отдаём клиентам, которые о них не знают
        try:
            out[r["service"]] = json.loads(st.accounts.fernet.decrypt(r["credentials"]))
        except (InvalidToken, ValueError, TypeError):
            # сменили ключ Fernet: «сервиса нет» клиенты поняли бы как «отключили на другом устройстве» и
            # отключили бы его у себя — на всех устройствах. Пусть лучше обмен не пройдёт, ничего не тронув.
            log.error("входы в сервисы: не расшифровать %s у %s — сменился SONAR_FERNET_KEY?", r["service"], dev.user_id)
            raise ApiError(500, "credentials_unreadable", "Входы в сервисы на сервере не читаются") from None
    return out


@router.put("/credentials", status_code=204)
async def put_credentials(request: Request, dev: Device = Depends(device)):
    """Тело — `{сервис: {поля…, name?}}` или `{сервис: null}` (отключить). Остальные сервисы не трогаются."""
    st = request.app.state
    data = await body(request)
    # сначала всё проверить: плохое поле не должно записать половину
    plan = [(svc, None if value is None else _clean(svc, value), None if value is None else _name(value))
            for svc, value in ((service_key(str(raw)), value) for raw, value in data.items())]
    t = now_ms()
    with tx(st.con):
        for svc, fields, name in plan:
            if fields is None:
                st.con.execute("DELETE FROM service_accounts WHERE user_id = ? AND service = ?", (dev.user_id, svc))
                continue
            blob = st.accounts.fernet.encrypt(json.dumps(fields, separators=(",", ":"), sort_keys=True).encode())
            st.con.execute(
                "INSERT INTO service_accounts (user_id, service, credentials, ext_name, connected_at) VALUES (?, ?, ?, ?, ?)"
                " ON CONFLICT (user_id, service) DO UPDATE SET credentials = excluded.credentials,"
                " ext_name = COALESCE(excluded.ext_name, service_accounts.ext_name)",
                (dev.user_id, svc, blob, name, t))
    return Response(status_code=204)


@router.delete("/{service}", status_code=204)
async def delete_service(service: str, request: Request, dev: Device = Depends(device)):
    con = request.app.state.con
    svc = service_key(service)
    with tx(con):
        con.execute("DELETE FROM service_accounts WHERE user_id = ? AND service = ?", (dev.user_id, svc))
    return Response(status_code=204)
