"""Админка: вход с заводским паролем, обязательная смена, CSRF, лимит попыток, страницы, действия, события."""
import hashlib
import re

import pytest
from fastapi.testclient import TestClient

from sonar import events
from sonar.admin import prefs
from sonar.admin.auth import FACTORY_HASH, FACTORY_LOGIN, AdminAuth, AuthError
from sonar.config import Settings
from sonar.db import now_ms
from sonar.web import create_app

FACTORY_PASSWORD = "folzy"  # заводской пароль из задачи; в коде сервера — только его хэш
NEW_PASSWORD = "river-sonar-42"


@pytest.fixture
def app(con, tmp_path):
    return create_app(con, Settings(data_dir=tmp_path))


@pytest.fixture
def client(app):
    return TestClient(app, base_url="http://testserver")


def csrf_of(html: str) -> str:
    return re.search(r'name="csrf" value="([^"]+)"', html).group(1)


def login(client, password=FACTORY_PASSWORD, user=FACTORY_LOGIN):
    page = client.get("/admin/login")
    return client.post("/admin/login", data={"login": user, "password": password, "csrf": csrf_of(page.text)},
                       follow_redirects=False)


def logged_in(client):
    """Вошёл и сменил заводской пароль — обычная рабочая сессия."""
    login(client)
    page = client.get("/admin/password")
    r = client.post("/admin/password", data={"csrf": csrf_of(page.text), "old": FACTORY_PASSWORD, "new": NEW_PASSWORD,
                                             "again": NEW_PASSWORD}, follow_redirects=False)
    assert r.headers["location"] == "/admin/?m=password_changed"
    return client


def add_user(con, uid="u_1", login="mira", created=None, n=1):
    con.execute("INSERT INTO users (id, number, login, username, display_name, created_at) VALUES (?,?,?,?,?,?)",
                (uid, n, login, login, login, created or now_ms()))
    return uid


# ---- заводской админ ----

def test_factory_admin_created_once_with_hash_only(con):
    auth = AdminAuth(con)
    assert auth.ensure_factory() is True
    assert auth.ensure_factory() is False
    row = con.execute("SELECT * FROM admins").fetchone()
    assert row["login"] == "folzy" and row["must_change"] == 1
    assert row["password_hash"].startswith("$argon2id$") and FACTORY_PASSWORD not in row["password_hash"]


def test_factory_password_not_in_source():
    from pathlib import Path
    root = Path(__file__).resolve().parent.parent
    for f in [*(root / "sonar").rglob("*.py"), root / "env.example"]:
        text = f.read_text(encoding="utf-8")
        assert not re.search(r"""password\w*\s*=\s*["']folzy["']""", text, re.I), f
    assert FACTORY_HASH.startswith("$argon2id$")


def test_login_requires_password_change_first(client):
    assert client.get("/admin/", follow_redirects=False).headers["location"] == "/admin/login"
    r = login(client)
    assert r.status_code == 303 and r.headers["location"] == "/admin/password"
    cookie = r.headers["set-cookie"].lower()
    assert "httponly" in cookie and "samesite=strict" in cookie
    for path in ("/admin/", "/admin/users", "/admin/settings", "/admin/audit"):
        assert client.get(path, follow_redirects=False).headers["location"] == "/admin/password"
    assert "Смени заводской пароль" in client.get("/admin/password").text


def test_password_change_rules(client):
    login(client)
    token = csrf_of(client.get("/admin/password").text)

    def change(old, new, again):
        return client.post("/admin/password", data={"csrf": token, "old": old, "new": new, "again": again},
                           follow_redirects=False).headers["location"]

    assert "e=bad_old" in change("nope", NEW_PASSWORD, NEW_PASSWORD)
    assert "e=mismatch" in change(FACTORY_PASSWORD, NEW_PASSWORD, NEW_PASSWORD + "x")
    assert "e=short" in change(FACTORY_PASSWORD, "short", "short")
    assert change(FACTORY_PASSWORD, NEW_PASSWORD, NEW_PASSWORD) == "/admin/?m=password_changed"
    assert client.get("/admin/").status_code == 200
    token = csrf_of(client.get("/admin/password").text)
    assert "e=weak" in change(NEW_PASSWORD, NEW_PASSWORD, NEW_PASSWORD)  # тот же пароль — не смена


def test_after_change_factory_password_stops_working(client, con):
    logged_in(client)
    other = TestClient(client.app)
    assert "e=bad" in login(other).headers["location"]
    assert login(other, NEW_PASSWORD).headers["location"] == "/admin/"
    assert con.execute("SELECT must_change FROM admins").fetchone()[0] == 0


def test_password_change_closes_other_sessions(client):
    logged_in(client)
    second = TestClient(client.app)
    login(second, NEW_PASSWORD)
    assert second.get("/admin/", follow_redirects=False).status_code == 200
    token = csrf_of(client.get("/admin/password").text)
    client.post("/admin/password", data={"csrf": token, "old": NEW_PASSWORD, "new": "another-pass-77", "again": "another-pass-77"})
    assert second.get("/admin/", follow_redirects=False).headers["location"] == "/admin/login"
    assert client.get("/admin/", follow_redirects=False).status_code == 200


def test_login_csrf_required(client):
    client.get("/admin/login")
    r = client.post("/admin/login", data={"login": "folzy", "password": FACTORY_PASSWORD, "csrf": "forged"},
                    follow_redirects=False)
    assert "e=csrf" in r.headers["location"]


def test_forms_reject_missing_csrf(client, con):
    logged_in(client)
    uid = add_user(con)
    r = client.post(f"/admin/users/{uid}/ban", data={"reason": "x"}, follow_redirects=False)
    assert "e=csrf" in r.headers["location"]
    assert con.execute("SELECT banned FROM users WHERE id = ?", (uid,)).fetchone()[0] == 0


def test_login_rate_limit(client):
    for _ in range(5):
        assert "e=bad" in login(client, "wrong").headers["location"]
    assert "e=too_many" in login(client).headers["location"]


def test_unknown_admin_is_bad_not_distinct(con):
    auth = AdminAuth(con)
    auth.ensure_factory()
    with pytest.raises(AuthError) as e:
        auth.login("ghost", "whatever", "1.1.1.1")
    assert e.value.code == "bad"


def test_logout(client):
    logged_in(client)
    token = csrf_of(client.get("/admin/").text)
    client.post("/admin/logout", data={"csrf": token})
    assert client.get("/admin/", follow_redirects=False).headers["location"] == "/admin/login"


def test_security_headers(client):
    r = client.get("/admin/login")
    assert "script-src" not in r.headers["content-security-policy"]  # default-src 'none' — скриптов нет вообще
    assert "frame-ancestors 'none'" in r.headers["content-security-policy"]
    assert r.headers["cache-control"] == "no-store"


# ---- страницы на пустой базе и на данных ----

def test_empty_dashboard_is_honest_zeroes(client):
    logged_in(client)
    html = client.get("/admin/").text
    assert "Событий ещё нет" in html and "Нет данных для оценки" in html


def test_dashboard_users_card_and_actions(client, con):
    logged_in(client)
    uid = add_user(con)
    con.execute("INSERT INTO sessions (id, user_id, token_hash, device_id, device_name, platform, created_at, last_seen_at)"
                " VALUES ('d_1', ?, ?, 'dev-1', 'iPhone 15', 'ios', 1, 1)", (uid, hashlib.sha256(b"tok").hexdigest()))
    dev = events.session_device(con, "tok")
    now = now_ms()
    assert events.record(con, dev, [{"kind": "open", "at": now - 1000},
                                    {"kind": "play", "at": now, "ref": "sc:1", "artist": "kyle", "title": "cold room"}]) == 2
    assert "cold room" in client.get("/admin/?p=today").text
    assert client.get("/admin/?p=custom&from=2026-01-01&to=bad").status_code == 200
    users_html = client.get("/admin/users?q=mir").text
    assert "mira" in users_html
    card = client.get(f"/admin/users/{uid}")
    assert "iPhone 15" in card.text
    token = csrf_of(card.text)
    assert "m=sub_granted" in client.post(f"/admin/users/{uid}/sub", data={"csrf": token, "plan": "echo", "days": "30",
                                                                         "amount": "190"}, follow_redirects=False).headers["location"]
    assert "Echo" in client.get("/admin/users?f=subscribed").text
    assert "m=login_set" in client.post(f"/admin/users/{uid}/login", data={"csrf": token, "login": "mira2"},
                                        follow_redirects=False).headers["location"]
    assert con.execute("SELECT login, username FROM users WHERE id = ?", (uid,)).fetchone()[:] == ("mira2", "mira")
    assert "m=banned" in client.post(f"/admin/users/{uid}/ban", data={"csrf": token, "reason": "спам"},
                                     follow_redirects=False).headers["location"]
    assert con.execute("SELECT COUNT(*) FROM sessions WHERE user_id = ?", (uid,)).fetchone()[0] == 0
    assert events.session_device(con, "tok") is None
    assert "Блокировка" in client.get("/admin/audit").text
    assert client.get("/admin/users/u_nope").status_code == 404


def test_set_login_rejects_taken_and_bad(con):
    from sonar.admin import users
    add_user(con, "u_1", "mira", n=1)
    add_user(con, "u_2", "lev", n=2)
    for login_, code in (("lev", "login_taken"), ("A B", "login_format"), ("mira", "no_change")):
        with pytest.raises(users.UserError) as e:
            users.set_login(con, "folzy", "u_1", login_)
        assert e.value.code == code


# ---- настройки ----

def test_settings_save_and_apply(client, app, con):
    logged_in(client)
    token = csrf_of(client.get("/admin/settings").text)
    form = {"csrf": token, "registration_open": "", "maintenance": "1", "maintenance_text": "Чиним",
            "yandex_enabled": "1", "bot_notice": "Завтра обновление", "site_url": "https://sonar.folzy.ru",
            "channel": "@SonarUpdates", "download_url": "", "download_url_ios": ""}
    r = client.post("/admin/settings", data=form, follow_redirects=False)
    assert "m=saved" in r.headers["location"]
    s = app.state.settings
    assert s.registration_open is False and s.maintenance is True and s.bot_notice == "Завтра обновление"
    cfg = client.get("/config").json()
    assert cfg["registration_open"] is False and cfg["maintenance"] == {"on": True, "text": "Чиним"}
    assert cfg["links"]["windows"] == prefs.ALL["download_url"].default
    bad = client.post("/admin/settings", data={**form, "site_url": "http://evil"}, follow_redirects=False)
    assert "e=not_https" in bad.headers["location"]


# ---- приём событий ----

def test_events_endpoint(client, con):
    uid = add_user(con)
    con.execute("INSERT INTO sessions (id, user_id, token_hash, device_id, device_name, platform, created_at, last_seen_at)"
                " VALUES ('d_1', ?, ?, 'dev-1', 'PC', 'windows', 1, 1)", (uid, hashlib.sha256(b"tok").hexdigest()))
    assert client.post("/events", json={"events": []}).status_code == 401
    assert client.post("/events", json={"events": []}, headers={"Authorization": "Bearer nope"}).status_code == 401
    h = {"Authorization": "Bearer tok"}
    now = now_ms()
    batch = {"events": [{"kind": "open", "at": now}, {"kind": "play", "at": now + 1, "ref": "ym:5", "artist": "A"},
                        {"kind": "play", "at": now + 2}, {"kind": "hack", "at": now},
                        {"kind": "open", "at": now - 30 * 86400_000}, {"kind": "open", "at": "x"}]}
    assert client.post("/events", json=batch, headers=h).json() == {"accepted": 2}
    assert client.post("/events", json=batch, headers=h).json() == {"accepted": 0}  # повтор пачки не удваивает
    row = con.execute("SELECT platform, service, device_id FROM events WHERE kind = 'play'").fetchone()
    assert tuple(row) == ("windows", "yandex", "dev-1")  # платформа и устройство — из сессии, сервис — из ref
    assert client.post("/events", json={"events": [{}] * 201}, headers=h).status_code == 400
    assert client.post("/events", content=b"{", headers={**h, "content-type": "application/json"}).status_code == 400


def test_admin_host_redirect(client):
    r = client.get("/", headers={"host": "admin.trysonar.ru"}, follow_redirects=False)
    assert r.status_code == 303 and r.headers["location"] == "/admin/"


def test_bot_notice_in_menus():
    from sonar.bot import screens as S
    s = Settings(bot_notice="Завтра <b>обновление</b>")
    assert "Завтра &lt;b&gt;обновление&lt;/b&gt;" in S.guest(s).html
    assert "обновление" not in S.guest(Settings()).html
