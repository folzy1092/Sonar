"""Обращения «Баг / Идея» (BOT.md §2.10): одно обращение = одна тема в группе поддержки.

Пока группы нет (SUPPORT_GROUP_ID пуст), обращения приходят владельцу в личку: ответ на
пересланное сообщение (reply) уходит пользователю. С группой — всё, что пишут в теме.
"""
from __future__ import annotations

import secrets
import sqlite3

from aiogram import Bot
from aiogram.exceptions import TelegramBadRequest
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup, Message

from ..accounts import User
from ..config import Settings
from ..db import kv_get, kv_set, now_ms
from .emoji import e, h, icon
from .screens import PLATFORMS, code, quote

KIND = {"bug": "🐞 Баг", "idea": "💡 Идея"}


class Support:
    def __init__(self, bot: Bot, con: sqlite3.Connection, settings: Settings):
        self.bot, self.con, self.s = bot, con, settings

    @property
    def staff_chat(self) -> int | None:
        return self.s.support_group_id or self.s.owner_tg_id

    @property
    def topics(self) -> bool:
        return bool(self.s.support_group_id)

    def open_ticket(self, tg_id: int) -> sqlite3.Row | None:
        return self.con.execute("SELECT * FROM tickets WHERE tg_id = ? AND status = 'open'", (tg_id,)).fetchone()

    def ticket(self, tid: str) -> sqlite3.Row | None:
        return self.con.execute("SELECT * FROM tickets WHERE id = ?", (tid,)).fetchone()

    def blocked(self, tg_id: int) -> bool:
        r = self.con.execute("SELECT until FROM support_blocks WHERE tg_id = ?", (tg_id,)).fetchone()
        return bool(r) and (not r["until"] or r["until"] > now_ms())

    def _staff_kb(self, tid: str) -> InlineKeyboardMarkup:
        b = lambda t, k, a: InlineKeyboardButton(text=t, icon_custom_emoji_id=icon(k), callback_data=f"t:{a}:{tid}")  # noqa: E731
        return InlineKeyboardMarkup(inline_keyboard=[[b("Принять", "confirm", "acc"), b("Отклонить", "cancel", "rej")],
                                                     [b("Закрыть", "closed", "cls")]])

    async def create(self, user: User | None, msg: Message, kind: str, platform: str) -> str:
        tid = secrets.token_hex(4)
        tg = msg.from_user
        who = h(tg.full_name) + (f" (@{h(tg.username)})" if tg.username else "")
        title = f"#{tid} · {KIND[kind]} · {PLATFORMS.get(platform, platform)} — {tg.full_name}"[:128]
        topic_id = None
        if self.topics:
            topic = await self.bot.create_forum_topic(chat_id=self.staff_chat, name=title)
            topic_id = topic.message_thread_id
        self.con.execute("INSERT INTO tickets (id, user_id, tg_id, kind, platform, topic_id, status, created_at) VALUES (?,?,?,?,?,?,?,?)",
                         (tid, user.id if user else None, tg.id, kind, platform, topic_id, "open", now_ms()))
        acc = (f"Логин: {code('@' + user.username)} · {code(f'#{user.number}')}\n"
               f"Профиль: {self.s.site_url}/@{h(user.username)}") if user else "Без аккаунта"
        card = (f"{e('support')} <b>Обращение {code('#' + tid)}</b> · {KIND[kind]} · {PLATFORMS.get(platform, platform)}\n"
                + quote(f"Кто: {who} · ID {code(tg.id)}\n{acc}")
                + ("" if self.topics else "\nОтветь реплаем на сообщение ниже — ответ уйдёт пользователю."))
        await self.bot.send_message(self.staff_chat, card, parse_mode="HTML", message_thread_id=topic_id,
                                    reply_markup=self._staff_kb(tid))
        await self.forward(self.ticket(tid), msg)
        return tid

    async def forward(self, t: sqlite3.Row, msg: Message) -> None:
        """Сообщение пользователя → в тему (или владельцу), копия — в support_messages."""
        sent = await self.bot.copy_message(chat_id=self.staff_chat, from_chat_id=msg.chat.id, message_id=msg.message_id,
                                           message_thread_id=t["topic_id"])
        kv_set(self.con, f"relay:{self.staff_chat}:{sent.message_id}", t["id"])
        file_id, kind = _file(msg)
        self.con.execute("INSERT INTO support_messages (ticket_id, author, text, file_id, file_kind, created_at) VALUES (?,?,?,?,?,?)",
                         (t["id"], "user", msg.text or msg.caption, file_id, kind, now_ms()))

    def ticket_for_staff_message(self, msg: Message) -> sqlite3.Row | None:
        if self.topics and msg.chat.id == self.s.support_group_id and msg.message_thread_id:
            return self.con.execute("SELECT * FROM tickets WHERE topic_id = ?", (msg.message_thread_id,)).fetchone()
        if not self.topics and msg.chat.id == self.s.owner_tg_id and msg.reply_to_message:
            tid = kv_get(self.con, f"relay:{msg.chat.id}:{msg.reply_to_message.message_id}")
            return self.ticket(tid) if tid else None
        return None

    async def reply(self, t: sqlite3.Row, msg: Message) -> None:
        """Ответ поддержки → пользователю: «💬 Поддержка:» + текст или медиа."""
        head = f"{e('support')} <b>Поддержка:</b>"
        if msg.text:
            await self.bot.send_message(t["tg_id"], f"{head}\n{h(msg.text)}", parse_mode="HTML")
        else:
            cap = f"{head}\n{h(msg.caption)}" if msg.caption else head
            await self.bot.copy_message(chat_id=t["tg_id"], from_chat_id=msg.chat.id, message_id=msg.message_id,
                                        caption=cap, parse_mode="HTML")
        file_id, kind = _file(msg)
        self.con.execute("INSERT INTO support_messages (ticket_id, author, text, file_id, file_kind, created_at) VALUES (?,?,?,?,?,?)",
                         (t["id"], "admin", msg.text or msg.caption, file_id, kind, now_ms()))

    async def verdict(self, tid: str, accepted: bool) -> bool:
        """«Принять» / «Отклонить»: сообщить пользователю. Обращение остаётся открытым до «Закрыть»."""
        t = self.ticket(tid)
        if not t:
            return False
        what = "Твоя идея" if t["kind"] == "idea" else "Твой баг-репорт"
        idea = t["kind"] == "idea"
        if accepted:
            text = f"{e('success')} {what} {code('#' + tid)} {e('confirm')} {'принята' if idea else 'принят'}"
        else:
            text = f"{e('cancel')} {what} {code('#' + tid)} {'отклонена' if idea else 'отклонён'}"
        await self.bot.send_message(t["tg_id"], text, parse_mode="HTML")
        return True

    async def close(self, tid: str, notify_user: bool) -> None:
        from .screens import ticket_closed
        t = self.ticket(tid)
        self.con.execute("UPDATE tickets SET status = CASE WHEN status = 'open' THEN 'closed' ELSE status END,"
                         " closed_at = COALESCE(closed_at, ?) WHERE id = ?", (now_ms(), tid))
        if notify_user and t:
            await self.bot.send_message(t["tg_id"], ticket_closed(tid), parse_mode="HTML")
        if t and t["topic_id"]:
            try:
                await self.bot.close_forum_topic(self.staff_chat, t["topic_id"])
            except TelegramBadRequest:
                pass
        if t:
            await self.bot.send_message(self.staff_chat, f"{e('closed')} Обращение {code('#' + tid)} закрыто.",
                                        parse_mode="HTML", message_thread_id=t["topic_id"])


def _file(msg: Message) -> tuple[str | None, str | None]:
    if msg.photo:
        return msg.photo[-1].file_id, "photo"
    for kind in ("video", "document", "voice", "animation", "video_note", "audio"):
        f = getattr(msg, kind, None)
        if f:
            return f.file_id, kind
    return None, None
