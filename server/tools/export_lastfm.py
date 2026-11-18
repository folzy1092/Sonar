"""Выгрузка всей истории Last.fm (скробблов) в server/data/lastfm-export.jsonl.

Срочно, до 1 декабря 2026: потом ключ API Last.fm работает только с Pro (docs/LASTFM_EXIT.md).
Файл потом импортирует сервер Sonar (`POST /plays/import`), чтобы статистика и итоги не начинались с нуля.

Ключ API и ник спрашиваются скрытым вводом (как пароль) — не в аргументах, не в файлах, нигде не
печатаются. Идём постранично (`user.getRecentTracks`, по 200), с паузой между страницами и повторами при
временных ошибках. Оборвалось (Ctrl+C, сеть, сон ноутбука) — запусти снова тем же ником: продолжит с
места обрыва, без дублей. Верхняя граница времени фиксируется при первом запуске, поэтому страницы не
съезжают, даже если ты слушаешь музыку во время выгрузки.

Строка файла: {"ts": <unix-время>, "artist": "...", "title": "...", "album": "...", "mbid": "..."},
от новых к старым. Рядом — lastfm-export.state.json (страница, число строк; ник — только хэшем).
Оба файла в .gitignore (server/data/), в репо не идут.

Запуск (из корня репо):  python server/tools/export_lastfm.py
Только стандартная библиотека — ничего ставить не нужно.
"""

import getpass
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://ws.audioscrobbler.com/2.0/"
PER_PAGE = 200  # больше Last.fm не отдаёт
PAUSE = 0.6  # секунд между страницами: у Last.fm предел ~5 запросов в секунду
RETRIES = 6
BACKOFF = 5  # секунд до первого повтора, дальше вдвое больше
TIMEOUT = 30
RETRY_CODES = {8, 11, 16, 29}  # временные: сбой Last.fm, сервис недоступен, «попробуй ещё», лимит
FRIENDLY = {
    6: "такого ника на Last.fm нет",
    10: "ключ API не подошёл — проверь его на last.fm/api/accounts",
    17: "история скрыта — в настройках приватности Last.fm открой «недавние прослушивания»",
    26: "ключ API заблокирован",
}

DATA = Path(__file__).resolve().parents[1] / "data"
OUT = DATA / "lastfm-export.jsonl"
STATE = DATA / "lastfm-export.state.json"


class LastfmError(Exception):
    def __init__(self, code, message):
        super().__init__(f"Last.fm {code}: {message}")
        self.code = code


def parse_page(payload):
    """Ответ user.getRecentTracks → (записи, всего страниц, всего скробблов). «Сейчас играет» пропускаем."""
    recent = payload["recenttracks"]
    attr = recent["@attr"]
    tracks = recent.get("track") or []
    if isinstance(tracks, dict):  # одна запись приходит объектом
        tracks = [tracks]
    records = [
        {
            "ts": int(t["date"]["uts"]),
            "artist": t["artist"]["#text"],
            "title": t["name"],
            "album": (t.get("album") or {}).get("#text", ""),
            "mbid": t.get("mbid") or "",
        }
        for t in tracks
        if "date" in t and not (t.get("@attr") or {}).get("nowplaying")
    ]
    return records, int(attr["totalPages"]), int(attr["total"])


def fetch_page(key, user, page, to):
    """Одна страница истории. Ошибки — LastfmError (адрес с ключом в текст ошибки не попадает)."""
    query = urllib.parse.urlencode(
        {
            "method": "user.getrecenttracks",
            "user": user,
            "api_key": key,
            "format": "json",
            "limit": PER_PAGE,
            "page": page,
            "to": to,
        }
    )
    request = urllib.request.Request(f"{API}?{query}", headers={"User-Agent": "Sonar-history-export/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as reply:
            data = json.loads(reply.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        data = _error_body(e)
        if data is None:
            # 5xx и прочее без тела Last.fm — считаем временным сбоем
            raise LastfmError(8 if e.code >= 500 or e.code == 429 else -e.code, f"HTTP {e.code}") from None
    except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
        raise LastfmError(8, f"нет связи ({type(e).__name__})") from None
    except json.JSONDecodeError:
        raise LastfmError(8, "непонятный ответ") from None
    if "error" in data:
        raise LastfmError(int(data["error"]), str(data.get("message", "")))
    return data


def _error_body(error):
    try:
        data = json.loads(error.read().decode("utf-8"))
    except (ValueError, OSError):
        return None
    return data if isinstance(data, dict) and "error" in data else None


def fetch_with_retry(key, user, page, to, log=print):
    """fetch_page с повторами при временных ошибках: пауза растёт вдвое."""
    for attempt in range(RETRIES):
        try:
            return fetch_page(key, user, page, to)
        except LastfmError as e:
            if e.code not in RETRY_CODES or attempt == RETRIES - 1:
                raise
            wait = BACKOFF * 2**attempt
            log(f"  стр. {page}: {e} — повтор через {wait} с")
            time.sleep(wait)
    raise AssertionError("unreachable")


def user_hash(user):
    return hashlib.sha256(user.strip().lower().encode("utf-8")).hexdigest()


def read_state(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None


def write_state(path, state):
    """Атомарно: сначала во временный файл, потом подмена — обрыв не оставит половину JSON."""
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(state), encoding="utf-8")
    os.replace(tmp, path)


def keep_lines(path, count):
    """Оставляет в файле первые count строк: всё, что дописалось после последнего сохранения, — долой."""
    if not path.exists():
        path.write_bytes(b"")
        return
    lines = path.read_bytes().split(b"\n")[:count]
    path.write_bytes(b"".join(line + b"\n" for line in lines))


def append_records(path, records):
    with path.open("a", encoding="utf-8") as f:
        for record in records:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
        f.flush()
        os.fsync(f.fileno())


def start_state(path, user, out, now):
    """Состояние выгрузки: новое или прежнее этого же ника (тогда файл обрезается до сохранённого)."""
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
    fresh = {"user": uid, "to": int(now()), "page": 0, "lines": 0, "done": False}
    write_state(path, fresh)
    return fresh


def export(key, user, out=OUT, state_path=STATE, fetch=None, log=print, now=time.time):
    """Выкачивает историю в out, страница за страницей. Возвращает, сколько скробблов в файле."""
    fetch = fetch or (lambda k, u, p, to: fetch_with_retry(k, u, p, to, log))
    out.parent.mkdir(parents=True, exist_ok=True)
    state = start_state(state_path, user, out, now)
    if state["done"]:
        log(f"Уже выгружено целиком: {state['lines']} скробблов → {out}")
        return state["lines"]
    if state["page"]:
        log(f"Продолжаю со страницы {state['page'] + 1} (уже {state['lines']} скробблов)")

    page = state["page"] + 1
    while True:
        records, pages, total = parse_page(fetch(key, user, page, state["to"]))
        append_records(out, records)
        state = {**state, "page": page, "lines": state["lines"] + len(records)}
        write_state(state_path, state)
        log(f"  стр. {page}/{max(pages, 1)} · {state['lines']} из ~{total}")
        if page >= pages:
            break
        page += 1
        time.sleep(PAUSE)

    state = {**state, "done": True, "total": total}
    write_state(state_path, state)
    return state["lines"]


def ask(prompt):
    value = getpass.getpass(prompt).strip()
    if not value:
        raise SystemExit("Пусто — выхожу.")
    return value


def main():
    print("Выгрузка истории Last.fm → server/data/lastfm-export.jsonl")
    key = ask("Ключ API Last.fm (ввод скрыт): ")
    if not re.fullmatch(r"[0-9a-fA-F]{32}", key):
        raise SystemExit("Ключ API Last.fm — 32 символа 0-9 и a-f (last.fm/api/accounts).")
    user = ask("Ник на Last.fm (ввод скрыт): ")
    try:
        count = export(key, user)
    except KeyboardInterrupt:
        state = read_state(STATE) or {}
        print(f"\nОстановлено. В файле {state.get('lines', 0)} скробблов — запусти снова, продолжу с места обрыва.")
        return 130
    except LastfmError as e:
        reason = FRIENDLY.get(e.code, str(e))
        print(f"\nНе получилось: {reason}. Сохранённое не пропало — запусти снова, продолжу с места обрыва.")
        return 1
    state = read_state(STATE) or {}
    print(f"\nГотово: {count} скробблов → {OUT}")
    if state.get("total") not in (None, count):
        print(f"Last.fm в начале насчитал {state['total']} — расхождение бывает из-за скробблов без даты.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
