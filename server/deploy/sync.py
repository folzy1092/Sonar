"""Запуск сервера Sonar на хостинге (Velt): в корне контейнера лежат только этот файл и `.env`.

Стартовая команда панели: `python sync.py`. При каждом старте:
1. читает `.env` рядом с собой (переменные панели важнее);
2. спрашивает у GitHub последний коммит ветки и, если он новый, скачивает архив репо и
   берёт из него только папку `server/` (git на хостинге не нужен; GITHUB_TOKEN — по желанию);
3. обновляет сам себя из `server/deploy/sync.py`, если тот поменялся;
4. ставит зависимости `requirements-run.txt` в свой venv — только когда файл поменялся;
5. запускает `python -m sonar` (бот + HTTP на PORT).

Раскладка в контейнере:
    sync.py  .env        — кладёт владелец
    app/                 — код `server/` из репо (заменяется целиком при обновлении)
    data/                — база и файлы (SONAR_DATA_DIR), обновление её не трогает
    .venv/               — зависимости

Нет сети или GitHub не ответил — запускается уже скачанная версия.
Только стандартная библиотека: зависимостей ещё нет, когда он стартует.
"""
from __future__ import annotations

import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import time
import urllib.error
import urllib.request
from pathlib import Path

HOME = Path(__file__).resolve().parent
APP = HOME / "app"
VENV = HOME / ".venv"
TAG = "[sync]"


def say(text: str) -> None:
    print(f"{TAG} {text}", flush=True)


def load_env(path: Path) -> None:
    """KEY=VALUE из .env в окружение; уже заданное панелью не перезаписывается."""
    if not path.is_file():
        say(f".env не найден ({path}) — беру только переменные панели")
        return
    for raw in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip().removeprefix("export ").strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if key:
            os.environ.setdefault(key, value)


def repo() -> str:
    return os.environ.get("SONAR_REPO", "folzy1092/Sonar").strip()


def branch() -> str:
    return os.environ.get("SONAR_BRANCH", "main").strip()


def token() -> str:
    """GITHUB_TOKEN (fine-grained, Contents: read) — нужен, только если репо станет приватным
    или упрёмся в лимит GitHub без токена (60 запросов в час с IP). Нигде не печатается."""
    return os.environ.get("GITHUB_TOKEN", "").strip()


def http_get(url: str, accept: str = "*/*", timeout: float = 30) -> bytes:
    headers = {"Accept": accept, "User-Agent": "sonar-sync"}
    if token() and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token()}"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read()
    except urllib.error.HTTPError as error:
        hint = " — проверь GITHUB_TOKEN" if error.code in (401, 403, 404) and token() else ""
        raise RuntimeError(f"GitHub ответил {error.code}{hint}") from None


def remote_sha() -> str:
    url = f"https://api.github.com/repos/{repo()}/commits/{branch()}"
    sha = http_get(url, accept="application/vnd.github.sha", timeout=15).decode().strip()
    if len(sha) != 40:
        raise RuntimeError(f"GitHub вернул не хэш коммита: {sha[:60]!r}")
    return sha


def local_sha() -> str:
    try:
        return (APP / ".sha").read_text().strip()
    except OSError:
        return ""


def extract_server(archive: bytes, dest: Path) -> int:
    """Распаковать из архива GitHub только `<корень>/server/…` в dest. Возвращает число файлов."""
    count = 0
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as tar:
        for member in tar.getmembers():
            parts = member.name.split("/")
            if len(parts) < 3 or parts[1] != "server" or not parts[2]:
                continue
            rel = parts[2:]
            if any(p in ("", ".", "..") for p in rel) or rel[0] in ("data", ".env"):
                continue
            if not (member.isfile() or member.isdir()):
                continue  # ссылки и прочее из архива не берём
            target = dest.joinpath(*rel)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            src = tar.extractfile(member)
            if src is None:
                continue
            with src, open(target, "wb") as out:
                shutil.copyfileobj(src, out)
            count += 1
    return count


def install_app(sha: str, archive: bytes) -> None:
    """Новая версия кладётся в app.new и меняется местами с app — без полупустой папки."""
    new, old = HOME / "app.new", HOME / "app.old"
    for p in (new, old):
        shutil.rmtree(p, ignore_errors=True)
    new.mkdir()
    files = extract_server(archive, new)
    if not (new / "sonar" / "__main__.py").is_file():
        shutil.rmtree(new, ignore_errors=True)
        raise RuntimeError("в архиве нет server/sonar — обновление отменено")
    (new / ".sha").write_text(sha)
    if APP.exists():
        APP.rename(old)
    new.rename(APP)
    shutil.rmtree(old, ignore_errors=True)
    say(f"код обновлён до {sha[:8]} ({files} файлов)")


def update_code() -> None:
    have = local_sha()
    try:
        sha = remote_sha()
    except Exception as error:
        say(f"GitHub не ответил ({error}); запускаю текущую версию {have[:8] or '—'}")
        return
    if sha == have and (APP / "sonar").is_dir():
        say(f"код актуален ({sha[:8]})")
        return
    started = time.monotonic()
    # С токеном — через API (подходит и для приватного репо), без — прямой архив.
    url = (f"https://api.github.com/repos/{repo()}/tarball/{sha}" if token()
           else f"https://codeload.github.com/{repo()}/tar.gz/{sha}")
    try:
        install_app(sha, http_get(url, timeout=120))
    except Exception as error:
        say(f"обновление не выполнено ({error}); запускаю текущую версию {have[:8] or '—'}")
        return
    say(f"скачано за {time.monotonic() - started:.1f} с")


def self_update() -> None:
    """Новый sync.py из репо заменяет этот файл и перезапускается (один раз за старт)."""
    fresh = APP / "deploy" / "sync.py"
    me = Path(__file__).resolve()
    if os.environ.get("SONAR_SYNC_REEXEC") or not fresh.is_file():
        return
    if fresh.read_bytes() == me.read_bytes():
        return
    shutil.copyfile(fresh, me)
    os.environ["SONAR_SYNC_REEXEC"] = "1"
    say("sync.py обновился — перезапускаю его")
    os.execv(sys.executable, [sys.executable, str(me), *sys.argv[1:]])


def venv_python() -> Path:
    return VENV / ("Scripts/python.exe" if os.name == "nt" else "bin/python")


def python_for_app() -> tuple[str, list[str]]:
    """Свой venv; если хостинг его не умеет — системный Python и `pip --user`."""
    if not venv_python().is_file():
        try:
            subprocess.run([sys.executable, "-m", "venv", str(VENV)], check=True, timeout=180)
            say("создан venv")
        except Exception as error:
            shutil.rmtree(VENV, ignore_errors=True)
            say(f"venv не создался ({error}); ставлю в пользовательский каталог")
            return sys.executable, ["--user"]
    return str(venv_python()), []


def install_deps(python: str, extra: list[str]) -> None:
    req = APP / "requirements-run.txt"
    if not req.is_file():
        say("requirements-run.txt не найден — зависимости не ставлю")
        return
    digest = hashlib.sha256(req.read_bytes() + python.encode() + sys.version.encode()).hexdigest()
    marker = HOME / ".deps.sha256"
    if marker.is_file() and marker.read_text().strip() == digest:
        say("зависимости не менялись")
        return
    say("ставлю зависимости")
    started = time.monotonic()
    subprocess.run([python, "-m", "pip", "install", "--disable-pip-version-check", "--no-cache-dir",
                    *extra, "-r", str(req)], check=True, timeout=600)
    marker.write_text(digest)
    say(f"зависимости установлены за {time.monotonic() - started:.1f} с")


def check_yandex(python: str) -> None:
    """SONAR_CHECK_YM=1 — перед стартом проверить, пускает ли Яндекс с этого IP (нужен YANDEX_TOKEN)."""
    if os.environ.get("SONAR_CHECK_YM", "").strip() not in ("1", "true", "yes"):
        return
    tool = APP / "tools" / "check_ym.py"
    if not os.environ.get("YANDEX_TOKEN"):
        say("SONAR_CHECK_YM=1, но YANDEX_TOKEN пуст — проверку Яндекса пропускаю")
        return
    say("проверка Яндекса с этого IP:")
    try:
        subprocess.run([python, str(tool)], cwd=str(APP), timeout=120, stdin=subprocess.DEVNULL)
    except Exception as error:
        say(f"проверка не прошла до конца: {error}")


def main() -> int:
    load_env(HOME / ".env")
    os.environ.setdefault("SONAR_DATA_DIR", str(HOME / "data"))
    os.environ.setdefault("SONAR_HTTP_HOST", "0.0.0.0")
    os.environ.setdefault("MALLOC_ARENA_MAX", "2")
    os.environ.setdefault("PYTHONUNBUFFERED", "1")
    say(f"{repo()} · ветка {branch()} · порт {os.environ.get('PORT') or os.environ.get('SERVER_PORT') or '—'}")
    if not os.environ.get("PORT") and os.environ.get("SERVER_PORT"):
        os.environ["PORT"] = os.environ["SERVER_PORT"]  # переменная Pterodactyl
    update_code()
    if not (APP / "sonar" / "__main__.py").is_file():
        say("кода сервера нет и скачать не удалось — запуск остановлен")
        return 1
    self_update()
    python, extra = python_for_app()
    try:
        install_deps(python, extra)
    except Exception as error:
        say(f"зависимости не поставились: {error}")
        if not (HOME / ".deps.sha256").is_file():
            return 1
        say("запускаю с прежними зависимостями")
    check_yandex(python)
    os.chdir(APP)
    say("запуск python -m sonar")
    os.execv(python, [python, "-m", "sonar"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
