"""API под /api (SERVER_PROMPT этап 1): ошибки одним видом, Bearer, лимиты на IP, статус, CORS, старые алиасы."""
import hashlib
import itertools

import pytest
from fastapi import Depends
from fastapi.testclient import TestClient

import sonar.accounts as accounts_mod
from sonar.api import deps
from sonar.api import status as api_status
from sonar.api.deps import device
from sonar.config import Settings
from sonar.db import now_ms
from sonar.events import Device
from sonar.status import DOWN, OK, PARTIAL, Item
from sonar.web import create_app

_numbers = itertools.count(1)


@pytest.fixture
def app(con, tmp_path):
    app = create_app(con, Settings(data_dir=tmp_path))

    @app.get("/api/_me_test")
    async def me(dev: Device = Depends(device)):
        return {"user_id": dev.user_id, "device_id": dev.device_id}

    return app


@pytest.fixture
def client(app):
    return TestClient(app, base_url="http://testserver")


def add_session(con, token="tok", banned=0) -> str:
    uid = f"u_{token}"
    con.execute("INSERT INTO users (id, number, login, username, display_name, created_at, banned)"
                " VALUES (?,?,?,?,?,?,?)", (uid, next(_numbers), token, token, token, 1, banned))
    con.execute("INSERT INTO sessions (id, user_id, token_hash, device_id, device_name, platform, created_at, last_seen_at)"
                " VALUES (?,?,?,'dev-1','PC','windows',1,1)",
                (f"s_{token}", uid, hashlib.sha256(token.encode()).hexdigest()))
    return uid


def test_health_and_aliases(client):
    assert client.get("/api/health").json() == {"ok": True}
    assert client.get("/health").json() == {"ok": True}  # старый путь — алиас
    assert client.get("/api/config").json() == client.get("/config").json()
    assert client.post("/events", json={"events": []}).status_code == 401


def test_errors_have_one_shape(client):
    r = client.get("/api/nope")
    assert r.status_code == 404 and r.json() == {"error": {"code": "not_found", "message": "Not Found"}}
    r = client.put("/api/health")
    assert r.status_code == 405 and r.json()["error"]["code"] == "method_not_allowed"
    r = client.post("/api/events", content=b"{", headers={"Authorization": "Bearer x", "content-type": "application/json"})
    assert r.status_code == 401 and r.json()["error"]["code"] == "unauthorized"
    # Вне /api — ответы FastAPI по-старому, без обёртки API.
    assert client.get("/nope").json() == {"detail": "Not Found"}


def test_bearer_dependency(client, con):
    uid = add_session(con)
    add_session(con, "bad", banned=1)
    assert client.get("/api/_me_test").status_code == 401
    assert client.get("/api/_me_test", headers={"Authorization": "Bearer "}).status_code == 401
    assert client.get("/api/_me_test", headers={"Authorization": "Basic tok"}).status_code == 401
    banned = client.get("/api/_me_test", headers={"Authorization": "Bearer bad"})   # бан — не «сессия кончилась»
    assert banned.status_code == 403 and banned.json()["error"]["code"] == "account_banned"
    r = client.get("/api/_me_test", headers={"Authorization": "Bearer tok"})
    assert r.json() == {"user_id": uid, "device_id": "dev-1"}
    assert con.execute("SELECT last_seen_at FROM sessions WHERE id = 's_tok'").fetchone()[0] > 1


def test_events_under_api(client, con):
    add_session(con)
    h = {"Authorization": "Bearer tok"}
    batch = {"events": [{"kind": "open", "at": now_ms()}]}
    assert client.post("/api/events", json=batch, headers=h).json() == {"accepted": 1}
    assert client.post("/api/events", json={"x": 1}, headers=h).json()["error"]["code"] == "bad_events"


def test_rate_limit_per_ip(client, monkeypatch):
    api_limit, auth_limit = client.app.state.api_limits
    monkeypatch.setattr(auth_limit, "limit", 3)
    for _ in range(3):
        assert client.post("/api/auth/x").status_code == 404  # даже на неизвестный путь лимит считает
    r = client.post("/api/auth/x")
    assert r.status_code == 429 and r.json()["error"]["code"] == "too_many" and r.headers["retry-after"] == "60"
    assert client.get("/api/health").status_code == 200  # общий лимит не исчерпан
    monkeypatch.setattr(api_limit, "limit", 1)
    api_limit.reset("testclient")
    assert client.get("/api/health").status_code == 200
    assert client.get("/api/health").status_code == 429
    assert client.get("/health").status_code == 200  # корневые алиасы и админка — вне лимита API


def test_rate_limit_ignores_forged_forwarded_for(client, monkeypatch):
    _, auth_limit = client.app.state.api_limits
    monkeypatch.setattr(auth_limit, "limit", 1)
    # testclient — не доверенный прокси: подделанный X-Forwarded-For не даёт обойти лимит.
    assert client.post("/api/auth/x", headers={"X-Forwarded-For": "1.1.1.1"}).status_code == 404
    assert client.post("/api/auth/x", headers={"X-Forwarded-For": "2.2.2.2"}).status_code == 429


def test_limiter_prunes_stale_ips(monkeypatch):
    lim = deps.Limiter(limit=5, window_s=60)
    monkeypatch.setattr(deps, "PRUNE_AT", 3)
    t = [1000.0]
    monkeypatch.setattr(deps.time, "monotonic", lambda: t[0])
    monkeypatch.setattr(accounts_mod.time, "monotonic", lambda: t[0])
    for ip in ("a", "b", "c"):
        assert lim.take(ip)
    t[0] += 120
    assert lim.take("d")
    assert set(lim.hits) == {"d"}


def test_cors_only_for_site(client):
    r = client.get("/api/health", headers={"Origin": "https://try-sonar.ru"})
    assert r.headers["access-control-allow-origin"] == "https://try-sonar.ru"
    r = client.get("/api/health", headers={"Origin": "https://evil.example"})
    assert "access-control-allow-origin" not in r.headers
    r = client.options("/api/status", headers={"Origin": "https://try-sonar.ru", "Access-Control-Request-Method": "GET"})
    assert r.status_code == 200 and r.headers["access-control-allow-origin"] == "https://try-sonar.ru"


def _seed_checks(con, states: dict[str, str]):
    ts = now_ms()
    con.executemany("INSERT INTO status_checks (ts, item, state, ms) VALUES (?,?,?,?)",
                    [(ts, k, v, 42) for k, v in states.items()])


def test_status_from_db_and_shape(client, con):
    _seed_checks(con, {"main": OK, "bot": OK, "storage": OK, "site": OK, "soundcloud": OK, "yandex": OK,
                       "lrclib": OK, "genius": OK, "telegram": OK, "spotify": PARTIAL, "media": OK, "proxy": OK})
    add_session(con)
    r = client.get("/api/status")
    body = r.json()
    assert r.headers["cache-control"] == "public, max-age=30"
    assert body["state"] == "ok" and body["title"] == "Все системы работают штатно"  # Spotify шапку не портит
    assert body["uptime_30d"] == 100.0 and body["users"] == 1
    assert body["listening_now"] == 0 and body["listeners_24h"] == 0
    assert [i["id"] for i in body["infra"]] == ["api", "bot", "site"]  # без «Медиа», «Прокси» и хранилища
    assert body["infra"][0] == {"id": "api", "name": "Основной", "icon": "🗄", "state": "ok", "ms": 42}
    ids = [p["id"] for p in body["platforms"]]
    assert "spotify" in ids and "youtube" not in ids and "vk" not in ids
    assert next(p for p in body["platforms"] if p["id"] == "spotify")["state"] == "degraded"


def test_status_states(app, con):
    st = app.state.status
    _seed_checks(con, {"main": OK, "storage": OK, "bot": OK, "site": DOWN, "soundcloud": OK, "yandex": OK})
    s = api_status.summary(st, con)
    site = next(i for i in s["infra"] if i["id"] == "site")
    assert site == {"id": "site", "name": "Сайт", "icon": "🌐", "state": "unset", "ms": None}  # ни разу не работал
    assert s["state"] == "ok"
    st.last = {"main": Item("main", OK, 5), "storage": Item("storage", OK), "bot": Item("bot", OK),
               "site": Item("site", OK), "soundcloud": Item("soundcloud", OK), "yandex": Item("yandex", PARTIAL)}
    assert api_status.summary(st, con)["state"] == "degraded"
    st.last["bot"] = Item("bot", DOWN)
    s = api_status.summary(st, con)
    assert s["state"] == "down" and s["title"] == "Сбой: Бот"


def test_status_is_cached(client, monkeypatch):
    calls = []
    real = api_status.summary
    monkeypatch.setattr(api_status, "summary", lambda st, c: calls.append(1) or real(st, c))
    client.get("/api/status")
    client.get("/api/status")
    assert len(calls) == 1
