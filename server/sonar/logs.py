"""Лог-группа владельца (SONAR_LOG_CHAT_ID, форум): как у LGU-бота и selfbot (их log_topic.py).

* Свои темы бот создаёт сам: «Sonar» — события, «Sonar · Ошибки» — ошибки. ID тем — в kv
  (`topic:<chat>:<имя>`); тему удалили — создаётся заново, отправка повторяется один раз.
* Темы нельзя создать (не форум, нет права can_manage_topics) — пишем в General, новая попытка
  не раньше чем через RETRY_S.
* Иконки: цвет задаётся только при создании, эмодзи — editForumTopic из стандартного набора.
* Бэкап базы — раз в сутки только в общую тему «Data» (её создал другой бот, а Bot API не умеет
  искать темы по имени, поэтому ID — config.DATA_THREAD_ID или SONAR_DATA_THREAD_ID).
* Лог никогда не ломает бота: любая ошибка здесь проглатывается.
"""
from __future__ import annotations

import asyncio
import logging
import os
import sqlite3
import tempfile
import time
import zipfile
from datetime import datetime
from html import escape

from aiogram import Bot
from aiogram.types import FSInputFile, User as TgUser

from .db import kv_get, kv_set

log = logging.getLogger("sonar.logs")

TOPIC = "Sonar"
ERROR_TOPIC = f"{TOPIC} · Ошибки"
RETRY_S = 300
GONE = ("thread not found", "topic_deleted", "topic_id_invalid")
ICONS = {TOPIC: ("🎵", "🎧", "🎶"), ERROR_TOPIC: ("❗", "‼", "🔥")}
BACKUP_EVERY_S = 86400


def person(u: TgUser | None, owner_id: int | None = None) -> str:
    """«@user | ID: 1»; владелец — DEV, чтобы не пинговать его в группе."""
    if u is None:
        return "неизвестно"
    if owner_id and u.id == owner_id:
        return f"DEV | ID: <code>{u.id}</code>"
    handle = f"@{u.username}" if u.username else u.full_name
    return f"{escape(handle)} | ID: <code>{u.id}</code>"


def _plain(e: str) -> str:
    return e.replace("️", "")


class LogGroup:
    def __init__(self, bot: Bot, con: sqlite3.Connection, chat_id: int | None, owner_id: int | None = None,
                 data_thread_id: int | None = None):
        self.bot, self.con, self.chat_id, self.owner_id = bot, con, chat_id, owner_id
        self.data_thread_id = data_thread_id
        self._blocked: dict[str, float] = {}
        self._icon_ids: dict[str, str] | None = None
        self._lock = asyncio.Lock()

    # ---- темы ----

    async def _icon(self, name: str, thread: int) -> None:
        key = f"topic-icon:{self.chat_id}:{name}"
        if (kv_get(self.con, key) or "").split(":")[0] == str(thread):
            return
        try:
            if self._icon_ids is None:
                stickers = await self.bot.get_forum_topic_icon_stickers()
                self._icon_ids = {_plain(s.emoji or ""): s.custom_emoji_id for s in stickers}
            icon = next((self._icon_ids[_plain(e)] for e in ICONS.get(name, ()) if _plain(e) in self._icon_ids), None)
            if icon:
                await self.bot.edit_forum_topic(chat_id=self.chat_id, message_thread_id=thread, icon_custom_emoji_id=icon)
            kv_set(self.con, key, f"{thread}:{icon}")
        except Exception as e:  # noqa: BLE001
            log.warning("иконка темы %s не поставлена: %s", name, e)
            kv_set(self.con, key, f"{thread}:fail")

    async def thread(self, name: str) -> int | None:
        key = f"topic:{self.chat_id}:{name}"
        async with self._lock:
            known = kv_get(self.con, key)
            if known:
                return int(known)
            if time.monotonic() < self._blocked.get(key, 0):
                return None
            try:
                topic = await self.bot.create_forum_topic(chat_id=self.chat_id, name=name)
            except Exception as e:  # noqa: BLE001
                self._blocked[key] = time.monotonic() + RETRY_S
                log.warning("тема %s не создана: %s", name, e)
                return None
            kv_set(self.con, key, str(topic.message_thread_id))
        await self._icon(name, topic.message_thread_id)
        return topic.message_thread_id

    def _forget(self, name: str) -> None:
        self.con.execute("DELETE FROM kv WHERE key = ?", (f"topic:{self.chat_id}:{name}",))

    async def _send(self, name: str, method, **kw):
        thread = await self.thread(name)
        try:
            return await method(chat_id=self.chat_id, message_thread_id=thread, **kw)
        except Exception as e:  # noqa: BLE001
            if not thread or not any(g in str(e).lower() for g in GONE):
                raise
        self._forget(name)
        return await method(chat_id=self.chat_id, message_thread_id=await self.thread(name), **kw)

    # ---- события ----

    async def event(self, icon: str, title: str, user: TgUser | None = None, lines: list[str] | None = None,
                    error: bool = False) -> None:
        if not self.chat_id:
            return
        parts = [f"{icon} <b>{escape(title)}</b>"]
        if user is not None:
            parts.append(f"Кто: {person(user, self.owner_id)}")
        parts += [x for x in (lines or []) if x]
        try:
            await self._send(ERROR_TOPIC if error else TOPIC, self.bot.send_message, text="\n".join(parts)[:4096],
                             parse_mode="HTML", link_preview_options={"is_disabled": True})
        except Exception as e:  # noqa: BLE001
            log.warning("лог не отправлен: %s", e)

    async def error(self, title: str, err: BaseException | str, user: TgUser | None = None) -> None:
        text = f"{type(err).__name__}: {err}" if isinstance(err, BaseException) else str(err)
        await self.event("❌", title, user, [f"<code>{escape(text[:3000])}</code>"], error=True)

    async def start_icons(self) -> None:
        """При старте — иконки всем уже известным темам."""
        if not self.chat_id:
            return
        for name in (TOPIC, ERROR_TOPIC):
            t = kv_get(self.con, f"topic:{self.chat_id}:{name}")
            if t:
                await self._icon(name, int(t))

    # ---- бэкап базы в «Data» ----

    def _archive(self, db_path: str, directory: str) -> str:
        stamp = datetime.now().strftime("%Y-%m-%d-%H%M%S")
        copy = os.path.join(directory, "sonar.db")
        target = sqlite3.connect(copy)
        try:
            self.con.backup(target)  # консистентно и при WAL
            target.execute("PRAGMA journal_mode=DELETE")
            target.execute("VACUUM")
            if [r[0] for r in target.execute("PRAGMA integrity_check")] != ["ok"]:
                raise ValueError("integrity_check не прошёл")
        finally:
            target.close()
        archive = os.path.join(directory, f"sonar-backup-{stamp}.zip")
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.write(copy, "sonar.db")
        return archive

    async def backup(self, db_path: str) -> bool:
        """Бэкап — только в тему «Data» (решение владельца 2026-11-15); не вышло — карточка в «Ошибки»."""
        if not self.chat_id or not self.data_thread_id:
            return False
        try:
            with tempfile.TemporaryDirectory(prefix="sonar-backup-") as d:
                archive = await asyncio.to_thread(self._archive, db_path, d)
                caption = (f"📁 <b>Бэкап Sonar</b>\n{datetime.now():%d.%m.%Y %H:%M}\nПроверка БД: успешно\n"
                           "Токены сервисов в копии зашифрованы — без SONAR_FERNET_KEY их не прочитать.")
                await self.bot.send_document(chat_id=self.chat_id, message_thread_id=self.data_thread_id,
                                             document=FSInputFile(archive), caption=caption, parse_mode="HTML")
            return True
        except Exception as e:  # noqa: BLE001
            await self.error("Бэкап базы не удался", e)
            return False

    async def backup_loop(self, db_path: str, check_every_s: int = 600) -> None:
        while True:
            last = float(kv_get(self.con, "backup:last") or 0)
            if time.time() - last >= BACKUP_EVERY_S and await self.backup(db_path):
                kv_set(self.con, "backup:last", str(time.time()))
            await asyncio.sleep(check_every_s)
