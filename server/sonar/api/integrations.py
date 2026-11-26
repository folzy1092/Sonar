"""Интеграции (API.md §7, SERVER_PROMPT этап 5): ключ API и «сейчас играет» для selfbot и своих сервисов.

Ключ один на аккаунт и тот же, что в боте (BOT.md §2.6а): создаётся / перевыпускается из приложения сессией,
а `/oauth/*` принимают сам ключ — заголовком `Authorization: Bearer <ключ>` или `?token=`, как у Dotify.
`/oauth/now` собирается из последнего `PUT /player/state`: метаданные трека клиент кладёт в `state.track`.
"""
from __future__ import annotations

import json

from fastapi import APIRouter, Depends, Request, Response

from ..db import now_ms
from ..sessions import Session
from .deps import bearer, session
from .errors import ApiError

router = APIRouter()

# Клиент шлёт состояние раз в 30 с, пока играет (ПК `HEARTBEAT_MS`, iPhone так же). Тишина дольше —
# приложение закрыли или пропала сеть: показываем паузу, а не трек, который «играет» вечно.
STALE_MS = 90_000
SOURCES = {"sc": "soundcloud", "ym": "yandex", "yt": "youtube", "vk": "vk", "sp": "spotify", "local": "local"}


def _user(request: Request, s: Session):
    user = request.app.state.accounts.by_id(s.user_id)
    if user is None:
        raise ApiError(401, "unauthorized", "Нет или неверная сессия")
    return user


def _created_at(request: Request, user_id: str) -> int | None:
    r = request.app.state.con.execute("SELECT created_at FROM api_keys WHERE user_id = ?", (user_id,)).fetchone()
    return r["created_at"] if r else None


@router.post("/integrations/api-key")
async def new_key(request: Request, s: Session = Depends(session)):
    user = _user(request, s)
    key = request.app.state.accounts.new_token(user)
    return {"key": key, "created_at": _created_at(request, user.id)}


@router.delete("/integrations/api-key", status_code=204)
async def drop_key(request: Request, s: Session = Depends(session)):
    request.app.state.accounts.revoke_token(_user(request, s))
    return Response(status_code=204)


@router.get("/me/integration")
async def my_key(request: Request, s: Session = Depends(session)):
    user = _user(request, s)
    return {"key": request.app.state.accounts.token(user), "created_at": _created_at(request, user.id)}


def _key_user(request: Request, token: str | None):
    key = bearer(request) or (token or "").strip()
    user = request.app.state.accounts.user_by_token(key) if key else None
    if user is None:
        raise ApiError(401, "unauthorized", "Нет или неверный ключ API")
    return user


def _int(v, default: int = 0) -> int:
    return int(v) if isinstance(v, (int, float)) and not isinstance(v, bool) else default


def _text(v) -> str:
    return v if isinstance(v, str) else ""


def now_json(state: dict | None, heartbeat_at: int | None, now: int) -> dict:
    """Ответ `/oauth/now` в формате Dotify из последнего PlayerState (чистая функция — для тестов).

    Как у Dotify: `position_ms` — позиция на момент `updated_at` (когда пришёл снимок), досчитывает читатель.
    Сервер сам не прибавляет `now − updated_at`, иначе читатель прибавит ещё раз и будет спешить на возраст снимка."""
    updated = heartbeat_at or now
    ref = state.get("ref") if state else None
    if not isinstance(ref, str) or ":" not in ref:
        return {"is_playing": False, "position_ms": 0, "state": "stopped", "track": None, "updated_at": updated}
    prefix, track_id = ref.split(":", 1)
    meta = state.get("track") if isinstance(state.get("track"), dict) else {}
    playing = bool(state.get("is_playing")) and now - updated <= STALE_MS
    duration_ms = max(_int(meta.get("duration_ms")), 0)
    position = _int(state.get("position_ms"))
    if duration_ms:
        position = min(position, duration_ms)
    position = max(position, 0)
    cover = meta.get("cover_url")
    track = {
        "artist": _text(meta.get("artist")),
        "context": state.get("context") if isinstance(state.get("context"), str) else None,
        "cover_art": cover if isinstance(cover, str) and cover else None,
        "duration": duration_ms // 1000,
        "duration_ms": duration_ms,
        "id": track_id,
        "is_playing": playing,
        "position_ms": position,
        "source": SOURCES.get(prefix, prefix),
        "title": _text(meta.get("title")),
        "track_id": track_id,
        "updated_at": updated,
    }
    return {"is_playing": playing, "position_ms": position, "state": "playing" if playing else "paused",
            "track": track, "updated_at": updated}


@router.get("/oauth/now")
async def oauth_now(request: Request, token: str | None = None):
    user = _key_user(request, token)
    r = request.app.state.con.execute("SELECT state_json, heartbeat_at FROM player_state WHERE user_id = ?",
                                      (user.id,)).fetchone()
    state = None
    if r and r["state_json"]:
        try:
            loaded = json.loads(r["state_json"])
        except ValueError:
            loaded = None
        state = loaded if isinstance(loaded, dict) else None
    return now_json(state, r["heartbeat_at"] if r else None, now_ms())


@router.get("/oauth/profile")
async def oauth_profile(request: Request, token: str | None = None):
    user = _key_user(request, token)
    return {"username": user.username, "display_name": user.display_name, "avatar_url": None}
