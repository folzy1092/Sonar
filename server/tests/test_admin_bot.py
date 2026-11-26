"""/admin в боте: только владелец, сброс забытого пароля админки (новый случайный, смена при входе, сессии закрыты)."""
import asyncio
from types import SimpleNamespace

import pytest

from sonar.admin.auth import FACTORY_LOGIN, AdminAuth, AuthError
from sonar.bot import handlers as H
from sonar.config import Settings

OWNER, STRANGER = 100, 200


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
def ctx(con, monkeypatch):
    scheduled = []
    monkeypatch.setattr(H.asyncio, "create_task", lambda coro: (scheduled.append(coro), coro.close())[0])
    deleted = []

    async def delete_message(chat_id, message_id):
        deleted.append((chat_id, message_id))
    return SimpleNamespace(settings=Settings(owner_tg_id=OWNER, public_url="https://try-sonar.ru"), shower=FakeShower(),
                           accounts=SimpleNamespace(con=con), is_owner=lambda uid: uid == OWNER,
                           bot=SimpleNamespace(delete_message=delete_message), scheduled=scheduled, deleted=deleted)


def message(uid):
    return SimpleNamespace(chat=SimpleNamespace(id=uid), from_user=SimpleNamespace(id=uid))


def query(data, uid):
    answers = []

    async def answer(text=None, **kw):
        answers.append(text)
    return SimpleNamespace(data=data, from_user=SimpleNamespace(id=uid), answers=answers, answer=answer,
                           message=SimpleNamespace(chat=SimpleNamespace(id=uid), message_id=42))


def buttons(screen):
    return [b.cb or b.url for row in screen.kb for b in row]


def test_reset_password_gives_new_random_one_and_forces_change(con):
    auth = AdminAuth(con)
    old = auth.ensure_factory()
    new = auth.reset_password()
    assert new != old and len(new) >= 20
    with pytest.raises(AuthError):
        asyncio.run(auth.login(FACTORY_LOGIN, old, "1.1.1.1"))
    _, session = asyncio.run(auth.login(FACTORY_LOGIN, new, "1.1.1.1"))
    assert session.admin.must_change is True            # сайт сразу просит придумать свой


def test_reset_closes_sessions_and_hides_the_hash(con):
    auth = AdminAuth(con)
    first = auth.ensure_factory()
    asyncio.run(auth.login(FACTORY_LOGIN, first, "1.1.1.1"))
    assert con.execute("SELECT COUNT(*) FROM admin_sessions").fetchone()[0] == 1
    new = auth.reset_password()
    assert con.execute("SELECT COUNT(*) FROM admin_sessions").fetchone()[0] == 0
    assert new not in con.execute("SELECT password_hash FROM admins").fetchone()[0]


def test_reset_without_any_admin_creates_the_factory_one(con):
    new = AdminAuth(con).reset_password()
    assert con.execute("SELECT login FROM admins").fetchone()[0] == FACTORY_LOGIN
    asyncio.run(AdminAuth(con).login(FACTORY_LOGIN, new, "1.1.1.1"))


def test_unknown_admin_login_is_an_error(con):
    with pytest.raises(AuthError):
        AdminAuth(con).reset_password("нет такого")


def test_admin_command_is_owner_only_and_silent_for_others(ctx):
    asyncio.run(H.cmd_admin(message(STRANGER), ctx))
    assert ctx.shower.shown == []
    asyncio.run(H.cmd_admin(message(OWNER), ctx))
    assert buttons(ctx.shower.shown[-1]) == ["https://try-sonar.ru/admin/", "mod:list", "adm:help", "bld:list", "adm:pw", "upd:chk", "status"]


def test_no_https_address_no_link_button(ctx):
    ctx.settings = Settings(owner_tg_id=OWNER, public_url="", site_url="")
    asyncio.run(H.cmd_admin(message(OWNER), ctx))
    assert buttons(ctx.shower.shown[-1])[0] == "mod:list"


def test_reset_needs_confirmation(ctx, con):
    old = AdminAuth(con).ensure_factory()
    asyncio.run(H.admin_button(query("adm:pw", OWNER), ctx))
    assert "adm:pw_yes" in buttons(ctx.shower.shown[-1])
    asyncio.run(H.admin_button(query("adm:menu", OWNER), ctx))
    asyncio.run(AdminAuth(con).login(FACTORY_LOGIN, old, "1.1.1.1"))     # пароль не менялся


def test_confirmed_reset_shows_password_audits_and_schedules_deletion(ctx, con):
    old = AdminAuth(con).ensure_factory()
    asyncio.run(H.admin_button(query("adm:pw_yes", OWNER), ctx))
    html = ctx.shower.shown[-1].html
    password = html.split("Пароль: <code>")[1].split("</code>")[0]
    assert "Логин: <code>folzy</code>" in html and "https://try-sonar.ru/admin/" in html and "2 мин" in html
    asyncio.run(AdminAuth(con).login(FACTORY_LOGIN, password, "1.1.1.1"))
    with pytest.raises(AuthError):
        asyncio.run(AdminAuth(con).login(FACTORY_LOGIN, old, "1.1.1.1"))
    row = con.execute("SELECT admin, action, target FROM admin_audit WHERE action = 'reset_admin_password'").fetchone()
    assert tuple(row) == (f"telegram:{OWNER}", "reset_admin_password", FACTORY_LOGIN)
    assert len(ctx.scheduled) == 1                                        # удаление сообщения с паролем


def test_stranger_cannot_reset(ctx, con):
    old = AdminAuth(con).ensure_factory()
    q = query("adm:pw_yes", STRANGER)
    asyncio.run(H.admin_button(q, ctx))
    assert q.answers == ["Только для владельца"] and ctx.shower.shown == []
    asyncio.run(AdminAuth(con).login(FACTORY_LOGIN, old, "1.1.1.1"))


def test_message_with_password_is_deleted_later(ctx):
    asyncio.run(H._delete_later(ctx, 100, 7, 0))
    assert ctx.deleted == [(100, 7)]
