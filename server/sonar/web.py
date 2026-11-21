"""HTTP-часть сервера: админка (`/admin`) и первые эндпоинты API (`POST /events`, `GET /config`).

Запуск отдельно от бота (локально посмотреть админку): `python -m sonar.web` (`--demo` — на тестовой базе
`data/demo.db` с выдуманными пользователями и событиями). В `python -m sonar` поднимается вместе с ботом.
"""
from __future__ import annotations

import argparse
import logging
import sqlite3

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from . import config, events
from .admin import prefs
from .admin.auth import AdminAuth
from .admin.web import BASE, HERE, router as admin_router
from .config import Settings

log = logging.getLogger("sonar.web")


def _error(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse({"error": {"code": code, "message": message}}, status_code=status)


def create_app(con: sqlite3.Connection, settings: Settings) -> FastAPI:
    app = FastAPI(title="Sonar", docs_url=None, redoc_url=None, openapi_url=None)
    app.state.con, app.state.settings = con, settings
    app.state.admin_auth = AdminAuth(con)
    if app.state.admin_auth.ensure_factory():
        log.warning("создан заводской админ folzy — смени пароль при первом входе")
    prefs.apply(con, settings)
    app.mount(BASE + "/static", StaticFiles(directory=str(HERE / "static")), name="admin-static")
    app.include_router(admin_router)

    @app.middleware("http")
    async def admin_host(request: Request, call_next):
        # Поддомен admin.* (Cloudflare Tunnel) смотрит в тот же процесс: корень ведёт в админку.
        if request.headers.get("host", "").startswith("admin.") and not request.url.path.startswith(BASE):
            return RedirectResponse(BASE + "/", status_code=303)
        return await call_next(request)

    @app.get("/health")
    async def health():
        return {"ok": True}

    @app.get("/config")
    async def get_config():
        return prefs.public_config(con)

    @app.post("/events")
    async def post_events(request: Request):
        auth = request.headers.get("authorization", "")
        dev = events.session_device(con, auth[7:].strip()) if auth.lower().startswith("bearer ") else None
        if dev is None:
            return _error(401, "unauthorized", "Нет или неверная сессия")
        try:
            body = await request.json()
        except ValueError:
            return _error(400, "bad_json", "Тело — JSON")
        items = body.get("events") if isinstance(body, dict) else None
        if not isinstance(items, list):
            return _error(400, "bad_events", "Нужно поле events — список")
        if len(items) > events.BATCH_MAX:
            return _error(400, "too_many", f"Не больше {events.BATCH_MAX} событий за раз")
        return {"accepted": events.record(con, dev, items)}

    return app


def main() -> None:
    import uvicorn

    from .db import connect

    ap = argparse.ArgumentParser(description="Sonar: админка и API без бота")
    ap.add_argument("--demo", action="store_true", help="тестовая база data/demo.db с выдуманными данными")
    ap.add_argument("--port", type=int, default=None)
    args = ap.parse_args()
    s = config.load()
    path = s.data_dir / ("demo.db" if args.demo else "sonar.db")
    con = connect(path)
    if args.demo:
        from .admin.demo import seed
        seed(con)
        # Демо всегда с заводским входом: пароль, сменённый при прошлом просмотре, не мешает зайти снова.
        con.execute("DELETE FROM admins")
    port = args.port or s.port
    print(f"Админка: http://127.0.0.1:{port}{BASE}/  (база {path})")
    uvicorn.run(create_app(con, s), host="127.0.0.1", port=port, log_level="warning")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    main()
