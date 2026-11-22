"""Тестовые данные для локального просмотра админки (`python -m sonar.web --demo`, база data/demo.db).

Только для глаз: выдуманные логины, устройства, события и подписки за 60 дней. В настоящую базу не пишет.
"""
from __future__ import annotations

import random
import sqlite3

from ..db import now_ms, tx
from ..events import day_of
from ..subs import DAY_MS, PLANS

NAMES = ["mira", "kostya", "lev_on", "dasha.k", "artem", "nika", "sergey_b", "oleg", "vika", "ilya", "tanya", "max",
         "polina", "roma", "yana", "egor", "liza", "denis", "kira", "timur", "alina", "gleb", "sonya", "pasha",
         "zhenya", "vlad", "masha", "anton", "lera", "nikita", "eva", "bogdan", "ksyusha", "fedya", "ulya", "stas"]
TRACKS = [("sc:1301", "ONDA ANDAR", "pressure"), ("sc:1302", "cowboyclicker", "zombie"), ("ym:5501", "Kleyy", "Клей"),
          ("ym:5502", "Монеточка", "Каждый раз"), ("yt:dQw4", "Kavinsky", "Nightcall"), ("vk:-2001_7", "Скриптонит", "Положение"),
          ("sp:4uLU6h", "Radiohead", "Weird Fishes"), ("sc:1303", "kyle", "cold room"), ("ym:5503", "Земфира", "Хочешь?"),
          ("yt:Zi_X", "Daft Punk", "Something About Us"), ("sc:1304", "ONDA ANDAR", "low tide"), ("ym:5504", "Kleyy", "Шум")]


def seed(con: sqlite3.Connection, days: int = 60, rnd_seed: int = 7) -> None:
    if con.execute("SELECT 1 FROM users LIMIT 1").fetchone():
        return
    rnd = random.Random(rnd_seed)
    now = now_ms()
    start = now - days * DAY_MS
    with tx(con):
        for i, name in enumerate(["folzy"] + NAMES):
            uid = f"u_demo{i:03d}"
            created = start + int((i / (len(NAMES) + 1)) ** 1.4 * days * DAY_MS)
            con.execute("INSERT INTO users (id, number, login, username, display_name, tg_id, tg_username, banned, created_at)"
                        " VALUES (?,?,?,?,?,?,?,?,?)",
                        (uid, i + 1, name, name, name.capitalize(), 7_000_000 + i if rnd.random() < 0.6 else None,
                         name if rnd.random() < 0.6 else None, 1 if i in (9, 23) else 0, created))
            devs = [("windows", "Windows 11 (" + name + ")")] + ([("ios", "iPhone 15")] if rnd.random() < 0.45 else [])
            if rnd.random() < 0.15:
                devs = [("ios", "iPhone 13")]
            for j, (plat, dname) in enumerate(devs):
                con.execute("INSERT INTO sessions (id, user_id, token_hash, device_id, device_name, platform, os, app_version,"
                            " build, created_at, last_seen_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                            (f"d_{uid}_{j}", uid, f"demo-{uid}-{j}", f"dev-{uid}-{j}", dname, plat,
                             "iOS 18.2" if plat == "ios" else "Windows 11 24H2", "0.1.42", 42, created, created))
            engaged = rnd.random()
            for d in range(days):
                t = start + d * DAY_MS + rnd.randint(8, 23) * 3600_000
                if t < created or t > now or rnd.random() > 0.15 + 0.7 * engaged:
                    continue
                j = rnd.randrange(len(devs))
                plat, dev = devs[j][0], f"dev-{uid}-{j}"
                con.execute("INSERT OR IGNORE INTO events (user_id, device_id, platform, kind, at, day) VALUES (?,?,?,?,?,?)",
                            (uid, dev, plat, "open", t, day_of(t)))
                if rnd.random() < 0.72:
                    for k in range(rnd.randint(1, 25)):
                        ref, artist, title = TRACKS[min(int(rnd.expovariate(0.35)), len(TRACKS) - 1)]
                        at = t + (k + 1) * 190_000
                        con.execute("INSERT OR IGNORE INTO events (user_id, device_id, platform, kind, service, ref, artist,"
                                    " title, at, day) VALUES (?,?,?,?,?,?,?,?,?,?)",
                                    (uid, dev, plat, "play", {"sc": "soundcloud", "ym": "yandex", "yt": "youtube",
                                                              "vk": "vk", "sp": "spotify"}[ref.split(":")[0]],
                                     ref, artist, title, at, day_of(at)))
            if engaged > 0.55 and i != 9:
                plan = rnd.choice(list(PLANS))
                t = max(created, start) + rnd.randint(0, 20) * DAY_MS
                for k in range(rnd.randint(1, 3)):
                    s0 = t + k * 30 * DAY_MS
                    if s0 > now:
                        break
                    con.execute("INSERT INTO subscriptions (user_id, plan, kind, source, started_at, ends_at, amount,"
                                " created_at) VALUES (?,?,?,?,?,?,?,?)",
                                (uid, plan, "new" if k == 0 else "renew", "demo", s0, s0 + 30 * DAY_MS, PLANS[plan][2], s0))
