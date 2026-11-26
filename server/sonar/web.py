"""HTTP-часть сервера: админка (`/admin`), API под `/api` (`sonar/api/`) и сайт `try-sonar.ru` из корня.

Сайт — собранный `site/dist`, который `deploy/sync.py` кладёт в `site/` рядом с `data/` (SERVER_PROMPT этап 6).
Отдаётся только то, что не нашли API и админка: их ответы и ошибки не меняются.

Запуск отдельно от бота (локально посмотреть админку): `python -m sonar.web` (`--demo` — на тестовой базе
`data/demo.db` с выдуманными пользователями и событиями). В `python -m sonar` поднимается вместе с ботом.
"""
from __future__ import annotations

import argparse
import asyncio
import logging
import os
import sqlite3
import time
from pathlib import Path

from cryptography.fernet import Fernet
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from starlette.exceptions import HTTPException

from . import api, builds, config, diag
from .accounts import Accounts
from .admin import prefs
from .admin.auth import FACTORY_LOGIN, AdminAuth
from .admin.web import BASE, HERE, _ip, router as admin_router, warm_site_addresses
from .config import Settings
from .api.errors import is_api
from .status import Status
from .updater import Updater

log = logging.getLogger("sonar.web")
# Что клиенты дёргают постоянно: в консоли хостинга они заглушили бы остальное.
# /api/diag/payload — страница /diag за прогон дёргает его 30 раз; итог виден на самой странице.
QUIET = {"/health", "/api/health", "/api/player/state", "/api/status/report", "/api/oauth/now", "/oauth/now",
         "/api/diag/payload"}
UA_MAX = 40
# Страница /diag (SERVER_DIAG_PROMPT §4.2): без внешних файлов, ходит только на свой /api/diag*.
DIAG_PAGE = (Path(__file__).with_name("diag_page.html")).read_text(encoding="utf-8")
DIAG_HEADERS = {"Cache-Control": "no-store", "Content-Security-Policy":
                "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'"}

# Файлы Astro с хэшем в имени не меняются никогда; HTML — всегда сверять, остальное (картинки, шрифты) — час.
IMMUTABLE = "public, max-age=31536000, immutable"
NO_CACHE = "no-cache"
ASSET_CACHE = "public, max-age=3600"


def site_dir(settings: Settings) -> Path:
    return Path(os.environ.get("SONAR_SITE_DIR") or settings.data_dir.parent / "site")


def _cache_control(path: str, media_type: str | None) -> str:
    if path.startswith("/_astro/"):
        return IMMUTABLE
    return NO_CACHE if (media_type or "").startswith("text/html") else ASSET_CACHE


def install_site(app: FastAPI, directory: Path) -> None:
    """Сайт из корня: www → без www, неизвестный приложению GET — файл сайта (или его 404.html).

    Наличие сайта проверяется на каждый запрос, а не при старте: «Сервер → Обновить сайт» подменяет папку на
    лету (`updater.update_site`), и первая установка тоже не требует перезапуска."""
    files = StaticFiles(directory=str(directory), html=True, check_dir=False)

    @app.middleware("http")
    async def site(request: Request, call_next):
        if not (directory / "index.html").is_file():
            return await call_next(request)  # сайта нет — только API и админка
        path = request.url.path
        reading = request.method in ("GET", "HEAD")
        mine = reading and not is_api(path) and not path.startswith(BASE)
        host = request.headers.get("host", "")
        if mine and host.startswith("www."):
            query = f"?{request.url.query}" if request.url.query else ""
            return RedirectResponse(f"https://{host.removeprefix('www.')}{path}{query}", status_code=301)
        response = await call_next(request)
        if not mine or response.status_code != 404:
            return response
        try:
            page = await files.get_response(path.lstrip("/") or ".", request.scope)
        except HTTPException:
            return response
        if page.status_code in (301, 302, 307, 308):
            # «/faq» → «/faq/»: StaticFiles пишет абсолютный адрес со схемой, которую видит uvicorn, а за прокси
            # хостинга это http. Относительный адрес оставляет браузер на https.
            query = f"?{request.url.query}" if request.url.query else ""
            page.headers["location"] = f"{path}/{query}"
            return page
        page.headers["Cache-Control"] = _cache_control(path, page.media_type)
        return page


def create_app(con: sqlite3.Connection, settings: Settings, status: Status | None = None,
               accounts: Accounts | None = None, bot_username: str = "SonarMusicApp",
               site: Path | None = None, updater: Updater | None = None) -> FastAPI:
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
    app.state.github = builds.GitHub(os.getenv("GITHUB_TOKEN"))  # «Сборки» в админке
    app.state.updater = updater or Updater(settings.data_dir)       # «Сервер» в админке; без бота перезапуска нет
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

    @app.get("/diag", include_in_schema=False)
    async def diag_page():
        return HTMLResponse(DIAG_PAGE, headers=DIAG_HEADERS)

    api.install(app)
    install_site(app, site or site_dir(settings))
    install_access_log(app)          # последним — снаружи всех: видит и ответы сайта, а не их внутренние 404
    warm_site_addresses()            # адреса прокси ищутся в фоне до первых запросов, а не на них
    return app


def _log_request(request: Request, status: int, started: float, sent: int, finished: bool) -> None:
    if request.url.path in QUIET:
        return
    ua = (request.headers.get("user-agent") or "-")[:UA_MAX]
    log.info("HTTP %s %s %s -> %s %d мс %d Б%s ua=%s", _ip(request), request.method, request.url.path[:120], status,
             int((time.monotonic() - started) * 1000), sent, "" if finished else " ОБОРВАН", ua)


def install_access_log(app: FastAPI) -> None:
    """Строка в консоль на каждый запрос, когда тело ушло до конца или оборвалось: настоящий IP (за прокси), метод,
    путь без query (в нём бывают ключи), код, время до последнего байта, сколько байт ушло, начало User-Agent.
    Нужна, чтобы увидеть, доходят ли запросы до сервера и уходят ли ответы целиком: uvicorn при log_level=warning
    молчит. Заодно — счётчик запросов и монитор event loop для `/api/diag`."""

    @app.middleware("http")
    async def access_log(request: Request, call_next):
        diag.MONITOR.start(asyncio.get_running_loop())    # один раз на loop
        diag.REQUESTS.hit()
        started = time.monotonic()
        try:
            response = await call_next(request)
        except Exception:
            _log_request(request, 500, started, 0, True)
            raise
        body = response.body_iterator

        async def counted():
            sent, finished = 0, False
            try:
                async for chunk in body:
                    sent += len(chunk)
                    yield chunk
                finished = True
            finally:
                _log_request(request, response.status_code, started, sent, finished)

        response.body_iterator = counted()
        return response


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
