"""Бот: вход нового устройства и привязка Telegram по ссылкам из приложения (BOT.md §3, handlers `start_link`)."""
import asyncio
from types import SimpleNamespace

import pytest

from sonar import sessions
from sonar.bot import handlers as H

PHONE = {"id": "uuid-phone", "name": "iPhone 15 Pro", "platform": "ios", "os": "iOS 18.1", "app_version": "1.0", "build": 1}


class FakeShower:
    def __init__(self):
        self.shown = []

    async def send(self, chat_id, screen, reply_to=None):
        self.shown.append(screen)
        return SimpleNamespace(chat=SimpleNamespace(id=chat_id))

    async def edit(self, msg, screen):
        self.shown.append(screen)
        return msg


def tg(uid, username="mira_tg"):
    return SimpleNamespace(id=uid, username=username)


def message(user):
    return SimpleNamespace(chat=SimpleNamespace(id=user.id), from_user=user)


def query(data, user):
    async def answer(*_a, **_k):
        return None
    return SimpleNamespace(data=data, from_user=user, message=message(user), answer=answer)


@pytest.fixture
def ctx(acc):
    return SimpleNamespace(accounts=acc, shower=FakeShower())


@pytest.fixture
def run(monkeypatch):
    loop = asyncio.new_event_loop()
    # «Разрешить» через 3 с — фоновая задача; в тесте ждать её незачем.
    monkeypatch.setattr(H.asyncio, "create_task", lambda coro: coro.close())
    yield loop.run_until_complete
    loop.close()


def test_device_login_approved_by_linked_telegram(ctx, acc, con, run):
    user = run(acc.register("mira", "secret-pass"))
    acc.link_tg(user, 777, "mira_tg")
    code, _ = sessions.new_link(con, "device", PHONE)
    run(H.start_link(ctx, message(tg(777)), f"link_{code}"))
    assert "Авторизация в аккаунт" in ctx.shower.shown[-1].html
    run(H.link_button(query(f"lk:a:{code}", tg(777)), ctx))
    link = sessions.get_link(con, code)
    assert link.status == "approved" and link.user_id == user.id
    assert sessions.claim(con, link)  # новое устройство забирает сессию
    # второй раз — уже нечего разрешать
    run(H.link_button(query(f"lk:a:{code}", tg(777)), ctx))
    assert "истекла" in ctx.shower.shown[-1].html


def test_device_login_needs_linked_telegram(ctx, con, run):
    code, _ = sessions.new_link(con, "device", PHONE)
    run(H.start_link(ctx, message(tg(999)), f"link_{code}"))
    assert "не привязан" in ctx.shower.shown[-1].html
    run(H.link_button(query(f"lk:a:{code}", tg(999)), ctx))
    assert sessions.get_link(con, code).status == "pending"  # чужой Telegram ничего не разрешил


def test_codes_are_not_interchangeable(ctx, acc, con, run):
    user = run(acc.register("mira", "secret-pass"))
    acc.link_tg(user, 777, "mira_tg")
    tg_code, _ = sessions.new_link(con, "tg_link", {}, user.id)
    dev_code, _ = sessions.new_link(con, "device", PHONE)
    # код привязки не пускает как вход устройства и наоборот
    run(H.start_link(ctx, message(tg(777)), f"link_{tg_code}"))
    assert "истекла" in ctx.shower.shown[-1].html
    run(H.link_button(query(f"lk:a:{tg_code}", tg(777)), ctx))
    assert sessions.get_link(con, tg_code).status == "pending"
    run(H.link_button(query(f"lk:t:{dev_code}", tg(777)), ctx))
    assert sessions.get_link(con, dev_code).status == "pending"


def test_telegram_link_from_app(ctx, acc, con, run):
    user = run(acc.register("mira", "secret-pass"))
    code, _ = sessions.new_link(con, "tg_link", {}, user.id)
    run(H.start_link(ctx, message(tg(555, "new_tg")), f"tg_{code}"))
    assert "Привязать Telegram" in ctx.shower.shown[-1].html
    run(H.link_button(query(f"lk:t:{code}", tg(555, "new_tg")), ctx))
    assert acc.by_id(user.id).tg_id == 555
    assert sessions.get_link(con, code).status == "approved"


def test_reject(ctx, acc, con, run):
    code, _ = sessions.new_link(con, "device", PHONE)
    run(H.link_button(query(f"lk:r:{code}", tg(1)), ctx))
    assert sessions.get_link(con, code).status == "rejected"
