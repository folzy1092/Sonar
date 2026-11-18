"""Проверка: работает ли VK Музыка с этого IP и с этим ключом.

Три шага: api.vk.com отвечает → ключ живой (users.get) → audio.search находит треки
(и CDN отдаёт поток первого из них). Запросы — POST с формой и User-Agent Kate Mobile,
как у Sonar (`windows/src-tauri/src/providers/vk.rs`), пауза между ними.

Ключ (`vk1.a.…`): переменная окружения VK_TOKEN → скрытый ввод (как пароль).
Ключ нигде не печатается и не сохраняется; из ответов VK он тоже вычищается.

Запуск (из корня репо):  VK_TOKEN=vk1.a.… python3 server/tools/check_vk.py
Код выхода: 0 — всё OK, 1 — что-то не так (строка FAIL объясняет что).
Только стандартная библиотека — ничего ставить не нужно.
"""

import getpass
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.vk.com/method"
VERSION = "5.131"
# так представляется Kate Mobile: ей VK открывает audio.*
UA = "KateMobileAndroid/56 lite-460 (Android 4.4.2; SDK 19; x86; unknown Android SDK built for x86; en)"
PAUSE = 0.5  # секунд между запросами (VK пускает до 3 в секунду)
TIMEOUT = 15
SEARCH = "Земфира"
STREAM_BYTES = 4096

# коды ошибок VK → понятный текст (как в providers/vk.rs)
AUTH_CODES = {5, 15, 25, 201, 1117}
TOO_MANY_CODES = {6, 9, 29}
CAPTCHA_CODES = {14, 17}


class Fail(Exception):
    pass


def explain(code):
    if code in AUTH_CODES:
        return "ключ VK больше не работает или без доступа к музыке — войди заново в Sonar и возьми новый"
    if code in TOO_MANY_CODES:
        return "VK просит реже — подожди минуту и запусти ещё раз"
    if code in CAPTCHA_CODES:
        return "VK просит подтвердить вход (капча) — войди в Sonar заново"
    return "VK ответил ошибкой"


def scrub(text, token):
    """Убирает ключ из любого текста, который может попасть на экран."""
    return text.replace(token, "<ключ>") if token else text


def load_token():
    token = os.environ.get("VK_TOKEN", "").strip()
    if not token:
        token = getpass.getpass("Вставь ключ VK (vk1.a.…, ввод не виден) и нажми Enter: ").strip()
    if not token:
        sys.exit("FAIL: ключ пустой — задай VK_TOKEN или вставь его при запросе.")
    return token


def call(method, params, token=None):
    """Метод API VK: POST с формой (ключ в теле, не в адресе). Возвращает (response, мс)."""
    form = {**params, "v": VERSION}
    if token:
        form["access_token"] = token
    body = urllib.parse.urlencode(form).encode()
    req = urllib.request.Request(
        f"{API}/{method}", data=body, method="POST",
        headers={"User-Agent": UA, "Content-Type": "application/x-www-form-urlencoded"},
    )
    started = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            raw = r.read(500_000)
    except urllib.error.HTTPError as e:
        raise Fail(f"HTTP {e.code} от api.vk.com")
    except (urllib.error.URLError, OSError) as e:
        reason = getattr(e, "reason", e)
        raise Fail(f"нет связи с api.vk.com: {scrub(str(reason), token)}")
    ms = int((time.monotonic() - started) * 1000)
    try:
        data = json.loads(raw or b"null")
    except ValueError:
        raise Fail("api.vk.com ответил не JSON")
    error = (data or {}).get("error") if isinstance(data, dict) else None
    if error:
        code = error.get("error_code")
        # текст ошибки VK не печатаем целиком: в нём бывают параметры запроса
        raise Fail(f"{method}: код {code} — {explain(code)}")
    return (data or {}).get("response"), ms


def check_stream(url):
    """Первые байты потока с CDN тем же User-Agent. Адрес не печатаем — только хост."""
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Range": f"bytes=0-{STREAM_BYTES - 1}"})
    host = urllib.parse.urlsplit(url).hostname
    started = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            chunk = r.read(STREAM_BYTES)
            kind = r.headers.get("Content-Type")
    except urllib.error.HTTPError as e:
        raise Fail(f"CDN {host}: HTTP {e.code}")
    except (urllib.error.URLError, OSError) as e:
        raise Fail(f"CDN {host}: нет связи ({getattr(e, 'reason', e)})")
    ms = int((time.monotonic() - started) * 1000)
    text = chunk.decode("utf-8", "replace")
    if text.startswith("#EXTM3U"):
        aes = "AES-128" if "METHOD=AES-128" in text else "без шифрования"
        return f"HLS ({aes}) с {host}, {ms} мс"
    return f"{len(chunk)} байт ({kind}) с {host}, {ms} мс"


def step(n, title):
    print(f"\n[{n}/4] {title}")


def run(token):
    step(1, "Связь: api.vk.com (utils.getServerTime, без ключа)")
    server_time, ms = call("utils.getServerTime", {})
    print(f"  OK {ms} мс · время сервера VK: {server_time}")
    time.sleep(PAUSE)

    step(2, "Ключ: users.get")
    users, ms = call("users.get", {}, token)
    me = (users or [{}])[0]
    name = " ".join(filter(None, [me.get("first_name"), me.get("last_name")])) or "?"
    print(f"  OK {ms} мс · аккаунт: {name} (id {me.get('id')})")
    time.sleep(PAUSE)

    step(3, f"Поиск: audio.search «{SEARCH}»")
    found, ms = call("audio.search", {"q": SEARCH, "count": "3", "auto_complete": "1", "sort": "2"}, token)
    items = (found or {}).get("items") or []
    if not items:
        raise Fail("audio.search ответил, но треков нет — у ключа нет доступа к музыке?")
    first = items[0]
    print(f"  OK {ms} мс · найдено: {(found or {}).get('count')} · первый: "
          f"{first.get('artist')} — {first.get('title')}")
    time.sleep(PAUSE)

    step(4, "Поток первого трека с CDN")
    url = first.get("url") or ""
    if not url or "audio_api_unavailable" in url:
        raise Fail("VK не отдал ссылку на поток — ключ не от Kate Mobile или трек закрыт")
    print(f"  OK {check_stream(url)}")


def main():
    token = load_token()
    print(f"Ключ: найден ({len(token)} символов)")
    try:
        run(token)
    except Fail as e:
        print(f"  FAIL: {scrub(str(e), token)}")
        print("\nИТОГ: FAIL — VK Музыка с этого IP/ключа не работает. Вывод можно присылать: ключа в нём нет.")
        return 1
    except Exception as e:  # неожиданный ответ — без текста запроса
        print(f"  FAIL: {type(e).__name__}: {scrub(str(e), token)}")
        print("\nИТОГ: FAIL — неожиданный ответ VK.")
        return 1
    print("\nИТОГ: OK — api.vk.com доступен, ключ живой, поиск и поток работают.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
