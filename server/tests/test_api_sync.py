"""Синк через настоящий сервер (SERVER_PROMPT этап 3, API.md §5–6): два устройства одного аккаунта, правила
`MemoryServer` / хаба ПК — повтор op_id, «побеждает позднее» у настроек, страницы pull, прослушивания."""
import pytest
from fastapi.testclient import TestClient

from sonar import sync
from sonar.api import auth as api_auth
from sonar.config import Settings
from sonar.db import now_ms
from sonar.web import create_app

PC = {"id": "pc-1", "name": "Windows 10 (Folzy)", "platform": "windows"}
PHONE = {"id": "phone-1", "name": "iPhone 15 Pro", "platform": "ios"}
TRACK = {"ref": "sc:1", "title": "zombie", "artist": "cowboyclicker", "artists": [], "album": None, "duration_ms": 1000,
         "cover_url": None, "url": None, "explicit": False, "available": True}


@pytest.fixture(autouse=True)
def fresh_register_limit(monkeypatch):
    monkeypatch.setattr(api_auth, "_register_limit", api_auth.RateLimit(limit=50, window_s=3600))


@pytest.fixture
def client(con, tmp_path):
    return TestClient(create_app(con, Settings(data_dir=tmp_path)), base_url="http://testserver")


def h(token):
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def devices(client):
    pc = client.post("/api/auth/register", json={"login": "mira", "password": "secret-pass", "device": PC}).json()["session"]
    phone = client.post("/api/auth/login", json={"login": "mira", "password": "secret-pass", "device": PHONE}).json()["session"]
    return pc, phone


def op(op_id, kind, key, value, ts=1):
    return {"op_id": op_id, "type": kind, "key": key, "value": value, "client_ts": ts}


def test_like_on_pc_arrives_on_phone(client, devices):
    pc, phone = devices
    r = client.post("/api/sync/push", headers=h(pc),
                    json={"ops": [op("pc:like:sc:1:1", "like", "sc:1", {"kind": "track", "added_at": 5, "track": TRACK})]})
    assert r.json()["applied"] == ["pc:like:sc:1:1"]
    got = client.get("/api/sync/pull?since=0", headers=h(phone)).json()
    assert [(c["type"], c["key"], c["value"]["track"]["title"]) for c in got["changes"]] == [("like", "sc:1", "zombie")]
    assert got["more"] is False and got["rev"] >= got["changes"][0]["rev"]
    # снятие лайка на телефоне — на ПК приходит удаление
    client.post("/api/sync/push", headers=h(phone), json={"ops": [op("ph:like:sc:1:2", "like", "sc:1", None, 9)]})
    back = client.get(f"/api/sync/pull?since={got['rev']}", headers=h(pc)).json()
    assert back["changes"][0]["value"] is None
    assert client.get(f"/api/sync/pull?since={back['rev']}", headers=h(pc)).json()["changes"] == []


def test_repeat_op_not_applied_twice(client, devices):
    pc, _ = devices
    client.post("/api/sync/push", headers=h(pc), json={"ops": [op("a", "like", "sc:1", {"kind": "track", "added_at": 1})]})
    rev = client.get("/api/sync/pull", headers=h(pc)).json()["rev"]
    r = client.post("/api/sync/push", headers=h(pc), json={"ops": [op("a", "like", "sc:1", None)]}).json()
    assert r["applied"] == ["a"] and r["rev"] == rev  # повтор подтверждён, но не применён
    assert client.get("/api/sync/pull", headers=h(pc)).json()["changes"][0]["value"] is not None


def test_later_setting_wins_and_loser_gets_winner(client, devices):
    pc, phone = devices
    client.post("/api/sync/push", headers=h(pc), json={"ops": [op("p1", "setting", "theme", "dark", 200)]})
    since = client.get("/api/sync/pull", headers=h(phone)).json()["rev"]
    r = client.post("/api/sync/push", headers=h(phone), json={"ops": [op("f1", "setting", "theme", "light", 100)]}).json()
    assert r["applied"] == ["f1"]
    again = client.get(f"/api/sync/pull?since={since}", headers=h(phone)).json()["changes"]
    assert again == [{"type": "setting", "key": "theme", "value": "dark", "rev": again[0]["rev"]}]


def test_users_do_not_see_each_other(client, devices):
    pc, _ = devices
    other = client.post("/api/auth/register", json={"login": "nova", "password": "secret-pass", "device": PC}).json()["session"]
    client.post("/api/sync/push", headers=h(pc), json={"ops": [op("x", "like", "sc:1", {"kind": "track", "added_at": 1})]})
    assert client.get("/api/sync/pull", headers=h(other)).json()["changes"] == []
    # одинаковый op_id у разных аккаунтов — не «повтор»
    client.post("/api/sync/push", headers=h(other), json={"ops": [op("x", "like", "sc:9", {"kind": "track", "added_at": 1})]})
    assert [c["key"] for c in client.get("/api/sync/pull", headers=h(other)).json()["changes"]] == ["sc:9"]


def test_pull_pages_by_size(con, client, devices, monkeypatch):
    pc, _ = devices
    big = "x" * 500
    client.post("/api/sync/push", headers=h(pc), json={"ops": [op(f"o{i}", "like", f"sc:{i}", {"pad": big}) for i in range(5)]})
    monkeypatch.setattr(sync, "PULL_BUDGET", 1200)
    since, seen = 0, []
    for _ in range(10):
        p = sync.pull(con, con.execute("SELECT id FROM users").fetchone()[0], since, sync.PULL_BUDGET)
        seen += [c["key"] for c in p.changes]
        since = p.rev
        if not p.more:
            break
    assert seen == [f"sc:{i}" for i in range(5)]


def test_bad_push_is_400(client, devices):
    pc, _ = devices
    for bad in ({"ops": "x"}, {"ops": [op("a", "hack", "k", 1)]}, {"ops": [{"op_id": "a", "type": "like", "key": "k"}]},
                {"ops": [op(str(i), "like", "k", 1) for i in range(501)]}):
        r = client.post("/api/sync/push", headers=h(pc), json=bad)
        assert r.status_code == 400, bad
    assert client.post("/api/sync/push", json={"ops": []}).status_code == 401
    r = client.post("/api/sync/push", headers={**h(pc), "content-length": str(5 * 1024 * 1024)}, content=b"{}")
    assert r.status_code in (400, 413)


def test_snapshot_and_replace(client, devices):
    pc, phone = devices
    client.post("/api/sync/push", headers=h(pc), json={"ops": [op("a", "like", "sc:1", {"kind": "track", "added_at": 1}),
                                                              op("b", "like", "sc:2", {"kind": "track", "added_at": 2})]})
    client.post("/api/sync/push", headers=h(pc), json={"ops": [op("c", "like", "sc:2", None)]})
    snap = client.get("/api/sync/snapshot", headers=h(phone)).json()
    assert [c["key"] for c in snap["changes"]] == ["sc:1"]  # удалённое в снимок не идёт
    r = client.post("/api/sync/replace", headers=h(phone), json={"ops": [op("r", "setting", "theme", "dark", 5)]})
    assert r.status_code == 200
    after = client.get("/api/sync/snapshot", headers=h(pc)).json()["changes"]
    assert [(c["type"], c["key"]) for c in after] == [("setting", "theme")]


def test_plays_once_with_artist(con, client, devices):
    pc, _ = devices
    client.post("/api/sync/push", headers=h(pc), json={"ops": [op("a", "like", "sc:1", {"kind": "track", "added_at": 1, "track": TRACK})]})
    now = now_ms()
    batch = {"plays": [{"ref": "sc:1", "played_at": now, "listened_ms": 90_000, "context": "favorites"},
                       {"ref": "sc:2", "played_at": now, "listened_ms": 1000, "context": None},
                       {"ref": "sc:3", "played_at": 5, "listened_ms": 1000},          # до 2020 — мусор
                       {"ref": "sc:4", "played_at": now, "listened_ms": -1}, "junk"]}
    assert client.post("/api/plays", headers=h(pc), json=batch).json() == {"accepted": 2}
    assert client.post("/api/plays", headers=h(pc), json=batch).json() == {"accepted": 0}  # повтор пачки
    rows = dict(con.execute("SELECT ref, artist FROM plays").fetchall())
    assert rows == {"sc:1": "cowboyclicker", "sc:2": ""}


def test_player_state(client, devices):
    pc, phone = devices
    assert client.get("/api/player/state", headers=h(phone)).status_code == 404
    state = {"device_id": "pc-1", "ref": "sc:1", "is_playing": True, "position_ms": 41000, "queue": ["sc:1"],
             "queue_index": 0, "shuffle": False, "repeat": "off", "client_ts": 1}
    assert client.put("/api/player/state", headers=h(pc), json=state).status_code == 204
    assert client.get("/api/player/state", headers=h(phone)).json() == state


def test_dotify_likes_arrive_by_pull(con, client, devices):
    from sonar import dotify
    _, phone = devices
    uid = con.execute("SELECT id FROM users").fetchone()[0]
    raw = b'{"tracks": [{"id": "7", "title": "t", "artist": "a", "source": "soundcloud", "added_at": 1}]}'
    dotify.apply(con, uid, dotify.parse(raw))
    got = client.get("/api/sync/pull", headers=h(phone)).json()["changes"]
    assert got[0]["key"] == "sc:7" and got[0]["value"]["track"]["title"] == "t" and got[0]["value"]["added_at"] == 1
