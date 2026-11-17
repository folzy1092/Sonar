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
from .logs import LogGroup
from .releases import Releases
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
    logs = LogGroup(bot, con, settings.log_chat_id, settings.owner_tg_id, settings.data_thread_id)
    ctx = Ctx(bot=bot, settings=settings, accounts=Accounts(con, settings.fernet_key), shower=Shower(bot, con),
              status=status, support=Support(bot, con, settings), logs=logs, releases=Releases(con),
              bot_username=me.username or "SonarMusicApp")
    dp = Dispatcher(storage=MemoryStorage())
    dp["ctx"] = ctx
    dp.include_router(router)

    names = {"main": "Основной", "media": "Медиа", "proxy": "Прокси", "bot": "Бот", "site": "Сайт", "storage": "Хранилище",
             "soundcloud": "SoundCloud", "yandex": "Яндекс Музыка", "lrclib": "lrclib", "genius": "Genius",
             "lastfm": "Last.fm", "telegram": "Telegram"}
    marks = {"ok": "✅", "partial": "⚠️", "down": "❌"}

    async def on_status_change(key, old, new):
        await logs.event(marks[new], f"Статус: {names.get(key, key)}", lines=[f"{marks[old]} → {marks[new]}"], error=new == "down")

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
    checks = asyncio.create_task(status.loop())
    backups = asyncio.create_task(logs.backup_loop(str(settings.db_path)))
    await logs.start_icons()
    await logs.event("▶️", "Бот запущен", lines=[f"@{me.username} · пользователей: {ctx.accounts.users_count()}"])
    try:
        await dp.start_polling(bot, allowed_updates=dp.resolve_used_update_types())
    finally:
        checks.cancel()
        backups.cancel()
        await bot.session.close()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
