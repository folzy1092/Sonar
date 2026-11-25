"""`GET /api/public/users/{username}` — шапка профиля для страницы сайта `/@username` (API.md §1).

Пока только шапка: остальное `PublicProfile` ждёт ответа владельца про приватность. Забаненных не показываем.
"""
from __future__ import annotations

from fastapi import APIRouter, Request, Response

from .errors import ApiError

router = APIRouter()

CACHE_S = 60


@router.get("/public/users/{username}")
async def public_user(username: str, request: Request, response: Response):
    r = request.app.state.con.execute(
        "SELECT username, display_name, number, created_at FROM users WHERE username = ? AND banned = 0",
        (username.removeprefix("@"),)).fetchone()
    if r is None:
        raise ApiError(404, "not_found", "Такого профиля нет")
    response.headers["Cache-Control"] = f"public, max-age={CACHE_S}"
    return {"username": r["username"], "display_name": r["display_name"], "number": r["number"],
            "avatar_url": None, "created_at": r["created_at"]}
