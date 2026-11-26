"""Страницы админки (`/admin/*`): FastAPI + Jinja, формы без JS.

Защита: сессия — httpOnly cookie (SameSite=Strict, Secure за HTTPS), CSRF-токен в каждой форме
(до входа — парный cookie), лимит попыток входа на IP и логин, пока не сменён заводской пароль —
доступна только форма смены. Заголовки: CSP без скриптов, no-store, запрет фреймов.
"""
from __future__ import annotations

import base64
import contextlib
import hashlib
import ipaddress
import os
import secrets
import time
import socket
import threading
from datetime import date, datetime
from pathlib import Path
from urllib.parse import urlencode, urlsplit

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.templating import Jinja2Templates

from .. import bans, builds, subs
from ..events import tz
from . import charts, dashboard, prefs, users
from .auth import PASSWORD_MIN, AdminAuth, AuthError, Session

HERE = Path(__file__).resolve().parent
COOKIE = "sonar_admin"
PRE_COOKIE = "sonar_admin_pre"
BASE = "/admin"

templates = Jinja2Templates(directory=str(HERE / "templates"))
# Стили кладём прямо в страницу: на медленном и нестабильном канале (хостинг за прокси, мобильная сеть) второй запрос
# за admin.css иногда не доходит, и страница остаётся голой. CSP разрешает именно этот текст по хэшу, не любой <style>.
ADMIN_CSS = (HERE / "static" / "admin.css").read_text(encoding="utf-8")
CSS_HASH = base64.b64encode(hashlib.sha256(ADMIN_CSS.encode("utf-8")).digest()).decode()

SERVICE_NAMES = {"soundcloud": "SoundCloud", "yandex": "Яндекс Музыка", "youtube": "YouTube Music", "vk": "VK Музыка",
                 "spotify": "Spotify", "local": "Локальные файлы", None: "Без сервиса"}
PLATFORM_NAMES = {"windows": "Windows", "ios": "iPhone", "android": "Android", "other": "Другое"}
MESSAGES = {
    "bad": "Неверный логин или пароль", "too_many": "Слишком много попыток. Подожди 15 минут",
    "csrf": "Форма устарела — открой страницу заново", "bad_old": "Текущий пароль неверный",
    "mismatch": "Новые пароли не совпадают", "short": f"Новый пароль — от {PASSWORD_MIN} символов",
    "weak": "Этот пароль не подойдёт: он совпадает с логином, старым или заводским",
    "login_format": "Логин — 3–24 символа: a-z 0-9 _ .", "login_taken": "Такой логин или @username уже занят",
    "no_change": "Ничего не изменилось", "no_user": "Пользователь не найден", "bad_plan": "Нет такого тарифа",
    "bad_days": "Срок — от 1 до 3660 дней", "bad_amount": "Сумма не может быть меньше нуля",
    "banned": "Пользователь заблокирован, все его сессии закрыты", "unbanned": "Блокировка снята",
    "login_set": "Логин изменён", "sub_granted": "Подписка выдана", "saved": "Сохранено",
    "password_changed": "Пароль изменён, остальные сессии закрыты", "too_long": "Слишком длинно",
    "not_https": "Ссылка должна начинаться с https://", "bad_period": "Неверный период",
    "device_ended": "Сессия устройства завершена", "logged_out": "Вышел на всех устройствах",
    "sessions_closed": "Остальные сессии админки закрыты",
    "published": "Сборка выпущена: файлы скачаны, клиенты увидят её при следующей проверке",
    "revoked": "Сборка отозвана — клиенты её больше не видят", "restored": "Сборка снова доступна",
    "bad_tag": "Нет такого тега сборки", "bad_channel": "Нет такого канала", "no_build": "Сборка не найдена",
    "no_release": "На GitHub нет такого релиза", "no_assets": "В релизе нет файлов сборки (exe с .sig или Sonar.ipa)",
    "no_version": "Не понял версию из названия релиза", "github": "GitHub не ответил или оборвал загрузку, попробуй ещё",
    "bad_host": "GitHub отправил на незнакомый адрес — загрузка остановлена", "too_big": "Файл больше 200 МБ",
    "no_notes": "Описание на русском и английском обязательно",
    "site_updated": "Сайт обновлён на лету — перезапуск не понадобился", "site_same": "Сайт уже актуален",
    "site_none": "В релизе site-latest нет архива сайта — ничего не менял",
    "site_failed": "Сайт не обновился, остаётся прежний — подробности в журнале сервера",
    "restarting": "Перезапускаюсь: страница не ответит секунд 20–40, потом обнови её",
    "no_restart": "Перезапуск недоступен: сервер запущен не через sync.py, это не бот, или перезапуск уже идёт",
    "bad_part": "Нечего обновлять с таким названием", "bad_duration": "Срок: 30м, 2ч, 3д, 1н или навсегда",
    "no_tg": "У пользователя не привязан Telegram — обращения идут только через бота",
    "report_blocked": "Обращения закрыты", "report_unblocked": "Обращения снова открыты",
}
ACTIONS = {"login": "Вход в админку", "password": "Смена пароля", "ban": "Блокировка", "unban": "Разблокировка",
           "set_login": "Смена логина", "grant_sub": "Подписка вручную", "settings": "Настройки",
           "end_device": "Завершена сессия устройства", "logout_all": "Выход на всех устройствах",
           "close_sessions": "Закрыты другие сессии админки", "login_failed": "Неудачный вход в админку",
           "publish_build": "Выпуск сборки", "revoke_build": "Отзыв сборки", "restore_build": "Возврат сборки",
           "reset_admin_password": "Сброс пароля админки из бота", "ban_expired": "Срок бана вышел",
           "report_block": "Закрыты обращения", "report_unblock": "Открыты обращения", "update_site": "Обновление сайта", "update_server": "Обновление сервера", "restart_server": "Перезапуск сервера", "restart_bot": "Перезапуск бота", "restart_api": "Перезапуск API"}
PERIODS = {"today": 1, "7": 7, "30": 30, "90": 90}
PAGE_MAX = 1_000_000  # дальше страниц всё равно нет, а огромный OFFSET роняет SQLite

router = APIRouter(prefix=BASE)


# ---- общее ----

def _fmt_num(n) -> str:
    if n is None:
        return "—"
    if isinstance(n, float) and not n.is_integer():
        return f"{n:.1f}".replace(".", ",")
    return f"{int(n):,}".replace(",", " ")


def _fmt_dt(ms, with_time: bool = True) -> str:
    if not ms:
        return "—"
    d = datetime.fromtimestamp(ms / 1000, tz())
    return d.strftime("%d.%m.%Y %H:%M" if with_time else "%d.%m.%Y")


def _fmt_day(day: str) -> str:
    return date.fromisoformat(day).strftime("%d.%m.%Y")


templates.env.filters.update(num=_fmt_num, dt=_fmt_dt, day=_fmt_day)
templates.env.globals.update(BASE=BASE, ADMIN_CSS=ADMIN_CSS, SERVICE_NAMES=SERVICE_NAMES, PLATFORM_NAMES=PLATFORM_NAMES, PLANS=subs.PLANS,
                             PLAN_NAMES={k: v[0] for k, v in subs.PLANS.items()},
                             MESSAGES=MESSAGES, ACTIONS=ACTIONS)


def _state(request: Request):
    return request.app.state


_DEFAULT_PROXIES = "127.0.0.0/8,::1/128,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.64.0.0/10,198.18.0.0/15,fc00::/7"


def _trusted_networks() -> list:
    """Прокси, которым можно верить в X-Forwarded-For (SONAR_TRUSTED_PROXIES, IP/CIDR через запятую).
    По умолчанию — локальные и внутренние сети: прокси хостинга перед контейнером."""
    nets = []
    for item in (os.getenv("SONAR_TRUSTED_PROXIES") or _DEFAULT_PROXIES).split(","):
        with contextlib.suppress(ValueError):
            if item.strip():
                nets.append(ipaddress.ip_network(item.strip(), strict=False))
    return nets


SITE_ADDRS_TTL_S = 600
_site_addrs: tuple[float | None, frozenset[str]] = (None, frozenset())   # None — DNS ещё не спрашивали
_dns_lock = threading.Lock()
_dns_busy = False


def _site_host() -> str | None:
    return urlsplit(os.getenv("SONAR_PUBLIC_URL") or "").hostname


def refresh_site_addresses() -> frozenset[str]:
    """Спросить DNS синхронно — только из фонового потока (`warm_site_addresses`) или теста, не из запроса."""
    global _site_addrs
    host = _site_host()
    found: set[str] = set()
    if host:
        with contextlib.suppress(OSError):
            found = {info[4][0] for info in socket.getaddrinfo(host, None)}
    _site_addrs = (time.monotonic(), frozenset(found) or _site_addrs[1])   # DNS не ответил — остаёмся с прежними
    return _site_addrs[1]


def warm_site_addresses() -> threading.Thread | None:
    """Обновить адреса в фоновом потоке, если он ещё не идёт. Зовётся при старте HTTP и когда кэш устарел."""
    global _dns_busy
    with _dns_lock:
        if _dns_busy or not _site_host():
            return None
        _dns_busy = True

    def run() -> None:
        global _dns_busy
        try:
            refresh_site_addresses()
        finally:
            with _dns_lock:
                _dns_busy = False
    thread = threading.Thread(target=run, name="site-dns", daemon=True)
    thread.start()
    return thread


def _site_addresses() -> frozenset[str]:
    """Адреса, в которые смотрит домен сайта (`SONAR_PUBLIC_URL`): на них стоит nginx хостинга. Прокси хостинга подключается
    к контейнеру с публичного адреса, а он не входит в списки частных сетей — без этого сервер принимал адрес прокси за адрес
    клиента, и лимиты входа, регистрации и запросов были общими на всех.

    Запрос DNS не ждёт: синхронный `getaddrinfo` в event loop держал бы и бота, и весь HTTP, пока резолвер думает
    (SERVER_DIAG_PROMPT §4.1.2). Отдаём то, что знаем, а устаревший кэш (10 минут) обновляется в фоне."""
    asked, known = _site_addrs
    if asked is None or time.monotonic() - asked >= SITE_ADDRS_TTL_S:
        warm_site_addresses()
    return known


def _trusted(addr: str) -> bool:
    try:
        ip = ipaddress.ip_address(addr.strip())
    except ValueError:
        return False
    return any(ip in net for net in _trusted_networks()) or str(ip) in _site_addresses()


def _ip(request: Request) -> str:
    # Лимит попыток входа держится на том, что IP нельзя подделать: заголовкам верим, только если
    # соединение пришло от доверенного прокси. Порт открыт наружу — напрямую клиент пишет их сам.
    remote = request.client.host if request.client else "?"
    if not _trusted(remote):
        return remote
    chain = [p.strip() for p in request.headers.get("x-forwarded-for", "").split(",") if p.strip()]
    for candidate in reversed(chain):
        if not _trusted(candidate):
            return candidate
    return request.headers.get("x-real-ip", "").strip() or (chain[0] if chain else remote)


def _https(request: Request) -> bool:
    if request.url.scheme == "https":
        return True
    remote = request.client.host if request.client else ""
    return _trusted(remote) and request.headers.get("x-forwarded-proto") == "https"


def _secure(resp: Response) -> Response:
    resp.headers.update({
        "Content-Security-Policy": "default-src 'none'; style-src 'self' 'sha256-" + CSS_HASH + "'; style-src-attr 'unsafe-inline'; img-src 'self' data:; form-action 'self';"
                                   " frame-ancestors 'none'; base-uri 'none'",
        "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer", "Cache-Control": "no-store",
        "X-Frame-Options": "DENY",
    })
    return resp


def _go(path: str, **q) -> RedirectResponse:
    q = {k: v for k, v in q.items() if v not in (None, "")}
    return _secure(RedirectResponse(BASE + path + ("?" + urlencode(q) if q else ""), status_code=303))


def _page(request: Request, name: str, s: Session | None, status: int = 200, **ctx) -> HTMLResponse:
    msg = request.query_params.get("m")
    err = request.query_params.get("e")
    ctx.update(admin=s.admin if s else None, csrf=s.csrf if s else "", msg=MESSAGES.get(msg), err=MESSAGES.get(err))
    return _secure(templates.TemplateResponse(request, name, ctx, status_code=status))


def _set_session_cookie(request: Request, resp: Response, token: str) -> None:
    resp.set_cookie(COOKIE, token, max_age=12 * 3600, httponly=True, samesite="strict", secure=_https(request),
                    path=BASE)


def _auth(request: Request) -> AdminAuth:
    return _state(request).admin_auth


def _session(request: Request) -> Session | None:
    return _auth(request).session(request.cookies.get(COOKIE))


async def _form(request: Request) -> dict[str, str]:
    return {k: v for k, v in (await request.form()).items() if isinstance(v, str)}


def _same(a: str, b: str) -> bool:
    """compare_digest для строк падает на не-ASCII: токен из формы приходит от клиента, сравниваем байты."""
    return secrets.compare_digest(a.encode(), b.encode())


def _csrf_ok(s: Session, form: dict) -> bool:
    return _same(form.get("csrf", ""), s.csrf)


def _int(v: str, low: int = 1) -> int:
    """Номер страницы из адреса: мусор и меньше `low` — `low`, огромное — `PAGE_MAX` (OFFSET в SQLite — int64)."""
    try:
        return min(max(low, int(v)), PAGE_MAX)
    except ValueError:
        return low


def _guard(request: Request) -> Session | Response:
    """Вошёл и сменил заводской пароль — сессия; иначе — куда отправить."""
    s = _session(request)
    if s is None:
        return _go("/login")
    if s.admin.must_change:
        return _go("/password")
    return s


# ---- вход ----

@router.get("/login", response_class=HTMLResponse)
async def login_page(request: Request):
    if _session(request):
        return _go("/")
    pre = secrets.token_urlsafe(24)
    resp = _page(request, "login.html", None, pre=pre)
    resp.set_cookie(PRE_COOKIE, pre, max_age=3600, httponly=True, samesite="strict", secure=_https(request), path=BASE)
    return resp


@router.post("/login")
async def login_submit(request: Request):
    form = await _form(request)
    pre = request.cookies.get(PRE_COOKIE, "")
    if not pre or not _same(form.get("csrf", ""), pre):
        return _go("/login", e="csrf")
    try:
        token, s = await _auth(request).login(form.get("login", ""), form.get("password", ""), _ip(request),
                                        request.headers.get("user-agent", ""))
    except AuthError as err:
        users.login_failed(_state(request).con, form.get("login", ""), _ip(request), err.code)
        return _go("/login", e=err.code)
    users.audit(_state(request).con, s.admin.login, "login", None, ip=_ip(request))
    resp = _go("/password" if s.admin.must_change else "/")
    _set_session_cookie(request, resp, token)
    resp.delete_cookie(PRE_COOKIE, path=BASE)
    return resp


@router.post("/logout")
async def logout(request: Request):
    s = _session(request)
    form = await _form(request)
    if s and _csrf_ok(s, form):
        _auth(request).logout(s)
    resp = _go("/login")
    resp.delete_cookie(COOKIE, path=BASE)
    return resp


@router.get("/password", response_class=HTMLResponse)
async def password_page(request: Request):
    s = _session(request)
    if s is None:
        return _go("/login")
    return _page(request, "password.html", s, forced=s.admin.must_change, min_len=PASSWORD_MIN,
                 sessions=_auth(request).sessions(s))


@router.post("/sessions/close_others")
async def close_other_sessions(request: Request):
    s = _guard(request)
    if not isinstance(s, Session):
        return s
    form = await _form(request)
    if not _csrf_ok(s, form):
        return _go("/password", e="csrf")
    n = _auth(request).close_others(s)
    if not n:
        return _go("/password", e="no_change")
    users.audit(_state(request).con, s.admin.login, "close_sessions", None, sessions=n)
    return _go("/password", m="sessions_closed")


@router.post("/password")
async def password_submit(request: Request):
    s = _session(request)
    if s is None:
        return _go("/login")
    form = await _form(request)
    if not _csrf_ok(s, form):
        return _go("/password", e="csrf")
    try:
        token, new = await _auth(request).change_password(s, form.get("old", ""), form.get("new", ""), form.get("again", ""),
                                                    _ip(request), request.headers.get("user-agent", ""))
    except AuthError as err:
        return _go("/password", e=err.code)
    users.audit(_state(request).con, new.admin.login, "password", None)
    resp = _go("/", m="password_changed")
    _set_session_cookie(request, resp, token)
    return resp


# ---- дашборд ----

def _period(request: Request) -> tuple[str, str, str]:
    """?p=today|7|30|90 или ?p=custom&from=YYYY-MM-DD&to=YYYY-MM-DD → (ключ, начало, конец)."""
    today = dashboard.today()
    p = request.query_params.get("p", "30")
    if p == "custom":
        try:
            a = date.fromisoformat(request.query_params.get("from", ""))
            b = date.fromisoformat(request.query_params.get("to", ""))
        except ValueError:
            return "30", dashboard.shift(today, -29), today
        a, b = min(a, b), max(a, b)
        b = min(b, date.fromisoformat(today))
        a = min(a, b)  # оба дня в будущем — период из одного сегодняшнего дня, а не «с завтра по сегодня»
        if (b - a).days > 366:
            a = date.fromordinal(b.toordinal() - 366)
        return "custom", a.isoformat(), b.isoformat()
    n = PERIODS.get(p, 30)
    return (p if p in PERIODS else "30"), dashboard.shift(today, 1 - n), today


@router.get("/", response_class=HTMLResponse)
async def dashboard_page(request: Request):
    s = _guard(request)
    if not isinstance(s, Session):
        return s
    key, start, end = _period(request)
    d = dashboard.build(_state(request).con, start, end)
    return _page(request, "dashboard.html", s, d=d, period=key, nav="dash",
                 main_chart=charts.lines(d["series"], [("openers", "открыли", "muted"), ("listeners", "слушали", "accent")]),
                 plays_chart=charts.bars(d["series"], "plays", "треков"),
                 regs_chart=charts.bars(d["series"], "registrations", "регистраций"),
                 subs_chart=charts.bars(d["series"], "subs", "подписок"))


# ---- пользователи ----

@router.get("/users", response_class=HTMLResponse)
async def users_page(request: Request):
    s = _guard(request)
    if not isinstance(s, Session):
        return s
    qp = request.query_params
    q, flt, sort = qp.get("q", "")[:64], qp.get("f", "all"), qp.get("sort", "new")
    flt = flt if flt in users.FILTERS else "all"
    page = _int(qp.get("page", "1"))
    rows, total = users.listing(_state(request).con, q, flt, sort, page)
    pages = max(1, (total + users.PAGE - 1) // users.PAGE)
    link = lambda n: BASE + "/users?" + urlencode({"q": q, "f": flt, "sort": sort, "page": n})  # noqa: E731
    return _page(request, "users.html", s, rows=rows, total=total, q=q, f=flt, sort=sort, page=page, pages=pages,
                 link=link, nav="users")


@router.get("/users/{user_id}", response_class=HTMLResponse)
async def user_page(request: Request, user_id: str):
    s = _guard(request)
    if not isinstance(s, Session):
        return s
    c = users.card(_state(request).con, user_id)
    if c is None:
        return _page(request, "404.html", s, status=404, nav="users")
    return _page(request, "user.html", s, c=c, nav="users")


@router.post("/users/{user_id}/{action}")
async def user_action(request: Request, user_id: str, action: str):
    s = _guard(request)
    if not isinstance(s, Session):
        return s
    form = await _form(request)
    path = f"/users/{user_id}"
    if not _csrf_ok(s, form):
        return _go(path, e="csrf")
    con, who = _state(request).con, s.admin.login
    try:
        if action == "ban":
            ok, duration = bans.parse_duration(form.get("duration", "") or "навсегда")
            if not ok:
                return _go(path, e="bad_duration")
            users.ban(con, who, user_id, form.get("reason", ""), bans.until_from(duration))
            msg = "banned"
        elif action in ("rblock", "runblock"):
            row = con.execute("SELECT tg_id FROM users WHERE id = ?", (user_id,)).fetchone()
            if row is None or not row["tg_id"]:
                return _go(path, e="no_tg")
            if action == "runblock":
                bans.report_unblock(con, who, row["tg_id"])
                msg = "report_unblocked"
            else:
                ok, duration = bans.parse_duration(form.get("duration", "") or "навсегда")
                if not ok:
                    return _go(path, e="bad_duration")
                bans.report_block(con, who, row["tg_id"], form.get("reason", ""), bans.until_from(duration))
                msg = "report_blocked"
        elif action == "unban":
            users.unban(con, who, user_id)
            msg = "unbanned"
        elif action == "login":
            users.set_login(con, who, user_id, form.get("login", ""))
            msg = "login_set"
        elif action == "sub":
            try:
                days, amount = int(form.get("days", "")), int(form.get("amount", "0") or 0)
            except ValueError:
                return _go(path, e="bad_days")
            users.grant_sub(con, who, user_id, form.get("plan", ""), days, amount, form.get("note", ""))
            msg = "sub_granted"
        elif action == "device":
            users.end_device(con, who, user_id, form.get("device", ""))
            msg = "device_ended"
        elif action == "logout_all":
            users.logout_all(con, who, user_id)
            msg = "logged_out"
        else:
            return _go(path)
    except users.UserError as err:
        return _go(path, e=err.code)
    except bans.ModerationError as err:
        return _go(path, e="no_change" if err.code == "no_change" else err.code)
    return _go(path, m=msg)


# ---- настройки и журнал ----

@router.get("/settings", response_class=HTMLResponse)
async def settings_page(request: Request):
    s = _guard(request)
    if not isinstance(s, Session):
        return s
    return _page(request, "settings.html", s, sections=prefs.SECTIONS, values=prefs.values(_state(request).con),
                 bad=request.query_params.get("k"), nav="settings")


@router.post("/settings")
async def settings_submit(request: Request):
    s = _guard(request)
    if not isinstance(s, Session):
        return s
    form = await _form(request)
    if not _csrf_ok(s, form):
        return _go("/settings", e="csrf")
    st = _state(request)
    try:
        new = prefs.parse(form)
    except prefs.PrefError as err:
        return _go("/settings", e=err.code, k=err.key)
    changed = prefs.save(st.con, new)
    if changed:
        prefs.apply(st.con, st.settings)
        users.audit(st.con, s.admin.login, "settings", None, changed=changed)
    return _go("/settings", m="saved" if changed else "no_change")


def _audit_action(request: Request) -> str:
    action = request.query_params.get("a", "")
    return action if action in ACTIONS else ""


@router.get("/audit.csv")
async def audit_csv(request: Request):
    s = _guard(request)
    if not isinstance(s, Session):
        return s
    action = _audit_action(request)
    iso = lambda ms: datetime.fromtimestamp(ms / 1000, tz()).isoformat(timespec="seconds")  # noqa: E731
    body = "\ufeff" + users.audit_csv(_state(request).con, action or None, iso)  # BOM — Excel узнаёт UTF-8
    name = f"sonar-audit{'-' + action if action else ''}-{date.today().isoformat()}.csv"
    return Response(body, media_type="text/csv; charset=utf-8",
                    headers={"Content-Disposition": f'attachment; filename="{name}"', "Cache-Control": "no-store"})


@router.get("/audit", response_class=HTMLResponse)
async def audit_page(request: Request):
    s = _guard(request)
    if not isinstance(s, Session):
        return s
    action = _audit_action(request)
    page = _int(request.query_params.get("page", "1"))
    rows, total = users.audit_page(_state(request).con, action or None, page)
    pages = max(1, (total + users.AUDIT_PAGE - 1) // users.AUDIT_PAGE)
    link = lambda n: BASE + "/audit?" + urlencode({"a": action, "page": n})  # noqa: E731
    return _page(request, "audit.html", s, rows=rows, total=total, a=action, page=page, pages=pages, link=link,
                 nav="audit")


# ---- сборки (SERVER_PROMPT этап 7) ----

CHANNEL_NAMES = {"release": "Релиз", "beta": "Бета"}
LANG_NAMES = {"ru": "Русский", "en": "English", "uk": "Українська", "es": "Español", "de": "Deutsch", "pl": "Polski"}
templates.env.globals.update(CHANNEL_NAMES=CHANNEL_NAMES, LANG_NAMES=LANG_NAMES, BUILD_LANGS=builds.LANGS,
                             REQUIRED_LANGS=builds.REQUIRED_LANGS, BUILD_KEEP=builds.KEEP)


@router.get("/builds", response_class=HTMLResponse)
async def builds_page(request: Request):
    s = _guard(request)
    if not isinstance(s, Session):
        return s
    st = _state(request)
    published = builds.listing(st.con)
    candidates, gh_error, chosen = [], None, None
    try:
        candidates = await st.github.releases()
    except builds.BuildError as err:
        gh_error = MESSAGES.get(err.code, err.code)
    tag = request.query_params.get("tag", "")
    if tag and builds.TAG_RE.match(tag):
        chosen = next((r for r in candidates if r.get("tag_name") == tag), None)
    return _page(request, "builds.html", s, published=published, candidates=candidates, gh_error=gh_error,
                 chosen=chosen, out={b.tag for b in published}, nav="builds")


@router.post("/builds/publish")
async def builds_publish(request: Request):
    s = _guard(request)
    if not isinstance(s, Session):
        return s
    form = await _form(request)
    tag = form.get("tag", "")
    if not _csrf_ok(s, form):
        return _go("/builds", e="csrf")
    st = _state(request)
    notes = {lang: form.get(f"notes_{lang}", "") for lang in builds.LANGS}
    try:
        b = await builds.publish(st.con, st.settings.data_dir, st.github, tag, form.get("channel", ""), notes,
                                 s.admin.login)
    except builds.BuildError as err:
        return _go("/builds", e=err.code, tag=tag if builds.TAG_RE.match(tag) else None)
    users.audit(st.con, s.admin.login, "publish_build", b.tag, channel=b.channel, version=b.version, size=b.size,
                sha256=b.sha256)
    return _go("/builds", m="published")


@router.post("/builds/{build_id}/{action}")
async def builds_action(request: Request, build_id: int, action: str):
    s = _guard(request)
    if not isinstance(s, Session):
        return s
    form = await _form(request)
    if not _csrf_ok(s, form):
        return _go("/builds", e="csrf")
    if action not in ("revoke", "restore"):
        return _go("/builds", e="no_build")
    st = _state(request)
    try:
        b = builds.set_revoked(st.con, build_id, action == "revoke")
    except builds.BuildError as err:
        return _go("/builds", e=err.code)
    users.audit(st.con, s.admin.login, f"{action}_build", b.tag, channel=b.channel)
    return _go("/builds", m="revoked" if action == "revoke" else "restored")


# ---- сервер: обновление по частям без панели (sonar/updater.py) ----

SITE_RESULT = {"updated": "site_updated", "same": "site_same", "none": "site_none", "failed": "site_failed"}


@router.get("/server", response_class=HTMLResponse)
async def server_page(request: Request):
    s = _guard(request)
    if not isinstance(s, Session):
        return s
    upd = _state(request).updater
    checked = request.query_params.get("check") == "1"
    return _page(request, "server.html", s, available=upd.available(), current=upd.current(),
                 st=await upd.check(force=True) if checked and upd.available() else None, checked=checked,
                 last=upd.last_result(), restarting=upd.restarting, nav="server")


@router.post("/server/{part}")
async def server_update(request: Request, part: str):
    s = _guard(request)
    if not isinstance(s, Session):
        return s
    form = await _form(request)
    if not _csrf_ok(s, form):
        return _go("/server", e="csrf")
    st = _state(request)
    if part not in ("site", "server", "all", "restart"):
        return _go("/server", e="bad_part")
    if not st.updater.available():
        return _go("/server", e="no_restart")
    if part == "site":
        state = await st.updater.update_site()
        users.audit(st.con, s.admin.login, "update_site", state)
        return _go("/server", m=SITE_RESULT[state])
    if part != "restart":
        await st.updater.check()   # нужна цель, с которой потом сверим коммит
    if not st.updater.request_restart(part, source="admin", by=s.admin.login):
        return _go("/server", e="no_restart")
    users.audit(st.con, s.admin.login, "restart_server" if part == "restart" else "update_server", part)
    return _go("/server", m="restarting")
