from sonar.config import Settings
from sonar.db import now_ms
from sonar.status import DOWN, OK, PARTIAL, Item, Status


def test_three_downs_in_a_row(con, tmp_path):
    st = Status(con, tmp_path, Settings())
    for n in range(3):
        con.execute("INSERT INTO status_checks (ts, item, state) VALUES (?, 'yandex', 'down')", (n,))
        assert st._smooth(Item("yandex", DOWN)).state == (DOWN if n == 2 else PARTIAL)
    con.execute("INSERT INTO status_checks (ts, item, state) VALUES (9, 'yandex', 'ok')")
    assert st._smooth(Item("yandex", OK)).state == PARTIAL  # недавние сбои ещё видны


def test_uptime(con, tmp_path):
    st = Status(con, tmp_path, Settings())
    assert st.uptime() is None
    t = now_ms()
    con.executemany("INSERT INTO status_checks (ts, item, state) VALUES (?, 'main', ?)",
                    [(t, "ok"), (t, "ok"), (t, "ok"), (t, "down")])
    assert st.uptime() == 75.0


def test_never_ok_items(con, tmp_path):
    st = Status(con, tmp_path, Settings())
    con.executemany("INSERT INTO status_checks (ts, item, state) VALUES (?, ?, ?)",
                    [(1, "site", "down"), (2, "site", "down"), (1, "main", "ok"), (1, "yandex", "down"), (2, "yandex", "ok")])
    assert st.never_ok() == {"site"}


def test_extra_platforms_checked():
    from sonar.status import EXTRA_PLATFORMS
    assert set(EXTRA_PLATFORMS) == {"youtube", "vk", "spotify", "apple"}


def test_storage_counts_own_files_against_quota(con, tmp_path, monkeypatch):
    import asyncio
    data = tmp_path / "data"
    data.mkdir()
    (tmp_path / "app.bin").write_bytes(b"x" * 3 * 1024 * 1024)  # код и .venv рядом с data/ тоже считаются
    (data / "f").write_bytes(b"x" * 1024 * 1024)
    monkeypatch.setenv("SONAR_DISK_QUOTA_MB", "200")
    item = asyncio.run(Status(con, data, Settings(data_dir=data))._storage())
    assert item.state == OK and item.note.startswith("занято 4 МБ из 200 МБ, свободно 196 МБ")
    monkeypatch.setenv("SONAR_DISK_QUOTA_MB", "20")
    st = Status(con, data, Settings(data_dir=data))
    assert asyncio.run(st._storage()).state == DOWN  # осталось 16 МБ — не «115 ГБ свободно» с хоста


def test_failure_reasons_for_owner():
    import asyncio

    import aiohttp

    from sonar.status import Throttled, _why
    assert _why(asyncio.TimeoutError()) == "не ответил за 5 с"
    assert "сети" in _why(aiohttp.ClientPayloadError())
    assert Throttled(403).status == 403


def _change(**kw):
    from sonar.status import Change
    base = dict(key="lrclib", old=OK, new=DOWN, now=Item("lrclib", DOWN, note="не ответил за 5 с", target="lrclib.net/api/search"),
                recent=(DOWN, DOWN, DOWN), bad_for_s=900.0, last_issue="не ответил за 5 с")
    return Change(**{**base, **kw})


def test_alert_shows_reason_target_and_history():
    from sonar.status_alert import alert_lines, alert_title
    lines = alert_lines(_change(old=PARTIAL))
    assert lines[0] == "⚠️ → ❌"
    assert lines[1] == "Причина: не ответил за 5 с\nСбой идёт 15 мин"
    assert lines[2] == "Проверка: lrclib.net/api/search"
    assert lines[3].startswith("Последние проверки: ❌ ❌ ❌")
    assert alert_title(_change(key="youtube")) == "Статус: YouTube Music"


def test_alert_recovery_tells_how_long_and_what_was_wrong():
    from sonar.status_alert import alert_lines
    lines = alert_lines(_change(old=PARTIAL, new=OK, now=Item("lrclib", OK, 180, target="lrclib.net/api/search"),
                                recent=(OK, DOWN, OK), bad_for_s=3900.0))
    assert lines[1] == "Снова работает · сбой длился 1 ч 5 мин\nБыло: не ответил за 5 с"
    assert lines[2] == "Проверка: lrclib.net/api/search · 180 мс"


def test_alert_explains_smoothed_warning_when_check_passed():
    from sonar.status_alert import alert_lines
    lines = alert_lines(_change(old=DOWN, new=PARTIAL, now=Item("lrclib", OK, 200), recent=(OK, DOWN, DOWN)))
    assert lines[1].startswith("Сейчас отвечает, но упали 2 из 3 последних проверок")


def test_alert_escapes_html_in_reason():
    from sonar.status_alert import alert_lines
    assert "&lt;b&gt;" in alert_lines(_change(now=Item("x", DOWN, note="<b>")))[1]


def test_span_is_human():
    from sonar.status_alert import span
    assert [span(40), span(900), span(3600), span(90000)] == ["40 с", "15 мин", "1 ч", "1 дн 1 ч"]


def test_changes_track_failure_duration_and_reason(con, tmp_path):
    st = Status(con, tmp_path, Settings())
    st.last = {"proxy": Item("proxy", OK)}
    raw = {"proxy": Item("proxy", PARTIAL, 2400, "медленно: 2.4 с", "try-sonar.ru/api/health")}
    [c] = st._changes(raw, raw, now=1000.0)
    assert (c.old, c.new, c.bad_for_s, c.now.target) == (OK, PARTIAL, None, "try-sonar.ru/api/health")
    st.last = raw
    ok = {"proxy": Item("proxy", OK, 300)}
    [back] = st._changes(ok, ok, now=1600.0)
    assert (back.bad_for_s, back.last_issue) == (600.0, "медленно: 2.4 с")
    assert st.bad_since == {}
    st.last = ok
    assert st._changes(ok, ok, now=1900.0) == []


# ---- Яндекс по отчётам устройств, а не с сервера (451 из Германии) ----

def _report(con, uid, ok, ms=150, note=None, at=None):
    con.execute("INSERT OR IGNORE INTO users (id, number, login, username, display_name, created_at) VALUES (?,?,?,?,?,?)",
                (uid, abs(hash(uid)) % 10**6, uid, uid, uid, 1))
    con.execute("INSERT OR REPLACE INTO client_checks (user_id, service, ok, ms, note, at) VALUES (?,?,?,?,?,?)",
                (uid, "yandex", int(ok), ms, note, at or now_ms()))


def test_yandex_is_not_checked_from_the_server():
    import inspect

    from sonar.status import Status as S
    assert "api.music.yandex.net" not in inspect.getsource(S.check)


def test_no_device_reports_means_no_data_not_a_failure(con, tmp_path):
    st = Status(con, tmp_path, Settings())
    assert st.from_devices("yandex") is None


def test_device_reports_decide_the_state(con, tmp_path):
    st = Status(con, tmp_path, Settings())
    _report(con, "a", True, 100)
    assert st.from_devices("yandex").state == OK
    _report(con, "b", False, note="HTTP 451")
    assert st.from_devices("yandex").state == PARTIAL           # один из двух не дозвонился
    for who in ("c", "d"):
        _report(con, who, True, 200)
    assert st.from_devices("yandex").state == OK                # плохой — меньшинство
    assert st.from_devices("yandex").ms == 200                  # медиана по тем, у кого работает: 100, 200, 200


def test_one_bad_device_alone_is_only_a_warning_two_are_an_outage(con, tmp_path):
    st = Status(con, tmp_path, Settings())
    _report(con, "a", False, note="HTTP 451")
    assert st.from_devices("yandex").state == PARTIAL
    _report(con, "b", False, note="таймаут")
    item = st.from_devices("yandex")
    assert item.state == DOWN and "❌ 2" in item.note and "HTTP 451" in item.note


def test_old_device_reports_are_ignored(con, tmp_path):
    st = Status(con, tmp_path, Settings())
    _report(con, "a", True, at=now_ms() - 25 * 60_000)
    assert st.from_devices("yandex") is None


def test_media_ignores_missing_yandex_data(con, tmp_path, monkeypatch):
    import asyncio

    async def fake_remote(self, session, key, url, **params):
        return Item(key, OK, 100, target=url)
    monkeypatch.setattr(Status, "_remote", fake_remote)
    monkeypatch.setattr(Status, "_telegram", lambda self: asyncio.sleep(0, Item("telegram", OK, 1)))
    st = Status(con, tmp_path, Settings(data_dir=tmp_path, site_url="https://x"), bot=object())
    got = asyncio.run(st.check())
    assert "yandex" not in got and got["media"].state == OK and "нет данных" in got["media"].target
    _report(con, "a", False, note="HTTP 451")
    again = asyncio.run(st.check())
    assert again["yandex"].state != OK and again["media"].state == PARTIAL


# ---- уведомления: только подтверждённый сбой и восстановление после него ----

def _gate(con):
    from sonar.status_alert import AlertGate
    return AlertGate(con)


def test_short_failures_and_warnings_stay_silent(con):
    gate = _gate(con)
    assert not gate.allow(_change(key="site", old=OK, new=PARTIAL, now=Item("site", DOWN, note="не ответил за 5 с")))
    assert not gate.allow(_change(key="site", old=PARTIAL, new=OK, now=Item("site", OK, 100)))
    assert not gate.allow(_change(key="site", old=OK, new=PARTIAL, now=Item("site", DOWN)))


def test_foreign_services_never_reach_the_log_even_when_down(con):
    """lrclib и Genius нашему сервису не нужны (тексты ищет приложение), SoundCloud и Яндекс играют с устройства."""
    gate = _gate(con)
    for key in ("lrclib", "genius", "soundcloud", "yandex", "youtube", "spotify", "apple", "media"):
        assert not gate.allow(_change(key=key, old=PARTIAL, new=DOWN)), key
        assert not gate.allow(_change(key=key, old=DOWN, new=OK, now=Item(key, OK, 90))), key
    assert gate.down == set()                                                   # и не запоминаем как «сообщённое»


def test_own_items_are_reported(con):
    gate = _gate(con)
    for key in ("main", "bot", "site", "storage", "proxy", "telegram"):
        assert gate.allow(_change(key=key, old=PARTIAL, new=DOWN)), key


def test_confirmed_outage_and_recovery_are_reported_once(con):
    gate = _gate(con)
    assert gate.allow(_change(key="site", old=PARTIAL, new=DOWN))
    assert not gate.allow(_change(key="site", old=DOWN, new=PARTIAL, now=Item("site", OK, 90)))   # промежуточное ⚠️ молчит
    assert gate.allow(_change(key="site", old=PARTIAL, new=OK, now=Item("site", OK, 90)))         # а «снова работает» придёт
    assert not gate.allow(_change(key="site", old=PARTIAL, new=OK, now=Item("site", OK, 90)))      # второй раз — нет


def test_recovery_after_restart_still_arrives(con):
    assert _gate(con).allow(_change(key="bot", old=PARTIAL, new=DOWN))
    after_restart = _gate(con)                                                            # новый процесс, память пуста
    assert after_restart.allow(_change(key="bot", old=PARTIAL, new=OK, now=Item("bot", OK, 90)))


def test_gate_is_per_item(con):
    gate = _gate(con)
    assert gate.allow(_change(key="site", old=PARTIAL, new=DOWN))
    assert not gate.allow(_change(key="bot", old=PARTIAL, new=OK, now=Item("bot", OK, 90)))   # у бота сбоя не было
