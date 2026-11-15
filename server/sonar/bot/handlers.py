"""Обработчики бота @SonarMusicApp (BOT.md): команды, кнопки, шаги ввода, обращения."""
from __future__ import annotations

import asyncio
import hashlib
import json
import secrets
import time
from dataclasses import dataclass
from datetime import datetime, timedelta

from aiogram import Bot, F, Router
from aiogram.exceptions import TelegramBadRequest
from aiogram.filters import Command, CommandObject, CommandStart
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import CallbackQuery, Message

from ..accounts import AccountError, Accounts, User, looks_like_token
from ..config import Settings
from ..db import now_ms
from ..status import Status
from . import screens as S
from .emoji import e
from .support import Support
from .ui import Screen, Shower

router = Router()
LINK_TTL_S = 5 * 60


class Login(StatesGroup):
    login = State()
    password = State()


class Reg(StatesGroup):
    login = State()
    password = State()
    again = State()


class Report(StatesGroup):
    first = State()


@dataclass
class Ctx:
    bot: Bot
    settings: Settings
    accounts: Accounts
    shower: Shower
    status: Status
    support: Support
    bot_username: str = "SonarMusicApp"

    def is_owner(self, tg_id: int) -> bool:
        return bool(self.settings.owner_tg_id) and tg_id == self.settings.owner_tg_id


# ---- общие шаги ----

async def home(ctx: Ctx, tg_id: int) -> Screen:
    user = ctx.accounts.by_tg(tg_id)
    return S.main(user, ctx.settings) if user else S.guest()


async def say(ctx: Ctx, chat_id: int, html: str, reply_to: int | None = None) -> Message:
    return await ctx.shower.send(chat_id, Screen(html=html), reply_to=reply_to)


async def delete_quietly(msg: Message) -> None:
    try:
        await msg.delete()
    except TelegramBadRequest:
        pass


def staff_only(ctx: Ctx):
    return lambda m: ctx.support.ticket_for_staff_message(m) is not None


# ---- команды ----

@router.message(CommandStart())
async def cmd_start(msg: Message, command: CommandObject, state: FSMContext, ctx: Ctx):
    await state.clear()
    arg = command.args or ""
    if arg.startswith("ref_"):
        await state.update_data(ref=arg[4:])
    await ctx.shower.send(msg.chat.id, await home(ctx, msg.from_user.id))


@router.message(Command("status"))
async def cmd_status(msg: Message, ctx: Ctx):
    await ctx.shower.send(msg.chat.id, await status_screen(ctx, msg.from_user.id))


async def status_screen(ctx: Ctx, tg_id: int, fresh: bool = False) -> Screen:
    items = await ctx.status.current(max_age_s=0 if fresh else 60)
    return S.status(items, ctx.accounts.listening_now(), ctx.accounts.users_count(), ctx.status.uptime(), ctx.is_owner(tg_id))


# ---- кнопки ----

GUEST_OK = {"login", "register", "cancel", "quick", "noop", "status", "android"}


@router.callback_query()
async def on_button(q: CallbackQuery, state: FSMContext, ctx: Ctx):
    data = q.data or "noop"
    msg = q.message
    if data.startswith("t:"):
        return await staff_button(q, ctx)
    user = ctx.accounts.by_tg(q.from_user.id)
    head, _, rest = data.partition(":")
    if user is None and head not in GUEST_OK:
        await q.answer("Сначала войди в Sonar", show_alert=True)
        return await ctx.shower.edit(msg, S.guest())
    edit = lambda s: ctx.shower.edit(msg, s)  # noqa: E731

    if head == "noop":
        return await q.answer()
    if head == "android":
        return await q.answer("Android-версия Sonar в разработке", show_alert=True)
    await q.answer()

    if head == "login":
        await state.set_state(Login.login)
        return await edit(S.login_ask())
    if head == "register":
        await state.set_state(Reg.login)
        return await edit(S.register_ask())
    if head == "cancel":
        await state.clear()
        await edit(S.bye())
        await asyncio.sleep(0.9)
        return await ctx.shower.send(msg.chat.id, await home(ctx, q.from_user.id))
    if head == "quick":
        await state.clear()
        return await quick_link(ctx, msg, q.from_user)
    if head == "status":
        return await edit(await status_screen(ctx, q.from_user.id, fresh=True))
    if head == "main":
        await state.clear()
        return await edit(S.main(user, ctx.settings))
    if head == "profile":
        week = ctx.accounts.totals(user, now_ms() - 7 * 86400_000)
        return await edit(S.profile(user, ctx.accounts.services(user), week, ctx.settings))
    if head == "integration":
        return await edit(S.integration(ctx.accounts.token(user), ctx.settings))
    if head == "token":
        if rest == "new":
            ctx.accounts.new_token(user)
        elif rest == "ask_new":
            return await edit(S.ask("Старый токен перестанет работать. Обновить?", "token:new", "integration"))
        elif rest == "ask_revoke":
            return await edit(S.ask("Отозвать токен? Всё, что им пользуется, перестанет работать.", "token:revoke", "integration"))
        elif rest == "revoke":
            ctx.accounts.revoke_token(user)
        return await edit(S.integration(ctx.accounts.token(user), ctx.settings))
    if head == "referral":
        return await edit(S.referral(user, ctx.accounts.referral_count(user), ctx.bot_username))
    if head == "versions":
        return await edit(S.versions(ctx.settings))
    if head == "logout":
        if rest != "yes":
            return await edit(S.logout_ask())
        try:
            ctx.accounts.unlink_tg(user)
        except AccountError as err:
            return await say(ctx, msg.chat.id, S.ERRORS[err.code])
        return await edit(S.guest())
    if head == "stats":
        period = rest if rest in S.PERIODS else "week"
        return await edit(S.stats(period, ctx.accounts.stats(user, S.PERIODS[period][1])))
    if head == "services":
        return await edit(S.services(rest or None))
    if head == "report":
        return await report_button(q, rest, state, ctx, user)
    if head == "ticket":
        _, _, tid = rest.partition(":")
        t = ctx.support.ticket(tid)
        if t and t["tg_id"] == q.from_user.id and t["status"] == "open":
            await ctx.support.close(tid, notify_user=True)
            try:
                await msg.edit_reply_markup(reply_markup=None)
            except TelegramBadRequest:
                pass
        return None
    return None


async def report_button(q: CallbackQuery, rest: str, state: FSMContext, ctx: Ctx, user: User):
    edit = lambda s: ctx.shower.edit(q.message, s)  # noqa: E731
    if not ctx.support.staff_chat:
        return await q.message.answer("Поддержка пока не подключена.")
    if ctx.support.blocked(q.from_user.id):
        return await say(ctx, q.message.chat.id, f"{e('warning')} Доступ к обращениям ограничен.")
    t = ctx.support.open_ticket(q.from_user.id)
    if t:
        return await say(ctx, q.message.chat.id, f"{e('info')} У тебя уже открыто обращение <code>#{t['id']}</code> — пиши сюда, всё уйдёт в поддержку.")
    parts = rest.split(":") if rest else []
    if not parts:
        return await edit(S.report_kind())
    kind = parts[0] if parts[0] in ("bug", "idea") else "bug"
    if len(parts) == 1:
        return await edit(S.report_platform(kind))
    platform = parts[1] if parts[1] in ("windows", "ios") else "windows"
    await state.set_state(Report.first)
    await state.update_data(kind=kind, platform=platform)
    return await edit(S.report_prompt(kind))


async def staff_button(q: CallbackQuery, ctx: Ctx):
    if not ctx.is_owner(q.from_user.id):
        return await q.answer("Только для владельца", show_alert=True)
    _, action, tid = (q.data.split(":") + ["", ""])[:3]
    if action == "cls":
        await ctx.support.close(tid, notify_user=True)
        await q.answer("Закрыто")
    else:
        ok = await ctx.support.verdict(tid, accepted=action == "acc")
        await q.answer(("Принято" if action == "acc" else "Отклонено") if ok else "Обращение не найдено")


# ---- быстрая ссылка (BOT.md §3): подтверждение — в приложении, где уже вошли ----

async def quick_link(ctx: Ctx, msg: Message, tg_user) -> None:
    code = secrets.token_urlsafe(24)
    now = now_ms()
    ctx.accounts.con.execute(
        "INSERT INTO auth_links (code_hash, for_kind, for_json, status, created_at, expires_at) VALUES (?,?,?,?,?,?)",
        (hashlib.sha256(code.encode()).hexdigest(), "telegram", json.dumps({"id": tg_user.id, "username": tg_user.username}),
         "pending", now, now + LINK_TTL_S * 1000))
    until = (datetime.now() + timedelta(seconds=LINK_TTL_S)).strftime("%H:%M")
    shown = await ctx.shower.edit(msg, S.quick(f"{ctx.settings.site_url}/auth/{code}", until))

    async def expire():
        await asyncio.sleep(LINK_TTL_S)
        r = ctx.accounts.con.execute("SELECT status FROM auth_links WHERE code_hash = ?",
                                     (hashlib.sha256(code.encode()).hexdigest(),)).fetchone()
        if r and r["status"] == "pending":
            ctx.accounts.con.execute("UPDATE auth_links SET status = 'expired' WHERE code_hash = ?",
                                     (hashlib.sha256(code.encode()).hexdigest(),))
            try:
                await ctx.shower.edit(shown, S.quick_expired())
            except TelegramBadRequest:
                pass

    asyncio.create_task(expire())


# ---- шаги ввода: вход ----

@router.message(Login.login, F.text)
async def login_name(msg: Message, state: FSMContext, ctx: Ctx):
    login = msg.text.strip().lstrip("@")
    if not ctx.accounts.by_login(login):
        await state.clear()
        return await ctx.shower.send(msg.chat.id, S.no_user())
    await state.update_data(login=login)
    await state.set_state(Login.password)
    await ctx.shower.send(msg.chat.id, S.password_ask())


@router.message(Login.password, F.text)
async def login_password(msg: Message, state: FSMContext, ctx: Ctx):
    await delete_quietly(msg)  # пароль не остаётся в чате
    data = await state.get_data()
    try:
        user = ctx.accounts.verify(data.get("login", ""), msg.text, tg_id=msg.from_user.id)
    except AccountError as err:
        if err.code in ("too_many", "no_user"):
            await state.clear()
        return await say(ctx, msg.chat.id, S.ERRORS.get(err.code, S.ERRORS["bad_password"]))
    await state.clear()
    user = ctx.accounts.link_tg(user, msg.from_user.id, msg.from_user.username)
    await ctx.shower.send(msg.chat.id, S.success_linked(user.login))
    await asyncio.sleep(1.5)
    await ctx.shower.send(msg.chat.id, S.main(user, ctx.settings))


# ---- шаги ввода: регистрация ----

@router.message(Reg.login, F.text)
async def reg_login(msg: Message, state: FSMContext, ctx: Ctx):
    try:
        login = ctx.accounts.check_login(msg.text)
    except AccountError as err:
        return await say(ctx, msg.chat.id, S.ERRORS[err.code])
    await state.update_data(login=login)
    await state.set_state(Reg.password)
    await ctx.shower.send(msg.chat.id, S.register_password(login))


@router.message(Reg.password, F.text)
async def reg_password(msg: Message, state: FSMContext, ctx: Ctx):
    await delete_quietly(msg)
    if len(msg.text) < 8:
        return await say(ctx, msg.chat.id, S.ERRORS["password_short"])
    await state.update_data(password=msg.text)
    await state.set_state(Reg.again)
    await ctx.shower.send(msg.chat.id, S.register_again())


@router.message(Reg.again, F.text)
async def reg_again(msg: Message, state: FSMContext, ctx: Ctx):
    await delete_quietly(msg)
    data = await state.get_data()
    if msg.text != data.get("password"):
        await state.set_state(Reg.password)
        return await say(ctx, msg.chat.id, S.ERRORS["password_mismatch"])
    try:
        user = ctx.accounts.register(data["login"], msg.text, referred_code=data.get("ref"))
    except AccountError as err:
        await state.set_state(Reg.login)
        return await say(ctx, msg.chat.id, S.ERRORS[err.code])
    await state.clear()
    user = ctx.accounts.link_tg(user, msg.from_user.id, msg.from_user.username)
    await ctx.shower.send(msg.chat.id, S.registered(user.login, ctx.settings))
    await asyncio.sleep(1.5)
    await ctx.shower.send(msg.chat.id, S.main(user, ctx.settings))


# ---- обращения ----

_albums: dict[str, int] = {}


async def ack(ctx: Ctx, msg: Message) -> None:
    """«✉️ Отправлено» / «📎 Прикреплено» — альбом одним «Прикреплено: N»."""
    media = bool(msg.photo or msg.video or msg.document or msg.voice or msg.animation or msg.audio or msg.video_note)
    if msg.media_group_id:
        first = msg.media_group_id not in _albums
        _albums[msg.media_group_id] = _albums.get(msg.media_group_id, 0) + 1
        if not first:
            return
        await asyncio.sleep(1.2)
        n = _albums.pop(msg.media_group_id, 1)
        return await say(ctx, msg.chat.id, f"{e('attached')} Прикреплено: {n}", reply_to=msg.message_id)
    await say(ctx, msg.chat.id, f"{e('attached')} Прикреплено" if media else f"{e('sent')} Отправлено", reply_to=msg.message_id)


@router.message(Report.first)
async def report_first(msg: Message, state: FSMContext, ctx: Ctx):
    data = await state.get_data()
    await state.clear()
    user = ctx.accounts.by_tg(msg.from_user.id)
    tid = await ctx.support.create(user, msg, data.get("kind", "bug"), data.get("platform", "windows"))
    await ctx.shower.send(msg.chat.id, S.ticket_opened(tid))


@router.message(F.chat.type == "private")
async def any_message(msg: Message, ctx: Ctx):
    # Ответ владельца на пересланное обращение (пока нет группы поддержки).
    t = ctx.support.ticket_for_staff_message(msg)
    if t:
        await ctx.support.reply(t, msg)
        return await say(ctx, msg.chat.id, f"{e('sent')} Ушло пользователю", reply_to=msg.message_id)
    t = ctx.support.open_ticket(msg.from_user.id)
    if t:
        await ctx.support.forward(t, msg)
        return await ack(ctx, msg)
    if msg.text and looks_like_token(msg.text):
        await delete_quietly(msg)
        return await say(ctx, msg.chat.id, f"{e('warning')} Токены вставляй в приложении, не сюда. Сообщение удалил.")
    await say(ctx, msg.chat.id, f"Не понял тебя {e('info')} Нажми /start — там всё кнопками.")


@router.message(F.chat.type.in_({"group", "supergroup"}))
async def group_message(msg: Message, ctx: Ctx):
    """Ответ в теме группы поддержки → пользователю."""
    if msg.from_user and msg.from_user.is_bot:
        return
    t = ctx.support.ticket_for_staff_message(msg)
    if not t or t["status"] != "open":
        return
    if msg.text and msg.text.strip().startswith("/close"):
        return await ctx.support.close(t["id"], notify_user=True)
    await ctx.support.reply(t, msg)


_started = time.monotonic()
