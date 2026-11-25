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
