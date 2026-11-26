"""Доступ помощникам: права panel / server / moderation из админки (staff.py, ADMIN.md «Доступ», BOT.md §2.12з)."""
import asyncio
import re
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from sonar import bans, staff
from sonar.admin.auth import AdminAuth
from sonar.bot import handlers as H
from sonar.bot import moderation as M
from sonar.config import Settings
from sonar.db import now_ms
from sonar.web import create_app

OWNER_TG, HELPER_TG, OTHER_TG = 100, 300, 555
NEW_PASSWORD = "river-sonar-42"
HELPER_PASSWORD = "helper-pass-777"


def csrf(html: str) -> str:
    return re.search(r'name="csrf" value="([^"]+)"', html).group(1)


def add_user(con, login, tg_id=None, n=1):
    uid = f"u_{login}"
    con.execute("INSERT INTO users (id, number, login, username, display_name, created_at, tg_id) VALUES (?,?,?,?,?,?,?)",
                (uid, n, login, login, login, now_ms(), tg_id))
    return uid


def sign_in(client, login, password, new):
    client.post("/admin/login", data={"login": login, "password": password, "csrf": csrf(client.get("/admin/login").text)})
    r = client.post("/admin/password", data={"csrf": csrf(client.get("/admin/password").text), "old": password,
                                             "new": new, "again": new}, follow_redirects=False)
    assert r.headers["location"] == "/admin/?m=password_changed"


@pytest.fixture
def site(con, tmp_path):
    factory = AdminAuth(con).ensure_factory()
    app = create_app(con, Settings(data_dir=tmp_path, owner_tg_id=OWNER_TG))
    owner = TestClient(app, base_url="http://testserver")
    sign_in(owner, "folzy", factory, NEW_PASSWORD)
    add_user(con, "boss", tg_id=OWNER_TG, n=1)
    add_user(con, "mira", tg_id=HELPER_TG, n=2)
    add_user(con, "kolya", tg_id=OTHER_TG, n=3)
    return SimpleNamespace(app=app, owner=owner, con=con)


def grant(site, user, *perms):
    data = {"csrf": csrf(site.owner.get("/admin/access").text), "user": user}
    data.update({f"perm_{p}": "1" for p in perms})
    return site.owner.post("/admin/access", data=data, follow_redirects=False)


def helper(site, *perms):
    """Выдать mira права с админкой, войти ею и сменить одноразовый пароль → её клиент."""
    r = grant(site, "#2", "panel", *perms)
    password = re.search(r'одноразовый пароль <span class="mono">([^<]+)</span>', r.text).group(1)
    client = TestClient(site.app, base_url="http://testserver")
    sign_in(client, "mira", password, HELPER_PASSWORD)
    return client


def user_action(client, uid, action, **data):
    token = csrf(client.get(f"/admin/users/{uid}").text)
    return client.post(f"/admin/users/{uid}/{action}", data={"csrf": token, **data}, follow_redirects=False)


# ---- админка: выдача и отзыв ----

def test_grant_panel_creates_one_time_login_and_is_audited(site, con):
    r = grant(site, "#2", "panel", "moderation")
    assert r.status_code == 200 and "одноразовый пароль" in r.text
    admin = con.execute("SELECT * FROM admins WHERE user_id = 'u_mira'").fetchone()
    assert admin["login"] == "mira" and admin["must_change"] == 1
    assert staff.stored_perms(con, "u_mira") == {"panel", "moderation"}
    audit = con.execute("SELECT * FROM admin_audit WHERE action = 'grant_staff'").fetchone()
    assert audit["admin"] == "folzy" and audit["target"] == "u_mira" and "panel,moderation" in audit["detail"]
    page = site.owner.get("/admin/access").text
    assert "mira" in page and "Модерация" in page and "одноразовый пароль" not in page


def test_grant_without_panel_makes_no_admin_login(site, con):
    r = grant(site, "mira", "server")
    assert r.headers["location"] == "/admin/access?m=staff_saved"
    assert con.execute("SELECT COUNT(*) FROM admins WHERE user_id = 'u_mira'").fetchone()[0] == 0


def test_grant_refusals(site, con):
    assert grant(site, "#1", "panel").headers["location"] == "/admin/access?e=owner"
    assert grant(site, "nobody", "panel").headers["location"] == "/admin/access?e=no_user"
    assert grant(site, "mira").headers["location"] == "/admin/access?e=no_change"
    add_user(con, "folzy", n=4)
    assert grant(site, "folzy", "panel").headers["location"] == "/admin/access?e=admin_login_taken"
    r = site.owner.post("/admin/access", data={"csrf": "x", "user": "mira", "perm_panel": "1"}, follow_redirects=False)
    assert r.headers["location"] == "/admin/access?e=csrf" and not staff.stored_perms(con, "u_mira")


def test_revoke_removes_login_and_sessions(site, con):
    client = helper(site, "moderation")
    assert client.get("/admin/users").status_code == 200
    token = csrf(site.owner.get("/admin/access").text)
    r = site.owner.post("/admin/access/revoke", data={"csrf": token, "user": "u_mira"}, follow_redirects=False)
    assert r.headers["location"] == "/admin/access?m=staff_revoked"
    assert con.execute("SELECT COUNT(*) FROM admins WHERE user_id = 'u_mira'").fetchone()[0] == 0
    assert not staff.stored_perms(con, "u_mira")
    assert client.get("/admin/", follow_redirects=False).headers["location"].startswith("/admin/login")
    assert con.execute("SELECT COUNT(*) FROM admin_audit WHERE action = 'revoke_staff'").fetchone()[0] == 1


def test_unticking_panel_keeps_other_rights_but_drops_login(site, con):
    helper(site, "server")
    grant(site, "mira", "server")
    assert staff.stored_perms(con, "u_mira") == {"server"}
    assert con.execute("SELECT COUNT(*) FROM admins WHERE user_id = 'u_mira'").fetchone()[0] == 0


# ---- админка: что видит помощник ----

def test_helper_sees_only_granted_pages(site):
    client = helper(site)
    home = client.get("/admin/").text
    assert "Пользователи" in home and "Доступ" not in home and "Настройки" not in home and "Сервер" not in home
    for path in ("/admin/access", "/admin/settings", "/admin/builds", "/admin/server"):
        assert client.get(path).status_code == 403, path
    assert client.get("/admin/users").status_code == 200 and client.get("/admin/audit").status_code == 200
    token = csrf(client.get("/admin/").text)
    r = client.post("/admin/access", data={"csrf": token, "user": "kolya", "perm_panel": "1"})
    assert r.status_code == 403 and not staff.stored_perms(site.con, "u_kolya")


def test_server_right_opens_server_page(site):
    client = helper(site, "server")
    assert client.get("/admin/server").status_code == 200 and "Сервер" in client.get("/admin/").text


def test_moderation_needs_its_right(site, con):
    client = helper(site)
    assert user_action(client, "u_kolya", "ban").status_code == 403
    assert bans.of_user(con, "u_kolya") is None
    assert "Заблокировать" not in client.get("/admin/users/u_kolya").text


def test_moderator_bans_others_but_not_owner_self_or_owner_only_actions(site, con):
    client = helper(site, "moderation")
    r = user_action(client, "u_kolya", "ban", duration="1д", reason="спам")
    assert r.headers["location"] == "/admin/users/u_kolya?m=banned" and bans.of_user(con, "u_kolya")
    assert user_action(client, "u_boss", "ban").headers["location"] == "/admin/users/u_boss?e=owner"
    assert user_action(client, "u_boss", "logout_all").headers["location"] == "/admin/users/u_boss?e=owner"
    assert user_action(client, "u_mira", "ban").headers["location"] == "/admin/users/u_mira?e=self"
    assert user_action(client, "u_kolya", "login", login="newname").status_code == 403
    assert user_action(client, "u_kolya", "sub", plan="ping", days="30").status_code == 403


def test_owner_still_cannot_ban_owner_account(site, con):
    r = user_action(site.owner, "u_boss", "ban")
    assert r.headers["location"] == "/admin/users/u_boss?e=owner" and bans.of_user(con, "u_boss") is None


def test_banned_helper_loses_panel_at_once(site, con):
    client = helper(site, "moderation")
    bans.ban(con, "folzy", "u_mira", "", None)
    r = client.get("/admin/users", follow_redirects=False)
    assert r.headers["location"] == "/admin/login?e=no_access"
    assert client.get("/admin/users", follow_redirects=False).headers["location"] == "/admin/login"


# ---- бот ----

class FakeShower:
    def __init__(self):
        self.shown = []

    async def send(self, chat_id, screen, reply_to=None):
        self.shown.append(screen)
        return SimpleNamespace(chat=SimpleNamespace(id=chat_id), message_id=1)

    async def edit(self, msg, screen):
        self.shown.append(screen)
        return msg


class Unavailable:
    def available(self):
        return False


@pytest.fixture
def bot(con):
    add_user(con, "boss", tg_id=OWNER_TG, n=1)
    add_user(con, "mira", tg_id=HELPER_TG, n=2)
    add_user(con, "kolya", tg_id=OTHER_TG, n=3)
    return SimpleNamespace(settings=Settings(owner_tg_id=OWNER_TG), shower=FakeShower(), updater=Unavailable(),
                           accounts=SimpleNamespace(con=con), is_owner=lambda uid: uid == OWNER_TG)


def set_perms(con, uid, perms):
    con.execute("INSERT INTO staff (user_id, perms, granted_at, granted_by) VALUES (?,?,?,?)",
                (uid, perms, now_ms(), "folzy"))


def message(uid):
    return SimpleNamespace(chat=SimpleNamespace(id=uid, type="private"), from_user=SimpleNamespace(id=uid))


def test_bot_update_needs_server_right(bot, con):
    set_perms(con, "u_mira", "moderation")
    asyncio.run(H.cmd_update(message(HELPER_TG), bot))
    assert bot.shower.shown == []
    con.execute("UPDATE staff SET perms = 'server' WHERE user_id = 'u_mira'")
    asyncio.run(H.cmd_update(message(HELPER_TG), bot))
    assert len(bot.shower.shown) == 1                        # меню (тут — «не на хостинге»), а не тишина


def test_bot_moderation_needs_moderation_right(bot, con):
    set_perms(con, "u_mira", "server")
    asyncio.run(M.cmd_ban(message(HELPER_TG), SimpleNamespace(args="kolya"), bot))
    assert bot.shower.shown == [] and bans.of_user(con, "u_kolya") is None
    con.execute("UPDATE staff SET perms = 'moderation' WHERE user_id = 'u_mira'")
    asyncio.run(M.cmd_ban(message(HELPER_TG), SimpleNamespace(args="kolya 1д флуд"), bot))
    assert bans.of_user(con, "u_kolya") is not None
    actor = con.execute("SELECT admin FROM admin_audit WHERE target = 'u_kolya'").fetchone()
    assert actor["admin"] == f"telegram:{HELPER_TG}"


def test_bot_moderator_cannot_ban_owner_or_self(bot, con):
    set_perms(con, "u_mira", "moderation")
    asyncio.run(M.cmd_ban(message(HELPER_TG), SimpleNamespace(args="boss"), bot))
    assert "Владельца" in bot.shower.shown[-1].html and bans.of_user(con, "u_boss") is None
    asyncio.run(M.cmd_ban(message(HELPER_TG), SimpleNamespace(args="mira"), bot))
    assert "Себя" in bot.shower.shown[-1].html and bans.of_user(con, "u_mira") is None
    asyncio.run(M.cmd_rban(message(HELPER_TG), SimpleNamespace(args="mira"), bot))
    assert "Себя" in bot.shower.shown[-1].html


def test_banned_helper_has_no_rights_in_bot(bot, con):
    set_perms(con, "u_mira", "server,moderation")
    bans.ban(con, "folzy", "u_mira", "", None)
    assert staff.perms_by_tg(con, HELPER_TG) == staff.NONE
    assert not staff.allowed(bot, HELPER_TG, "server")
    assert staff.allowed(bot, OWNER_TG, "server") and staff.allowed(bot, OWNER_TG, "moderation")
