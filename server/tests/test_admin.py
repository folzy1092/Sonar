"""Админка: вход со случайным заводским паролем, обязательная смена, CSRF, лимит попыток, страницы, действия, события."""
import hashlib
import re
from asyncio import run

import pytest
from fastapi.testclient import TestClient

from sonar import events
from sonar.admin import prefs
from sonar.admin.auth import (FACTORY_LOGIN, LOGIN_TRIES_PER_IP, LOGIN_TRIES_PER_LOGIN, PASSWORD_MIN, AdminAuth,
                              AuthError)
from sonar.config import Settings
from sonar.db import now_ms
from sonar.web import create_app

FACTORY_PASSWORD = ""  # случайный, его задаёт фикстура app (create_app сам печатает пароль в журнал)
NEW_PASSWORD = "river-sonar-42"


@pytest.fixture
def app(con, tmp_path):
    global FACTORY_PASSWORD
    FACTORY_PASSWORD = AdminAuth(con).ensure_factory()
    return create_app(con, Settings(data_dir=tmp_path))


@pytest.fixture
def client(app):
    return TestClient(app, base_url="http://testserver")


def csrf_of(html: str) -> str:
    return re.search(r'name="csrf" value="([^"]+)"', html).group(1)


def login(client, password=None, user=FACTORY_LOGIN):
    password = FACTORY_PASSWORD if password is None else password
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

def test_factory_admin_created_once_with_random_password(con):
    auth = AdminAuth(con)
    password = auth.ensure_factory()
    assert password and len(password) >= PASSWORD_MIN and password.lower() != FACTORY_LOGIN
    assert auth.ensure_factory() is None
    row = con.execute("SELECT * FROM admins").fetchone()
    assert row["login"] == "folzy" and row["must_change"] == 1
    assert row["password_hash"].startswith("$argon2id$") and password not in row["password_hash"]
    run(auth.login("folzy", password, "1.1.1.1"))


def test_factory_password_differs_per_install(tmp_path):
    from sonar.db import connect
    first = AdminAuth(connect(tmp_path / "a.db")).ensure_factory()
    second = AdminAuth(connect(tmp_path / "b.db")).ensure_factory()
    assert first != second


def test_factory_password_logged_once(con, tmp_path, caplog):
    with caplog.at_level("WARNING", logger="sonar.web"):
        create_app(con, Settings(data_dir=tmp_path))
        create_app(con, Settings(data_dir=tmp_path))
    shown = [r.getMessage() for r in caplog.records if "пароль" in r.getMessage()]
    assert len(shown) == 1
    password = shown[0].split("пароль: ")[1].split(" ")[0]
    run(AdminAuth(con).login("folzy", password, "1.1.1.1"))


def test_factory_password_not_in_source():
    from pathlib import Path
    root = Path(__file__).resolve().parent.parent
    for f in [*(root / "sonar").rglob("*.py"), root / "env.example"]:
        text = f.read_text(encoding="utf-8")
        assert not re.search(r"""password\w*\s*=\s*["']folzy["']""", text, re.I), f
        assert "$argon2id$" not in text, f  # ни пароля, ни его хэша в публичном репо


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
        run(auth.login("ghost", "whatever", "1.1.1.1"))
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
            "yandex_enabled": "1", "bot_notice": "Завтра обновление", "site_url": "https://try-sonar.ru",
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


# ---- выход с устройств, журнал, свои сессии ----

def add_session(con, uid, sid, device):
    con.execute("INSERT INTO sessions (id, user_id, token_hash, device_id, device_name, platform, created_at, last_seen_at)"
                " VALUES (?, ?, ?, ?, ?, 'ios', 1, 1)", (sid, uid, hashlib.sha256(sid.encode()).hexdigest(), device, device))


def test_end_one_device_and_all_devices_without_ban(client, con):
    logged_in(client)
    uid = add_user(con)
    add_session(con, uid, "s_1", "dev-1")
    add_session(con, uid, "s_2", "dev-2")
    token = csrf_of(client.get(f"/admin/users/{uid}").text)
    r = client.post(f"/admin/users/{uid}/device", data={"csrf": token, "device": "dev-1"}, follow_redirects=False)
    assert "m=device_ended" in r.headers["location"]
    assert [r[0] for r in con.execute("SELECT device_id FROM sessions WHERE user_id = ?", (uid,))] == ["dev-2"]
    r = client.post(f"/admin/users/{uid}/device", data={"csrf": token, "device": "dev-1"}, follow_redirects=False)
    assert "e=no_change" in r.headers["location"]
    r = client.post(f"/admin/users/{uid}/logout_all", data={"csrf": token}, follow_redirects=False)
    assert "m=logged_out" in r.headers["location"]
    assert con.execute("SELECT COUNT(*) FROM sessions WHERE user_id = ?", (uid,)).fetchone()[0] == 0
    assert con.execute("SELECT banned FROM users WHERE id = ?", (uid,)).fetchone()[0] == 0
    actions = [r[0] for r in con.execute("SELECT action FROM admin_audit WHERE target = ? ORDER BY id", (uid,))]
    assert actions == ["end_device", "logout_all"]
    assert "e=no_change" in client.post(f"/admin/users/{uid}/logout_all", data={"csrf": token},
                                        follow_redirects=False).headers["location"]


def test_audit_filter_and_pages(client, con):
    from sonar.admin import users as admin_users
    logged_in(client)
    uid = add_user(con)
    for i in range(admin_users.AUDIT_PAGE + 5):
        admin_users.audit(con, "folzy", "grant_sub", uid, n=i)
    admin_users.audit(con, "folzy", "ban", uid, reason="спам")
    page = client.get("/admin/audit?a=ban").text
    assert "спам" in page and "Подписка вручную</td>" not in page
    first = client.get("/admin/audit?a=grant_sub").text
    assert "page=2" in first
    second = client.get("/admin/audit?a=grant_sub&page=2").text
    assert second.count("Подписка вручную</td>") == 5
    assert client.get("/admin/audit?a=nope&page=x").status_code == 200


def test_admin_sees_own_sessions_and_closes_others(app, con):
    a = logged_in(TestClient(app, base_url="http://testserver"))
    b = TestClient(app, base_url="http://testserver")
    login(b, NEW_PASSWORD)
    page = a.get("/admin/password").text
    assert page.count('<li class="sess') == 2
    r = a.post("/admin/sessions/close_others", data={"csrf": csrf_of(page)}, follow_redirects=False)
    assert "m=sessions_closed" in r.headers["location"]
    assert b.get("/admin/", follow_redirects=False).headers["location"] == "/admin/login"
    assert a.get("/admin/", follow_redirects=False).status_code == 200


def test_failed_logins_go_to_audit_with_cap(client, con):
    from sonar.admin import users as admin_users
    login(client, "wrong", user="intruder")
    row = con.execute("SELECT admin, detail FROM admin_audit WHERE action = 'login_failed'").fetchone()
    assert row["admin"] == "—" and '"login": "intruder"' in row["detail"] and '"reason": "bad"' in row["detail"]
    for _ in range(5):
        login(client, "wrong")
    reasons = [r[0] for r in con.execute("SELECT detail FROM admin_audit WHERE action = 'login_failed'")]
    assert any('"reason": "too_many"' in d for d in reasons)
    for _ in range(admin_users.FAILED_LOGIN_CAP):
        admin_users.login_failed(con, "x", "1.1.1.1", "bad")
    assert admin_users.login_failed(con, "x", "1.1.1.1", "bad") is False
    assert con.execute("SELECT COUNT(*) FROM admin_audit WHERE action = 'login_failed'").fetchone()[0] \
        == admin_users.FAILED_LOGIN_CAP


def test_audit_csv_export_filtered_and_formula_safe(client, con):
    from sonar.admin import users as admin_users
    assert client.get("/admin/audit.csv", follow_redirects=False).headers["location"] == "/admin/login"
    logged_in(client)
    uid = add_user(con)
    admin_users.audit(con, "folzy", "ban", uid, reason="=HYPERLINK(\"x\")")
    admin_users.audit(con, "folzy", "grant_sub", uid, days=30)
    r = client.get("/admin/audit.csv?a=ban")
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/csv")
    assert "attachment" in r.headers["content-disposition"] and "-ban-" in r.headers["content-disposition"]
    text = r.text.lstrip("﻿")
    assert text.splitlines()[0] == "at,admin,action,user_id,user_login,detail"
    assert "mira" in text and "grant_sub" not in text
    assert admin_users.csv_cell("=1+1") == "'=1+1" and admin_users.csv_cell("-5") == "'-5"
    assert admin_users.csv_cell("ok") == "ok" and admin_users.csv_cell(None) == ""
    assert "Скачать CSV" in client.get("/admin/audit").text


def test_users_search_by_telegram_id(client, con):
    logged_in(client)
    add_user(con, "u_1", "mira", n=1)
    add_user(con, "u_2", "lev", n=2)
    con.execute("UPDATE users SET tg_id = 987654321 WHERE id = 'u_2'")
    page = client.get("/admin/users?q=987654321").text
    assert "lev" in page and "mira" not in page


def test_rate_limit_check_does_not_grow_memory():
    from sonar.accounts import RateLimit
    limit = RateLimit(limit=2, window_s=60)
    for i in range(500):
        assert limit.blocked(f"ip:10.0.0.{i}", f"login:user{i}") is False
    assert limit.hits == {}, "проверка без попыток не заводит записей"
    limit.hit("ip:1")
    limit.hits["ip:1"][0] -= 120  # попытка старше окна
    assert limit.blocked("ip:1") is False and "ip:1" not in limit.hits, "отжившая очередь удаляется"


def test_admin_login_key_is_capped(con):
    auth = AdminAuth(con)
    with pytest.raises(AuthError):
        run(auth.login("x" * 10_000, "wrong", "1.2.3.4"))
    assert max(len(k) for k in auth.login_limit.hits) <= len("login:") + 64


def test_lockout_from_one_ip_does_not_lock_owner(con):
    """Аудит п. 11: пять неудачных попыток с чужого IP закрывают этот IP, а не логин для всех."""
    auth = AdminAuth(con)
    password = auth.ensure_factory()
    for _ in range(LOGIN_TRIES_PER_IP):
        with pytest.raises(AuthError):
            run(auth.login("folzy", "wrong", "6.6.6.6"))
    with pytest.raises(AuthError) as e:
        run(auth.login("folzy", password, "6.6.6.6"))
    assert e.value.code == "too_many"
    run(auth.login("folzy", password, "1.1.1.1"))


def test_spread_brute_force_hits_soft_login_limit(con):
    auth = AdminAuth(con)
    password = auth.ensure_factory()
    for i in range(LOGIN_TRIES_PER_LOGIN):
        with pytest.raises(AuthError):
            run(auth.login("folzy", "wrong", f"10.0.{i // 256}.{i % 256}"))
    with pytest.raises(AuthError) as e:
        run(auth.login("folzy", password, "1.1.1.1"))
    assert e.value.code == "too_many"


def test_future_custom_period_and_huge_page(client, con):
    from sonar.admin.web import PAGE_MAX, _int
    logged_in(client)
    assert _int("9" * 40) == PAGE_MAX and _int("-5") == 1 and _int("x") == 1
    assert client.get("/admin/audit?page=" + "9" * 40).status_code == 200
    assert client.get("/admin/users?page=" + "9" * 40).status_code == 200
    r = client.get("/admin/?p=custom&from=2999-01-01&to=2999-02-01")
    assert r.status_code == 200


def _req(client_host: str, headers: dict[str, str]):
    from starlette.requests import Request
    raw = [(k.lower().encode(), v.encode()) for k, v in headers.items()]
    return Request({"type": "http", "client": (client_host, 1234), "headers": raw, "scheme": "http",
                    "path": "/", "server": ("x", 80), "query_string": b""})


def test_ip_headers_only_from_trusted_proxy(monkeypatch):
    from sonar.admin.web import _https, _ip
    monkeypatch.delenv("SONAR_TRUSTED_PROXIES", raising=False)
    spoof = {"X-Forwarded-For": "1.2.3.4", "CF-Connecting-IP": "5.6.7.8", "X-Forwarded-Proto": "https"}
    # Напрямую на открытый порт: заголовкам не верим.
    assert _ip(_req("203.0.113.9", spoof)) == "203.0.113.9"
    assert not _https(_req("203.0.113.9", spoof))
    # Через прокси хостинга: берём клиента справа, пропуская доверенные адреса.
    assert _ip(_req("10.0.0.2", {"X-Forwarded-For": "9.9.9.9, 1.2.3.4, 10.0.0.5"})) == "1.2.3.4"
    assert _ip(_req("10.0.0.2", {"X-Real-IP": "8.8.4.4"})) == "8.8.4.4"
    assert _https(_req("10.0.0.2", {"X-Forwarded-Proto": "https"}))
    monkeypatch.setenv("SONAR_TRUSTED_PROXIES", "203.0.113.0/24")
    assert _ip(_req("203.0.113.9", spoof)) == "1.2.3.4"
