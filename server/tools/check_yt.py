"""Проверка: работает ли YouTube Music с этого IP (как check_ym.py для Яндекса).

Четыре шага, каждый — OK или FAIL с причиной, пауза между запросами, без входа и без секретов:
  1. music.youtube.com открывается;
  2. поиск InnerTube (WEB_REMIX) находит трек;
  3. player (клиент VISIONOS, как в Sonar) отдаёт аудиоформаты с прямыми ссылками;
  4. с CDN googlevideo качается ограниченный Range за пределами первого мегабайта.

Запуск (из корня репо):  python server/tools/check_yt.py ["запрос"]
Только стандартная библиотека — ничего ставить не нужно.
"""

import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SITE = "https://music.youtube.com/"
API = "https://music.youtube.com/youtubei/v1"
PLAYER = "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
REMIX = {"clientName": "WEB_REMIX", "clientVersion": "1.20251110.01.00", "hl": "ru", "gl": "LV"}
VISION = {
    "clientName": "VISIONOS", "clientVersion": "0.1", "deviceMake": "Apple", "deviceModel": "RealityDevice14,1",
    "osName": "visionOS", "osVersion": "1.3.21O771", "hl": "ru", "gl": "LV",
}
VISION_UA = "Mozilla/5.0 (iPad; CPU OS 16_7_10 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)"
SEARCH_SONGS = "EgWKAQIIAWoKEAkQBRAKEAMQBA=="
AUDIO_ITAGS = (139, 140, 141, 249, 250, 251, 774)
PAUSE = 1.5  # секунд между запросами
TIMEOUT = 20
MB = 1024 * 1024
RANGE = (MB, 2 * MB - 1)  # второй мегабайт: CDN режет только запросы без конца диапазона
STEPS = 4
DEFAULT_QUERY = "Daft Punk Get Lucky"


class Fail(Exception):
    pass


def request(url, body=None, headers=None, limit=4 * MB):
    data = json.dumps(body).encode() if body is not None else None
    h = {"User-Agent": UA, **({"Content-Type": "application/json"} if data else {}), **(headers or {})}
    req = urllib.request.Request(url, data=data, headers=h, method="POST" if data else "GET")
    started = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            raw = r.read(limit)
            return r.status, int((time.monotonic() - started) * 1000), raw, dict(r.headers)
    except urllib.error.HTTPError as e:
        raise Fail(f"HTTP {e.code}: {e.read(300).decode('utf-8', 'replace')!r}") from None
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise Fail(f"сеть: {e}") from None


def post_json(url, body, headers=None):
    code, ms, raw, _ = request(url, body, headers)
    try:
        return code, ms, json.loads(raw)
    except ValueError:
        raise Fail(f"не JSON ({len(raw)} байт)") from None


def first_video(node):
    """Первый videoId трека в ответе поиска (обход в глубину)."""
    if isinstance(node, dict):
        if node.get("musicResponsiveListItemRenderer"):
            hit = find_key(node["musicResponsiveListItemRenderer"], "videoId")
            if hit:
                title = find_key(node["musicResponsiveListItemRenderer"], "text") or "?"
                return hit, title
        for v in node.values():
            got = first_video(v)
            if got:
                return got
    elif isinstance(node, list):
        for v in node:
            got = first_video(v)
            if got:
                return got
    return None


def find_key(node, key):
    if isinstance(node, dict):
        if isinstance(node.get(key), str):
            return node[key]
        children = node.values()
    elif isinstance(node, list):
        children = node
    else:
        return None
    for v in children:
        got = find_key(v, key)
        if got:
            return got
    return None


def host_of(url):
    return urllib.parse.urlsplit(url).hostname or "?"


def step_site(state):
    code, ms, raw, _ = request(SITE, limit=512 * 1024)
    if b"ytcfg" not in raw and b"youtube" not in raw.lower():
        raise Fail(f"HTTP {code}, но это не страница YouTube Music")
    return f"HTTP {code}, {ms} мс"


def step_search(state):
    body = {"context": {"client": REMIX}, "query": state["query"], "params": SEARCH_SONGS}
    code, ms, data = post_json(f"{API}/search?prettyPrint=false", body, {"Origin": SITE.rstrip("/")})
    hit = first_video(data)
    if not hit:
        raise Fail(f"HTTP {code}, но треков нет")
    state["video"], title = hit
    state["visitor"] = (data.get("responseContext") or {}).get("visitorData", "")
    return f"HTTP {code}, {ms} мс · «{title}» (id {state['video']})"


def step_player(state):
    client = {**VISION, "visitorData": state["visitor"]}
    body = {"context": {"client": client}, "videoId": state["video"], "contentCheckOk": True, "racyCheckOk": True}
    headers = {"User-Agent": VISION_UA, "X-YouTube-Client-Name": "101", "X-YouTube-Client-Version": "0.1"}
    if state["visitor"]:
        headers["X-Goog-Visitor-Id"] = state["visitor"]
    code, ms, data = post_json(PLAYER, body, headers)
    status = (data.get("playabilityStatus") or {}).get("status")
    if status != "OK":
        reason = (data.get("playabilityStatus") or {}).get("reason", "без причины")
        raise Fail(f"трек не играется: {status} — {reason}")
    formats = (data.get("streamingData") or {}).get("adaptiveFormats") or []
    audio = [f for f in formats if f.get("itag") in AUDIO_ITAGS and f.get("url")]
    if not audio:
        raise Fail(f"HTTP {code}, но аудио с прямой ссылкой нет (форматов всего: {len(formats)})")
    best = next((f for f in audio if f["itag"] == 251), audio[-1])
    state["url"], state["clen"] = best["url"], int(best.get("contentLength") or 0)
    found = ", ".join(f"{f['itag']} ({f.get('bitrate', 0) // 1000} кбит/с)" for f in audio)
    return f"HTTP {code}, {ms} мс · аудио: {found} · CDN {host_of(best['url'])}"


def step_range(state):
    a, b = RANGE
    if state["clen"] and state["clen"] <= a:
        raise Fail(f"файл короче {a // MB} МБ ({state['clen']} байт) — возьми другой запрос")
    b = min(b, state["clen"] - 1) if state["clen"] else b
    code, ms, raw, h = request(state["url"], headers={"Range": f"bytes={a}-{b}"}, limit=2 * MB)
    want = b - a + 1
    if code != 206 or len(raw) != want:
        raise Fail(f"HTTP {code}, получено {len(raw)} из {want} байт")
    speed = len(raw) / max(ms, 1) * 1000 / MB
    return f"HTTP {code}, {ms} мс · {len(raw)} байт ({h.get('Content-Range')}) · ≈ {speed:.1f} МБ/с"


def main():
    state = {"query": " ".join(sys.argv[1:]) or DEFAULT_QUERY}
    steps = [
        ("music.youtube.com открывается", step_site),
        (f"Поиск InnerTube: «{state['query']}»", step_search),
        ("player (VISIONOS) отдаёт аудиоформаты", step_player),
        (f"Range {RANGE[0]}-{RANGE[1]} с googlevideo", step_range),
    ]
    for n, (title, run) in enumerate(steps, 1):
        print(f"\n[{n}/{STEPS}] {title}")
        try:
            print(f"  OK   {run(state)}")
        except Fail as e:
            print(f"  FAIL {e}")
            print("\nИТОГ: YouTube Music с этого IP не работает на этом шаге — скопируй вывод (секретов в нём нет).")
            sys.exit(1)
        if n < STEPS:
            time.sleep(PAUSE)
    print("\nИТОГ: YouTube Music работает с этого IP — поиск, ссылки на аудио и поток кусками.")


if __name__ == "__main__":
    main()
