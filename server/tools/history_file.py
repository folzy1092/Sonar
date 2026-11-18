"""Общее для выгрузок истории прослушиваний (export_lastfm.py, export_listenbrainz.py).

Строка файла: {"ts": <unix-время>, "artist": "...", "title": "...", "album": "...", "mbid": "..."}.
Рядом — файл состояния: сколько строк записано и откуда продолжать; ник в нём — только хэшем.
Обрыв (Ctrl+C, сеть, сон ноутбука) не портит файл: при продолжении он обрезается до сохранённого.
"""

import getpass
import hashlib
import json
import os
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / "data"  # server/data — в .gitignore


def user_hash(user: str) -> str:
    return hashlib.sha256(user.strip().lower().encode("utf-8")).hexdigest()


def read_state(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None


def write_state(path: Path, state: dict) -> None:
    """Атомарно: сначала во временный файл, потом подмена — обрыв не оставит половину JSON."""
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, path)


def keep_lines(path: Path, count: int) -> None:
    """Оставляет в файле первые count строк: всё, что дописалось после последнего сохранения, — долой."""
    if not path.exists():
        path.write_bytes(b"")
        return
    lines = path.read_bytes().split(b"\n")[:count]
    path.write_bytes(b"".join(line + b"\n" for line in lines))


def append_records(path: Path, records: list[dict]) -> None:
    with path.open("a", encoding="utf-8") as f:
        for record in records:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
        f.flush()
        os.fsync(f.fileno())


def start_state(path: Path, user: str, out: Path, fresh: dict) -> dict:
    """Состояние выгрузки: прежнее этого же ника (файл обрезается до сохранённого) или новое из fresh."""
    state = read_state(path)
    uid = user_hash(user)
    if state and state["user"] != uid:
        raise SystemExit(
            f"В {path.name} — выгрузка другого ника. Убери {path.name} и {out.name}, чтобы начать заново."
        )
    if state:
        keep_lines(out, state["lines"])
        return state
    out.write_bytes(b"")
    state = {"user": uid, "lines": 0, "done": False, **fresh}
    write_state(path, state)
    return state


def ask(prompt: str) -> str:
    """Скрытый ввод (как пароль): не в аргументах, не в истории терминала."""
    value = getpass.getpass(prompt).strip()
    if not value:
        raise SystemExit("Пусто — выхожу.")
    return value
