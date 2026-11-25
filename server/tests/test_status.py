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
