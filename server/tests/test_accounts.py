import pytest

from sonar.accounts import AccountError, looks_like_token
from sonar.db import now_ms


def test_register_and_login(acc):
    u = acc.register("Folzy", "password1")
    assert u.login == "folzy" and u.username == "folzy" and u.number == 1 and len(u.referral_code) == 6
    assert acc.verify("folzy", "password1").id == u.id
    assert acc.verify("@FOLZY", "password1").id == u.id
    with pytest.raises(AccountError) as e:
        acc.verify("folzy", "nope")
    assert e.value.code == "bad_password"
    assert acc.register("second", "password2").number == 2


@pytest.mark.parametrize("login", ["ab", "Кот", "a b", "x" * 25])
def test_bad_logins(acc, login):
    with pytest.raises(AccountError) as e:
        acc.register(login, "password1")
    assert e.value.code == "login_format"


def test_taken_and_short_password(acc):
    acc.register("folzy", "password1")
    with pytest.raises(AccountError) as e:
        acc.register("FOLZY", "password1")
    assert e.value.code == "login_taken"
    with pytest.raises(AccountError) as e:
        acc.register("other", "short")
    assert e.value.code == "password_short"


def test_rate_limit(acc):
    acc.register("folzy", "password1")
    for _ in range(5):
        with pytest.raises(AccountError):
            acc.verify("folzy", "wrong", tg_id=1)
    with pytest.raises(AccountError) as e:
        acc.verify("folzy", "password1", tg_id=1)
    assert e.value.code == "too_many"


def test_telegram_link_moves_between_accounts(acc):
    a = acc.register("first", "password1")
    b = acc.register("second", "password1")
    acc.link_tg(a, 42, "me")
    acc.link_tg(b, 42, "me")
    assert acc.by_tg(42).id == b.id
    assert acc.by_id(a.id).tg_id is None
    acc.unlink_tg(acc.by_id(b.id))
    assert acc.by_tg(42) is None


def test_token_always_visible(acc):
    u = acc.register("folzy", "password1")
    assert acc.token(u) is None
    t1 = acc.new_token(u)
    assert t1.startswith("snr_") and acc.token(u) == t1 and acc.user_by_token(t1).id == u.id
    t2 = acc.new_token(u)
    assert t2 != t1 and acc.token(u) == t2 and acc.user_by_token(t1) is None
    acc.revoke_token(u)
    assert acc.token(u) is None


def test_referral(acc):
    a = acc.register("first", "password1")
    acc.register("second", "password1", referred_code=a.referral_code.lower())
    assert acc.referral_count(a) == 1


def test_stats(acc, con):
    u = acc.register("folzy", "password1")
    t = now_ms() - 3600_000
    con.executemany("INSERT INTO plays (user_id, ref, artist, played_at, listened_ms) VALUES (?,?,?,?,?)",
                    [(u.id, "sc:1", "Mareux", t, 180_000), (u.id, "sc:1", "Mareux", t + 1, 180_000),
                     (u.id, "ym:2", "Скриптонит", t + 2, 120_000)])
    st = acc.stats(u, 7)
    assert st["minutes"] == 8 and st["tracks"] == 3 and st["artists"][0] == "Mareux" and st["delta"] is None
    assert acc.totals(u, now_ms() - 7 * 86400_000) == (8, 3)


def test_token_detector():
    assert looks_like_token("y0_AgAAAAAxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
    assert looks_like_token("2-292929-123456789-AbCdEfGhIjKl")
    assert not looks_like_token("folzy")
    assert not looks_like_token("привет как дела")


def test_listeners_today_counts_accounts_once(acc, con):
    a, b, c = (acc.register(n, "password1") for n in ("folzy", "second", "third"))
    day = now_ms() - 3600_000
    con.executemany("INSERT INTO plays (user_id, ref, artist, played_at, listened_ms) VALUES (?,?,?,?,?)",
                    [(a.id, "sc:1", "A", day + 1, 1000), (a.id, "sc:2", "A", day + 2, 1000),
                     (b.id, "sc:1", "A", day - 86400_000, 1000)])  # b слушал вчера
    con.execute("INSERT INTO player_state (user_id, is_playing, heartbeat_at) VALUES (?, 1, ?)", (c.id, now_ms()))
    con.execute("INSERT INTO player_state (user_id, is_playing, heartbeat_at) VALUES (?, 1, ?)", (a.id, now_ms()))
    assert acc.listeners_today(day) == 2
