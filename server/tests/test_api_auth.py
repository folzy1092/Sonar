"""Аккаунт через API (SERVER_PROMPT этап 2, API.md §1): вход, регистрация, /me, пароль, устройства, ссылки, Telegram."""
import json

import pytest
from fastapi.testclient import TestClient

from sonar import sessions
from sonar.api import auth as api_auth
from sonar.config import Settings
from sonar.db import now_ms
from sonar.web import create_app

PC = {"id": "hwid-pc", "name": "Windows 10 (Folzy)", "platform": "windows", "os": "Windows 10 22H2",
      "app_version": "0.1.0", "build": 5}
PHONE = {"id": "uuid-phone", "name": "iPhone 15 Pro", "platform": "ios", "os": "iOS 18.1", "app_version": "1.0", "build": 239}


@pytest.fixture(autouse=True)
def fresh_register_limit(monkeypatch):
    monkeypatch.setattr(api_auth, "_register_limit", api_auth.RateLimit(limit=api_auth.REGISTER_PER_IP, window_s=3600))


@pytest.fixture
def app(con, tmp_path):
    return create_app(con, Settings(data_dir=tmp_path))


@pytest.fixture
def client(app):
    return TestClient(app, base_url="http://testserver")


def register(client, login="mira", password="secret-pass", device=PC):
    r = client.post("/api/auth/register", json={"login": login, "password": password, "device": device})
    assert r.status_code == 200, r.text
    return r.json()


def bearer(token):
    return {"Authorization": f"Bearer {token}"}


def age_session(con, token, hours):
    con.execute("UPDATE sessions SET created_at = ? WHERE token_hash = ?",
                (now_ms() - int(hours * 3600_000), sessions._h(token)))


def test_register_and_me(client, con):
    out = register(client, login="Mira")
    u = out["user"]
    assert u["login"] == "mira" and u["username"] == "mira" and u["has_password"] is True and u["telegram"] is None
    assert u["services"] == {"soundcloud": {"connected": False}, "yandex": {"connected": False}}
    assert client.get("/api/me", headers=bearer(out["session"])).json() == u
    # В базе — только хэш токена.
    row = con.execute("SELECT token_hash, device_name, build FROM sessions").fetchone()
    assert row["token_hash"] != out["session"] and row["device_name"] == "Windows 10 (Folzy)" and row["build"] == 5


def test_register_errors(client, app):
    register(client)
    r = client.post("/api/auth/register", json={"login": "mira", "password": "secret-pass", "device": PC})
    assert r.status_code == 409 and r.json()["error"]["code"] == "login_taken"
    r = client.post("/api/auth/register", json={"login": "x", "password": "secret-pass", "device": PC})
    assert r.json()["error"]["code"] == "login_format"
    r = client.post("/api/auth/register", json={"login": "nova", "password": "short", "device": PC})
    assert r.json()["error"]["code"] == "password_short"
    r = client.post("/api/auth/register", json={"login": "nova", "password": "secret-pass", "device": {"id": "x"}})
    assert r.status_code == 400 and r.json()["error"]["code"] == "bad_device"
    app.state.settings.registration_open = False
    r = client.post("/api/auth/register", json={"login": "nova", "password": "secret-pass", "device": PC})
    assert r.status_code == 403 and r.json()["error"]["code"] == "registration_closed"


def test_register_limit_per_ip(client):
    for i in range(api_auth.REGISTER_PER_IP):
        register(client, login=f"user{i}")
    r = client.post("/api/auth/register", json={"login": "extra", "password": "secret-pass", "device": PC})
    assert r.status_code == 429


def test_login_replaces_session_of_same_device(client, con):
    first = register(client)["session"]
    r = client.post("/api/auth/login", json={"login": "@MIRA", "password": "secret-pass", "device": PC})
    second = r.json()["session"]
    assert r.status_code == 200 and second != first
    assert client.get("/api/me", headers=bearer(first)).status_code == 401
    assert con.execute("SELECT COUNT(*) FROM sessions").fetchone()[0] == 1


def test_login_errors_do_not_reveal_login(client):
    register(client)
    bad = client.post("/api/auth/login", json={"login": "mira", "password": "wrong-pass", "device": PC}).json()
    none = client.post("/api/auth/login", json={"login": "ghost", "password": "wrong-pass", "device": PC}).json()
    assert bad == none == {"error": {"code": "bad_credentials", "message": "Неверный логин или пароль"}}


def test_login_limit(client):
    register(client)
    for _ in range(5):
        client.post("/api/auth/login", json={"login": "mira", "password": "wrong-pass", "device": PC})
    r = client.post("/api/auth/login", json={"login": "mira", "password": "secret-pass", "device": PC})
    assert r.status_code == 429 and r.json()["error"]["code"] == "too_many"


def test_logout(client):
    tok = register(client)["session"]
    assert client.post("/api/auth/logout", headers=bearer(tok)).status_code == 204
    assert client.get("/api/me", headers=bearer(tok)).status_code == 401


def test_patch_me(client):
    tok = register(client)["session"]
    register(client, login="nova", device=PHONE)
    r = client.patch("/api/me", json={"username": "@Mira_Music", "display_name": "  Мира   Ш "}, headers=bearer(tok))
    assert r.json()["username"] == "mira_music" and r.json()["display_name"] == "Мира Ш" and r.json()["login"] == "mira"
    assert client.patch("/api/me", json={"username": "nova"}, headers=bearer(tok)).json()["error"]["code"] == "login_taken"
    assert client.patch("/api/me", json={"username": "mira"}, headers=bearer(tok)).status_code == 200  # свой логин можно
    assert client.patch("/api/me", json={"display_name": " "}, headers=bearer(tok)).json()["error"]["code"] == "name_format"


def test_password_change(client):
    tok = register(client)["session"]
    r = client.put("/api/me/password", json={"old_password": "nope-nope", "new_password": "new-secret"}, headers=bearer(tok))
    assert r.status_code == 403 and r.json()["error"]["code"] == "bad_password"
    r = client.put("/api/me/password", json={"new_password": "new-secret"}, headers=bearer(tok))
    assert r.status_code == 403
    phone = client.post("/api/auth/login", json={"login": "mira", "password": "secret-pass", "device": PHONE}).json()["session"]
    r = client.put("/api/me/password", json={"old_password": "secret-pass", "new_password": "new-secret"}, headers=bearer(tok))
    assert r.status_code == 204
    # сменил пароль — остальные устройства вышли, это осталось
    assert client.get("/api/me", headers=bearer(phone)).status_code == 401
    assert client.get("/api/me", headers=bearer(tok)).status_code == 200
    r = client.post("/api/auth/login", json={"login": "mira", "password": "new-secret", "device": PHONE})
    assert r.status_code == 200


def test_devices_list_rename_report(client):
    tok = register(client)["session"]
    client.post("/api/auth/login", json={"login": "mira", "password": "secret-pass", "device": PHONE})
    devs = client.get("/api/me/devices", headers=bearer(tok)).json()
    assert [d["id"] for d in devs] == ["hwid-pc", "uuid-phone"] and devs[0]["current"] and not devs[1]["current"]
    r = client.patch("/api/me/devices/uuid-phone", json={"name": "Мой телефон"}, headers=bearer(tok))
    assert r.json()["name"] == "Мой телефон"
    assert client.patch("/api/me/devices/uuid-phone", json={"name": "x" * 49}, headers=bearer(tok)).status_code == 400
    assert client.patch("/api/me/devices/ghost", json={"name": "a"}, headers=bearer(tok)).status_code == 404
    # При запуске: новая версия; id устройства из тела не подменяет сессию.
    r = client.put("/api/me/device", json={"device": {**PC, "id": "other", "app_version": "0.2.0", "build": 9}}, headers=bearer(tok))
    assert r.json()["id"] == "hwid-pc" and r.json()["app_version"] == "0.2.0" and r.json()["build"] == 9


def test_revoke_other_device_needs_day_old_session(client, con):
    tok = register(client)["session"]
    client.post("/api/auth/login", json={"login": "mira", "password": "secret-pass", "device": PHONE})
    r = client.delete("/api/me/devices/uuid-phone", headers=bearer(tok))
    assert r.status_code == 403 and r.json()["error"]["code"] == "session_too_new"
    age_session(con, tok, 25)
    assert client.delete("/api/me/devices/uuid-phone", headers=bearer(tok)).status_code == 204
    assert [d["id"] for d in client.get("/api/me/devices", headers=bearer(tok)).json()] == ["hwid-pc"]


def test_revoke_own_device_always(client):
    tok = register(client)["session"]
    assert client.delete("/api/me/devices/hwid-pc", headers=bearer(tok)).status_code == 204
    assert client.get("/api/me", headers=bearer(tok)).status_code == 401


def test_other_user_devices_invisible(client):
    a = register(client)["session"]
    register(client, login="nova", device=PHONE)
    assert client.patch("/api/me/devices/uuid-phone", json={"name": "x"}, headers=bearer(a)).status_code == 404
    assert client.delete("/api/me/devices/uuid-phone", headers=bearer(a)).status_code == 404


# ---- быстрая ссылка ----

def test_quick_link_device_flow(client):
    tok = register(client)["session"]
    link = client.post("/api/auth/link", json={"device": PHONE}).json()
    code = link["code"]
    assert link["url"] == f"https://try-sonar.ru/auth/{code}"
    assert link["bot_url"] == f"https://t.me/SonarMusicApp?start=link_{code}"
    assert client.get(f"/api/auth/link/{code}/poll").json() == {"status": "pending"}
    assert client.get(f"/api/auth/link/{code}").status_code == 401  # кто просит — только вошедшему
    info = client.get(f"/api/auth/link/{code}", headers=bearer(tok)).json()
    assert info["for"] == {"kind": "device", "name": "iPhone 15 Pro · Sonar 1.0", "platform": "ios"}
    assert client.post(f"/api/auth/link/{code}/approve", headers=bearer(tok)).status_code == 204
    assert client.post(f"/api/auth/link/{code}/approve", headers=bearer(tok)).status_code == 410  # второй раз — нет
    got = client.get(f"/api/auth/link/{code}/poll").json()
    assert got["status"] == "approved" and got["user"]["login"] == "mira"
    assert client.get("/api/me", headers=bearer(got["session"])).status_code == 200
    # Сессию выдают один раз.
    assert client.get(f"/api/auth/link/{code}/poll").json() == {"status": "expired"}


def test_quick_link_reject_and_expire(client, con):
    tok = register(client)["session"]
    code = client.post("/api/auth/link", json={"device": PHONE}).json()["code"]
    assert client.post(f"/api/auth/link/{code}/reject", headers=bearer(tok)).status_code == 204
    assert client.get(f"/api/auth/link/{code}/poll").json() == {"status": "rejected"}
    code = client.post("/api/auth/link", json={"device": PHONE}).json()["code"]
    con.execute("UPDATE auth_links SET expires_at = 1 WHERE code_hash = ?", (sessions._h(code),))
    assert client.get(f"/api/auth/link/{code}/poll").json() == {"status": "expired"}
    assert client.post(f"/api/auth/link/{code}/approve", headers=bearer(tok)).status_code == 410
    assert client.get("/api/auth/link/nope/poll").status_code == 404


def test_link_from_telegram_only_by_bot(client):
    r = client.post("/api/auth/link", json={"telegram": {"id": 1, "username": "x"}})
    assert r.status_code == 403


def test_bot_quick_link_approved_in_app(client, app, con):
    tok = register(client)["session"]
    code, _ = sessions.new_link(con, "telegram", {"id": 777, "username": "mira_tg"})  # так делает бот
    seen = []

    async def hook(tg_id, user):
        seen.append((tg_id, user.login))

    app.state.on_telegram_linked = hook
    assert client.get(f"/api/auth/link/{code}", headers=bearer(tok)).json()["for"] == {"kind": "telegram",
                                                                                       "name": "Telegram @mira_tg"}
    assert client.post(f"/api/auth/link/{code}/approve", headers=bearer(tok)).status_code == 204
    assert seen == [(777, "mira")]
    assert client.get("/api/me", headers=bearer(tok)).json()["telegram"] == {"id": 777, "username": "mira_tg"}
    assert client.get(f"/api/auth/link/{code}/poll").status_code == 404  # опрос — только у запросов устройства


# ---- Telegram ----

def test_telegram_login_flow(client, con):
    register(client)
    start = client.post("/api/auth/telegram/start", json={"purpose": "login", "device": PHONE}).json()
    rid = start["request_id"]
    assert start["link"] == f"https://t.me/SonarMusicApp?start=link_{rid}"
    assert client.get(f"/api/auth/telegram/poll/{rid}").json() == {"status": "pending"}
    link = sessions.get_link(con, rid)
    uid = con.execute("SELECT id FROM users").fetchone()[0]
    assert sessions.decide(con, link, "approved", uid)  # так делает бот после «Разрешить»
    got = client.get(f"/api/auth/telegram/poll/{rid}").json()
    assert got["status"] == "approved" and got["session"]


def test_telegram_link_flow(client, con):
    tok = register(client)["session"]
    other = register(client, login="nova", device=PHONE)["session"]
    assert client.post("/api/auth/telegram/start", json={"purpose": "link"}).status_code == 401
    start = client.post("/api/auth/telegram/start", json={"purpose": "link"}, headers=bearer(tok)).json()
    rid = start["request_id"]
    assert start["link"].endswith(f"?start=tg_{rid}")
    assert client.get(f"/api/auth/telegram/poll/{rid}", headers=bearer(tok)).json() == {"status": "pending"}
    assert client.get(f"/api/auth/telegram/poll/{rid}", headers=bearer(other)).status_code == 404
    link = sessions.get_link(con, rid)
    assert sessions.decide(con, link, "approved")
    con.execute("UPDATE users SET tg_id = 55 WHERE login = 'mira'")  # бот привязал
    got = client.get(f"/api/auth/telegram/poll/{rid}", headers=bearer(tok)).json()
    assert got["status"] == "approved" and got["user"]["telegram"]["id"] == 55 and "session" not in got
    assert client.post("/api/auth/telegram/start", json={"purpose": "x"}, headers=bearer(tok)).status_code == 400


def test_telegram_unlink_needs_password(client, con):
    tok = register(client)["session"]
    con.execute("UPDATE users SET tg_id = 55")
    assert client.delete("/api/auth/telegram", headers=bearer(tok)).status_code == 204
    con.execute("UPDATE users SET tg_id = 55, password_hash = NULL")
    r = client.delete("/api/auth/telegram", headers=bearer(tok))
    assert r.status_code == 403 and r.json()["error"]["code"] == "no_password"


def test_poll_is_not_strictly_limited(client, monkeypatch):
    _, auth_limit = client.app.state.api_limits
    monkeypatch.setattr(auth_limit, "limit", 2)
    code = client.post("/api/auth/link", json={"device": PHONE}).json()["code"]
    for _ in range(5):
        assert client.get(f"/api/auth/link/{code}/poll").status_code == 200


def test_link_data_has_no_secrets(client, con):
    client.post("/api/auth/link", json={"device": PHONE})
    row = con.execute("SELECT for_json FROM auth_links").fetchone()
    assert json.loads(row[0])["id"] == "uuid-phone"
