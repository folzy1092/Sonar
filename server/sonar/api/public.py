"""`GET /api/public/users/{username}` — шапка профиля для страницы сайта `/@username` (API.md §1).

Разделы и приватность — `sonar/public_profile.py`. Забаненных не показываем.
"""
from __future__ import annotations

from fastapi import APIRouter, Request, Response

from .. import public_profile
from ..db import now_ms
from .errors import ApiError

router = APIRouter()

CACHE_S = 60


@router.get("/public/users/{username}")
async def public_user(username: str, request: Request, response: Response):
    r = request.app.state.con.execute(
        "SELECT id, username, display_name, number, created_at FROM users WHERE username = ? AND banned = 0",
        (username.removeprefix("@"),)).fetchone()
    if r is None:
        raise ApiError(404, "not_found", "Такого профиля нет")
    response.headers["Cache-Control"] = f"public, max-age={CACHE_S}"
    return public_profile.build(request.app.state.con, r, now_ms())
