"""Проверка: пускает ли Spotify с этого IP и подходит ли ключ sp_dc (как в Sonar, API.md §2 «Spotify»).

Аккуратно: 4 шага, пауза между ними, остановка на первом отказе.
  1. open.spotify.com отвечает (без ключа);
  2. токен веб-плеера по sp_dc и TOTP (тот же шифр, что вшит в клиенты);
  3. аккаунт /v1/me (есть ли Premium);
  4. поиск трека через Web API.
Ключ sp_dc (по порядку): переменная окружения SP_DC → скрытый ввод (как пароль). Можно вставить как есть,
с «sp_dc=» или всей строкой cookie. Ключ и токен нигде не печатаются и не сохраняются.

Запуск (из корня репо):  SP_DC=… python3 server/tools/check_sp.py
Только стандартная библиотека — ничего ставить не нужно.
"""

import getpass
import hashlib
import hmac
import json
import os
import string
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

WEB = "https://open.spotify.com"
API = "https://api.spotify.com/v1"
PAUSE = 2.0  # секунд между запросами — не спешим
SEARCH = "Daft Punk One More Time"
STEPS = 4
TOTP_STEP = 30
MIN_SP_DC = 20

# Шифр TOTP веб-плеера: версия и байты — как `default_totp` в windows/src-tauri/src/providers/spotify.rs
# и `Spotify.TotpSecret.default` на iPhone. Потом — с сервера (`GET /config` → spotify_totp).
TOTP_VER = 5
TOTP_CIPHER = [12, 56, 76, 33, 88, 44, 88, 33, 78, 78, 11, 66, 22, 22, 55, 69, 54]

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
SP_DC_CHARS = set(string.ascii_letters + string.digits + "-_")

STALE = "ключ веб-плеера устарел — шифр TOTP сменился, нужен новый в providers/spotify.rs и Spotify.swift"


class Stop(Exception):
    pass


def totp_key(cipher):
    """Каждый байт XOR ((i % 33) + 9), числа подряд десятичной строкой."""
    return "".join(str(b ^ ((i % 33) + 9)) for i, b in enumerate(cipher)).encode()


def totp(key, unix_secs):
    """RFC 6238: HMAC-SHA1, 6 цифр, шаг 30 с."""
    digest = hmac.new(key, struct.pack(">Q", unix_secs // TOTP_STEP), hashlib.sha1).digest()
    offset = digest[-1] & 0x0F
    code = struct.unpack(">I", digest[offset:offset + 4])[0] & 0x7FFFFFFF
    return f"{code % 1_000_000:06d}"


def normalize_sp_dc(raw):
    raw = raw.strip()
    parts = [p.strip() for p in raw.split(";")]
    value = next((p[len("sp_dc="):] for p in parts if p.startswith("sp_dc=")), raw.rstrip(";"))
    value = value.strip().strip('"')
    ok = len(value) >= MIN_SP_DC and all(c in SP_DC_CHARS for c in value)
    return value if ok else None


def self_test():
    """Тот же шифр и те же векторы, что в тестах Rust и Swift — без сети."""
    rfc = b"12345678901234567890"
    assert totp(rfc, 59) == "287082" and totp(rfc, 1_111_111_109) == "081804", "TOTP не сходится с RFC 6238"
    key = totp_key(TOTP_CIPHER)
    assert key == b"5507145853487499592248630329347", "ключ из шифра не тот"
    assert totp(key, 1_700_000_000) == "863172", "TOTP шифра не тот"


def load_sp_dc():
    raw = os.environ.get("SP_DC", "")
    if not raw.strip():
        raw = getpass.getpass("Вставь cookie sp_dc с open.spotify.com (ввод не виден) и нажми Enter: ")
    sp_dc = normalize_sp_dc(raw)
    if not sp_dc:
        sys.exit("Это не похоже на sp_dc (нужно значение cookie sp_dc с open.spotify.com) — выхожу.")
    return sp_dc


def request(url, headers, raw=False):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json", **headers})
    started = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            body = r.read(300_000)
            ms = int((time.monotonic() - started) * 1000)
            return r.status, ms, body if raw else json.loads(body or b"null")
    except urllib.error.HTTPError as e:
        ms = int((time.monotonic() - started) * 1000)
        # тело ошибки не печатаем целиком: там может быть что угодно, а ключ — точно не нужен
        snippet = e.read(300).decode("utf-8", "replace").replace("\n", " ")
        return e.code, ms, snippet
    except urllib.error.URLError as e:
        raise Stop(f"сеть недоступна: {e.reason}") from None


def step(n, title):
    print(f"\n[{n}/{STEPS}] {title}")


def check_web():
    code, ms, _ = request(f"{WEB}/", {"Accept": "text/html"}, raw=True)
    if code >= 400:
        raise Stop(f"open.spotify.com ответил HTTP {code} за {ms} мс")
    print(f"  OK {code}, {ms} мс")


def web_token(sp_dc):
    code_now = totp(totp_key(TOTP_CIPHER), int(time.time()))
    query = urllib.parse.urlencode({
        "reason": "init", "productType": "web-player",
        "totp": code_now, "totpServer": code_now, "totpVer": TOTP_VER,
    })
    code, ms, data = request(f"{WEB}/api/token?{query}", {"Cookie": f"sp_dc={sp_dc}"})
    text = data if isinstance(data, str) else json.dumps(data)
    # «totp» ищем только в ответе с ошибкой: в удачном случайный accessToken может его содержать
    if code == 400 or (not 200 <= code < 300 and "totp" in text.lower()):
        raise Stop(f"HTTP {code} за {ms} мс: {STALE}")
    if code >= 400:
        raise Stop(f"HTTP {code} за {ms} мс")
    token = (data or {}).get("accessToken")
    if not token or (data or {}).get("isAnonymous"):
        raise Stop(f"HTTP {code} за {ms} мс, но токен анонимный — sp_dc не подошёл, войди заново")
    left = int(((data or {}).get("accessTokenExpirationTimestampMs", 0) / 1000 - time.time()) // 60)
    print(f"  OK {code}, {ms} мс · токен получен (живёт ещё ~{left} мин)")
    return token


def api(path, token):
    code, ms, data = request(f"{API}{path}", {"Authorization": f"Bearer {token}"})
    if code >= 400:
        raise Stop(f"{path}: HTTP {code} за {ms} мс: {str(data)[:200]}")
    return code, ms, data


def main():
    self_test()
    sp_dc = load_sp_dc()
    print(f"Ключ sp_dc: найден ({len(sp_dc)} символов)")
    try:
        step(1, "open.spotify.com")
        check_web()
        time.sleep(PAUSE)

        step(2, f"Токен веб-плеера (TOTP v{TOTP_VER})")
        token = web_token(sp_dc)
        time.sleep(PAUSE)

        step(3, "Аккаунт: /v1/me")
        code, ms, me = api("/me", token)
        premium = (me or {}).get("product") == "premium"
        print(f"  OK {code}, {ms} мс · имя: {(me or {}).get('display_name')} · страна: {(me or {}).get('country')}"
              f" · Premium: {premium}")
        time.sleep(PAUSE)

        step(4, f"Поиск: «{SEARCH}»")
        q = urllib.parse.urlencode({"q": SEARCH, "type": "track", "limit": 3})
        code, ms, found = api(f"/search?{q}", token)
        items = ((found or {}).get("tracks") or {}).get("items") or []
        if not items:
            print(f"  {code}, {ms} мс, но треков нет — поиск пустой")
            return
        for t in items:
            artists = ", ".join(a.get("name", "") for a in t.get("artists") or [])
            print(f"  · sp:{t.get('id')} — {artists} — {t.get('name')}")
    except Stop as e:
        print(f"  СТОП: {e}")
        sys.exit(1)

    print("\nИтог: Spotify отвечает, ключ подходит — медиатека и поиск в Sonar будут работать.")
    if not premium:
        print("Premium нет — играть Spotify не будет, треки сыграет резервный сервис.")


if __name__ == "__main__":
    main()
