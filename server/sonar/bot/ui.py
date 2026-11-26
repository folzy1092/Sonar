"""Экран бота = баннер (или нет) + HTML-текст + inline-кнопки. Показ правит то же сообщение (BOT.md §0)."""
from __future__ import annotations

import re
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path

from aiogram import Bot
from aiogram.exceptions import TelegramBadRequest
from aiogram.types import (
    CopyTextButton, FSInputFile, InlineKeyboardButton, InlineKeyboardMarkup, InputMediaPhoto, Message,
)

from ..db import kv_get, kv_set
from .emoji import h, icon

ASSETS = Path(__file__).resolve().parent / "assets"


@dataclass
class Btn:
    text: str
    icon: str | None = None        # ключ из emoji.py → icon_custom_emoji_id
    cb: str | None = None
    url: str | None = None
    copy: str | None = None

    def build(self) -> InlineKeyboardButton:
        kw = {"text": self.text, "icon_custom_emoji_id": icon(self.icon)}
        if self.url:
            kw["url"] = self.url
        elif self.copy is not None:
            kw["copy_text"] = CopyTextButton(text=self.copy)
        else:
            kw["callback_data"] = self.cb or "noop"
        return InlineKeyboardButton(**kw)


def separate_quotes(html: str) -> str:
    """Две цитаты подряд Telegram склеивает в одну — между ними нужна строка. Профиль, статус и «Сервисы» собираются из
    нескольких `quote(...)`, поэтому разделитель ставим здесь, при создании экрана, а не в каждом месте."""
    return re.sub(r"</blockquote>(?=<blockquote)", "</blockquote>\n", html)


@dataclass
class Screen:
    html: str
    kb: list[list[Btn]] = field(default_factory=list)
    banner: str | None = None      # main | profile | login | register | stats | support

    def __post_init__(self) -> None:
        self.html = separate_quotes(self.html)

    def markup(self) -> InlineKeyboardMarkup | None:
        return InlineKeyboardMarkup(inline_keyboard=[[b.build() for b in row] for row in self.kb]) if self.kb else None


def quote(html: str, head: str | None = None) -> str:
    return f"<blockquote>{f'<b>{head}</b>' + chr(10) if head else ''}{html}</blockquote>"


def code(text: object) -> str:
    return f"<code>{h(text)}</code>"


class Shower:
    """Отправка и правка экранов; file_id баннеров кэшируется в kv."""

    def __init__(self, bot: Bot, con: sqlite3.Connection):
        self.bot, self.con = bot, con

    def _photo(self, name: str):
        fid = kv_get(self.con, f"banner:{name}")
        return fid or FSInputFile(ASSETS / f"{name}.jpg")

    def _remember(self, name: str, msg: Message) -> None:
        if msg.photo and not kv_get(self.con, f"banner:{name}"):
            kv_set(self.con, f"banner:{name}", msg.photo[-1].file_id)

    async def send(self, chat_id: int, s: Screen, reply_to: int | None = None) -> Message:
        common = {"chat_id": chat_id, "reply_markup": s.markup(), "parse_mode": "HTML"}
        if reply_to:
            common["reply_to_message_id"] = reply_to
        if s.banner:
            msg = await self.bot.send_photo(photo=self._photo(s.banner), caption=s.html, **common)
            self._remember(s.banner, msg)
            return msg
        return await self.bot.send_message(text=s.html, link_preview_options={"is_disabled": True}, **common)

    async def edit(self, msg: Message, s: Screen) -> Message:
        """Правит то же сообщение; фото ↔ текст в Telegram не правится — тогда удаляем и шлём новое."""
        try:
            if msg.photo and s.banner:
                r = await self.bot.edit_message_media(
                    chat_id=msg.chat.id, message_id=msg.message_id, reply_markup=s.markup(),
                    media=InputMediaPhoto(media=self._photo(s.banner), caption=s.html, parse_mode="HTML"),
                )
                if isinstance(r, Message):
                    self._remember(s.banner, r)
                    return r
                return msg
            if not msg.photo and not s.banner:
                r = await self.bot.edit_message_text(chat_id=msg.chat.id, message_id=msg.message_id, text=s.html,
                                                     parse_mode="HTML", reply_markup=s.markup(),
                                                     link_preview_options={"is_disabled": True})
                return r if isinstance(r, Message) else msg
        except TelegramBadRequest as e:
            if "not modified" in str(e):
                return msg
            raise
        try:
            await msg.delete()
        except TelegramBadRequest:
            pass
        return await self.send(msg.chat.id, s)
