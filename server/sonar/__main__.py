"""python -m sonar — бот (polling) и в том же процессе HTTP: админка `/admin` и API (`sonar/web.py`)."""
from __future__ import annotations

import asyncio
import contextlib
import logging
import os
import sys

from aiogram import Bot, Dispatcher
from aiogram.fsm.storage.memory import MemoryStorage
from aiogram.types import BotCommand

from . import config
from .accounts import Accounts
from . import bans
from .bot.handlers import Ctx, announce_update, router
from .bot.moderation import router as moderation_router
from .bot.support import Support
from .bot.ui import Shower
from .db import connect
from .logs import LogGroup
from .releases import Releases
from .status import Status
from .status_alert import MARKS, alert_lines, alert_title
from .updater import Updater

log = logging.getLogger("sonar")


async def serve_web(con, settings, status, ctx) -> None:
    """Админка и API на PORT. Локально — 127.0.0.1; на хостинге deploy/sync.py ставит SONAR_HTTP_HOST=0.0.0.0."""
    import uvicorn

    from .bot.handlers import telegram_linked
    from .web import create_app
    host = os.getenv("SONAR_HTTP_HOST", "127.0.0.1")
    app = create_app(con, settings, status, accounts=ctx.accounts, bot_username=ctx.bot_username,
                     updater=ctx.updater)
    app.state.on_telegram_linked = lambda tg_id, user: telegram_linked(ctx, tg_id, user)
    server = uvicorn.Server(uvicorn.Config(app, host=host, port=settings.port,
                                           log_level="warning", proxy_headers=True))
    # Сигналы (Ctrl+C) ловит бот; uvicorn свои обработчики не ставит.
    server.capture_signals = contextlib.nullcontext
    log.info("HTTP: http://%s:%s/admin/", host, settings.port)
    await server.serve()


async def bans_loop(con, every_s: int = 60) -> None:
    """Временные баны снимаются сами: остальной код смотрит просто на `banned = 0` (bans.py)."""
    while True:
        try:
            for uid in bans.expire(con):
                log.info("срок бана вышел: %s", uid)
        except Exception:  # noqa: BLE001
            log.exception("снятие просроченных банов")
        await asyncio.sleep(every_s)


async def main() -> Updater:
    """Возвращает Updater: если из бота или админки запросили перезапуск, `finish()` делает его после выхода из цикла."""
    settings = config.load()
    if not settings.bot_token:
        sys.exit("SONAR_BOT_TOKEN пуст — заполни server/.env (пример: server/env.example)")
    con = connect(settings.db_path)
    bot = Bot(settings.bot_token)
    me = await bot.get_me()
    status = Status(con, settings.data_dir, settings, bot)
    logs = LogGroup(bot, con, settings.log_chat_id, settings.owner_tg_id, settings.data_thread_id)
    ctx = Ctx(bot=bot, settings=settings, accounts=Accounts(con, settings.fernet_key), shower=Shower(bot, con),
              status=status, support=Support(bot, con, settings), logs=logs, releases=Releases(con),
              bot_username=me.username or "SonarMusicApp")
    dp = Dispatcher(storage=MemoryStorage())
    ctx.updater = Updater(settings.data_dir, dp)
    dp["ctx"] = ctx
    dp.include_router(moderation_router)   # раньше основного: там есть «поймать всё» для личных сообщений
    dp.include_router(router)

    async def on_status_change(change):
        await logs.event(MARKS[change.new], alert_title(change), lines=alert_lines(change), error=change.new == "down")

    status.on_change = on_status_change

    @dp.errors()
    async def on_error(event):
        upd = event.update
        who = (upd.message or upd.callback_query or upd.edited_message)
        log.exception("ошибка в обработчике", exc_info=event.exception)
        await logs.error("Ошибка в боте", event.exception, getattr(who, "from_user", None))
        return True
    await bot.set_my_commands([BotCommand(command="start", description="Главное меню"),
                               BotCommand(command="status", description="Состояние Sonar")])
    log.info("бот @%s запущен, база %s", me.username, settings.db_path)
    web = asyncio.create_task(serve_web(con, settings, status, ctx))
    checks = asyncio.create_task(status.loop())
    backups = asyncio.create_task(logs.backup_loop(str(settings.db_path)))
    expiry = asyncio.create_task(bans_loop(con))
    await logs.start_icons()
    await logs.event("▶️", "Бот запущен", lines=[f"@{me.username} · пользователей: {ctx.accounts.users_count()}"])
    await announce_update(ctx)
    try:
        await dp.start_polling(bot, allowed_updates=dp.resolve_used_update_types())
    finally:
        checks.cancel()
        backups.cancel()
        expiry.cancel()
        web.cancel()
        await bot.session.close()
    return ctx.updater


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    try:
        asyncio.run(main()).finish()
    except KeyboardInterrupt:
        pass
