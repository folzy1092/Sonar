"""Входы в сервисы на всех устройствах (SERVER_PROMPT этап 4): только владелец, шифр в базе, без значений в ошибках."""
import logging

import pytest
from fastapi.testclient import TestClient

from sonar.api import auth as api_auth
from sonar.config import Settings
from sonar.web import create_app

PC = {"id": "pc-1", "name": "Windows", "platform": "windows"}
PHONE = {"id": "phone-1", "name": "iPhone", "platform": "ios"}
SECRET = "y0_SECRET-token-value"


@pytest.fixture(autouse=True)
def fresh_register_limit(monkeypatch):
    monkeypatch.setattr(api_auth, "_register_limit", api_auth.RateLimit(limit=50, window_s=3600))


@pytest.fixture
def client(con, tmp_path):
    return TestClient(create_app(con, Settings(data_dir=tmp_path)), base_url="http://testserver")


def h(token):
    return {"Authorization": f"Bearer {token}"}


def register(client, login, device):
    return client.post("/api/auth/register", json={"login": login, "password": "secret-pass", "device": device}).json()["session"]


@pytest.fixture
def devices(client):
    pc = register(client, "mira", PC)
    phone = client.post("/api/auth/login", json={"login": "mira", "password": "secret-pass", "device": PHONE}).json()["session"]
    return pc, phone


def test_login_on_pc_arrives_on_phone(client, devices):
    pc, phone = devices
    r = client.put("/api/services/credentials", headers=h(pc),
                   json={"yandex": {"token": SECRET, "name": "Mira"}, "sc": {"client_id": "a" * 32, "oauth_token": "tok"}})
    assert r.status_code == 204
    got = client.get("/api/services/credentials", headers=h(phone)).json()
    assert got == {"yandex": {"token": SECRET}, "soundcloud": {"client_id": "a" * 32, "oauth_token": "tok"}}
    # имя аккаунта — в /me, ключи — нет
    me = client.get("/api/me", headers=h(phone)).json()
    assert me["services"]["yandex"] == {"connected": True, "name": "Mira", "premium": None}


def test_stored_encrypted(client, con, devices):
    pc, _ = devices
    client.put("/api/services/credentials", headers=h(pc), json={"yandex": {"token": SECRET}})
    blob = con.execute("SELECT credentials FROM service_accounts").fetchone()["credentials"]
    assert SECRET.encode() not in bytes(blob)


def test_other_user_sees_nothing(client, devices):
    pc, _ = devices
    client.put("/api/services/credentials", headers=h(pc), json={"spotify": {"sp_dc": SECRET}})
    stranger = register(client, "olga", {"id": "x", "name": "X", "platform": "windows"})
    assert client.get("/api/services/credentials", headers=h(stranger)).json() == {}
    client.delete("/api/services/spotify", headers=h(stranger))
    assert client.get("/api/services/credentials", headers=h(pc)).json() == {"spotify": {"sp_dc": SECRET}}


def test_needs_session(client):
    assert client.get("/api/services/credentials").status_code == 401
    assert client.put("/api/services/credentials", json={}).status_code == 401


def test_update_only_listed_and_null_deletes(client, devices):
    pc, phone = devices
    client.put("/api/services/credentials", headers=h(pc), json={"yandex": {"token": "one"}, "youtube": {"cookie": "c=1"}})
    client.put("/api/services/credentials", headers=h(phone), json={"yandex": {"token": "two"}, "youtube": None})
    assert client.get("/api/services/credentials", headers=h(pc)).json() == {"yandex": {"token": "two"}}


def test_delete(client, devices):
    pc, phone = devices
    client.put("/api/services/credentials", headers=h(pc), json={"yandex": {"token": "one"}})
    assert client.delete("/api/services/ym", headers=h(phone)).status_code == 204
    assert client.get("/api/services/credentials", headers=h(pc)).json() == {}
    assert client.delete("/api/services/vk", headers=h(pc)).json()["error"]["code"] == "unknown_service"


@pytest.mark.parametrize("payload", [
    {"yandex": {"token": SECRET, "extra": SECRET}},
    {"yandex": {"token": 5}},
    {"soundcloud": {"oauth_token": SECRET}},
    {"yandex": SECRET},
    {"vk": {"token": SECRET}},
    {"yandex": {"token": SECRET * 2000}},
])
def test_bad_input_rejected_without_leaking(client, devices, caplog, payload):
    pc, _ = devices
    caplog.set_level(logging.DEBUG)
    r = client.put("/api/services/credentials", headers=h(pc), json=payload)
    assert r.status_code in (400, 404)
    assert SECRET not in r.text and SECRET not in caplog.text
    assert client.get("/api/services/credentials", headers=h(pc)).json() == {}


def test_bad_field_writes_nothing(client, devices):
    pc, _ = devices
    r = client.put("/api/services/credentials", headers=h(pc), json={"yandex": {"token": "ok"}, "spotify": {}})
    assert r.status_code == 400
    assert client.get("/api/services/credentials", headers=h(pc)).json() == {}


def test_trims_and_drops_empty_optional(client, devices):
    pc, _ = devices
    client.put("/api/services/credentials", headers=h(pc), json={"soundcloud": {"client_id": " id ", "oauth_token": ""}})
    assert client.get("/api/services/credentials", headers=h(pc)).json() == {"soundcloud": {"client_id": "id"}}


def test_unreadable_credentials_fail_instead_of_looking_disconnected(client, con, devices):
    # «сервиса нет» клиенты поймут как «отключили там» и отключат у себя — поэтому ошибка, а не пустой ответ
    pc, _ = devices
    client.put("/api/services/credentials", headers=h(pc), json={"yandex": {"token": SECRET}})
    con.execute("UPDATE service_accounts SET credentials = ?", (b"not-a-fernet-token",))
    r = client.get("/api/services/credentials", headers=h(pc))
    assert r.status_code == 500
    assert r.json()["error"]["code"] == "credentials_unreadable"
