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
