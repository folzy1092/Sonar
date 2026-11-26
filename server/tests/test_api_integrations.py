"""Ключ API и «сейчас играет» (SERVER_PROMPT этап 5, API.md §7): ключ из приложения = ключ бота, `/oauth/now` — формат Dotify."""
import pytest
from fastapi.testclient import TestClient

from sonar.api import auth as api_auth
from sonar.api.integrations import STALE_MS, now_json
from sonar.config import Settings
from sonar.web import create_app

PC = {"id": "pc-1", "name": "Windows 10 (Folzy)", "platform": "windows"}
STATE = {"device_id": None, "ref": "sc:2296053116", "context": "favorites", "is_playing": True, "position_ms": 1000,
         "queue": ["sc:2296053116"], "queue_index": 0, "shuffle": False, "repeat": "off", "client_ts": 1,
         "track": {"title": "море стало моим домом.", "artist": "одиссея", "duration_ms": 123000,
                   "cover_url": "https://i1.sndcdn.com/a-t500x500.png"}}


@pytest.fixture(autouse=True)
def fresh_register_limit(monkeypatch):
    monkeypatch.setattr(api_auth, "_register_limit", api_auth.RateLimit(limit=50, window_s=3600))


@pytest.fixture
def client(con, tmp_path):
    return TestClient(create_app(con, Settings(data_dir=tmp_path)), base_url="http://testserver")


@pytest.fixture
def sess(client):
    return client.post("/api/auth/register", json={"login": "mira", "password": "secret-pass", "device": PC}).json()["session"]


def h(token):
    return {"Authorization": f"Bearer {token}"}


def test_key_lifecycle_and_same_key_as_bot(client, sess, con):
    assert client.get("/api/me/integration", headers=h(sess)).json() == {"key": None, "created_at": None}
    made = client.post("/api/integrations/api-key", headers=h(sess)).json()
    assert made["key"].startswith("snr_") and made["created_at"]
    assert client.get("/api/me/integration", headers=h(sess)).json() == made
    # бот читает тот же ключ из той же таблицы
    user = client.app.state.accounts.by_login("mira")
    assert client.app.state.accounts.token(user) == made["key"]
    again = client.post("/api/integrations/api-key", headers=h(sess)).json()
    assert again["key"] != made["key"]
    assert client.get(f"/api/oauth/profile?token={made['key']}").status_code == 401, "перевыпуск — старый ключ мёртв"
    assert client.delete("/api/integrations/api-key", headers=h(sess)).status_code == 204
    assert client.get(f"/api/oauth/profile?token={again['key']}").status_code == 401


def test_key_methods_need_session(client):
    assert client.post("/api/integrations/api-key").status_code == 401
    assert client.get("/api/me/integration", headers=h("snr_nope")).status_code == 401


def test_oauth_accepts_bearer_or_query_and_rejects_session_token(client, sess):
    key = client.post("/api/integrations/api-key", headers=h(sess)).json()["key"]
    prof = client.get("/api/oauth/profile", headers=h(key)).json()
    assert prof == {"username": "mira", "display_name": prof["display_name"], "avatar_url": None}
    assert client.get(f"/api/oauth/now?token={key}").status_code == 200
    assert client.get("/api/oauth/now").status_code == 401
    assert client.get("/api/oauth/now", headers=h(sess)).status_code == 401, "сессия приложения — не ключ API"


def test_now_from_player_state(client, sess):
    key = client.post("/api/integrations/api-key", headers=h(sess)).json()["key"]
    assert client.get("/api/oauth/now", headers=h(key)).json()["state"] == "stopped"
    assert client.put("/api/player/state", headers=h(sess), json=STATE).status_code == 204
    now = client.get("/api/oauth/now", headers=h(key)).json()
    assert now["state"] == "playing" and now["is_playing"] is True
    t = now["track"]
    assert (t["source"], t["id"], t["track_id"], t["title"], t["artist"]) == \
        ("soundcloud", "2296053116", "2296053116", "море стало моим домом.", "одиссея")
    assert (t["duration"], t["duration_ms"], t["context"]) == (123, 123000, "favorites")
    assert t["cover_art"].endswith("t500x500.png")
    assert 1000 <= now["position_ms"] <= 123000


def test_now_json_rules():
    base = 1_000_000
    # играет — позиция на момент снимка (updated_at = сердцебиение), досчитывает читатель; не дальше длины трека
    live = now_json(STATE, base, base + 5000)
    assert (live["position_ms"], live["updated_at"], live["track"]["updated_at"]) == (1000, base, base)
    assert now_json(STATE, base, base + 9000)["position_ms"] == 1000
    short = {**STATE, "position_ms": 5000, "track": {**STATE["track"], "duration_ms": 2000}}
    assert now_json(short, base, base + 5000)["position_ms"] == 2000
    bare = {**STATE, "track": {"title": "t", "artist": "a", "cover_url": ""}}
    blank = now_json(bare, base, base + 5000)["track"]
    assert (blank["cover_art"], blank["duration_ms"]) == (None, 0), "пустая обложка — null, а не пустая строка"
    # тишина дольше STALE_MS — пауза на последней известной позиции
    stale = now_json(STATE, base, base + STALE_MS + 1)
    assert (stale["state"], stale["is_playing"], stale["position_ms"], stale["track"]["is_playing"]) == ("paused", False, 1000, False)
    paused = now_json({**STATE, "is_playing": False}, base, base + 5000)
    assert (paused["state"], paused["position_ms"]) == ("paused", 1000)
    # нет трека или мусор — stopped, track null
    for bad in (None, {}, {"ref": None}, {"ref": "nocolon"}):
        assert now_json(bad, base, base)["track"] is None
    # старый клиент без метаданных — пустые строки, а не падение
    bare = now_json({"ref": "ym:42", "is_playing": False, "position_ms": 3}, base, base)
    assert (bare["track"]["source"], bare["track"]["title"], bare["track"]["duration"]) == ("yandex", "", 0)
    junk = now_json({**STATE, "track": {"title": 5, "duration_ms": "x", "cover_url": 1}}, base, base)["track"]
    assert (junk["title"], junk["duration_ms"], junk["cover_art"]) == ("", 0, None)
