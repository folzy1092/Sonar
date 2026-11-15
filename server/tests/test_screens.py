import re

from sonar.accounts import User
from sonar.bot import screens as S
from sonar.bot.emoji import EMOJI
from sonar.config import Settings
from sonar.status import DOWN, OK, PARTIAL, Item

SET = Settings(lastfm_api_key="x")
USER = User("u_1", 104633, "folzy", "folzy", "Folzy", True, 1, "ZTRMC6", 1794700000000)
TAG = re.compile(r"<(/?)([a-z-]+)[^>]*>")
KEYS = ["main", "media", "proxy", "bot", "site", "storage", "soundcloud", "yandex", "lrclib", "genius", "lastfm", "telegram"]


def all_screens():
    st = {"minutes": 412, "tracks": 96, "delta": 12, "artists": ["A"], "top_tracks": ["A — B"], "day": 5, "hour": 23}
    empty = {**st, "tracks": 0}
    items = {k: Item(k, OK, 10) for k in KEYS}
    bad = {**items, "yandex": Item("yandex", PARTIAL, 2900), "main": Item("main", DOWN)}
    return [
        S.guest(), S.login_ask(), S.password_ask(), S.no_user(), S.quick("https://x/auth/1", "13:15"), S.quick_expired(),
        S.success_linked("folzy"), S.register_ask(), S.register_password("folzy"), S.register_again(),
        S.registered("folzy", SET), S.bye(), S.main(USER, SET),
        S.profile(USER, {"soundcloud": True, "yandex": False, "lastfm": False}, (412, 96), SET),
        S.integration(None, SET), S.integration("snr_abc", SET), S.ask("?", "a", "b"), S.referral(USER, 2, "SonarMusicApp"),
        S.versions(SET), S.logout_ask(), S.stats("week", st), S.stats("day", empty), S.services(), S.services("ym"),
        S.services("sc"), S.report_kind(), S.report_platform("bug"), S.report_platform("idea"), S.report_prompt("bug"),
        S.ticket_opened("053d4a74"), S.status(items, 3, 12, 99.98, owner=True), S.status(items, 3, 12, None, owner=False),
        S.status(bad, 0, 1, 50.0, owner=True),
    ]


def test_screens_render_and_tags_balance():
    for s in all_screens():
        stack = []
        for close, tag in TAG.findall(s.html):
            if close:
                assert stack and stack.pop() == tag, s.html
            else:
                stack.append(tag)
        assert not stack, s.html
        if s.banner:
            assert len(TAG.sub("", s.html)) <= 1024, s.banner  # подпись к фото
        s.markup()


def test_button_icons_known():
    for s in all_screens():
        for row in s.kb:
            for b in row:
                assert b.icon is None or b.icon in EMOJI, b.icon


def test_guest_has_no_report():
    assert not any("Баг" in b.text for row in S.guest().kb for b in row)


def test_android_not_selectable():
    android = [b for row in S.report_platform("bug").kb for b in row if "Android" in b.text][0]
    assert android.cb == "android"


def test_status_header():
    items = {k: Item(k, OK, 5) for k in ["main", "storage", "soundcloud", "yandex"]}
    assert "штатно" in S.status(items, 0, 0, None, owner=False).html
    items["yandex"] = Item("yandex", PARTIAL, 2900)
    assert "перебоями" in S.status(items, 0, 0, None, owner=False).html
    items["main"] = Item("main", DOWN)
    assert "Сбой: Основной" in S.status(items, 0, 0, None, owner=False).html
