from asyncio import run

import pytest

from sonar.bot import screens as S
from sonar.config import Settings
from sonar.releases import ReleaseError, Releases, check_url, parse_targets, version_from_url, visible_to

WIN = "https://github.com/folzy1092/Sonar/releases/download/windows-v0.1.42/Sonar-setup.exe"
IPA = "https://github.com/folzy1092/Sonar/releases/download/ios-build-229/Sonar.ipa"


@pytest.fixture
def rels(con):
    return Releases(con)


@pytest.fixture
def users(acc):
    a = run(acc.register("folzy", "password1", tg_id=111111))
    b = run(acc.register("tester", "password1", tg_id=222222))
    c = run(acc.register("noTg", "password1"))
    return a, b, c


def test_parse_targets_normalizes_every_kind():
    assert parse_targets("@Folzy, tester #104634\n123456789 @folzy") == ["u:folzy", "l:tester", "n:104634", "tg:123456789"]
    assert parse_targets("  ") == []


def test_url_and_version_from_url():
    assert version_from_url(WIN) == "windows-v0.1.42"
    assert version_from_url("https://github.com/folzy1092/Sonar/releases/download/ios-latest/Sonar.ipa") is None
    assert version_from_url("https://github.com/folzy1092/Sonar/releases/tag/ios-build-229") == "ios-build-229"
    with pytest.raises(ReleaseError):
        check_url("http://example.com/x.exe")
    with pytest.raises(ReleaseError):
        check_url("не ссылка")


def test_newest_visible_release_wins(rels, users):
    folzy, tester, _ = users
    old = rels.add("ios", "", IPA, audience="all")
    beta = rels.add("ios", "build 230", IPA.replace("229", "230"), audience="only", targets=["u:tester"])
    assert old.version == "ios-build-229"
    assert rels.current("ios", tester).id == beta.id          # тестер видит бету
    assert rels.current("ios", folzy).id == old.id            # остальные — прошлую проверенную
    assert rels.current("ios", None).id == old.id
    assert rels.current("windows", folzy) is None             # своей версии нет — общая ссылка


def test_except_hides_from_listed(rels, users):
    folzy, tester, _ = users
    r = rels.add("windows", "0.1.42", WIN, audience="except", targets=[f"tg:{tester.tg_id}"])
    assert visible_to(r, folzy) and not visible_to(r, tester)


def test_deactivate_and_recipients(rels, users):
    folzy, tester, no_tg = users
    r = rels.add("windows", "0.1.42", WIN, audience="only", targets=[f"n:{folzy.number}", "l:notg"])
    assert [u.login for u in rels.recipients(r)] == ["folzy"]   # без Telegram алерт не получить
    r = rels.set_active(r.id, False)
    assert rels.current("windows", folzy) is None and rels.recipients(r) == []


def test_list_audience_needs_targets(rels):
    with pytest.raises(ReleaseError):
        rels.add("ios", "x", IPA, audience="only", targets=[])


def test_screens_render(rels, users):
    folzy, _, _ = users
    s = Settings()
    r = rels.add("ios", "build 229", IPA, notes="Текст песни", audience="only", targets=["u:folzy", "#1"])
    for screen in [S.versions(s), S.versions(s, None, owner=True), S.rel_admin({"windows": None, "ios": r}, s),
                   S.rel_ask_url("ios"), S.rel_ask_version("ios", "ios-build-229"), S.rel_ask_notes(), S.rel_ask_audience(),
                   S.rel_ask_targets("only"), S.rel_list("ios", [r]), S.rel_item(r, 1), S.rel_alert(r),
                   S.rel_confirm({"platform": "ios", "version": "b", "url": IPA, "audience": "except", "targets": ["u:x"]})]:
        assert screen.html and all(len(b.cb or "") <= 64 for row in screen.kb for b in row)
    kb = S.versions(s).kb[0]
    assert kb[1].url == s.download_url_ios and kb[0].url == s.download_url   # кнопки — файлы с сайта, не закреплённая ссылка


def test_post_draft_rows_and_presets():
    from sonar.posts import Draft
    d = Draft(chat_id=1, message_id=5)
    d.add("Windows", WIN)
    d.add("iPhone", IPA)
    d.add("как запустить…", "https://t.me/SonarUpdates/1")
    assert [len(r) for r in d.rows()] == [2, 1]
    d.cycle_row()
    assert [len(r) for r in d.rows()] == [3]
    with pytest.raises(ReleaseError):
        d.add("x", "ftp://bad")
    d.pop()
    assert Draft.of(d.dump()) == d
    s = Settings()
    for screen in [S.post_ask(s.channel), S.post_builder(d, s.channel), S.post_builder(Draft(), s.channel),
                   S.post_ask_button_text(), S.post_ask_button_url("Windows"), S.post_confirm(s.channel, 2)]:
        assert screen.html and all(len(b.cb or "") <= 64 for row in screen.kb for b in row)
