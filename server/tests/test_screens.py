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


def test_unset_items_do_not_spoil_header():
    items = {k: Item(k, OK, 5) for k in KEYS}
    items["site"] = Item("site", DOWN)
    items["proxy"] = Item("proxy", DOWN)
    html = S.status(items, 0, 0, None, owner=True, unset={"site", "proxy"}).html
    assert "штатно" in html and "не настроен" in html


def test_status_public_numbers_and_platforms():
    items = {k: Item(k, OK, 42) for k in KEYS + ["youtube", "vk", "spotify", "apple"]}
    html = S.status(items, 1, 5, 99.9, owner=False, day=3).html
    assert "Слушателей за 24 часа: <b>3</b>" in html
    assert "Основной: " in html and "42 мс" in html.split("Хранилище")[0]  # мс «Основного» — всем
    for name in ("YouTube Music", "VK Музыка", "Spotify", "Apple Music"):
        assert name in html
    items["spotify"] = Item("spotify", DOWN)
    assert "штатно" in S.status(items, 0, 0, None, owner=False).html  # будущие платформы шапку не портят
    assert "Слушателей за 24 часа" not in S.status(items, 0, 0, None, owner=False).html


def test_status_page_button_in_own_row():
    kb = S.status({}, 0, 0, None, owner=False).kb
    assert [len(r) for r in kb] == [1, 1] and kb[1][0].url


def test_pack_badge_fits_100_and_detects_color():
    import io
    from PIL import Image
    from sonar.bot.packimg import to_badge
    def png(color, size=(300, 120)):
        b = io.BytesIO(); Image.new("RGBA", size, color).save(b, "PNG"); return b.getvalue()
    out, mono = to_badge(png((255, 255, 255, 255)))
    assert Image.open(io.BytesIO(out)).size == (100, 100) and mono
    assert to_badge(png((230, 40, 40, 255)))[1] is False


def test_pack_placeholder():
    from sonar.bot.handlers import _placeholder
    assert _placeholder("🔄 обновить") == "🔄" and _placeholder("просто текст") == "⭐" and _placeholder(None) == "⭐"


def test_status_zero_ms_is_valid_html():
    html = S.status({"main": Item("main", OK, 0)}, 0, 0, None, owner=False).html
    assert "&lt; 1 мс" in html and "< 1" not in html
