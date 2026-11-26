"""Обновление частей сервера без панели хостинга: бот (`/update`) и админка («Сервер»).

Что обновляется отдельно, а что нет:
- **сайт** (`site/`, архив из релиза `site-latest`) — на лету, процесс не перезапускается;
- **сервер** (`server/`: бот, API и админка — один процесс, одна база и один порт) — скачать код и перезапустить
  процесс; бот и API по отдельности не обновить, пока это один процесс;
- зависимости и сам `sync.py` едут вместе с сервером;
- **перезапуск** без обновления — подхватить правки `.env`.

Как перезапуск: полный рестарт контейнера не нужен (как в lengubot `self_update.py`). Останавливаем опрос бота,
`main()` дочищает за собой, и `finish()` делает `os.execv(sync.py)` — тот же PID, контейнер не перезапускается.
`sync.py` при этом получает `SONAR_SYNC_SKIP`: что на этом старте пропустить (при «только сервер» — сайт,
при «просто перезапустить» — и код, и сайт). Итог пишется в `data/update_result.json`, а в Telegram — сообщение
«Обновляю…» правится на итог после старта (`bot/handlers.py` `announce_update`).

`sync.py` лежит в корне контейнера (`SONAR_HOME` ставит он сам), поэтому его подгружаем по пути, а не импортом.
Без `SONAR_HOME` (локальная разработка, тесты) `available()` ложно, и обновлять нечего.
"""
from __future__ import annotations

import asyncio
import importlib.util
import json
import logging
import os
import sys
import time
from pathlib import Path
from types import ModuleType

log = logging.getLogger("sonar.updater")

CACHE_S = 30           # сколько держать ответ GitHub: у запросов без токена лимит 60 в час
STATE_FILE = "update_state.json"
RESULT_FILE = "update_result.json"
STOP_TRIES = 20
STOP_DELAY_S = 1.0     # ответ бота и админки успевает уйти раньше, чем встанет опрос
STOP_RETRY_S = 0.5
WHATS = ("server", "all", "restart")
# Что sync.py пропускает на старте после перезапуска.
SKIP = {"server": "site", "all": "", "restart": "code,site"}


def short(sha: str | None) -> str:
    return (sha or "")[:8] or "—"


class Updater:
    def __init__(self, data_dir: Path, dp=None):
        self.data_dir = Path(data_dir)
        self.dp = dp                       # Dispatcher бота: его опрос останавливаем перед перезапуском
        self.restarting = False
        self._plan: dict = {}
        self._cache: tuple[float, dict] | None = None
        self._lock = asyncio.Lock()
        self._task: asyncio.Task | None = None

    # ---- sync.py ----

    def _sync_path(self) -> Path | None:
        home = os.environ.get("SONAR_HOME", "").strip()
        path = Path(home) / "sync.py" if home else None
        return path if path and path.is_file() else None

    def available(self) -> bool:
        return self._sync_path() is not None

    def _module(self) -> ModuleType:
        """Свежий sync.py с диска: он мог обновиться сам, пока процесс работает."""
        path = self._sync_path()
        if path is None:
            raise RuntimeError("не на хостинге: нет sync.py (SONAR_HOME)")
        spec = importlib.util.spec_from_file_location("sonar_deploy_sync", path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    # ---- что стоит и что на GitHub ----

    def current(self) -> dict:
        """Без сети: коммит кода и версия сайта на диске."""
        try:
            module = self._module()
            return {"sha": module.local_sha(), "site": module.site_have()}
        except Exception:  # noqa: BLE001
            return {"sha": "", "site": ""}

    async def check(self, force: bool = False) -> dict:
        """`sync.status()` — по каждой части have / remote / new, либо ошибка. 30 секунд держим в памяти."""
        if not force and self._cache and time.monotonic() - self._cache[0] < CACHE_S:
            return self._cache[1]
        status = await asyncio.to_thread(lambda: self._module().status())
        self._cache = (time.monotonic(), status)
        return status

    def forget(self) -> None:
        self._cache = None

    # ---- сайт: на лету ----

    async def update_site(self) -> str:
        """`updated` / `same` / `none` / `failed` — как у `sync.update_site()`."""
        async with self._lock:
            state = await asyncio.to_thread(lambda: self._module().update_site())
        self.forget()
        return state

    # ---- сервер и перезапуск ----

    def request_restart(self, what: str, *, source: str, by: str = "", chat_id: int | None = None,
                        message_id: int | None = None) -> bool:
        """Остановить опрос бота и перезапустить процесс. False — уже идёт или обновлять нечем."""
        if what not in WHATS or self.restarting or not self.available() or self.dp is None:
            return False
        cached = self._cache[1] if self._cache else {}
        code = cached.get("code") or {}
        self.restarting = True
        self._plan = {"what": what, "skip": SKIP[what], "source": source, "by": by, "chat_id": chat_id,
                      "message_id": message_id, "at": time.time(), "old": self.current()["sha"],
                      "target": code.get("remote", "") if what != "restart" else ""}
        self._task = asyncio.get_running_loop().create_task(self._stop())
        return True

    async def _stop(self) -> None:
        await asyncio.sleep(STOP_DELAY_S)
        for _ in range(STOP_TRIES):
            try:
                await self.dp.stop_polling()
                return
            except RuntimeError:           # опрос ещё не начался или уже кончился
                await asyncio.sleep(STOP_RETRY_S)
            except Exception:  # noqa: BLE001
                log.exception("не удалось остановить опрос бота")
                break
        log.error("перезапуск отменён: опрос бота не остановился")
        self.restarting = False

    def finish(self) -> None:
        """После остановки опроса и `asyncio.run`: запомнить план и перезапустить процесс через sync.py.
        Не запрошено — ничего не делает (обычная остановка)."""
        if not self.restarting:
            return
        path = self._sync_path()
        if path is None:
            return
        self._write(STATE_FILE, self._plan)
        # Флаг повторного запуска остался бы от прошлого старта и запретил sync.py обновить самого себя.
        os.environ.pop("SONAR_SYNC_REEXEC", None)
        os.environ["SONAR_SYNC_SKIP"] = self._plan["skip"]
        log.info("перезапуск через sync.py (%s, пропуск: %s)", self._plan["what"], self._plan["skip"] or "—")
        for stream in (sys.stdout, sys.stderr):
            try:
                stream.flush()
            except Exception:  # noqa: BLE001
                pass
        os.execv(sys.executable, [sys.executable, str(path)])

    # ---- итог после старта ----

    def take_result(self) -> dict | None:
        """Первый старт после перезапуска: сверить коммит с целью и записать итог. Нет плана — None."""
        path = self.data_dir / STATE_FILE
        try:
            plan = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        try:
            path.unlink()
        except OSError:
            pass
        current = self.current()["sha"]
        target = plan.get("target") or ""
        what = plan.get("what")
        # ok: перезапуск без обновления всегда удался; иначе версия должна совпасть. Цель неизвестна (GitHub не
        # ответил при нажатии) — честно None, а не «всё хорошо».
        ok = True if what == "restart" else (current == target if target else None)
        result = {**plan, "current": current, "ok": ok, "done_at": time.time()}
        self._write(RESULT_FILE, result)
        return result

    def last_result(self) -> dict | None:
        try:
            return json.loads((self.data_dir / RESULT_FILE).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None

    def _write(self, name: str, data: dict) -> None:
        try:
            self.data_dir.mkdir(parents=True, exist_ok=True)
            tmp = self.data_dir / f"{name}.tmp"
            tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
            os.replace(tmp, self.data_dir / name)
        except OSError:
            log.exception("не записал %s", name)
