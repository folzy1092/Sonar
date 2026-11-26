"""Выпуск сборок из бота и экран «Версии» из выпущенных сборок (BOT.md §2.12е)."""
import asyncio
from types import SimpleNamespace

import pytest

from sonar import builds
from sonar.bot import publishing as P
from sonar.bot import screens as S
from sonar.bot.handlers import versions_screen
from sonar.builds import BuildError
from sonar.config import Settings
from test_builds import EXE, FakeGitHub, ios_release, win_release

OWNER, STRANGER = 100, 200


class Shower:
    def __init__(self):
        self.shown = []

    async def edit(self, msg, screen):
        self.shown.append(screen)
        return msg


@pytest.fixture
def ctx(con, tmp_path):
    gh = FakeGitHub([win_release("windows-v0.3.0"), win_release("windows-v0.2.9"), ios_release("ios-build-776", "0.3.0")])
    gh.by_tag["windows-v0.3.0"]["body"] = "- Блокировки\n- Обновления с сайта"
    return SimpleNamespace(settings=Settings(owner_tg_id=OWNER, data_dir=tmp_path), shower=Shower(), github=gh,
                           accounts=SimpleNamespace(con=con), is_owner=lambda uid: uid == OWNER)


def query(data, uid=OWNER):
    answers = []

    async def answer(text=None, **kw):
        answers.append(text)
    return SimpleNamespace(data=data, from_user=SimpleNamespace(id=uid), answer=answer, answers=answers,
                           message=SimpleNamespace(chat=SimpleNamespace(id=uid), message_id=1))


def press(ctx, data, uid=OWNER):
    q = query(data, uid)
    asyncio.run(P.bld_button(q, ctx))
    return q


def buttons(screen):
    return [b.cb for row in screen.kb for b in row]


def test_list_shows_latest_builds_and_what_is_already_out(ctx, con, tmp_path):
    press(ctx, "bld:list")
    screen = ctx.shower.shown[-1]
    assert "windows-v0.3.0" in screen.html and "ios-build-776" in screen.html and "не выпущена" in screen.html
    assert "bld:pub:windows-v0.3.0" in buttons(screen) and "bld:pub:ios-build-776" in buttons(screen)
    asyncio.run(builds.publish(con, tmp_path, ctx.github, "windows-v0.3.0", "release", {"ru": "а", "en": "b"}, "x"))
    press(ctx, "bld:list")
    again = ctx.shower.shown[-1]
    assert "на сайте" in again.html and "bld:pub:windows-v0.3.0" not in buttons(again)      # выпущенную второй раз не предлагаем
    assert "bld:pub:windows-v0.2.9" in buttons(again)


def test_publish_makes_a_release_with_notes_and_writes_the_journal(ctx, con, tmp_path):
    press(ctx, "bld:pub:windows-v0.3.0")
    shown = ctx.shower.shown
    assert "Скачиваю" in shown[-2].html and "Выпущено" in shown[-1].html and "0.3.0" in shown[-1].html
    b = builds.current(con, "windows", "release")
    assert (b.tag, b.version, b.channel) == ("windows-v0.3.0", "0.3.0", "release")
    assert b.notes_for("ru") == "- Блокировки\n- Обновления с сайта" == b.notes_for("en")
    assert builds.file_path(tmp_path, b).read_bytes() == EXE
    row = con.execute("SELECT admin, action, target, detail FROM admin_audit WHERE action = 'publish_build'").fetchone()
    assert (row["admin"], row["target"]) == (f"telegram:{OWNER}", "windows-v0.3.0") and '"via": "bot"' in row["detail"]


def test_publish_ios_build(ctx, con):
    press(ctx, "bld:pub:ios-build-776")
    b = builds.current(con, "ios", "release")
    assert (b.build, b.version) == (776, "0.3.0")


def test_missing_body_still_gets_a_description(ctx, con):
    ctx.github.by_tag["windows-v0.2.9"].pop("body", None)
    press(ctx, "bld:pub:windows-v0.2.9")
    assert builds.current(con, "windows", "release").notes_for("ru") == "Сборка windows-v0.2.9"


def test_only_the_owner_can_publish(ctx, con):
    q = press(ctx, "bld:pub:windows-v0.3.0", STRANGER)
    assert q.answers == ["Только для владельца"] and ctx.shower.shown == [] and builds.current(con, "windows", "release") is None


def test_junk_tags_are_ignored(ctx, con):
    for bad in ("bld:pub:../../etc", "bld:pub:windows-v1;rm", "bld:pub:", "bld:what"):
        press(ctx, bad)
    assert builds.listing(con) == []


def test_github_failure_is_explained_not_swallowed(ctx, con):
    async def broken(tag):
        raise BuildError("github")
    ctx.github.release = broken
    press(ctx, "bld:pub:windows-v0.3.0")
    assert "Не выпустилось" in ctx.shower.shown[-1].html and "GitHub" in ctx.shower.shown[-1].html
    assert builds.listing(con) == []


def test_no_github_client_says_so(ctx):
    ctx.github = None
    press(ctx, "bld:list")
    assert "недоступен" in ctx.shower.shown[-1].html


def test_versions_screen_reflects_published_builds(ctx, con, tmp_path):
    user = SimpleNamespace()
    before = versions_screen(ctx, user, OWNER)
    assert "Windows: ещё не выпущено" in before.html and "iOS: ещё не выпущено" in before.html and "—" not in before.html
    assert "bld:list" in buttons(before)                                     # владельцу — кнопка выпуска
    press(ctx, "bld:pub:windows-v0.3.0")
    press(ctx, "bld:pub:ios-build-776")
    after = versions_screen(ctx, user, STRANGER)
    assert "Windows: <b>0.3.0</b>" in after.html and "iOS: <b>0.3.0</b> (776)" in after.html
    assert "Блокировки" in after.html and "bld:list" not in buttons(after)    # чужому кнопки выпуска нет, заметки видны
    s = ctx.settings
    assert [b.url for row in after.kb for b in row if b.url] == [s.download_url, s.download_url_ios]


def test_callbacks_fit_telegram_limit():
    rows = [{"tag": "windows-v0.3.12345", "platform": "windows", "version": "x", "state": "new"},
            {"tag": "ios-build-123456789", "platform": "ios", "version": "y", "state": "new"}]
    assert all(len((b.cb or "").encode()) <= 64 for row in S.builds_list(rows).kb for b in row)
