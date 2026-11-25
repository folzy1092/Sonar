"""Этап 6 (SERVER_PROMPT): сайт из корня сервера, профиль `/@username` и история статуса для сайта."""
import itertools
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
                        "avatar_url": None, "created_at": 1700000000000}
    for nope in ("evil", "ghost"):
        r = client.get(f"/api/public/users/{nope}")
        assert r.status_code == 404 and r.json()["error"]["code"] == "not_found"


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
