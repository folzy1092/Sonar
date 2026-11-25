"""Перенос плейлиста Dotify (.dotifyplaylist) в «Любимые» Sonar на ПК.

Запуск:  python windows/scripts/import-dotify-playlist.py <файл.dotifyplaylist> [--dry-run] [--db=путь]
Sonar перед этим закрыть (из трея): пока он открыт, база живёт и в его памяти.

Пишет прямо в локальную базу %APPDATA%/com.folzy.sonar/sonar.db (перед записью — копия
sonar.db.bak-<время>). Каждый трек становится лайком `sc:<id>` / `ym:<id>` с датой добавления
из Dotify; метаданные трека кладутся в `tracks`, только если их там ещё нет. Лайки, снятые
в Sonar вручную (deleted = 1), не возвращаются. После записи — запустить Sonar.
"""
import json
import os
import sqlite3
import sys
import time

PREFIX = {"soundcloud": ("sc", "sca"), "yandex": ("ym", "yma")}
USER = "u_local"


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    dry = "--dry-run" in sys.argv
    if len(args) != 1:
        sys.exit(__doc__)
    data = json.load(open(args[0], encoding="utf-8"))
    db_path = next((a[5:] for a in sys.argv if a.startswith("--db=")),
                   os.path.join(os.environ["APPDATA"], "com.folzy.sonar", "sonar.db"))

    db = sqlite3.connect(db_path, timeout=10)
    if not dry:
        bak = f"{db_path}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
        db.execute("VACUUM INTO ?", (bak,))
        print("копия базы:", bak)

    existing = dict(db.execute("SELECT ref, deleted FROM likes WHERE user_id = ?", (USER,)))
    added = skipped_live = skipped_deleted = unknown = 0
    now = int(time.time() * 1000)
    with db:
        for t in data["tracks"]:
            pfx = PREFIX.get(t.get("source"))
            if not pfx:
                unknown += 1
                print("пропуск, неизвестный источник:", t.get("source"), t.get("title"))
                continue
            ref = f"{pfx[0]}:{t['id']}"
            artists = [
                {"ref": f"{pfx[1]}:{a['id']}", "name": a["name"], "avatar_url": a.get("avatar") or None}
                for a in t.get("artists") or []
            ]
            db.execute(
                "INSERT OR IGNORE INTO tracks (ref, title, artist, artists_json, album_json, duration_ms,"
                " cover_url, url, fetched_at) VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?)",
                (ref, t["title"], t["artist"], json.dumps(artists, ensure_ascii=False),
                 int(t.get("duration") or 0) * 1000, t.get("cover_art") or None, t.get("url") or None, now),
            )
            state = existing.get(ref)
            if state == 0:
                skipped_live += 1
                continue
            if state == 1:
                skipped_deleted += 1
                continue
            rev = db.execute("UPDATE sync_rev SET value = value + 1 WHERE id = 1 RETURNING value").fetchone()[0]
            db.execute(
                "INSERT INTO likes (user_id, ref, kind, added_at, deleted, rev) VALUES (?, ?, 'track', ?, 0, ?)",
                (USER, ref, int(t.get("added_at") or now), rev),
            )
            added += 1
        if dry:
            db.rollback()

    print(f"добавлено: {added}, уже были: {skipped_live}, сняты в Sonar (не трогал): {skipped_deleted},"
          f" неизвестный источник: {unknown}" + ("  [dry-run, ничего не записано]" if dry else ""))


if __name__ == "__main__":
    main()
