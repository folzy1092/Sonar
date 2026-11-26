"""Обновление сервера по частям: `deploy/sync.py` (проверка, пропуск ненужных скачиваний), `sonar/updater.py`
(перезапуск через sync.py с тем же PID), `/update` в боте, страница «Сервер» в админке, сайт на лету."""
import asyncio
import importlib.util
import json
import os
import re
import shutil
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from sonar import updater as U
from sonar.admin.auth import AdminAuth
from sonar.bot import handlers as H
from sonar.config import Settings
from sonar.web import create_app

SYNC_FILE = Path(__file__).resolve().parent.parent / "deploy" / "sync.py"
OLD, NEW = "a" * 40, "b" * 40


def load_sync():
    spec = importlib.util.spec_from_file_location("sync_under_test", SYNC_FILE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def sync(tmp_path, monkeypatch):
    module = load_sync()
    monkeypatch.setattr(module, "HOME", tmp_path)
    monkeypatch.setattr(module, "APP", tmp_path / "app")
    monkeypatch.setattr(module, "SITE", tmp_path / "site")
    (tmp_path / "app" / "sonar").mkdir(parents=True)
    (tmp_path / "app" / ".sha").write_text(OLD)
    return module


def compare(files, status="ahead"):
    return {"status": status, "files": [{"filename": f} if isinstance(f, str) else f for f in files],
            "base_commit": {"commit": {"committer": {"date": "2026-11-20T10:00:00Z"}}}}


def commit(sha, message):
    return {"sha": sha, "commit": {"message": message}}


def fake_api(monkeypatch, sync, compare_data=None, commits=None, fail=False):
    def api_json(path):
        if fail:
            raise RuntimeError("GitHub ответил 500")
        return compare_data if path.startswith("compare/") else (commits or [])
    monkeypatch.setattr(sync, "api_json", api_json)


# ---- sync.py: что поменялось в server/ ----

def test_server_diff_changed_lists_only_server_commits(sync, monkeypatch):
    fake_api(monkeypatch, sync, compare(["server/sonar/web.py", "windows/src/App.svelte"]),
             [commit(NEW, "бот: /update"), commit(OLD, "старый, уже стоит")])
    diff = sync.server_diff(OLD, NEW)
    assert diff == {"known": True, "changed": True, "deps": False, "commits": [f"{NEW[:7]} бот: /update"]}


def test_server_diff_other_folders_do_not_count(sync, monkeypatch):
    fake_api(monkeypatch, sync, compare(["windows/a.rs", "ios/b.swift", "docs/c.md", "site/d.astro"]))
    diff = sync.server_diff(OLD, NEW)
    assert diff["known"] and not diff["changed"] and diff["commits"] == []


def test_server_diff_move_out_of_server_is_a_change(sync, monkeypatch):
    fake_api(monkeypatch, sync, compare([{"filename": "tools/x.py", "previous_filename": "server/tools/x.py"}]))
    assert sync.server_diff(OLD, NEW)["changed"]


def test_server_diff_flags_requirements(sync, monkeypatch):
    fake_api(monkeypatch, sync, compare(["server/requirements-run.txt"]))
    assert sync.server_diff(OLD, NEW)["deps"]


@pytest.mark.parametrize("old,new,kw", [
    ("", NEW, {}), (OLD, "не хэш", {}), (OLD, NEW, {"fail": True}),
    (OLD, NEW, {"compare_data": compare(["docs/a.md"], status="diverged")}),
    (OLD, NEW, {"compare_data": compare(["docs/a.md"] * 300)}),
])
def test_server_diff_unknown_means_changed(sync, monkeypatch, old, new, kw):
    fake_api(monkeypatch, sync, **({"compare_data": compare([])} | kw))
    diff = sync.server_diff(old, new)
    assert diff["known"] is False and diff["changed"] is True


# ---- sync.py: не качаем репо ради чужих коммитов ----

def test_update_code_skips_download_when_server_untouched(sync, monkeypatch):
    monkeypatch.setattr(sync, "remote_sha", lambda: NEW)
    monkeypatch.setattr(sync, "server_diff", lambda *_: {"known": True, "changed": False, "deps": False, "commits": []})
    monkeypatch.setattr(sync, "http_get", lambda *a, **k: pytest.fail("архив не должен качаться"))
    sync.update_code()
    assert (sync.APP / ".sha").read_text() == NEW


def test_update_code_downloads_when_server_changed(sync, monkeypatch):
    got = []
    monkeypatch.setattr(sync, "remote_sha", lambda: NEW)
    monkeypatch.setattr(sync, "server_diff", lambda *_: {"known": True, "changed": True, "deps": False, "commits": []})
    monkeypatch.setattr(sync, "http_get", lambda url, **k: b"archive")
    monkeypatch.setattr(sync, "install_app", lambda sha, data: got.append((sha, data)))
    sync.update_code()
    assert got == [(NEW, b"archive")]
    assert (sync.APP / ".sha").read_text() == OLD   # пишет install_app, а не мы


def test_update_code_first_install_always_downloads(sync, monkeypatch):
    shutil.rmtree(sync.APP)
    got = []
    monkeypatch.setattr(sync, "remote_sha", lambda: NEW)
    monkeypatch.setattr(sync, "server_diff", lambda *_: pytest.fail("сравнивать не с чем"))
    monkeypatch.setattr(sync, "http_get", lambda url, **k: b"archive")
    monkeypatch.setattr(sync, "install_app", lambda sha, data: got.append(sha))
    sync.update_code()
    assert got == [NEW]


def test_take_skip_reads_env_without_erasing_it(sync, monkeypatch):
    monkeypatch.setenv(sync.SKIP_ENV, "code, site")
    assert sync.take_skip() == {"code", "site"}
    assert sync.take_skip() == {"code", "site"}   # self_update перезапускает sync.py с тем же окружением
    monkeypatch.delenv(sync.SKIP_ENV)
    assert sync.take_skip() == set()


def test_status_collects_errors_per_part(sync, monkeypatch):
    monkeypatch.setattr(sync, "check_code", lambda: {"have": OLD})
    monkeypatch.setattr(sync, "check_site", lambda: (_ for _ in ()).throw(RuntimeError("GitHub ответил 403")))
    st = sync.status()
    assert st["code"] == {"have": OLD} and st["site"] is None and st["errors"] == {"site": "GitHub ответил 403"}


@pytest.mark.parametrize("remote,have,expect", [
    (("", ""), "", "none"), (("v1", "u"), "v1", "same"), (("v2", "u"), "v1", "updated")])
def test_update_site_states(sync, monkeypatch, remote, have, expect):
    installed = []
    monkeypatch.setattr(sync, "site_remote", lambda: remote)
    monkeypatch.setattr(sync, "site_have", lambda: have)
    monkeypatch.setattr(sync, "download", lambda url: b"x")
    monkeypatch.setattr(sync, "install_site", lambda version, data: installed.append(version))
    assert sync.update_site() == expect
    assert installed == (["v2"] if expect == "updated" else [])


def test_update_site_failure_keeps_old(sync, monkeypatch):
    monkeypatch.setattr(sync, "site_remote", lambda: (_ for _ in ()).throw(RuntimeError("нет сети")))
    assert sync.update_site() == "failed"


# ---- Updater ----

class FakeDispatcher:
    def __init__(self):
        self.stopped = 0

    async def stop_polling(self):
        self.stopped += 1


@pytest.fixture
def home(tmp_path, monkeypatch):
    """Как на хостинге: в корне лежит sync.py, SONAR_HOME указывает на корень."""
    root = tmp_path / "home"
    (root / "app" / "sonar").mkdir(parents=True)
    (root / "app" / ".sha").write_text(OLD)
    shutil.copyfile(SYNC_FILE, root / "sync.py")
    monkeypatch.setenv("SONAR_HOME", str(root))
    monkeypatch.setattr(U, "STOP_DELAY_S", 0)
    return root


def test_unavailable_without_sync_py(tmp_path, monkeypatch):
    monkeypatch.delenv("SONAR_HOME", raising=False)
    upd = U.Updater(tmp_path, FakeDispatcher())
    assert not upd.available() and upd.current() == {"sha": "", "site": ""}

    async def go():
        assert upd.request_restart("restart", source="admin") is False
    asyncio.run(go())


def test_current_reads_disk_without_network(home, tmp_path):
    assert U.Updater(tmp_path).current()["sha"] == OLD


def test_restart_stops_polling_then_execs_sync_with_skip(home, tmp_path, monkeypatch):
    calls = []
    monkeypatch.setattr(os, "execv", lambda exe, argv: calls.append((exe, argv)))
    monkeypatch.setenv("SONAR_SYNC_REEXEC", "1")
    dp = FakeDispatcher()
    upd = U.Updater(tmp_path / "data", dp)
    upd._cache = (0.0, {"code": {"remote": NEW}})

    async def go():
        assert upd.request_restart("server", source="telegram", by="7", chat_id=5, message_id=9)
        assert not upd.request_restart("server", source="admin")      # второй раз — уже идёт
        await upd._task
    asyncio.run(go())
    assert dp.stopped == 1
    upd.finish()
    assert calls == [(U.sys.executable, [U.sys.executable, str(home / "sync.py")])]
    assert os.environ["SONAR_SYNC_SKIP"] == "site" and "SONAR_SYNC_REEXEC" not in os.environ
    plan = json.loads((tmp_path / "data" / U.STATE_FILE).read_text())
    assert plan["target"] == NEW and plan["old"] == OLD and plan["chat_id"] == 5 and plan["message_id"] == 9


@pytest.mark.parametrize("what,skip", [("server", "site"), ("all", ""), ("restart", "code,site")])
def test_skip_per_part(home, tmp_path, monkeypatch, what, skip):
    monkeypatch.setattr(os, "execv", lambda *_: None)
    upd = U.Updater(tmp_path, FakeDispatcher())

    async def go():
        assert upd.request_restart(what, source="admin", by="folzy")
        await upd._task
    asyncio.run(go())
    upd.finish()
    assert os.environ["SONAR_SYNC_SKIP"] == skip


def test_finish_does_nothing_when_nobody_asked(home, tmp_path, monkeypatch):
    monkeypatch.setattr(os, "execv", lambda *_: pytest.fail("обычная остановка не должна перезапускаться"))
    U.Updater(tmp_path, FakeDispatcher()).finish()


def test_stop_failure_cancels_restart(home, tmp_path, monkeypatch):
    class Stuck:
        async def stop_polling(self):
            raise RuntimeError("Polling is not started")
    monkeypatch.setattr(U, "STOP_TRIES", 2)
    monkeypatch.setattr(U, "STOP_RETRY_S", 0)
    upd = U.Updater(tmp_path, Stuck())

    async def go():
        upd.request_restart("restart", source="admin")
        await upd._task
    asyncio.run(go())
    assert upd.restarting is False        # процесс остаётся жить, а не зависает «в перезапуске»


def write_plan(data_dir, **kw):
    data_dir.mkdir(parents=True, exist_ok=True)
    plan = {"what": "server", "old": OLD, "target": NEW, "source": "telegram", "by": "7", "chat_id": 5,
            "message_id": 9, "at": 1.0} | kw
    (data_dir / U.STATE_FILE).write_text(json.dumps(plan))


@pytest.mark.parametrize("what,target,sha,ok", [
    ("server", NEW, NEW, True),            # поставилось
    ("server", NEW, OLD, False),           # скачать не вышло, стартовали старым кодом
    ("server", "", OLD, None),             # GitHub не ответил при нажатии — цели нет, честно «не знаю»
    ("restart", "", OLD, True),
])
def test_result_compares_commit_with_target(home, tmp_path, what, target, sha, ok):
    (home / "app" / ".sha").write_text(sha)
    write_plan(tmp_path, what=what, target=target)
    upd = U.Updater(tmp_path)
    result = upd.take_result()
    assert result["ok"] is ok and result["current"] == sha
    assert upd.take_result() is None                      # план отдаётся один раз
    assert upd.last_result()["ok"] is ok                  # а итог остаётся для админки


# ---- бот: /update ----

class FakeShower:
    def __init__(self):
        self.shown = []

    async def send(self, chat_id, screen, reply_to=None):
        self.shown.append(screen)
        return SimpleNamespace(chat=SimpleNamespace(id=chat_id), message_id=1)

    async def edit(self, msg, screen):
        self.shown.append(screen)
        return msg


class FakeUpdater:
    restarting = False

    def __init__(self, new_code=True, new_site=False, available=True):
        self._available, self.requests, self.site_calls = available, [], 0
        self.st = {"repo": "x/y", "branch": "main", "errors": {},
                   "code": {"have": OLD, "remote": NEW, "new": True, "known": True, "changed": new_code, "deps": False,
                            "commits": [f"{NEW[:7]} бот: /update"] if new_code else []},
                   "site": {"have": "v1", "remote": "v2" if new_site else "v1", "new": new_site}}

    def available(self):
        return self._available

    async def check(self, force=False):
        return self.st

    async def update_site(self):
        self.site_calls += 1
        return "updated"

    def request_restart(self, what, **kw):
        self.requests.append((what, kw))
        return True

    bot_restart = api_restart = False
    parts: list = []

    @property
    def busy(self):
        return self.restarting

    def restart_bot(self, notice=None):
        self.parts.append(("bot", notice))
        return True

    async def restart_api(self):
        self.parts.append(("api", None))
        return True


OWNER, STRANGER = 100, 200


def bot_ctx(updater):
    from sonar.db import connect
    return SimpleNamespace(settings=Settings(owner_tg_id=OWNER), shower=FakeShower(), updater=updater,
                           accounts=SimpleNamespace(con=connect(":memory:")), is_owner=lambda uid: uid == OWNER)


def message(uid):
    return SimpleNamespace(chat=SimpleNamespace(id=uid), from_user=SimpleNamespace(id=uid))


def query(data, uid):
    answers = []

    async def answer(text=None, **kw):
        answers.append(text)
    return SimpleNamespace(data=data, from_user=SimpleNamespace(id=uid), answers=answers, answer=answer,
                           message=SimpleNamespace(chat=SimpleNamespace(id=uid), message_id=42))


def buttons(screen):
    return [b.cb for row in screen.kb for b in row]


def test_update_command_is_owner_only_and_silent_for_others():
    ctx = bot_ctx(FakeUpdater())
    asyncio.run(H.cmd_update(message(STRANGER), ctx))
    assert ctx.shower.shown == []
    asyncio.run(H.cmd_update(message(OWNER), ctx))
    menu = ctx.shower.shown[-1]
    assert "Сервер" in menu.html and "бот: /update" in menu.html
    assert buttons(menu) == ["upd:server", "upd:chk", "upd:rst", "adm:menu"]     # сайт актуален — кнопки нет


def test_menu_offers_all_when_both_new():
    ctx = bot_ctx(FakeUpdater(new_site=True))
    asyncio.run(H.cmd_update(message(OWNER), ctx))
    assert buttons(ctx.shower.shown[-1]) == ["upd:all", "upd:server", "upd:site", "upd:chk", "upd:rst", "adm:menu"]


def test_nothing_new_offers_only_check_and_restart():
    ctx = bot_ctx(FakeUpdater(new_code=False))
    asyncio.run(H.cmd_update(message(OWNER), ctx))
    assert "актуален" in ctx.shower.shown[-1].html
    assert buttons(ctx.shower.shown[-1]) == ["upd:chk", "upd:rst", "adm:menu"]


def test_not_on_hosting_says_so():
    ctx = bot_ctx(FakeUpdater(available=False))
    asyncio.run(H.cmd_update(message(OWNER), ctx))
    assert "sync.py" in ctx.shower.shown[-1].html


def test_stranger_cannot_press_update_buttons():
    upd = FakeUpdater()
    ctx = bot_ctx(upd)
    q = query("upd:server", STRANGER)
    asyncio.run(H.update_button(q, ctx))
    assert upd.requests == [] and q.answers == ["Только для владельца"]


def test_server_button_requests_restart_remembering_the_message():
    upd = FakeUpdater()
    ctx = bot_ctx(upd)
    asyncio.run(H.update_button(query("upd:server", OWNER), ctx))
    what, kw = upd.requests[0]
    assert what == "server" and kw["source"] == "telegram" and kw["chat_id"] == OWNER and kw["message_id"] == 42
    assert "Обновляю сервер" in ctx.shower.shown[-1].html


def test_site_button_updates_in_place_without_restart():
    upd = FakeUpdater(new_site=True)
    ctx = bot_ctx(upd)
    asyncio.run(H.update_button(query("upd:site", OWNER), ctx))
    assert upd.site_calls == 1 and upd.requests == []
    assert "Сайт обновлён" in ctx.shower.shown[-1].html


def test_bare_restart_asks_for_confirmation_first():
    upd = FakeUpdater()
    ctx = bot_ctx(upd)
    asyncio.run(H.update_button(query("upd:rst", OWNER), ctx))
    assert buttons(ctx.shower.shown[-1]) == ["upd:rst_bot", "upd:rst_api", "upd:rst_all", "upd:menu"]
    asyncio.run(H.update_button(query("upd:rst_all", OWNER), ctx))
    assert upd.requests == [] and "upd:rst_yes" in buttons(ctx.shower.shown[-1])
    asyncio.run(H.update_button(query("upd:rst_yes", OWNER), ctx))
    assert upd.requests[0][0] == "restart"


def test_restart_one_part_from_the_bot():
    upd = FakeUpdater()
    upd.parts = []
    ctx = bot_ctx(upd)
    asyncio.run(H.update_button(query("upd:rst_bot", OWNER), ctx))
    assert [p for p, _ in upd.parts] == ["bot"] and upd.parts[0][1]["message_id"] == 42
    assert upd.requests == [] and "Перезапускаю бота" in ctx.shower.shown[-1].html   # итог допишет main() после запуска опроса
    asyncio.run(H.update_button(query("upd:rst_api", OWNER), ctx))
    assert [p for p, _ in upd.parts] == ["bot", "api"]
    assert "API перезапущен" in ctx.shower.shown[-1].html
    audit = [r["action"] for r in ctx.accounts.con.execute("SELECT action FROM admin_audit ORDER BY id")]
    assert audit == ["restart_bot", "restart_api"]


def test_updater_restarts_bot_polling_only(home):
    async def run():
        dp = FakeDispatcher()
        upd = U.Updater(home, dp)
        assert upd.restart_bot({"chat_id": 1})
        assert not upd.restart_bot() and upd.busy       # второй перезапуск не накладывается
        await upd._task
        assert dp.stopped == 1 and upd.bot_restart and not upd.restarting   # флаг снимает main() после запуска опроса
    asyncio.run(run())


def test_restart_api_waits_for_the_new_server():
    async def run():
        upd = U.Updater(Path("."), FakeDispatcher())
        server = SimpleNamespace(started=True, should_exit=False)
        upd.api = server

        async def serve_again():                         # как цикл в `serve_web`: увидел выход и поднял новый сервер
            while not server.should_exit:
                await asyncio.sleep(0.01)
            await asyncio.sleep(0.05)
            upd.api_restart = False
        task = asyncio.create_task(serve_again())
        assert await upd.restart_api() is True and server.should_exit
        await task
        upd.api = SimpleNamespace(started=False, should_exit=False)
        assert await upd.restart_api() is False          # ещё не поднялся — перезапускать нечего
    asyncio.run(run())


def test_serve_web_comes_back_after_api_restart(tmp_path):
    """Настоящий uvicorn: после `restart_api` порт снова отвечает, и тем же приложением."""
    import socket
    import urllib.request

    from sonar import __main__ as M
    from sonar.config import Settings
    from sonar.db import connect

    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()

    async def run():
        upd = U.Updater(tmp_path, FakeDispatcher())
        ctx = SimpleNamespace(accounts=None, bot_username="x", updater=upd)
        task = asyncio.create_task(M.serve_web(connect(":memory:"), Settings(data_dir=tmp_path, port=port), None, ctx))
        for _ in range(100):
            if upd.api is not None and upd.api.started:
                break
            await asyncio.sleep(0.05)
        first = upd.api
        get = lambda: asyncio.to_thread(lambda: urllib.request.urlopen(f"http://127.0.0.1:{port}/api/health", timeout=5).status)  # noqa: E731
        assert await get() == 200
        assert await upd.restart_api() is True
        assert upd.api is not first and upd.api.started and await get() == 200
        upd.api.should_exit = True                       # обычная остановка — цикл заканчивается
        await asyncio.wait_for(task, 10)
    asyncio.run(run())


def test_buttons_ignored_while_restarting():
    upd = FakeUpdater()
    upd.restarting = True
    q = query("upd:all", OWNER)
    asyncio.run(H.update_button(q, bot_ctx(upd)))
    assert upd.requests == [] and q.answers == ["Перезапуск уже идёт"]


def test_announce_edits_the_original_message(home, tmp_path):
    (home / "app" / ".sha").write_text(NEW)
    write_plan(tmp_path)
    edited, events = [], []

    async def edit_message_text(text, **kw):
        edited.append((text, kw))

    async def event(icon, title, lines=(), **kw):
        events.append((title, lines))
    ctx = SimpleNamespace(updater=U.Updater(tmp_path), bot=SimpleNamespace(edit_message_text=edit_message_text),
                          settings=Settings(owner_tg_id=OWNER), logs=SimpleNamespace(event=event),
                          shower=FakeShower())
    asyncio.run(H.announce_update(ctx))
    text, kw = edited[0]
    assert "Сервер обновлён" in text and kw["chat_id"] == 5 and kw["message_id"] == 9
    assert events[0][0] == "Сервер обновлён" and "ок" in events[0][1][0]
    asyncio.run(H.announce_update(ctx))                    # второй старт без плана — тишина
    assert len(edited) == 1


def test_announce_wrong_version_is_not_hidden(home, tmp_path):
    write_plan(tmp_path)                                    # цель NEW, а стоит OLD
    edited = []

    async def edit_message_text(text, **kw):
        edited.append(text)

    async def event(*a, **k):
        pass
    ctx = SimpleNamespace(updater=U.Updater(tmp_path), bot=SimpleNamespace(edit_message_text=edit_message_text),
                          settings=Settings(), logs=SimpleNamespace(event=event), shower=FakeShower())
    asyncio.run(H.announce_update(ctx))
    assert "версия не та" in edited[0]


# ---- админка: «Сервер» ----

FACTORY = ""
NEW_PASSWORD = "river-sonar-42"


@pytest.fixture
def admin(con, tmp_path):
    global FACTORY
    FACTORY = AdminAuth(con).ensure_factory()
    upd = FakeUpdater()
    app = create_app(con, Settings(data_dir=tmp_path), updater=upd)
    client = TestClient(app, base_url="http://testserver")
    csrf = lambda html: re.search(r'name="csrf" value="([^"]+)"', html).group(1)  # noqa: E731
    page = client.get("/admin/login")
    client.post("/admin/login", data={"login": "folzy", "password": FACTORY, "csrf": csrf(page.text)})
    page = client.get("/admin/password")
    client.post("/admin/password", data={"csrf": csrf(page.text), "old": FACTORY, "new": NEW_PASSWORD,
                                         "again": NEW_PASSWORD})
    upd.current = lambda: {"sha": OLD, "site": "sha256:" + "c" * 64}
    upd.last_result = lambda: None
    return SimpleNamespace(client=client, upd=upd, csrf=lambda: csrf(client.get("/admin/server").text), con=con)


def test_server_page_requires_login(con, tmp_path):
    client = TestClient(create_app(con, Settings(data_dir=tmp_path)), base_url="http://testserver")
    r = client.get("/admin/server", follow_redirects=False)
    assert r.status_code == 303 and r.headers["location"].startswith("/admin/login")


def test_server_page_shows_parts_only_after_check(admin):
    r = admin.client.get("/admin/server")
    assert r.status_code == 200 and "не проверено" in r.text and OLD[:8] in r.text
    r = admin.client.get("/admin/server?check=1")
    assert NEW[:8] in r.text and "есть правки в server/" in r.text and "бот: /update" in r.text


def test_server_actions_need_csrf(admin):
    r = admin.client.post("/admin/server/restart", data={"csrf": "нет"}, follow_redirects=False)
    assert "e=csrf" in r.headers["location"] and admin.upd.requests == []


def test_admin_update_server_restarts_and_is_audited(admin):
    r = admin.client.post("/admin/server/server", data={"csrf": admin.csrf()}, follow_redirects=False)
    assert "m=restarting" in r.headers["location"]
    what, kw = admin.upd.requests[0]
    assert what == "server" and kw["source"] == "admin" and kw["by"] == "folzy"
    row = admin.con.execute("SELECT action, target FROM admin_audit WHERE action = 'update_server'").fetchone()
    assert row["target"] == "server"


def test_admin_update_site_does_not_restart(admin):
    r = admin.client.post("/admin/server/site", data={"csrf": admin.csrf()}, follow_redirects=False)
    assert "m=site_updated" in r.headers["location"]
    assert admin.upd.site_calls == 1 and admin.upd.requests == []


def test_admin_unknown_part_and_unavailable(admin):
    token = admin.csrf()
    r = admin.client.post("/admin/server/bot", data={"csrf": token}, follow_redirects=False)
    assert "e=bad_part" in r.headers["location"]
    admin.upd._available = False
    r = admin.client.post("/admin/server/restart", data={"csrf": token}, follow_redirects=False)
    assert "e=no_restart" in r.headers["location"] and admin.upd.requests == []
    assert "sync.py" in admin.client.get("/admin/server").text


# ---- сайт подменяется на лету ----

def test_site_appears_without_restart(con, tmp_path):
    site = tmp_path / "site"                               # папки нет, когда сервер стартует
    client = TestClient(create_app(con, Settings(data_dir=tmp_path), site=site), base_url="http://testserver")
    assert client.get("/").status_code == 404
    site.mkdir()
    (site / "index.html").write_text("<h1>v1</h1>")
    assert "v1" in client.get("/").text
    new = tmp_path / "site.new"                            # так делает sync.install_site: переименование папок
    new.mkdir()
    (new / "index.html").write_text("<h1>v2</h1>")
    site.rename(tmp_path / "site.old")
    new.rename(site)
    assert "v2" in client.get("/").text
