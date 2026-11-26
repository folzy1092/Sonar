"""Вход и регистрация (API.md §1): пароль, Telegram, быстрая ссылка. Логика — `accounts.py` и `sessions.py`."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Request, Response

from .. import bans, sessions
from ..accounts import AccountError, RateLimit
from ..sessions import DeviceError, DeviceInfo
from .deps import banned_error, client_ip, session
from .errors import ApiError

router = APIRouter(prefix="/auth")

# Регистрация — 5 в час на IP (SPEC §3.4); вход считает сам `Accounts.verify` (логин, IP).
REGISTER_PER_IP = 5
REGISTER_WINDOW_S = 3600
_register_limit = RateLimit(limit=REGISTER_PER_IP, window_s=REGISTER_WINDOW_S)

# AccountError → (HTTP, код, текст). Нет логина и неверный пароль — одним ответом: не подсказываем, что логин есть.
ERRORS = {
    "login_format": (400, "login_format", "Логин — от 3 до 24 символов: латиница, цифры, «_» и «.»"),
    "login_taken": (409, "login_taken", "Логин уже занят"),
    "password_short": (400, "password_short", "Пароль — от 8 символов"),
    "name_format": (400, "name_format", "Имя — от 1 до 48 символов"),
    "no_user": (401, "bad_credentials", "Неверный логин или пароль"),
    "bad_password": (401, "bad_credentials", "Неверный логин или пароль"),
    "too_many": (429, "too_many", "Слишком много попыток — подожди 15 минут"),
    "no_password": (403, "no_password", "Сначала задай пароль — иначе в аккаунт будет не войти"),
    "tg_taken": (409, "tg_taken", "Этот Telegram уже привязан к другому аккаунту"),
}


def account_error(err: AccountError) -> ApiError:
    if err.code == "banned" and err.ban is not None:
        return banned_error(err.ban)
    status, code, message = ERRORS.get(err.code, (400, err.code, err.code))
    return ApiError(status, code, message, {"Retry-After": "900"} if status == 429 else None)


async def body(request: Request) -> dict:
    try:
        data = await request.json()
    except ValueError:
        raise ApiError(400, "bad_json", "Тело — JSON") from None
    if not isinstance(data, dict):
        raise ApiError(400, "bad_json", "Тело — JSON-объект")
    return data


def device_of(data: dict) -> DeviceInfo:
    try:
        return DeviceInfo.parse(data.get("device"))
    except DeviceError as err:
        raise ApiError(400, "bad_device", str(err)) from None


def text_field(data: dict, key: str, limit: int = 256) -> str:
    v = data.get(key)
    if not isinstance(v, str) or not v:
        raise ApiError(400, "bad_request", f"Нужно поле {key}")
    return v[:limit]


def _signed_in(request: Request, user_id: str, dev: DeviceInfo) -> dict:
    st = request.app.state
    token = sessions.create(st.con, user_id, dev)
    return {"session": token, "user": sessions.user_json(st.con, st.accounts.by_id(user_id))}


@router.post("/register")
async def register(request: Request):
    st = request.app.state
    data = await body(request)
    login, password, dev = text_field(data, "login", 64), text_field(data, "password"), device_of(data)
    if not st.settings.registration_open:
        raise ApiError(403, "registration_closed", "Регистрация временно закрыта")
    ip = client_ip(request)
    if _register_limit.blocked(ip):
        raise ApiError(429, "too_many", "Слишком много регистраций с этого адреса — попробуй через час",
                       {"Retry-After": str(REGISTER_WINDOW_S)})
    ban = bans.of_device(st.con, dev.id)
    if ban:
        raise banned_error(ban)   # с устройства заблокированного новый аккаунт не завести
    try:
        user = await st.accounts.register(login, password)
    except AccountError as err:
        raise account_error(err) from None
    _register_limit.hit(ip)
    return _signed_in(request, user.id, dev)


@router.post("/login")
async def login(request: Request):
    st = request.app.state
    data = await body(request)
    login_, password, dev = text_field(data, "login", 64), text_field(data, "password"), device_of(data)
    try:
        user = await st.accounts.verify(login_, password, ip=client_ip(request))
    except AccountError as err:
        raise account_error(err) from None
    return _signed_in(request, user.id, dev)


@router.post("/logout", status_code=204)
async def logout(request: Request, s: sessions.Session = Depends(session)):
    sessions.drop(request.app.state.con, s.id)
    return Response(status_code=204)


# ---- быстрая ссылка (BOT.md §3) ----

def _link_urls(request: Request, code: str, prefix: str) -> tuple[str, str]:
    st = request.app.state
    return f"{st.settings.site_url}/auth/{code}", f"https://t.me/{st.bot_username}?start={prefix}_{code}"


@router.post("/link")
async def create_link(request: Request):
    data = await body(request)
    # Только новое устройство. Запрос «от Telegram» создаёт бот сам: снаружи id и ник Telegram не проверить.
    if "telegram" in data and "device" not in data:
        raise ApiError(403, "forbidden", "Запрос от Telegram создаёт только бот")
    dev = device_of(data)
    sessions.purge(request.app.state.con)
    code, link = sessions.new_link(request.app.state.con, "device", dev.__dict__)
    url, bot_url = _link_urls(request, code, "link")
    return {"code": code, "url": url, "bot_url": bot_url, "expires_at": link.expires_at}


def _link_or_404(request: Request, code: str) -> sessions.Link:
    link = sessions.get_link(request.app.state.con, code)
    if link is None:
        raise ApiError(404, "not_found", "Ссылка не найдена")
    return link


def _poll_answer(request: Request, link: sessions.Link) -> dict:
    st = request.app.state
    if link.status == "done":
        return {"status": "expired"}  # сессию уже забрали — второй раз не выдаём
    if link.status != "approved":
        return {"status": link.status}
    token = sessions.claim(st.con, link)
    if token is None:
        return {"status": "expired"}
    return {"status": "approved", "session": token, "user": sessions.user_json(st.con, st.accounts.by_id(link.user_id))}


@router.get("/link/{code}/poll")
async def poll_link(request: Request, code: str):
    link = _link_or_404(request, code)
    if link.kind != "device":
        raise ApiError(404, "not_found", "Ссылка не найдена")
    return _poll_answer(request, link)


def _requester(link: sessions.Link) -> dict:
    if link.kind == "telegram":
        nick = link.data.get("username")
        return {"kind": "telegram", "name": f"Telegram @{nick}" if nick else f"Telegram {link.data.get('id')}"}
    dev = DeviceInfo.parse(link.data)
    return {"kind": "device", "name": dev.label(), "platform": dev.platform}


@router.get("/link/{code}")
async def link_info(request: Request, code: str, _s: sessions.Session = Depends(session)):
    link = _link_or_404(request, code)
    if link.kind not in ("device", "telegram"):
        raise ApiError(404, "not_found", "Ссылка не найдена")
    if link.status != "pending":
        raise ApiError(410, "link_closed", "Ссылка истекла или уже использована")
    return {"for": _requester(link), "created_at": link.created_at, "expires_at": link.expires_at}


@router.post("/link/{code}/approve", status_code=204)
async def approve_link(request: Request, code: str, s: sessions.Session = Depends(session)):
    st = request.app.state
    link = _link_or_404(request, code)
    if link.kind not in ("device", "telegram") or not sessions.decide(st.con, link, "approved", s.user_id):
        raise ApiError(410, "link_closed", "Ссылка истекла или уже использована")
    if link.kind == "telegram":
        user = st.accounts.link_tg(st.accounts.by_id(s.user_id), int(link.data["id"]), link.data.get("username"))
        hook = getattr(st, "on_telegram_linked", None)
        if hook:
            await hook(int(link.data["id"]), user)
    return Response(status_code=204)


@router.post("/link/{code}/reject", status_code=204)
async def reject_link(request: Request, code: str, _s: sessions.Session = Depends(session)):
    link = _link_or_404(request, code)
    if link.kind not in ("device", "telegram") or not sessions.decide(request.app.state.con, link, "rejected"):
        raise ApiError(410, "link_closed", "Ссылка истекла или уже использована")
    return Response(status_code=204)


# ---- Telegram ----

@router.post("/telegram/start")
async def telegram_start(request: Request):
    """`login` — без авторизации, подтверждает бот (у кого Telegram привязан); `link` — привязать Telegram к себе."""
    st = request.app.state
    data = await body(request)
    purpose = data.get("purpose")
    sessions.purge(st.con)
    if purpose == "login":
        dev = device_of(data)
        code, link = sessions.new_link(st.con, "device", dev.__dict__)
        prefix = "link"
    elif purpose == "link":
        s = session(request)
        code, link = sessions.new_link(st.con, "tg_link", {}, s.user_id)
        prefix = "tg"
    else:
        raise ApiError(400, "bad_request", "purpose — login или link")
    return {"request_id": code, "link": _link_urls(request, code, prefix)[1], "expires_at": link.expires_at}


@router.get("/telegram/poll/{request_id}")
async def telegram_poll(request: Request, request_id: str):
    link = _link_or_404(request, request_id)
    if link.kind == "device":
        return _poll_answer(request, link)
    # Привязка — только тот, кто её начал.
    s = session(request)
    if link.kind != "tg_link" or link.user_id != s.user_id:
        raise ApiError(404, "not_found", "Запрос не найден")
    if link.status != "approved":
        return {"status": link.status}
    st = request.app.state
    return {"status": "approved", "user": sessions.user_json(st.con, st.accounts.by_id(s.user_id))}


@router.delete("/telegram", status_code=204)
async def telegram_unlink(request: Request, s: sessions.Session = Depends(session)):
    st = request.app.state
    try:
        st.accounts.unlink_tg(st.accounts.by_id(s.user_id))
    except AccountError as err:
        raise account_error(err) from None
    return Response(status_code=204)
