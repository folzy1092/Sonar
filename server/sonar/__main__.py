"""python -m sonar — запуск бота (polling). API (FastAPI) добавится сюда же, когда будет сервер."""
from __future__ import annotations

import asyncio
import logging
import sys

from aiogram import Bot, Dispatcher
from aiogram.fsm.storage.memory import MemoryStorage
from aiogram.types import BotCommand

from . import config
from .accounts import Accounts
from .bot.handlers import Ctx, router
from .bot.support import Support
from .bot.ui import Shower
from .db import connect
from .status import Status

log = logging.getLogger("sonar")


async def main() -> None:
    settings = config.load()
    if not settings.bot_token:
        sys.exit("SONAR_BOT_TOKEN пуст — заполни server/.env (пример: server/env.example)")
    con = connect(settings.db_path)
    bot = Bot(settings.bot_token)
    me = await bot.get_me()
    status = Status(con, settings.data_dir, settings, bot)
    ctx = Ctx(bot=bot, settings=settings, accounts=Accounts(con, settings.fernet_key), shower=Shower(bot, con),
              status=status, support=Support(bot, con, settings), bot_username=me.username or "SonarMusicApp")
    dp = Dispatcher(storage=MemoryStorage())
    dp["ctx"] = ctx
    dp.include_router(router)
    await bot.set_my_commands([BotCommand(command="start", description="Главное меню"),
                               BotCommand(command="status", description="Состояние Sonar")])
    log.info("бот @%s запущен, база %s", me.username, settings.db_path)
    checks = asyncio.create_task(status.loop())
    try:
        await dp.start_polling(bot, allowed_updates=dp.resolve_used_update_types())
    finally:
        checks.cancel()
        await bot.session.close()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
