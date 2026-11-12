"""Проверка: пускает ли Яндекс Музыка с этого IP.

Аккуратно: 5 запросов, пауза между ними, остановка при первом отказе (403/429/451).
Токен (по порядку): переменная окружения YANDEX_TOKEN → строка YANDEX_TOKEN=... в
server/.env → скрытый ввод (как пароль). Токен нигде не печатается и не сохраняется.

Запуск (из корня репо):  python server/tools/check_ym.py
Только стандартная библиотека — ничего ставить не нужно.
"""

import getpass
import hashlib
import os
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

API = "https://api.music.yandex.net"
PAUSE = 2.5  # секунд между запросами — не спешим
SALT = "XGRlBW9FXlekgbPrRHuSiA"  # соль подписи ссылки на mp3 (как в yandex-music-api)
SEARCH = "Lil Peep Benz Truck"

ENV = Path(__file__).resolve().parents[1] / ".env"


def load_token():
    token = os.environ.get("YANDEX_TOKEN", "").strip()
    if not token and ENV.exists():
        for line in ENV.read_text(encoding="utf-8").splitlines():
            if line.startswith("YANDEX_TOKEN="):
                token = line.split("=", 1)[1].strip().strip('"').strip("'")
    if not token or token.startswith("<"):
        token = getpass.getpass("Вставь токен Яндекс Музыки (y0_..., ввод не виден) и нажми Enter: ").strip()
    if not token:
        sys.exit("Токен пустой — выхожу.")
    return token


def headers(token=None):
    h = {
        # так представляется официальное Android-приложение (как в yandex-music-api)
        "X-Yandex-Music-Client": "YandexMusicAndroid/24023621",
        "User-Agent": "Yandex-Music-API",
        "Accept-Language": "ru",
        "Accept": "application/json",
    }
    if token:
        h["Authorization"] = f"OAuth {token}"
    return h


class Blocked(Exception):
    pass


def get(url, token=None, raw=False, extra=None, method="GET"):
    req = urllib.request.Request(url, headers={**headers(token), **(extra or {})}, method=method)
    started = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            body = r.read(200_000)
            ms = int((time.monotonic() - started) * 1000)
            return r.status, ms, body if raw else json.loads(body or b"null"), dict(r.headers)
    except urllib.error.HTTPError as e:
        ms = int((time.monotonic() - started) * 1000)
        snippet = e.read(600).decode("utf-8", "replace").replace("\n", " ")
        if e.code in (401, 403, 429, 451):
            raise Blocked(f"HTTP {e.code} за {ms} мс: {snippet[:400]}")
        raise RuntimeError(f"HTTP {e.code} за {ms} мс: {snippet[:400]}")


def step(n, title):
    print(f"\n[{n}/5] {title}")


def main():
    token = load_token()
    print(f"Токен: найден ({len(token)} символов, начинается на {token[:3]}…)")
    track_id = None
    try:
        step(1, "Аккаунт: /account/status")
        code, ms, data, _ = get(f"{API}/account/status", token)
        acc = (data or {}).get("result", {}).get("account", {})
        plus = (data or {}).get("result", {}).get("plus", {}).get("hasPlus")
        print(f"  OK {code}, {ms} мс · логин: {acc.get('login')} · страна: {acc.get('region')} · Плюс: {plus}")
        time.sleep(PAUSE)

        step(2, f"Поиск: «{SEARCH}»")
        q = urllib.parse.urlencode({"text": SEARCH, "type": "track", "page": 0, "nocorrect": "false"})
        code, ms, data, _ = get(f"{API}/search?{q}", token)
        results = ((data or {}).get("result", {}).get("tracks") or {}).get("results") or []
        if not results:
            print(f"  {code}, {ms} мс, но треков нет — поиск пустой")
            return
        t = results[0]
        track_id = t["id"]
        artists = ", ".join(a["name"] for a in t.get("artists", []))
        print(f"  OK {code}, {ms} мс · {artists} — {t['title']} (id {track_id}, доступен: {t.get('available')})")
        time.sleep(PAUSE)

        step(3, "Похожие: /tracks/{id}/similar")
        code, ms, data, _ = get(f"{API}/tracks/{track_id}/similar", token)
        sim = (data or {}).get("result", {}).get("similarTracks") or []
        print(f"  OK {code}, {ms} мс · похожих: {len(sim)}"
              + (f" · первый: {sim[0]['artists'][0]['name']} — {sim[0]['title']}" if sim else ""))
        time.sleep(PAUSE)

        step(4, "Ссылка на поток: /tracks/{id}/download-info")
        code, ms, data, _ = get(f"{API}/tracks/{track_id}/download-info", token)
        infos = (data or {}).get("result") or []
        print(f"  OK {code}, {ms} мс · вариантов: "
              + ", ".join(f"{i['codec']} {i['bitrateInKbps']}" for i in infos))
        mp3 = sorted((i for i in infos if i["codec"] == "mp3"), key=lambda i: -i["bitrateInKbps"])
        if not mp3:
            print("  mp3 нет — дальше не проверяю")
            return
        time.sleep(PAUSE)
        code, ms, xml_body, _ = get(mp3[0]["downloadInfoUrl"], token, raw=True)
        x = ET.fromstring(xml_body)
        host, path, ts, s = (x.findtext(k) for k in ("host", "path", "ts", "s"))
        sign = hashlib.md5((SALT + path[1:] + s).encode()).hexdigest()
        link = f"https://{host}/get-mp3/{sign}/{ts}{path}"
        print(f"  OK, CDN-хост: {host}")
        time.sleep(PAUSE)

        step(5, "Сам аудиофайл: первые 64 КБ с CDN")
        code, ms, chunk, h = get(link, raw=True, extra={"Range": "bytes=0-65535"})
        size = h.get("Content-Range", "").split("/")[-1] or h.get("Content-Length")
        print(f"  OK {code}, {ms} мс · получено {len(chunk)} байт · весь файл ≈ "
              f"{int(size) // 1024 if size and size.isdigit() else '?'} КБ · тип {h.get('Content-Type')}")
        print("\nИТОГ: Яндекс пускает с этого IP — API и поток работают.")
    except Blocked as e:
        print(f"  СТОП — отказ: {e}")
        print("\nИТОГ: Яндекс не пустил. Дальше не долблю, чтобы не продлить бан."
              "\nСкопируй этот вывод мне (токена в нём нет).")
    except Exception as e:  # сеть, неожиданный ответ
        print(f"  ОШИБКА: {type(e).__name__}: {e}")


if __name__ == "__main__":
    main()
