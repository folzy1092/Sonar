"""Блокировки: бан аккаунта на срок и навсегда, 403 `account_banned` в API, вход заблокированного, фильтр в боте,
команды владельца, блок обращений «Баг / Идея»."""
import asyncio
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from sonar import bans, sessions
from sonar.api import auth as api_auth
from sonar.bot import handlers as H
from sonar.bot import moderation as M
from sonar.config import Settings
from sonar.db import now_ms
from sonar.web import create_app

PC = {"id": "hwid-pc", "name": "Windows 10", "platform": "windows", "os": "Windows 10", "app_version": "0.2.0", "build": 5}
OWNER, TG, STRANGER = 100, 555, 777


# ---- срок ----

@pytest.mark.parametrize("text,expect", [
    ("30m", (True, 30 * 60_000)), ("2ч", (True, 2 * 3600_000)), ("3д", (True, 3 * 86400_000)),
    ("1w", (True, 7 * 86400_000)), ("5мин", (True, 5 * 60_000)), ("навсегда", (True, None)), ("perm", (True, None)),
    ("0д", (False, None)), ("спам", (False, None)), ("12", (False, None)), ("", (False, None))])
def test_parse_duration(text, expect):
    assert bans.parse_duration(text) == expect


@pytest.mark.parametrize("text,expect", [
    ("mira 7д спамит в репортах", ("mira", 7 * 86400_000, "спамит в репортах")),
    ("mira 7 дней спам", ("mira", 7 * 86400_000, "спам")),      # иначе «7 дней» стало бы вечным баном
    ("mira спам", ("mira", None, "спам")), ("mira", ("mira", None, "")), ("mira навсегда флуд", ("mira", None, "флуд")),
    ("", ("", None, ""))])
def test_split_args(text, expect):
    assert bans.split_args(text) == expect


# ---- аккаунт ----

def add_user(con, login="mira", tg_id=None, n=1, banned=0, until=None):
    con.execute("INSERT INTO users (id, number, login, username, display_name, tg_id, created_at, banned, ban_until)"
                " VALUES (?,?,?,?,?,?,?,?,?)", (f"u_{login}", n, login, login, login.title(), tg_id, now_ms(), banned, until))
    return f"u_{login}"


def add_session(con, uid, token="tok", device="dev-1"):
    con.execute("INSERT INTO sessions (id, user_id, token_hash, device_id, device_name, platform, created_at, last_seen_at)"
                " VALUES (?,?,?,?,?,?,?,?)", (f"s_{token}", uid, sessions._h(token), device, "ПК", "windows", now_ms(), now_ms()))


def test_ban_keeps_sessions_and_unban_restores_access(con):
    uid = add_user(con)
    add_session(con, uid)
    bans.ban(con, "folzy", uid, "спам", None)
    assert sessions.by_token(con, "tok") is None                       # доступ закрыт
    assert con.execute("SELECT COUNT(*) FROM sessions").fetchone()[0] == 1   # а сессия цела: клиент узнает причину
    ban = bans.of_token(con, sessions._h("tok"))
    assert ban.reason == "спам" and ban.forever
    bans.unban(con, "folzy", uid)
    assert sessions.by_token(con, "tok") is not None and bans.of_user(con, uid) is None


def test_temporary_ban_expires(con):
    uid = add_user(con)
    bans.ban(con, "folzy", uid, "", now_ms() + 60_000)
    assert bans.of_user(con, uid).until is not None
    assert bans.expire(con, now=now_ms() + 61_000) == [uid]
    assert bans.of_user(con, uid) is None
    row = con.execute("SELECT admin, action FROM admin_audit WHERE action = 'ban_expired'").fetchone()
    assert tuple(row) == ("system", "ban_expired")


def test_of_user_notices_expiry_even_between_loop_runs(con):
    uid = add_user(con)
    con.execute("UPDATE users SET banned = 1, ban_until = ? WHERE id = ?", (now_ms() - 1, uid))
    assert bans.of_user(con, uid) is None


def test_repeat_ban_changes_term(con):
    uid = add_user(con)
    bans.ban(con, "a", uid, "первый раз", now_ms() + 3600_000)
    bans.ban(con, "a", uid, "второй раз", None)
    ban = bans.of_user(con, uid)
    assert ban.forever and ban.reason == "второй раз"


def test_ban_unknown_user_and_double_unban(con):
    with pytest.raises(bans.ModerationError):
        bans.ban(con, "a", "u_нет")
    uid = add_user(con)
    with pytest.raises(bans.ModerationError):
        bans.unban(con, "a", uid)


@pytest.mark.parametrize("query,login", [("mira", "mira"), ("@mira", "mira"), ("#7", "mira"), ("7", "mira"), ("555", "mira"),
                                         ("MIRA", "mira")])
def test_find_by_any_handle(con, query, login):
    add_user(con, "mira", tg_id=555, n=7)
    assert bans.find(con, query)["login"] == login
    assert bans.find(con, "нет") is None


# ---- API ----

@pytest.fixture(autouse=True)
def fresh_register_limit(monkeypatch):
    monkeypatch.setattr(api_auth, "_register_limit", api_auth.RateLimit(limit=api_auth.REGISTER_PER_IP, window_s=3600))


@pytest.fixture
def client(con, tmp_path):
    return TestClient(create_app(con, Settings(data_dir=tmp_path)), base_url="http://testserver")


def bearer(token):
    return {"Authorization": f"Bearer {token}"}


def signup(client, login="mira", device=PC):
    r = client.post("/api/auth/register", json={"login": login, "password": "secret-pass", "device": device})
    assert r.status_code == 200, r.text
    return r.json()["session"], r.json()["user"]["id"]


def test_api_tells_banned_client_why(client, con):
    token, uid = signup(client)
    until = now_ms() + 3600_000
    bans.ban(con, "folzy", uid, "спам в поддержку", until)
    r = client.get("/api/me", headers=bearer(token))
    assert r.status_code == 403
    err = r.json()["error"]
    assert err["code"] == "account_banned" and err["until"] == until and err["reason"] == "спам в поддержку"
    assert "заблокирована" in err["message"] and "спам в поддержку" in err["message"]
    assert client.post("/api/auth/logout", headers=bearer(token)).status_code == 403


def test_api_permanent_ban_has_null_until(client, con):
    token, uid = signup(client)
    bans.ban(con, "folzy", uid, "", None)
    err = client.get("/api/me", headers=bearer(token)).json()["error"]
    assert err["until"] is None and err["reason"] is None and "навсегда" in err["message"]


def test_api_bogus_token_is_still_401_and_unban_restores(client, con):
    token, uid = signup(client)
    assert client.get("/api/me", headers=bearer("bogus")).status_code == 401
    bans.ban(con, "folzy", uid, "", None)
    bans.unban(con, "folzy", uid)
    assert client.get("/api/me", headers=bearer(token)).status_code == 200      # тот же токен снова работает


def test_banned_cannot_log_in_and_is_told_only_with_right_password(client, con):
    _, uid = signup(client)
    bans.ban(con, "folzy", uid, "спам", None)
    ok = client.post("/api/auth/login", json={"login": "mira", "password": "secret-pass", "device": PC})
    assert ok.status_code == 403 and ok.json()["error"]["code"] == "account_banned" and ok.json()["error"]["reason"] == "спам"
    wrong = client.post("/api/auth/login", json={"login": "mira", "password": "не тот", "device": PC})
    assert wrong.status_code == 401 and wrong.json()["error"]["code"] == "bad_credentials"   # аккаунт не выдаём


def test_temporary_ban_lets_in_after_expiry(client, con):
    _, uid = signup(client)
    bans.ban(con, "folzy", uid, "", now_ms() + 60_000)
    con.execute("UPDATE users SET ban_until = ? WHERE id = ?", (now_ms() - 1, uid))
    assert client.post("/api/auth/login", json={"login": "mira", "password": "secret-pass", "device": PC}).status_code == 200


def test_banned_device_cannot_register_a_new_account(client, con):
    _, uid = signup(client)
    bans.ban(con, "folzy", uid, "обход", None)
    r = client.post("/api/auth/register", json={"login": "mira2", "password": "secret-pass", "device": PC})
    assert r.status_code == 403 and r.json()["error"]["code"] == "account_banned"
    other = dict(PC, id="hwid-other")
    assert client.post("/api/auth/register", json={"login": "lev", "password": "secret-pass", "device": other}).status_code == 200


# ---- бот: фильтр ----

class FakeShower:
    def __init__(self):
        self.shown = []

    async def send(self, chat_id, screen, reply_to=None):
        self.shown.append(screen)
        return SimpleNamespace(chat=SimpleNamespace(id=chat_id), message_id=1)

    async def edit(self, msg, screen):
        self.shown.append(screen)
        return msg


@pytest.fixture
def ctx(con):
    return SimpleNamespace(settings=Settings(owner_tg_id=OWNER), shower=FakeShower(), accounts=SimpleNamespace(con=con),
                           is_owner=lambda uid: uid == OWNER,
                           support=SimpleNamespace(block_of=lambda tg: bans.report_block_of(con, tg)))


def message(uid, chat="private", text=""):
    return SimpleNamespace(chat=SimpleNamespace(id=uid, type=chat), from_user=SimpleNamespace(id=uid), text=text)


def run(coro):
    return asyncio.run(coro)


def gate(ctx, event):
    called = []

    async def handler(ev, data):
        called.append(ev)
        return "handled"
    out = run(M.ban_gate(handler, event, {"ctx": ctx}))
    return out, called


def test_banned_user_gets_ban_screen_instead_of_the_bot(ctx, con):
    uid = add_user(con, tg_id=TG)
    bans.ban(con, "folzy", uid, "спам", now_ms() + 86400_000)
    out, called = gate(ctx, message(TG))
    assert out is None and called == []
    html = ctx.shower.shown[-1].html
    assert "Учётная запись заблокирована" in html and "спам" in html and "до " in html


def test_buttons_of_banned_user_are_stopped_too(ctx, con):
    uid = add_user(con, tg_id=TG)
    bans.ban(con, "folzy", uid, "", None)
    answered = []

    async def answer(*a, **k):
        answered.append(1)
    q = SimpleNamespace(data="x", from_user=SimpleNamespace(id=TG), answer=answer, message=message(TG))
    out, called = gate(ctx, q)
    assert out is None and called == [] and answered == [1] and "навсегда" in ctx.shower.shown[-1].html


def test_gate_lets_through_everyone_else(ctx, con):
    uid = add_user(con, tg_id=TG)
    bans.ban(con, "folzy", uid, "", None)
    assert gate(ctx, message(STRANGER))[0] == "handled"                   # чужой, без бана
    assert gate(ctx, message(TG, chat="supergroup"))[0] == "handled"       # группа поддержки
    con.execute("UPDATE users SET tg_id = ? WHERE id = ?", (OWNER, uid))
    assert gate(ctx, message(OWNER))[0] == "handled"                       # владельца не выкинуть


def test_gate_unblocks_when_ban_lifted(ctx, con):
    uid = add_user(con, tg_id=TG)
    bans.ban(con, "folzy", uid, "", None)
    bans.unban(con, "folzy", uid)
    assert gate(ctx, message(TG))[0] == "handled"


# ---- бот: команды владельца ----

def command(ctx, handler, uid, args):
    run(handler(message(uid), SimpleNamespace(args=args), ctx))


def test_commands_are_owner_only_and_silent_for_others(ctx, con):
    add_user(con, tg_id=TG)
    for handler in (M.cmd_ban, M.cmd_unban, M.cmd_rban, M.cmd_runban, M.cmd_who):
        command(ctx, handler, STRANGER, "mira")
    assert ctx.shower.shown == [] and bans.of_user(con, "u_mira") is None
    run(M.cmd_banned(message(STRANGER), ctx))
    assert ctx.shower.shown == []


def test_ban_command_with_term_and_reason(ctx, con):
    add_user(con, tg_id=TG)
    command(ctx, M.cmd_ban, OWNER, "mira 7д спамит в топиках")
    ban = bans.of_user(con, "u_mira")
    assert ban.reason == "спамит в топиках" and 6.9 * 86400_000 < ban.until - now_ms() <= 7 * 86400_000
    assert "Заблокирован" in ctx.shower.shown[-1].html and "Разбанить" in str([b.text for r in ctx.shower.shown[-1].kb for b in r])
    command(ctx, M.cmd_unban, OWNER, "@mira")
    assert bans.of_user(con, "u_mira") is None


def test_ban_command_without_term_is_forever(ctx, con):
    add_user(con, tg_id=TG)
    command(ctx, M.cmd_ban, OWNER, "mira флуд")
    assert bans.of_user(con, "u_mira").forever


def test_ban_command_errors(ctx, con):
    command(ctx, M.cmd_ban, OWNER, "нет-такого")
    assert "не найден" in ctx.shower.shown[-1].html
    command(ctx, M.cmd_ban, OWNER, "")
    assert "/ban" in ctx.shower.shown[-1].html


def test_owner_cannot_be_banned(ctx, con):
    add_user(con, "boss", tg_id=OWNER)
    command(ctx, M.cmd_ban, OWNER, "boss")
    command(ctx, M.cmd_rban, OWNER, "boss")
    assert bans.of_user(con, "u_boss") is None and bans.report_block_of(con, OWNER) is None
    assert "Владельца не блокирую" in ctx.shower.shown[-1].html


def test_report_block_for_account_and_for_bare_telegram_id(ctx, con):
    add_user(con, tg_id=TG)
    command(ctx, M.cmd_rban, OWNER, "mira 1д спам")
    block = bans.report_block_of(con, TG)
    assert block.reason == "спам" and block.until > now_ms()
    command(ctx, M.cmd_rban, OWNER, "4242 навсегда")                       # без аккаунта — по Telegram ID
    assert bans.report_block_of(con, 4242).forever
    command(ctx, M.cmd_runban, OWNER, "4242")
    assert bans.report_block_of(con, 4242) is None
    command(ctx, M.cmd_runban, OWNER, "4242")
    assert "и так открыты" in ctx.shower.shown[-1].html


def test_report_block_expires_and_is_cleaned(con):
    bans.report_block(con, "a", TG, "x", now_ms() - 1)
    assert bans.report_block_of(con, TG) is None
    assert con.execute("SELECT COUNT(*) FROM support_blocks").fetchone()[0] == 0


def test_rban_needs_a_telegram(ctx, con):
    add_user(con, "nogram")
    command(ctx, M.cmd_rban, OWNER, "nogram")
    assert "нет привязанного Telegram" in ctx.shower.shown[-1].html


def test_banned_list_shows_both(ctx, con):
    add_user(con, tg_id=TG)
    command(ctx, M.cmd_ban, OWNER, "mira 3д")
    bans.report_block(con, "a", 4242, "флуд", None)
    run(M.cmd_banned(message(OWNER), ctx))
    html = ctx.shower.shown[-1].html
    assert "mira" in html and "4242" in html and "флуд" in html


def query(data, uid):
    answers = []

    async def answer(text=None, **kw):
        answers.append(text)
    return SimpleNamespace(data=data, from_user=SimpleNamespace(id=uid), answers=answers, answer=answer, message=message(uid))


def buttons(screen):
    return [b.cb for row in screen.kb for b in row]


def test_card_buttons_ban_and_unban(ctx, con):
    uid = add_user(con, tg_id=TG)
    command(ctx, M.cmd_who, OWNER, "mira")
    kb = buttons(ctx.shower.shown[-1])
    assert f"mod:ban:{uid}:7d" in kb and f"mod:rb:{uid}:perm" in kb
    run(M.mod_button(query(f"mod:ban:{uid}:1d", OWNER), ctx))
    assert bans.of_user(con, uid) is not None and f"mod:unban:{uid}" in buttons(ctx.shower.shown[-1])
    run(M.mod_button(query(f"mod:unban:{uid}", OWNER), ctx))
    assert bans.of_user(con, uid) is None


def test_card_buttons_report_block(ctx, con):
    uid = add_user(con, tg_id=TG)
    run(M.mod_button(query(f"mod:rb:{uid}:7d", OWNER), ctx))
    assert bans.report_block_of(con, TG) is not None and f"mod:rub:{uid}" in buttons(ctx.shower.shown[-1])
    run(M.mod_button(query(f"mod:rub:{uid}", OWNER), ctx))
    assert bans.report_block_of(con, TG) is None


def test_card_buttons_are_owner_only(ctx, con):
    uid = add_user(con, tg_id=TG)
    q = query(f"mod:ban:{uid}:perm", STRANGER)
    run(M.mod_button(q, ctx))
    assert q.answers == ["Только для владельца"] and bans.of_user(con, uid) is None


def test_callback_data_fits_telegram_limit(ctx, con):
    uid = "u_" + "a" * 16
    con.execute("INSERT INTO users (id, number, login, username, display_name, tg_id, created_at) VALUES (?,?,?,?,?,?,?)",
                (uid, 1, "x", "x", "X", TG, now_ms()))
    row = con.execute("SELECT * FROM users WHERE id = ?", (uid,)).fetchone()
    for b in buttons(M.card(ctx, row, TG)):
        assert len(b.encode()) <= 64


# ---- обращения: блок срабатывает в трёх местах ----

def test_blocked_user_cannot_open_report(ctx, con):
    bans.report_block(con, "a", TG, "спам", None)
    ctx.support.staff_chat, ctx.support.open_ticket = 1, lambda tg: None
    q = query("report", TG)
    run(H.report_button(q, "", SimpleNamespace(), ctx, None))
    assert "Обращения отключены" in ctx.shower.shown[-1].html and "спам" in ctx.shower.shown[-1].html


def test_block_set_while_writing_stops_the_ticket(ctx, con):
    bans.report_block(con, "a", TG, "", now_ms() + 3600_000)
    created = []

    class State:
        async def get_data(self):
            return {"kind": "bug", "platform": "windows"}

        async def clear(self):
            pass
    ctx.support.create = lambda *a: created.append(a)
    run(H.report_first(message(TG), State(), ctx))
    assert created == [] and "Обращения отключены" in ctx.shower.shown[-1].html


def test_spam_into_open_ticket_is_not_forwarded(ctx, con):
    bans.report_block(con, "a", TG, "", None)
    forwarded = []

    async def forward(t, msg):
        forwarded.append(msg)
    ctx.support.ticket_for_staff_message = lambda m: None
    ctx.support.open_ticket = lambda tg: {"id": "t1"}
    ctx.support.forward = forward
    run(H.any_message(message(TG, text="спам"), ctx))
    assert forwarded == [] and "Обращения отключены" in ctx.shower.shown[-1].html


# ---- админка ----

@pytest.fixture
def admin(con, tmp_path):
    import re

    from sonar.admin.auth import AdminAuth
    password = AdminAuth(con).ensure_factory()
    client = TestClient(create_app(con, Settings(data_dir=tmp_path)), base_url="http://testserver")
    csrf = lambda html: re.search(r'name="csrf" value="([^"]+)"', html).group(1)  # noqa: E731
    client.post("/admin/login", data={"login": "folzy", "password": password, "csrf": csrf(client.get("/admin/login").text)})
    client.post("/admin/password", data={"csrf": csrf(client.get("/admin/password").text), "old": password,
                                         "new": "river-sonar-42", "again": "river-sonar-42"})
    return SimpleNamespace(client=client, token=lambda: csrf(client.get("/admin/users").text))


def test_web_ban_with_duration_and_page_shows_term(admin, con):
    uid = add_user(con, tg_id=TG)
    r = admin.client.post(f"/admin/users/{uid}/ban", data={"csrf": admin.token(), "reason": "флуд", "duration": "7д"},
                          follow_redirects=False)
    assert "m=banned" in r.headers["location"]
    ban = bans.of_user(con, uid)
    assert ban.reason == "флуд" and ban.until is not None
    page = admin.client.get(f"/admin/users/{uid}").text
    assert "до " in page and "флуд" in page
    assert "m=unbanned" in admin.client.post(f"/admin/users/{uid}/unban", data={"csrf": admin.token()},
                                              follow_redirects=False).headers["location"]


def test_web_ban_rejects_bad_duration(admin, con):
    uid = add_user(con, tg_id=TG)
    r = admin.client.post(f"/admin/users/{uid}/ban", data={"csrf": admin.token(), "duration": "хз"}, follow_redirects=False)
    assert "e=bad_duration" in r.headers["location"] and bans.of_user(con, uid) is None


def test_web_report_block_and_unblock(admin, con):
    uid = add_user(con, tg_id=TG)
    r = admin.client.post(f"/admin/users/{uid}/rblock", data={"csrf": admin.token(), "duration": "1д", "reason": "спам"},
                          follow_redirects=False)
    assert "m=report_blocked" in r.headers["location"] and bans.report_block_of(con, TG).reason == "спам"
    assert "Открыть обращения" in admin.client.get(f"/admin/users/{uid}").text
    r = admin.client.post(f"/admin/users/{uid}/runblock", data={"csrf": admin.token()}, follow_redirects=False)
    assert "m=report_unblocked" in r.headers["location"] and bans.report_block_of(con, TG) is None


def test_web_report_block_needs_telegram(admin, con):
    uid = add_user(con, "nogram")
    r = admin.client.post(f"/admin/users/{uid}/rblock", data={"csrf": admin.token()}, follow_redirects=False)
    assert "e=no_tg" in r.headers["location"]
