from asyncio import run

import pytest

from sonar.accounts import AccountError, looks_like_token
from sonar.db import now_ms


def test_register_and_login(acc):
    u = run(acc.register("Folzy", "password1"))
    assert u.login == "folzy" and u.username == "folzy" and u.number == 1 and len(u.referral_code) == 6
    assert run(acc.verify("folzy", "password1")).id == u.id
    assert run(acc.verify("@FOLZY", "password1")).id == u.id
    with pytest.raises(AccountError) as e:
        run(acc.verify("folzy", "nope"))
    assert e.value.code == "bad_password"
    assert run(acc.register("second", "password2")).number == 2


@pytest.mark.parametrize("login", ["ab", "Кот", "a b", "x" * 25])
def test_bad_logins(acc, login):
    with pytest.raises(AccountError) as e:
        run(acc.register(login, "password1"))
    assert e.value.code == "login_format"


def test_taken_and_short_password(acc):
    run(acc.register("folzy", "password1"))
    with pytest.raises(AccountError) as e:
        run(acc.register("FOLZY", "password1"))
    assert e.value.code == "login_taken"
    with pytest.raises(AccountError) as e:
        run(acc.register("other", "short"))
    assert e.value.code == "password_short"


def test_rate_limit(acc):
    run(acc.register("folzy", "password1"))
    for _ in range(5):
        with pytest.raises(AccountError):
            run(acc.verify("folzy", "wrong", tg_id=1))
    with pytest.raises(AccountError) as e:
        run(acc.verify("folzy", "password1", tg_id=1))
    assert e.value.code == "too_many"


def test_telegram_link_moves_between_accounts(acc):
    a = run(acc.register("first", "password1"))
    b = run(acc.register("second", "password1"))
    acc.link_tg(a, 42, "me")
    acc.link_tg(b, 42, "me")
    assert acc.by_tg(42).id == b.id
    assert acc.by_id(a.id).tg_id is None
    acc.unlink_tg(acc.by_id(b.id))
    assert acc.by_tg(42) is None


def test_token_always_visible(acc):
    u = run(acc.register("folzy", "password1"))
    assert acc.token(u) is None
    t1 = acc.new_token(u)
    assert t1.startswith("snr_") and acc.token(u) == t1 and acc.user_by_token(t1).id == u.id
    t2 = acc.new_token(u)
    assert t2 != t1 and acc.token(u) == t2 and acc.user_by_token(t1) is None
    acc.revoke_token(u)
    assert acc.token(u) is None


def test_referral(acc):
    a = run(acc.register("first", "password1"))
    run(acc.register("second", "password1", referred_code=a.referral_code.lower()))
    assert acc.referral_count(a) == 1


def test_stats(acc, con):
    u = run(acc.register("folzy", "password1"))
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


def test_listeners_24h_counts_accounts_once(acc, con):
    a, b, c = (run(acc.register(n, "password1")) for n in ("folzy", "second", "third"))
    day = now_ms() - 3600_000
    con.executemany("INSERT INTO plays (user_id, ref, artist, played_at, listened_ms) VALUES (?,?,?,?,?)",
                    [(a.id, "sc:1", "A", day + 1, 1000), (a.id, "sc:2", "A", day + 2, 1000),
                     (b.id, "sc:1", "A", day - 86400_000, 1000)])  # b слушал больше суток назад
    con.execute("INSERT INTO player_state (user_id, is_playing, heartbeat_at) VALUES (?, 1, ?)", (c.id, now_ms()))
    con.execute("INSERT INTO player_state (user_id, is_playing, heartbeat_at) VALUES (?, 1, ?)", (a.id, now_ms()))
    assert acc.listeners_24h() == 2


# ---- argon2 по минимуму OWASP: быстрее на 25 % vCPU, старые хэши переписываются при входе ----

def test_new_hashes_use_the_light_parameters(acc):
    from argon2 import PasswordHasher
    from argon2.low_level import Type
    user = run(acc.register("mira", "secret-pass"))
    stored = acc.con.execute("SELECT password_hash FROM users WHERE id = ?", (user.id,)).fetchone()[0]
    assert stored.startswith("$argon2id$") and "m=19456,t=2,p=1" in stored
    assert not PasswordHasher(time_cost=2, memory_cost=19456, parallelism=1, type=Type.ID).check_needs_rehash(stored)


def test_old_heavy_hash_still_logs_in_and_is_rewritten(acc):
    from argon2 import PasswordHasher
    user = run(acc.register("mira", "secret-pass"))
    heavy = PasswordHasher().hash("secret-pass")                       # параметры библиотеки по умолчанию: 64 МБ, t=3, p=4
    acc.con.execute("UPDATE users SET password_hash = ? WHERE id = ?", (heavy, user.id))
    assert run(acc.verify("mira", "secret-pass")).id == user.id        # старый хэш проверяется по своим параметрам
    now = acc.con.execute("SELECT password_hash FROM users WHERE id = ?", (user.id,)).fetchone()[0]
    assert now != heavy and "m=19456,t=2,p=1" in now                    # и переписан на облегчённый
    assert run(acc.verify("mira", "secret-pass")).id == user.id        # новый хэш работает
    with pytest.raises(AccountError):
        run(acc.verify("mira", "wrong-password"))


def test_wrong_password_does_not_rewrite_the_hash(acc):
    from argon2 import PasswordHasher
    user = run(acc.register("mira", "secret-pass"))
    heavy = PasswordHasher().hash("secret-pass")
    acc.con.execute("UPDATE users SET password_hash = ? WHERE id = ?", (heavy, user.id))
    with pytest.raises(AccountError):
        run(acc.verify("mira", "nope-nope-nope"))
    assert acc.con.execute("SELECT password_hash FROM users WHERE id = ?", (user.id,)).fetchone()[0] == heavy


def test_ip_limit_is_looser_than_the_login_one(acc):
    """Пять опечаток с одного IP (мобильный оператор, общий nginx) не запирают вход другим логинам."""
    for n in range(10):
        with pytest.raises(AccountError) as e:
            run(acc.verify(f"user{n}", "wrong-password", ip="203.0.113.5"))
        assert e.value.code == "no_user"
    run(acc.register("mira", "secret-pass"))
    assert run(acc.verify("mira", "secret-pass", ip="203.0.113.5")).login == "mira"


def test_ip_limit_still_stops_a_spray(acc):
    from sonar.accounts import IP_LOGIN_TRIES
    for n in range(IP_LOGIN_TRIES):
        with pytest.raises(AccountError):
            run(acc.verify(f"user{n}", "wrong-password", ip="198.51.100.9"))
    with pytest.raises(AccountError) as e:
        run(acc.verify("brand-new", "wrong-password", ip="198.51.100.9"))
    assert e.value.code == "too_many"
    with pytest.raises(AccountError) as other:                       # а с другого адреса — по-прежнему «нет такого»
        run(acc.verify("brand-new", "wrong-password", ip="198.51.100.10"))
    assert other.value.code == "no_user"


def test_successful_login_does_not_clear_the_ip_counter(acc):
    from sonar.accounts import IP_LOGIN_TRIES
    run(acc.register("mira", "secret-pass"))
    for n in range(IP_LOGIN_TRIES - 1):
        with pytest.raises(AccountError):
            run(acc.verify(f"user{n}", "wrong-password", ip="192.0.2.7"))
    run(acc.verify("mira", "secret-pass", ip="192.0.2.7"))           # 30-я попытка, успешная
    with pytest.raises(AccountError) as e:
        run(acc.verify("mira", "secret-pass", ip="192.0.2.7"))
    assert e.value.code == "too_many"
