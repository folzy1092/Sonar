"""Ошибки API в одном виде (API.md): `{"error": {"code", "message"}}`."""
from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.exception_handlers import http_exception_handler, request_validation_exception_handler
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

PREFIX = "/api"

# Стандартные ответы Starlette (404 неизвестного пути, 405 не тот метод) — своими кодами.
_HTTP_CODES = {400: "bad_request", 401: "unauthorized", 403: "forbidden", 404: "not_found",
               405: "method_not_allowed", 409: "conflict", 413: "too_large", 429: "too_many"}


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str, headers: dict[str, str] | None = None):
        super().__init__(code)
        self.status, self.code, self.message, self.headers = status, code, message, headers


def error(status: int, code: str, message: str, headers: dict[str, str] | None = None) -> JSONResponse:
    return JSONResponse({"error": {"code": code, "message": message}}, status_code=status, headers=headers)


def is_api(path: str) -> bool:
    return path == PREFIX or path.startswith(PREFIX + "/")


def install(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def on_api_error(_request: Request, exc: ApiError):
        return error(exc.status, exc.code, exc.message, exc.headers)

    @app.exception_handler(StarletteHTTPException)
    async def on_http(request: Request, exc: StarletteHTTPException):
        if not is_api(request.url.path):
            return await http_exception_handler(request, exc)  # админка — как была
        code = _HTTP_CODES.get(exc.status_code, "error")
        message = exc.detail if isinstance(exc.detail, str) else code
        return error(exc.status_code, code, message, getattr(exc, "headers", None))

    @app.exception_handler(RequestValidationError)
    async def on_validation(request: Request, exc: RequestValidationError):
        if not is_api(request.url.path):
            return await request_validation_exception_handler(request, exc)
        first = exc.errors()[0] if exc.errors() else {}
        where = ".".join(str(p) for p in first.get("loc", ()) if p != "body")
        return error(400, "bad_request", f"{where}: {first.get('msg', 'неверные данные')}" if where else "Неверные данные")
