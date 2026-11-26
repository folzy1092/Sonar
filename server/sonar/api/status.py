"""`GET /api/status` и `/api/status/history` — статус сервиса для сайта (API.md §9): те же данные, что бот `/status`,
без пунктов владельца."""
from __future__ import annotations

import time

from fastapi import APIRouter, Depends, Query, Request, Response

from .. import accounts, sessions
from ..db import now_ms
from ..status import DEVICE_CHECKED, DOWN, OK, PARTIAL, Item, Status
from .deps import session
from .errors import ApiError

router = APIRouter()

CACHE_S = 30
HISTORY_CACHE_S = 300
DAY_MS = 86400_000
# Наши пункты (SPEC §3.11). «Медиа» и «Прокси» — только владельцу в боте, сюда не идут.
# Хранилище — только владельцу в боте (решение 2026-11-25), на публичную страницу не идёт.
INFRA = [("main", "api", "Основной", "🗄"), ("bot", "bot", "Бот", "🤖"), ("site", "site", "Сайт", "🌐")]
PLATFORMS = [("soundcloud", "SoundCloud", "🌐"), ("yandex", "Яндекс Музыка", "🌐"), ("youtube", "YouTube Music", "🌐"),
             ("spotify", "Spotify", "🌐"), ("apple", "Apple Music", "🌐"), ("lrclib", "lrclib", "📝"),
             ("genius", "Genius", "📝"), ("telegram", "Telegram", "✈️")]
# С чем Sonar работает сейчас: их сбой портит шапку, остальные платформы — нет (как в боте).
CORE = {"soundcloud", "yandex"}
_STATE = {OK: "ok", PARTIAL: "degraded", DOWN: "down"}
TITLES = {"ok": "Все системы работают штатно", "degraded": "Некоторые сервисы работают с перебоями"}


def _from_db(con) -> dict[str, Item]:
    """Последняя проверка каждого пункта из базы — пока цикл проверок процесса ещё не отработал (или без бота)."""
    rows = con.execute("SELECT c.item, c.state, c.ms FROM status_checks c JOIN"
                       " (SELECT item, MAX(ts) AS ts FROM status_checks GROUP BY item) m"
                       " ON m.item = c.item AND m.ts = c.ts").fetchall()
    return {r["item"]: Item(r["item"], r["state"], r["ms"]) for r in rows}


def summary(status: Status, con) -> dict:
    items = status.last or _from_db(con)
    unset = status.never_ok()

    def row(key: str, id_: str, name: str, icon: str, infra: bool = False) -> dict:
        i = items.get(key)
        # «unset» — наш пункт ещё ни разу не работал (сайт до переезда): не настроен, шапку не портит.
        # Чужие платформы так не прячем: Spotify, вечно отвечающий 429, честно «с перебоями».
        state = "unset" if infra and key in unset else (_STATE.get(i.state, "down") if i else "unknown")
        return {"id": id_, "name": name, "icon": icon, "state": state, "ms": i.ms if i and state != "unset" else None}

    infra = [row(k, id_, n, ic, infra=True) for k, id_, n, ic in INFRA]
    platforms = [row(k, k, n, ic) for k, n, ic in PLATFORMS if k in CORE or k in items]
    down = [r["name"] for r in infra if r["state"] == "down" and r["id"] in ("api", "bot")]
    shaky = any(r["state"] in ("degraded", "down") for r in infra) or \
        any(r["state"] in ("degraded", "down") for r in platforms if r["id"] in CORE)
    state = "down" if down else "degraded" if shaky else "ok"
    up = status.uptime()
    return {
        "state": state,
        "title": f"Сбой: {', '.join(down)}" if down else TITLES[state],
        "uptime_30d": None if up is None else round(up, 2),
        "listening_now": accounts.listening_now(con),
        "listeners_24h": accounts.listeners_24h(con),
        "users": accounts.users_count(con),
        "checked_at": now_ms(),
        "infra": infra,
        "platforms": platforms,
    }


@router.get("/status")
async def get_status(request: Request, response: Response):
    st = request.app.state
    cached = getattr(st, "status_cache", None)
    if cached is None or time.monotonic() - cached[0] > CACHE_S:
        cached = (time.monotonic(), summary(st.status, st.con))
        st.status_cache = cached
    response.headers["Cache-Control"] = f"public, max-age={CACHE_S}"
    return cached[1]


def history(status: Status, con, days: int) -> dict:
    """% успешных проверок по дням (UTC) для публичных пунктов; пункт, ни разу не работавший, не показываем."""
    ids = {k: id_ for k, id_, _, _ in INFRA} | {k: k for k, _, _ in PLATFORMS}
    hidden = status.never_ok()
    since = (now_ms() // DAY_MS - days + 1) * DAY_MS
    rows = con.execute("SELECT item, ts / ? AS day, COUNT(*) AS n, SUM(state = 'ok') AS ok FROM status_checks"
                       " WHERE ts >= ? GROUP BY item, day ORDER BY day", (DAY_MS, since)).fetchall()
    out: dict[int, dict[str, float]] = {}
    for r in rows:
        if r["item"] in ids and r["item"] not in hidden:
            out.setdefault(r["day"], {})[ids[r["item"]]] = round(r["ok"] * 100 / r["n"], 2)
    return {"days": [{"date": time.strftime("%Y-%m-%d", time.gmtime(day * 86400)), "items": items}
                     for day, items in out.items()]}


@router.get("/status/history")
async def get_history(request: Request, response: Response, days: int = Query(90, ge=1, le=90)):
    st = request.app.state
    cache = getattr(st, "history_cache", None) or {}
    hit = cache.get(days)
    if hit is None or time.monotonic() - hit[0] > HISTORY_CACHE_S:
        hit = (time.monotonic(), history(st.status, st.con, days))
        st.history_cache = {**cache, days: hit}
    response.headers["Cache-Control"] = f"public, max-age={HISTORY_CACHE_S}"
    return hit[1]


REPORT_NOTE_MAX = 100


@router.post("/status/report", status_code=204)
async def report(request: Request, s: sessions.Session = Depends(session)):
    """Устройство сообщает, дошёл ли запрос до сервиса (сейчас — Яндекс: с серверов Velt он отвечает 451, а играет само
    устройство). Тело: `{"service": "yandex", "ok": true, "ms": 180, "note": "HTTP 451"}`. У пользователя одна запись на
    сервис — повторный отчёт её заменяет; в статусе учитываются отчёты за последние 20 минут (`Status.from_devices`)."""
    try:
        data = await request.json()
    except ValueError:
        raise ApiError(400, "bad_json", "Тело — JSON") from None
    if not isinstance(data, dict) or data.get("service") not in DEVICE_CHECKED or not isinstance(data.get("ok"), bool):
        raise ApiError(400, "bad_request", "Нужны service (yandex) и ok (true / false)")
    ms = data.get("ms")
    ms = int(ms) if isinstance(ms, (int, float)) and not isinstance(ms, bool) and 0 <= ms < 600_000 else None
    note = data.get("note")
    note = note.strip()[:REPORT_NOTE_MAX] if isinstance(note, str) and note.strip() else None
    request.app.state.con.execute(
        "INSERT INTO client_checks (user_id, service, ok, ms, note, at) VALUES (?,?,?,?,?,?)"
        " ON CONFLICT(user_id, service) DO UPDATE SET ok = excluded.ok, ms = excluded.ms, note = excluded.note, at = excluded.at",
        (s.user_id, data["service"], int(data["ok"]), ms, note, now_ms()))
    return Response(status_code=204)
