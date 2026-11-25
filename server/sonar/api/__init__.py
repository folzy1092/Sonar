"""API сервера под `/api` (SERVER_PROMPT §1): по модулю на раздел API.md, общие ошибки, лимиты и сессия — здесь.

`install(app)` вешает на приложение обработку ошибок, CORS для сайта, лимит запросов на IP и роутеры.
Первые методы (`/health`, `/config`, `/events`) жили в корне — там они остаются алиасами, пока клиенты не переедут.
"""
from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from . import auth, errors, integrations, me, misc, public, services, status, sync
from .deps import API_PER_IP, AUTH_PER_IP, WINDOW_S, Limiter, client_ip
from .errors import PREFIX, error, is_api

# Из браузера API зовёт только сайт; приложениям CORS не нужен.
SITE_ORIGINS = ["https://try-sonar.ru", "https://www.try-sonar.ru"]


def install(app: FastAPI) -> None:
    errors.install(app)
    api_limit = Limiter(limit=API_PER_IP, window_s=WINDOW_S)
    auth_limit = Limiter(limit=AUTH_PER_IP, window_s=WINDOW_S)
    app.state.api_limits = (api_limit, auth_limit)

    @app.middleware("http")
    async def rate_limit(request: Request, call_next):
        path = request.url.path
        if is_api(path) and request.method != "OPTIONS":
            ip = client_ip(request)
            # Строже — только попытки (POST): опрос быстрой ссылки раз в 2 с за 5 минут сюда не упирается.
            strict = request.method == "POST" and path.startswith(PREFIX + "/auth/")
            if not api_limit.take(ip) or (strict and not auth_limit.take(ip)):
                return error(429, "too_many", "Слишком много запросов, попробуй через минуту",
                             headers={"Retry-After": str(WINDOW_S)})
        return await call_next(request)

    # После лимита — значит, снаружи: ответ 429 тоже получает заголовки CORS, и сайт видит ошибку, а не «сбой сети».
    app.add_middleware(CORSMiddleware, allow_origins=SITE_ORIGINS, allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
                       allow_headers=["Authorization", "Content-Type"], max_age=600)

    for router in (misc.router, status.router, auth.router, me.router, sync.router, services.router,
                   integrations.router, public.router):
        app.include_router(router, prefix=PREFIX)
    app.include_router(misc.router, include_in_schema=False)  # старые пути в корне — алиасы
