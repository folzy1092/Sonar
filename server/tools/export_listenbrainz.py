"""Выгрузка истории прослушиваний из ListenBrainz в server/data/listenbrainz-export.jsonl.

Путь без ключа Last.fm (docs/LASTFM_EXIT.md, п. 1): ListenBrainz сам забирает историю Last.fm по нику
(listenbrainz.org → Settings → Import → Last.fm), а отсюда она выкачивается к нам — ListenBrainz отдаёт
прослушивания открыто, без ключей и токенов. Формат строк — тот же, что у export_lastfm.py:
{"ts": <unix-время>, "artist": "...", "title": "...", "album": "...", "mbid": "..."}, от новых к старым.
Файл потом импортирует сервер Sonar (`POST /plays/import`).

Ник ListenBrainz спрашивается скрытым вводом — не в аргументах, не в файлах. Идём назад во времени
(`max_ts`, по 1000 за запрос), с паузой и повторами при лимите и сбоях. Оборвалось — запусти снова тем
же ником: продолжит с места обрыва, без дублей. Прослушивания одной секунды на стыке страниц не теряются и
не дублируются; предел API — больше 1000 прослушиваний в одну и ту же секунду (такого не бывает).

Запуск (из корня репо):  python3 server/tools/export_listenbrainz.py
Только стандартная библиотека — ничего ставить не нужно.
"""

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from history_file import DATA, append_records, ask, read_state, start_state, write_state  # noqa: E402

API = "https://api.listenbrainz.org/1/user/"
PER_PAGE = 1000  # больше ListenBrainz за раз не отдаёт
PAUSE = 0.5  # секунд между запросами
RETRIES = 6
BACKOFF = 5  # секунд до первого повтора, дальше вдвое больше
TIMEOUT = 30
NO_NETWORK = 0
TEMPORARY = {NO_NETWORK, 429, 500, 502, 503, 504}
FRIENDLY = {404: "такого ника на ListenBrainz нет"}
HEADERS = {"User-Agent": "Sonar-history-export/1.0", "Accept": "application/json"}

OUT = DATA / "listenbrainz-export.jsonl"
STATE = DATA / "listenbrainz-export.state.json"


class ListenbrainzError(Exception):
    def __init__(self, code: int, message: str, retry_after: int | None = None):
        super().__init__(f"ListenBrainz {code}: {message}")
        self.code = code
        self.retry_after = retry_after


def to_record(listen: dict) -> dict:
    """Прослушивание ListenBrainz → строка файла (как у выгрузки Last.fm)."""
    meta = listen["track_metadata"]
    info = meta.get("additional_info") or {}
    mapping = meta.get("mbid_mapping") or {}
    return {
        "ts": int(listen["listened_at"]),
        "artist": meta.get("artist_name") or "",
        "title": meta.get("track_name") or "",
        "album": meta.get("release_name") or "",
        "mbid": info.get("recording_mbid") or mapping.get("recording_mbid") or "",
    }


def record_key(record: dict) -> tuple:
    return (record["ts"], record["artist"], record["title"])


def get_json(url: str) -> dict:
    """GET с разбором ошибок: лимит (429) несёт, сколько ждать; нет связи — код 0."""
    request = urllib.request.Request(url, headers=HEADERS)
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as reply:
            return json.loads(reply.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        reset = str((e.headers or {}).get("X-RateLimit-Reset-In") or "")
        retry_after = int(reset) + 1 if reset.isdigit() else None
        raise ListenbrainzError(e.code, f"HTTP {e.code}", retry_after) from None
    except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
        raise ListenbrainzError(NO_NETWORK, f"нет связи ({type(e).__name__})") from None
    except (json.JSONDecodeError, UnicodeDecodeError):
        raise ListenbrainzError(NO_NETWORK, "непонятный ответ") from None


def user_url(user: str, path: str) -> str:
    return f"{API}{urllib.parse.quote(user, safe='')}/{path}"


def fetch_listens(user: str, max_ts: int, per_page: int = PER_PAGE) -> list[dict]:
    """До per_page прослушиваний строго раньше max_ts, от новых к старым."""
    query = urllib.parse.urlencode({"count": per_page, "max_ts": max_ts})
    payload = get_json(f"{user_url(user, 'listens')}?{query}").get("payload")
    if not isinstance(payload, dict):
        raise ListenbrainzError(NO_NETWORK, "в ответе нет прослушиваний")
    return [to_record(listen) for listen in payload.get("listens") or []]


def fetch_count(user: str) -> int | None:
    """Сколько всего прослушиваний у ника — для прогресса; не вышло — None."""
    try:
        return int(get_json(user_url(user, "listen-count"))["payload"]["count"])
    except (ListenbrainzError, KeyError, TypeError, ValueError):
        return None


def fetch_with_retry(user: str, max_ts: int, per_page: int = PER_PAGE, log=print) -> list[dict]:
    """fetch_listens с повторами: при лимите ждём, сколько сказал ListenBrainz, иначе пауза растёт вдвое."""
    for attempt in range(RETRIES):
        try:
            return fetch_listens(user, max_ts, per_page)
        except ListenbrainzError as e:
            if e.code not in TEMPORARY or attempt == RETRIES - 1:
                raise
            wait = e.retry_after or BACKOFF * 2**attempt
            log(f"  {e} — повтор через {wait} с")
            time.sleep(wait)
    raise AssertionError("unreachable")


def next_step(state: dict, records: list[dict], per_page: int, log) -> tuple[list[dict], dict]:
    """Что из страницы ещё не записано и откуда идти дальше.

    Следующий запрос берёт max_ts = самая старая секунда страницы + 1, чтобы не потерять прослушивания
    этой секунды на стыке страниц; уже записанные из неё (edge) отбрасываются.
    """
    edge = {tuple(key) for key in state["edge"]}
    new = [r for r in records if record_key(r) not in edge]
    if not new:  # в странице только уже записанная секунда — шагаем за неё
        if len(records) >= per_page:
            log(f"  в одну секунду больше {per_page} прослушиваний — часть могла не попасть")
        return [], {**state, "max_ts": state["max_ts"] - 1, "edge": []}
    oldest = min(r["ts"] for r in records)
    boundary = {record_key(r) for r in records if r["ts"] == oldest}
    if oldest + 1 == state["max_ts"]:  # всё ещё та же секунда — помним и записанное раньше
        boundary = boundary | edge
    return new, {**state, "max_ts": oldest + 1, "edge": sorted(list(key) for key in boundary)}


def day(ts: int) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).date().isoformat()


def export(user, out=OUT, state_path=STATE, fetch=None, per_page=PER_PAGE, log=print, now=time.time, total=None):
    """Выкачивает историю в out, назад во времени. Возвращает, сколько прослушиваний в файле."""
    fetch = fetch or (lambda u, max_ts: fetch_with_retry(u, max_ts, per_page, log))
    out.parent.mkdir(parents=True, exist_ok=True)
    state = start_state(state_path, user, out, {"max_ts": int(now()) + 1, "edge": []})
    if state["done"]:
        log(f"Уже выгружено целиком: {state['lines']} прослушиваний → {out}")
        return state["lines"]
    if state["lines"]:
        log(f"Продолжаю с {day(state['max_ts'])} (уже {state['lines']} прослушиваний)")

    of_total = f" из ~{total}" if total else ""
    while records := fetch(user, state["max_ts"]):
        new, moved = next_step(state, records, per_page, log)
        append_records(out, new)
        state = {**moved, "lines": state["lines"] + len(new)}
        write_state(state_path, state)
        if new:
            log(f"  {state['lines']}{of_total} · дошёл до {day(state['max_ts'])}")
        time.sleep(PAUSE)

    state = {**state, "done": True}
    write_state(state_path, state)
    return state["lines"]


def main() -> int:
    print("Выгрузка истории ListenBrainz → server/data/listenbrainz-export.jsonl")
    user = ask("Ник на ListenBrainz (ввод скрыт): ")
    total = fetch_count(user)
    try:
        count = export(user, total=total)
    except KeyboardInterrupt:
        state = read_state(STATE) or {}
        print(f"\nОстановлено. В файле {state.get('lines', 0)} прослушиваний — запусти снова, продолжу с места обрыва.")
        return 130
    except ListenbrainzError as e:
        reason = FRIENDLY.get(e.code, str(e))
        print(f"\nНе получилось: {reason}. Сохранённое не пропало — запусти снова, продолжу с места обрыва.")
        return 1
    print(f"\nГотово: {count} прослушиваний → {OUT}")
    if total and count < total:
        print(
            f"ListenBrainz насчитал {total}. Если импорт из Last.fm ещё идёт (listenbrainz.org → Settings → Import),"
            f" дождись его, удали {STATE.name} и {OUT.name} в server/data и запусти снова."
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
