"""Дашборд: уникальные люди, «открыл vs слушал», DAU/WAU/MAU, сервисы и платформы, подписки и прогноз."""
from sonar import subs
from sonar.admin import dashboard as D
from sonar.events import day_of

DAY = subs.DAY_MS
NOW = 1_795_000_000_000  # фиксированное «сейчас» — тест не зависит от часов


def user(con, uid, created=NOW - 100 * DAY):
    n = con.execute("SELECT COUNT(*) FROM users").fetchone()[0] + 1
    con.execute("INSERT INTO users (id, number, login, username, display_name, created_at) VALUES (?,?,?,?,?,?)",
                (uid, n, uid, uid, uid, created))


def ev(con, uid, kind, at, platform="windows", ref=None, artist=None, device=None):
    con.execute("INSERT INTO events (user_id, device_id, platform, kind, service, ref, artist, title, at, day)"
                " VALUES (?,?,?,?,?,?,?,?,?,?)",
                (uid, device or f"{uid}-{platform}", platform, kind,
                 {"sc": "soundcloud", "ym": "yandex"}.get(ref.split(":")[0]) if ref else None, ref, artist,
                 ref and f"t{ref}", at, day_of(at)))


def test_open_vs_listen_counts_people_not_events(con):
    for u in ("a", "b", "c"):
        user(con, u)
    today = day_of(NOW)
    ev(con, "a", "open", NOW)
    ev(con, "a", "open", NOW + 1)              # второе открытие того же — всё равно один человек
    ev(con, "a", "play", NOW + 2, ref="sc:1")
    ev(con, "a", "play", NOW + 3, ref="sc:2")
    ev(con, "b", "open", NOW)                  # открыл и ушёл
    ev(con, "c", "play", NOW, ref="ym:1")      # play без open тоже значит «открыл»
    s = D.summary(con, today, today)
    assert (s["openers"], s["listeners"], s["idle"], s["plays"]) == (3, 2, 1, 3)
    assert s["per_listener"] == 1.5 and s["listen_share"] == 67


def test_period_uniques_not_sum_of_days(con):
    user(con, "a")
    for d in range(5):
        ev(con, "a", "play", NOW - d * DAY, ref="sc:1")
    end = day_of(NOW)
    assert D.summary(con, D.shift(end, -4), end)["listeners"] == 1
    days = D.series(con, D.shift(end, -6), end)
    assert len(days) == 7 and [d["listeners"] for d in days] == [0, 0, 1, 1, 1, 1, 1]


def test_dau_wau_mau(con):
    for u in ("a", "b", "c", "d"):
        user(con, u)
    ev(con, "a", "open", NOW)
    ev(con, "b", "open", NOW - 3 * DAY)
    ev(con, "c", "open", NOW - 20 * DAY)
    ev(con, "d", "open", NOW - 40 * DAY)
    a = D.active(con, day_of(NOW))
    assert (a["dau"], a["wau"], a["mau"], a["stickiness"]) == (1, 2, 3, 33)


def test_services_platforms_and_tops(con):
    for u in ("a", "b"):
        user(con, u)
    t = day_of(NOW)
    ev(con, "a", "play", NOW, ref="sc:1", artist="Kyle")
    ev(con, "a", "play", NOW + 1, ref="sc:1", artist="kyle")
    ev(con, "b", "play", NOW + 2, platform="ios", ref="sc:1", artist="Kyle")
    ev(con, "b", "play", NOW + 3, platform="ios", ref="ym:9", artist="Zemfira")
    ev(con, "b", "open", NOW + 4, platform="windows")
    sv = {s["key"]: (s["users"], s["plays"]) for s in D.by_service(con, t, t)}
    assert sv["soundcloud"] == (2, 3) and sv["yandex"] == (1, 1) and sv["spotify"] == (0, 0)
    pl = {p["key"]: (p["users"], p["listeners"], p["plays"]) for p in D.by_platform(con, t, t)}
    assert pl["windows"] == (2, 1, 2) and pl["ios"] == (1, 1, 2)
    assert D.top_tracks(con, t, t)[0]["ref"] == "sc:1" and D.top_tracks(con, t, t)[0]["users"] == 2
    top = D.top_artists(con, t, t)
    assert top[0]["users"] == 2 and top[0]["plays"] == 3  # «Kyle» и «kyle» — один исполнитель


def test_registrations_by_local_day(con):
    user(con, "a", created=NOW)
    user(con, "b", created=NOW - 2 * DAY)
    end = day_of(NOW)
    assert D.summary(con, end, end)["registrations"] == 1
    assert sum(d["registrations"] for d in D.series(con, D.shift(end, -6), end)) == 2


def test_empty_db_gives_zeroes_and_no_forecast(con):
    t = day_of(NOW)
    d = D.build(con, D.shift(t, -29), t, now=NOW)
    assert d["period"]["openers"] == 0 and d["period"]["per_listener"] is None
    assert d["top_tracks"] == [] and d["forecast"] is None and d["has_events"] is False
    assert d["subs"]["active"] == 0 and d["subs"]["revenue"] == {}


# ---- подписки ----

def test_grant_chains_and_kinds(con):
    user(con, "a")
    subs.grant(con, "a", "echo", 30, 190, now=NOW)
    subs.grant(con, "a", "echo", 30, 190, now=NOW + DAY)       # продление до конца — встаёт в очередь
    rows = subs.history(con, "a")
    assert [r["kind"] for r in rows] == ["renew", "new"]
    assert rows[0]["started_at"] == rows[1]["ends_at"]
    act = subs.active(con, "a", NOW + 2 * DAY)
    assert act.plan == "echo" and act.ends_at == NOW + 60 * DAY


def test_subscription_summary(con):
    for u in ("a", "b", "c"):
        user(con, u)
    subs.grant(con, "a", "ping", 30, 100, now=NOW - 25 * DAY)   # кончится через 5 дней
    subs.grant(con, "b", "fleet", 30, 380, now=NOW - DAY)
    subs.grant(con, "c", "pod", 10, 0, now=NOW - 20 * DAY)      # уже кончилась
    t = day_of(NOW)
    s = D.subscriptions(con, D.shift(t, -29), t, now=NOW)
    assert s["active"] == 2 and {p["plan"]: p["users"] for p in s["by_plan"]} == {"ping": 1, "echo": 0, "pod": 0, "fleet": 1}
    assert s["new"] == 3 and s["renew"] == 0 and s["expiring_7d"] == 1
    assert s["revenue"] == {"RUB": 480}


def test_renew_rate_counts_only_decided(con):
    for u in ("a", "b", "c", "d"):
        user(con, u)
    # a: кончилась 40 дней назад и продлил; b: кончилась 40 дней назад, не продлил;
    # c: кончилась 2 дня назад, ещё думает — не считаем; d: продлил заранее, период кончился вчера — считаем.
    subs.grant(con, "a", "ping", 30, 100, now=NOW - 70 * DAY)
    subs.grant(con, "a", "ping", 30, 100, now=NOW - 39 * DAY)
    subs.grant(con, "b", "ping", 30, 100, now=NOW - 70 * DAY)
    subs.grant(con, "c", "ping", 30, 100, now=NOW - 32 * DAY)
    subs.grant(con, "d", "ping", 30, 100, now=NOW - 31 * DAY)
    subs.grant(con, "d", "ping", 30, 100, now=NOW - 5 * DAY)
    renewed, due = D.renew_rate(con, NOW)
    # «a» первый период и «d» первый период — продлены; «a» второй (кончился 9 дней назад) — не продлён и решён.
    assert (renewed, due) == (2, 4)


def test_forecast_formula(con):
    # 10 действующих, 4 из них кончатся за 30 дней; продлений 1 из 2; новых: 6 за последние 30 дней, 4 — за прошлые.
    for i in range(20):
        user(con, f"u{i}")
    for i in range(4):   # прошлые 30–60 дней — новые, у двоих периоды по 10 дней уже кончились (одного продлили)
        subs.grant(con, f"u{i}", "ping", 10 if i < 2 else 90, 100, now=NOW - 50 * DAY)
    subs.grant(con, "u0", "ping", 90, 100, now=NOW - 40 * DAY)  # продлил u0 ровно в конец периода
    for i in range(4, 10):  # последние 30 дней — 6 новых
        subs.grant(con, f"u{i}", "ping", 30 if i < 7 else 60, 100, now=NOW - 20 * DAY)
    f = D.forecast(con, NOW)
    assert f["active"] == 9 and f["new_last"] == 6 and f["new_prev"] == 4
    assert f["renewed"] == 1 and f["due"] == 2 and f["renew_rate"] == 50
    assert f["expiring"] == 3            # u4–u6 (30 дней с NOW−20 кончатся через 10)
    assert f["new_next"] == 8            # тренд: 2·6 − 4
    assert f["estimate"] == round(9 - 3 + 3 * 0.5 + 8)
    assert f["low"] <= f["estimate"] <= f["high"]
    assert f["revenue"] == round((3 * 0.5 + 8) * 100)


def test_forecast_unknown_rate_gives_wide_range(con):
    user(con, "a")
    subs.grant(con, "a", "ping", 20, 0, now=NOW - 5 * DAY)
    f = D.forecast(con, NOW)
    assert f["renew_rate"] is None and f["revenue"] is None
    # 1 действует и кончится; новых 1 и 0 → тренд 2. Вилка: никто не продлит и 1 новый … все продлят и 2 новых.
    assert (f["low"], f["estimate"], f["high"]) == (1, 2, 3)


# ---- динамика ----

def test_compare_with_previous_period(con):
    for u in ("a", "b", "c"):
        user(con, u)
    end = day_of(NOW)
    ev(con, "a", "play", NOW - 10 * DAY, ref="sc:1")          # прошлые 7 дней: 1 слушатель
    for u in ("a", "b", "c"):
        ev(con, u, "play", NOW - DAY, ref="sc:1")             # эти 7 дней: 3
    rows = {r["key"]: r for r in D.compare(con, D.shift(end, -6), end)["rows"]}
    assert (rows["listeners"]["now"], rows["listeners"]["before"], rows["listeners"]["delta"]) == (3, 1, 200)
    assert rows["registrations"]["delta"] is None             # прошлого не было — не «+∞%»


def test_pace_linear_trend():
    series = [{"listeners": v} for v in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10)]
    p = D.pace(series, "listeners", ahead=30)
    assert p["now"] == 7.0 and p["per_week"] == 7.0 and p["later"] == 37.0
    assert D.pace(series[:5], "listeners") is None            # меньше недели — тренд не строим
    assert D.pace([{"listeners": 0}] * 10, "listeners") is None
    assert D.pace([{"listeners": v} for v in (9, 8, 7, 6, 5, 4, 3, 2, 1, 0)], "listeners")["later"] == 0  # не ниже нуля


def test_milestone_date_and_progress(con):
    for i in range(20):
        user(con, f"u{i}", created=NOW - (i % 10) * DAY)       # 20 человек, все за последние 10 дней
    end = day_of(NOW)
    m = D.milestone(con, D.shift(end, -9), end, now=NOW)
    assert (m["total"], m["target"], m["progress"]) == (20, 25, 67)
    assert m["per_day"] == 2.0 and m["days"] == 3 and m["date"] == day_of(NOW + 3 * DAY)
    quiet = D.milestone(con, D.shift(end, -40), D.shift(end, -30), now=NOW)
    assert quiet["date"] is None
