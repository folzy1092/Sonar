"""HTTP-часть сервера: админка (`/admin`) и API под `/api` (`sonar/api/`).

Запуск отдельно от бота (локально посмотреть админку): `python -m sonar.web` (`--demo` — на тестовой базе
`data/demo.db` с выдуманными пользователями и событиями). В `python -m sonar` поднимается вместе с ботом.
"""
from __future__ import annotations

import argparse
import logging
import sqlite3

from cryptography.fernet import Fernet
from fastapi import FastAPI, Request
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles

from . import api, config
from .accounts import Accounts
from .admin import prefs
from .admin.auth import FACTORY_LOGIN, AdminAuth
from .admin.web import BASE, HERE, router as admin_router
from .config import Settings
from .status import Status

log = logging.getLogger("sonar.web")


def create_app(con: sqlite3.Connection, settings: Settings, status: Status | None = None,
               accounts: Accounts | None = None, bot_username: str = "SonarMusicApp") -> FastAPI:
    """status и accounts — общие с ботом (`python -m sonar`): одни лимиты входа и одна сводка статуса.
    Без них (`python -m sonar.web`, тесты) — свои; `/api/status` тогда читает последние проверки из базы."""
    app = FastAPI(title="Sonar", docs_url=None, redoc_url=None, openapi_url=None)
    app.state.con, app.state.settings = con, settings
    app.state.status = status or Status(con, settings.data_dir, settings)
    # Ключ Fernet есть всегда, кроме тестов: config.load() создаёт локальный, на сервере он в .env.
    app.state.accounts = accounts or Accounts(con, settings.fernet_key or Fernet.generate_key().decode())
    app.state.bot_username = bot_username
    app.state.on_telegram_linked = None  # бот ставит: «Успешно! Аккаунт привязан» после «Разрешить» в приложении
    app.state.admin_auth = AdminAuth(con)
    factory_password = app.state.admin_auth.ensure_factory()
    if factory_password:
        # Единственный раз, когда пароль виден: в базе только хэш. Потерял — python -m sonar.admin passwd.
        log.warning("создан заводской админ %s, пароль: %s — войди и смени его (показывается один раз)",
                    FACTORY_LOGIN, factory_password)
    prefs.apply(con, settings)
    app.mount(BASE + "/static", StaticFiles(directory=str(HERE / "static")), name="admin-static")
    app.include_router(admin_router)

    @app.middleware("http")
    async def admin_host(request: Request, call_next):
        # Поддомен admin.* (Cloudflare Tunnel) смотрит в тот же процесс: корень ведёт в админку.
        if request.headers.get("host", "").startswith("admin.") and not request.url.path.startswith(BASE):
            return RedirectResponse(BASE + "/", status_code=303)
        return await call_next(request)

    api.install(app)
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
