"""Этап 6 (SERVER_PROMPT): сайт из корня сервера, профиль `/@username` и история статуса для сайта."""
import itertools
import json
import time

import pytest
from fastapi.testclient import TestClient

from sonar.config import Settings
from sonar.db import now_ms
from sonar.web import IMMUTABLE, NO_CACHE, create_app

DAY = 86400_000
_numbers = itertools.count(1)


@pytest.fixture
def site(tmp_path):
    root = tmp_path / "site"
    (root / "_astro").mkdir(parents=True)
    (root / "faq").mkdir()
    (root / "index.html").write_text("<h1>главная</h1>")
    (root / "404.html").write_text("<h1>нет такой</h1>")
    (root / "faq" / "index.html").write_text("<h1>faq</h1>")
    (root / "_astro" / "app.abc123.js").write_text("console.log(1)")
    (root / "favicon.svg").write_text("<svg/>")
    return root


@pytest.fixture
def client(con, tmp_path, site):
    data = tmp_path / "data"
    data.mkdir()
    return TestClient(create_app(con, Settings(data_dir=data), site=site), base_url="http://testserver")


def add_user(con, username, banned=0):
    n = next(_numbers)
    con.execute("INSERT INTO users (id, number, login, username, display_name, created_at, banned)"
                " VALUES (?,?,?,?,?,?,?)", (f"u{n}", n, username, username, username.title(), 1700000000000, banned))


def test_public_profile_header(client, con):
    add_user(con, "mira")
    add_user(con, "evil", banned=1)
    r = client.get("/api/public/users/@mira")
    assert r.status_code == 200 and r.headers["cache-control"].startswith("public")
    assert r.json() == {"username": "mira", "display_name": "Mira", "number": r.json()["number"],
                        "avatar_url": None, "created_at": 1700000000000, "now_playing": None, "stats": None,
                        "top_artists": [], "likes": None, "playlists": None, "playlist_count": 0, "showcase": [],
                        "private": []}, "пустой профиль — пустые разделы, а не нули"
    for nope in ("evil", "ghost"):
        r = client.get(f"/api/public/users/{nope}")
        assert r.status_code == 404 and r.json()["error"]["code"] == "not_found"


def put_row(con, uid, kind, key, value):
    con.execute("INSERT OR REPLACE INTO sync_rows (user_id, type, key, value_json, rev, client_ts) VALUES (?,?,?,?,1,0)",
                (uid, kind, key, None if value is None else json.dumps(value)))


def card(ref, title, cover=None, ms=0):
    return {"ref": ref, "title": title, "artist": "одиссея", "cover_url": cover, "duration_ms": ms}


def user_id(con, username):
    add_user(con, username)
    return con.execute("SELECT id FROM users WHERE username = ?", (username,)).fetchone()["id"]


def fill_profile(con, uid):
    now = now_ms()
    for i, (artist, days_ago) in enumerate([("одиссея", 0), ("одиссея", 1), ("ссш", 1), ("одиссея", 2), ("ссш", 9)]):
        con.execute("INSERT INTO plays (user_id, ref, artist, played_at, listened_ms) VALUES (?,?,?,?,?)",
                    (uid, f"sc:{i % 3}", artist, now - days_ago * DAY, 60_000))
    put_row(con, uid, "like", "sc:1", {"kind": "track", "added_at": 1, "track": card("sc:1", "старый", ms=1000)})
    put_row(con, uid, "like", "sc:2", {"kind": "track", "added_at": 5,
                                       "track": card("sc:2", "новый", "https://i1.sndcdn.com/a.jpg")})
    put_row(con, uid, "like", "sc:3", None)
    put_row(con, uid, "like", "ar:1", {"kind": "artist", "added_at": 9})
    put_row(con, uid, "playlist", "pl_a", {"name": "Ночь", "hidden": False, "updated_at": 10})
    put_row(con, uid, "playlist", "pl_b", {"name": "Скрыт", "hidden": True, "updated_at": 20})
    put_row(con, uid, "playlist", "pl_c", {"name": "Личный", "hidden": False, "updated_at": 30})
    for i, pos in enumerate([2, 1, 3]):
        put_row(con, uid, "playlist_item", f"it{i}", {"playlist_id": "pl_a", "ref": f"sc:{i}", "position": pos,
                                                       "track": card(f"sc:{i}", "т", f"https://c/{i % 2}", 1000)})
    put_row(con, uid, "setting", "privacy.hidden_playlists", ["pl_c"])
    con.execute("INSERT INTO player_state (user_id, is_playing, heartbeat_at, state_json) VALUES (?,1,?,?)",
                (uid, now, json.dumps({"ref": "sc:2", "is_playing": True, "position_ms": 1000, "client_ts": now,
                                       "track": {"title": "новый", "artist": "одиссея", "duration_ms": 93000}})))


def test_public_profile_full(client, con):
    fill_profile(con, user_id(con, "nika"))
    p = client.get("/api/public/users/nika").json()
    assert p["now_playing"] == {"ref": "sc:2", "title": "новый", "artist": "одиссея", "cover_url": None,
                                "duration_ms": 93000}
    assert p["stats"] == {"plays": 5, "total_ms": 300_000, "tracks": 3, "artists": 2, "streak_days": 3}
    assert p["top_artists"][0] == {"name": "одиссея", "plays": 3, "avatar_url": None, "ref": None}
    assert p["likes"]["count"] == 2, "артист и удалённый лайк не считаются"
    assert [t["title"] for t in p["likes"]["tracks"]] == ["новый", "старый"]
    assert p["likes"]["tracks"][1]["cover_url"] is None and p["likes"]["tracks"][0]["duration_ms"] is None
    assert p["playlist_count"] == 1, "скрытый и спрятанный от всех не видны"
    assert p["playlists"] == [{"id": "pl_a", "name": "Ночь", "track_count": 3, "duration_ms": 3000,
                               "covers": ["https://c/1", "https://c/0"]}]
    assert p["private"] == []


def test_public_profile_respects_privacy(client, con):
    uid = user_id(con, "ghosty")
    fill_profile(con, uid)
    for key in ("now_playing", "stats", "likes", "playlists"):
        put_row(con, uid, "setting", f"privacy.{key}", "nobody" if key == "stats" else "friends")
    put_row(con, uid, "setting", "profile.showcase", [{"kind": "playlist", "ref": "pl_a", "title": "Ночь"},
                                                      {"kind": "track", "ref": "sc:2", "title": "новый"}])
    p = client.get("/api/public/users/ghosty").json()
    assert p["private"] == ["now_playing", "stats", "likes", "playlists"]
    assert p["now_playing"] is None and p["stats"] is None and p["likes"] is None and p["playlists"] is None
    assert p["top_artists"] == [] and p["playlist_count"] == 0
    assert [s["ref"] for s in p["showcase"]] == ["sc:2"], "плейлист в витрине прячется вместе с плейлистами"


def test_public_profile_stale_player_is_not_now_playing(client, con):
    uid = user_id(con, "sleepy")
    old = now_ms() - 10 * 60_000
    con.execute("INSERT INTO player_state (user_id, is_playing, heartbeat_at, state_json) VALUES (?,1,?,?)",
                (uid, old, json.dumps({"ref": "sc:1", "is_playing": True, "client_ts": old, "track": {"title": "x"}})))
    assert client.get("/api/public/users/sleepy").json()["now_playing"] is None


def test_status_history_per_day(client, con):
    today = now_ms() // DAY * DAY
    rows = [(today + 1000, "main", "ok"), (today + 2000, "main", "down"), (today - DAY + 1, "main", "ok"),
            (today + 1000, "soundcloud", "ok"), (today + 1000, "site", "down"),  # сайт ни разу не работал — скрыт
            (today - 200 * DAY, "main", "down"), (today + 1000, "junk", "ok")]
    con.executemany("INSERT INTO status_checks (ts, item, state, ms) VALUES (?,?,?,1)", rows)
    days = client.get("/api/status/history?days=90").json()["days"]
    assert [d["items"] for d in days] == [{"api": 100.0}, {"api": 50.0, "soundcloud": 100.0}]
    assert days[-1]["date"] == time.strftime("%Y-%m-%d", time.gmtime(today / 1000))
    assert client.get("/api/status/history?days=0").status_code == 400
    assert client.get("/api/status/history?days=91").status_code == 400


def test_site_served_from_root(client):
    r = client.get("/")
    assert r.status_code == 200 and "главная" in r.text and r.headers["cache-control"] == NO_CACHE
    assert "faq" in client.get("/faq/").text
    r = client.get("/_astro/app.abc123.js")
    assert r.status_code == 200 and r.headers["cache-control"] == IMMUTABLE
    assert client.get("/favicon.svg").headers["cache-control"].startswith("public, max-age=3600")
    r = client.get("/@mira")
    assert r.status_code == 404 and "нет такой" in r.text, "неизвестный путь — 404.html сайта"
    assert client.get("/../../etc/passwd").status_code == 404


def test_site_slash_redirect_keeps_scheme(client):
    # За прокси хостинга uvicorn видит http: абсолютный адрес в редиректе уводил бы с https на http.
    r = client.get("/faq?x=1", follow_redirects=False)
    assert r.status_code == 307 and r.headers["location"] == "/faq/?x=1"


def test_site_does_not_touch_api_and_admin(client):
    r = client.get("/api/nope")
    assert r.status_code == 404 and r.json() == {"error": {"code": "not_found", "message": "Not Found"}}
    assert client.put("/api/health").json()["error"]["code"] == "method_not_allowed"
    assert client.get("/health").json() == {"ok": True}, "алиасы API в корне живут как раньше"
    assert client.post("/").status_code in (404, 405), "сайт — только чтение"
    assert "нет такой" not in client.get("/admin/nope").text


def test_www_redirects_to_bare_domain(client):
    r = client.get("/faq/?x=1", headers={"host": "www.try-sonar.ru"}, follow_redirects=False)
    assert r.status_code == 301 and r.headers["location"] == "https://try-sonar.ru/faq/?x=1"
    assert client.get("/api/health", headers={"host": "www.try-sonar.ru"}).json() == {"ok": True}


def test_no_site_dir_is_fine(con, tmp_path):
    c = TestClient(create_app(con, Settings(data_dir=tmp_path), site=tmp_path / "missing"))
    assert c.get("/").status_code == 404
    assert c.get("/api/health").json() == {"ok": True}
