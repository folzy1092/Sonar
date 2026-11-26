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

from .. import builds, dotify, sessions, staff
from ..admin import users as admin_users
from ..admin.auth import FACTORY_LOGIN, AdminAuth, AuthError
from ..accounts import AccountError, Accounts, User, looks_like_token
from ..config import Settings
from ..db import now_ms
from ..logs import LogGroup
from ..posts import Draft
from ..releases import PLATFORMS, ReleaseError, Releases, check_url, parse_targets, version_from_url
from ..status import Status
from ..updater import Updater, short
from . import screens as S
from .emoji import e
from .support import Support
from .ui import Btn, Screen, Shower

router = Router()
LINK_TTL_S = 5 * 60


class Login(StatesGroup):
    login = State()
    password = State()


class Reg(StatesGroup):
    login = State()
    password = State()
    again = State()


class Dotify(StatesGroup):
    """Скрытая /dotify: ждём файл .dotifyplaylist, потом — подтверждение."""
    file = State()


class Report(StatesGroup):
    first = State()


class Post(StatesGroup):
    """Пост в канал с кнопками (BOT.md §2.6д)."""
    message = State()
    button_text = State()
    button_url = State()


class PackAdd(StatesGroup):
    wait = State()


class RelAdd(StatesGroup):
    """Владелец закрепляет проверенную версию (BOT.md §2.12)."""
    url = State()
    version = State()
    notes = State()
    targets = State()


@dataclass
class Ctx:
    bot: Bot
    settings: Settings
    accounts: Accounts
    shower: Shower
    status: Status
    support: Support
    logs: LogGroup
    releases: Releases | None = None
    bot_username: str = "SonarMusicApp"
    updater: Updater | None = None
    github: builds.GitHub | None = None     # выпуск сборок из бота (bot/publishing.py)

    def is_owner(self, tg_id: int) -> bool:
        return bool(self.settings.owner_tg_id) and tg_id == self.settings.owner_tg_id


# ---- общие шаги ----

async def home(ctx: Ctx, tg_id: int) -> Screen:
    user = ctx.accounts.by_tg(tg_id)
    return S.main(user, ctx.settings) if user else S.guest(ctx.settings)


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
    if arg.startswith(("link_", "tg_")):
        return await start_link(ctx, msg, arg)
    await ctx.shower.send(msg.chat.id, await home(ctx, msg.from_user.id))


# ---- вход и привязка из приложения через бота (BOT.md §3, API.md §1) ----

LINK_GONE = "Ссылка истекла или уже использована — сделай новую в приложении"


async def start_link(ctx: Ctx, msg: Message, arg: str) -> None:
    kind, _, code = arg.partition("_")
    con = ctx.accounts.con
    link = sessions.get_link(con, code)
    if link is None or link.status != "pending" or link.kind != ("device" if kind == "link" else "tg_link"):
        await ctx.shower.send(msg.chat.id, S.link_done(LINK_GONE, ok=False))
        return
    if kind == "tg":
        owner = ctx.accounts.by_id(link.user_id)
        await ctx.shower.send(msg.chat.id, S.tg_link_confirm(owner.login, code))
        return
    user = ctx.accounts.by_tg(msg.from_user.id)
    if user is None:
        await ctx.shower.send(msg.chat.id, S.link_done("Этот Telegram не привязан к аккаунту Sonar. Войди в приложении "
                                                       "логином и паролем, а Telegram привяжи в «Аккаунте».", ok=False))
        return
    who = sessions.DeviceInfo.parse(link.data).label()
    shown = await ctx.shower.send(msg.chat.id, S.link_approve(user.login, who, False, code))

    async def arm():
        await asyncio.sleep(3)  # «Разрешить» — не сразу: защита от «нажми, не глядя»
        try:
            await ctx.shower.edit(shown, S.link_approve(user.login, who, True, code))
        except TelegramBadRequest:
            pass

    asyncio.create_task(arm())


async def link_button(q: CallbackQuery, ctx: Ctx) -> None:
    _, action, code = (q.data.split(":", 2) + ["", ""])[:3]
    con = ctx.accounts.con
    link = sessions.get_link(con, code)
    await q.answer()
    if link is None or link.status != "pending":
        return await ctx.shower.edit(q.message, S.link_done(LINK_GONE, ok=False))
    if action == "r":
        sessions.decide(con, link, "rejected")
        return await ctx.shower.edit(q.message, S.link_done("Вход отклонён", ok=False))
    if action == "a" and link.kind == "device":
        user = ctx.accounts.by_tg(q.from_user.id)
        if user is None or not sessions.decide(con, link, "approved", user.id):
            return await ctx.shower.edit(q.message, S.link_done(LINK_GONE, ok=False))
        return await ctx.shower.edit(q.message, S.link_done(f"Вход разрешён: {sessions.DeviceInfo.parse(link.data).label()}"))
    if action == "t" and link.kind == "tg_link":
        owner = ctx.accounts.by_id(link.user_id)
        if owner is None or not sessions.decide(con, link, "approved"):
            return await ctx.shower.edit(q.message, S.link_done(LINK_GONE, ok=False))
        ctx.accounts.link_tg(owner, q.from_user.id, q.from_user.username)
        return await ctx.shower.edit(q.message, S.success_linked(owner.login))


async def telegram_linked(ctx: Ctx, tg_id: int, user: User) -> None:
    """В приложении нажали «Разрешить» на быстрой ссылке из бота — сказать об этом в боте."""
    try:
        await ctx.shower.send(tg_id, S.success_linked(user.login))
    except Exception:  # noqa: BLE001 — бот не должен ронять ответ API
        pass

# ---- обновление сервера по частям: скрытая /update — владелец и помощники с правом `server` (sonar/updater.py, staff.py) ----

@router.message(Command("update"))
async def cmd_update(msg: Message, ctx: Ctx):
    if not staff.allowed(ctx, msg.from_user.id, "server"):
        return
    if ctx.updater is None or not ctx.updater.available():
        return await ctx.shower.send(msg.chat.id, S.update_unavailable())
    shown = await ctx.shower.send(msg.chat.id, S.update_checking())
    await ctx.shower.edit(shown, S.update_menu(await ctx.updater.check(force=True)))


async def update_button(q: CallbackQuery, ctx: Ctx) -> None:
    if not staff.allowed(ctx, q.from_user.id, "server"):
        return await q.answer("Только для владельца", show_alert=True)
    upd = ctx.updater
    if upd is None or not upd.available():
        await q.answer()
        return await ctx.shower.edit(q.message, S.update_unavailable())
    edit = lambda s: ctx.shower.edit(q.message, s)  # noqa: E731
    action = (q.data or "").partition(":")[2]
    if upd.busy:
        return await q.answer("Перезапуск уже идёт", show_alert=True)
    await q.answer()
    if action in ("chk", "menu"):
        if action == "chk":
            await edit(S.update_checking())
        return await edit(S.update_menu(await upd.check(force=action == "chk")))
    if action == "rst":
        return await edit(S.update_restart_menu())
    if action == "rst_all":
        return await edit(S.update_confirm_restart())
    if action in ("rst_bot", "rst_api"):
        part = action[4:]
        _audit(ctx, q.from_user.id, "restart_" + part, part)
        await edit(S.update_part_pending(part))
        if part == "bot":
            notice = {"chat_id": q.message.chat.id, "message_id": q.message.message_id, "by": q.from_user.id}
            if not upd.restart_bot(notice):
                await edit(S.update_part_done(part, False))
            return None
        return await edit(S.update_part_done(part, await upd.restart_api()))
    if action == "site":
        await edit(S.update_checking())
        return await edit(S.update_site_done(await upd.update_site()))
    what = {"server": "server", "all": "all", "rst_yes": "restart"}.get(action)
    if what is None:
        return None
    st = await upd.check()
    await edit(S.update_pending(what, st))
    if not upd.request_restart(what, source="telegram", by=str(q.from_user.id), chat_id=q.message.chat.id,
                               message_id=q.message.message_id):
        await edit(S.update_unavailable())
    return None


def _audit(ctx: Ctx, tg_id: int, action: str, target: str) -> None:
    ctx.accounts.con.execute("INSERT INTO admin_audit (at, admin, action, target) VALUES (?,?,?,?)",
                             (now_ms(), f"telegram:{tg_id}", action, target))


async def announce_part(ctx: Ctx, part: str) -> None:
    """Опрос бота поднялся заново: итог — в то же сообщение, где нажали «Только бота»."""
    notice, ctx.updater.notice = ctx.updater.notice, None
    if notice:
        try:
            screen = S.update_part_done(part, True)
            await ctx.bot.edit_message_text(screen.html, chat_id=notice["chat_id"], message_id=notice["message_id"],
                                            parse_mode="HTML", reply_markup=screen.markup())
        except Exception:  # noqa: BLE001 — итог не должен ронять опрос
            pass
    await ctx.logs.event("🔄", "Бот перезапущен", lines=["опрос Telegram, HTTP не прерывался"])


async def announce_update(ctx: Ctx) -> None:
    """Первый старт после перезапуска из бота или админки: итог — в то же сообщение, и строкой в лог-группу."""
    if ctx.updater is None:
        return
    result = ctx.updater.take_result()
    if result is None:
        return
    screen = S.update_done(result)
    chat_id, message_id = result.get("chat_id"), result.get("message_id")
    try:
        if chat_id and message_id:
            await ctx.bot.edit_message_text(screen.html, chat_id=chat_id, message_id=message_id, parse_mode="HTML",
                                            reply_markup=screen.markup())
        elif result.get("source") != "telegram" and ctx.settings.owner_tg_id:
            await ctx.shower.send(ctx.settings.owner_tg_id, screen)
    except Exception:  # noqa: BLE001 — итог не должен ронять запуск
        pass
    word = {True: "ок", False: "версия не та", None: "версия не проверена"}[result["ok"]]
    await ctx.logs.event("🔄", "Сервер перезапущен" if result.get("what") == "restart" else "Сервер обновлён",
                         lines=[f"{short(result.get('old'))} → {short(result.get('current'))} · {word}",
                                f"запросил: {result.get('source')}"])




# ---- /admin: команды владельца (скрытая, только владелец) ----

PASSWORD_SHOWN_S = 120   # сколько живёт сообщение с новым паролем админки


def _https_base(ctx: Ctx) -> str:
    base = (ctx.settings.public_url or ctx.settings.site_url or "").rstrip("/")
    return base if base.startswith("https://") else ""


def _admin_url(ctx: Ctx) -> str:
    base = _https_base(ctx)
    return f"{base}/admin/" if base else ""


def _admin_menu(ctx: Ctx) -> Screen:
    base = _https_base(ctx)
    return S.admin_menu(_admin_url(ctx), f"{base}/diag" if base else "")


@router.message(Command("admin"))
async def cmd_admin(msg: Message, ctx: Ctx):
    if not ctx.is_owner(msg.from_user.id):
        return
    await ctx.shower.send(msg.chat.id, _admin_menu(ctx))


async def _delete_later(ctx: Ctx, chat_id: int, message_id: int, seconds: int) -> None:
    await asyncio.sleep(seconds)
    try:
        await ctx.bot.delete_message(chat_id, message_id)
    except TelegramBadRequest:
        pass


async def admin_button(q: CallbackQuery, ctx: Ctx) -> None:
    if not ctx.is_owner(q.from_user.id):
        return await q.answer("Только для владельца", show_alert=True)
    await q.answer()
    action = (q.data or "").partition(":")[2]
    edit = lambda s: ctx.shower.edit(q.message, s)  # noqa: E731
    if action == "menu":
        return await edit(_admin_menu(ctx))
    if action == "help":
        from .moderation import HELP
        return await edit(Screen(html=HELP, kb=[[Btn("Назад", "back", "adm:menu")]]))
    if action == "pw":
        return await edit(S.admin_reset_confirm(FACTORY_LOGIN))
    if action != "pw_yes":
        return None
    con = ctx.accounts.con
    try:
        password = AdminAuth(con).reset_password(FACTORY_LOGIN)   # argon2 ~0,1 с — раз в жизни, поток не нужен
    except AuthError:
        return await edit(_admin_menu(ctx))
    admin_users.audit(con, f"telegram:{q.from_user.id}", "reset_admin_password", FACTORY_LOGIN)
    shown = await edit(S.admin_reset_done(FACTORY_LOGIN, password, _admin_url(ctx), PASSWORD_SHOWN_S // 60))
    chat_id = q.message.chat.id
    asyncio.create_task(_delete_later(ctx, chat_id, getattr(shown, "message_id", q.message.message_id), PASSWORD_SHOWN_S))
    return None



# ---- перенос Любимых из Dotify (скрытая команда, в меню её нет) ----

@router.message(Command("dotify"))
async def cmd_dotify(msg: Message, state: FSMContext, ctx: Ctx):
    if ctx.accounts.by_tg(msg.from_user.id) is None:
        return await ctx.shower.send(msg.chat.id, S.guest(ctx.settings))
    await state.set_state(Dotify.file)
    await ctx.shower.send(msg.chat.id, S.dotify_ask())


async def _dotify_parse(ctx: Ctx, file_id: str) -> dotify.Parsed:
    return dotify.parse((await ctx.bot.download(file_id)).read())


@router.message(Dotify.file, F.document)
async def dotify_file(msg: Message, state: FSMContext, ctx: Ctx):
    user = ctx.accounts.by_tg(msg.from_user.id)
    if user is None:
        await state.clear()
        return await ctx.shower.send(msg.chat.id, S.guest(ctx.settings))
    if (msg.document.file_size or 0) > dotify.FILE_MAX:
        return await say(ctx, msg.chat.id, f"{e('cancel')} Файл больше 5 МБ — это не плейлист Dotify")
    try:
        parsed = await _dotify_parse(ctx, msg.document.file_id)
    except dotify.DotifyError as err:
        return await say(ctx, msg.chat.id, f"{e('cancel')} {err}")
    c = dotify.preview(ctx.accounts.con, user.id, parsed)
    # Сам файл не храним: на «Добавить» скачаем ещё раз по file_id.
    await state.update_data(dotify_file=msg.document.file_id)
    await ctx.shower.send(msg.chat.id, S.dotify_preview(parsed.title, c.new, c.have, c.removed, c.unknown))


async def dotify_button(q: CallbackQuery, state: FSMContext, ctx: Ctx, user: User) -> None:
    data = await state.get_data()
    file_id = data.get("dotify_file")
    await state.clear()
    if q.data != "dot:ok" or not file_id:
        return await ctx.shower.edit(q.message, await home(ctx, q.from_user.id))
    try:
        parsed = await _dotify_parse(ctx, file_id)
    except dotify.DotifyError as err:
        return await say(ctx, q.message.chat.id, f"{e('cancel')} {err}")
    c = dotify.apply(ctx.accounts.con, user.id, parsed)
    await ctx.shower.edit(q.message, S.dotify_done(c.new, c.have))


@router.message(Command("status"))
async def cmd_status(msg: Message, ctx: Ctx):
    await ctx.shower.send(msg.chat.id, await status_screen(ctx, msg.from_user.id))


async def status_screen(ctx: Ctx, tg_id: int, fresh: bool = False) -> Screen:
    items = await ctx.status.current(max_age_s=0 if fresh else 60)
    return S.status(items, ctx.accounts.listening_now(), ctx.accounts.users_count(), ctx.status.uptime(), ctx.is_owner(tg_id),
                    ctx.status.never_ok(), day=ctx.accounts.listeners_24h())


# ---- кнопки ----

GUEST_OK = {"login", "register", "cancel", "quick", "noop", "status", "android"}


@router.callback_query()
async def on_button(q: CallbackQuery, state: FSMContext, ctx: Ctx):
    data = q.data or "noop"
    msg = q.message
    if data.startswith("t:"):
        return await staff_button(q, ctx)
    if data.startswith("lk:"):
        return await link_button(q, ctx)
    if data.startswith("upd:"):
        return await update_button(q, ctx)
    if data.startswith("adm:"):
        return await admin_button(q, ctx)
    user = ctx.accounts.by_tg(q.from_user.id)
    head, _, rest = data.partition(":")
    if user is None and head not in GUEST_OK:
        await q.answer("Сначала войди в Sonar", show_alert=True)
        return await ctx.shower.edit(msg, S.guest(ctx.settings))
    edit = lambda s: ctx.shower.edit(msg, s)  # noqa: E731

    if head == "noop":
        return await q.answer()
    if head == "android":
        return await q.answer("Android-версия Sonar в разработке", show_alert=True)
    await q.answer()

    if head == "dot":
        return await dotify_button(q, state, ctx, user)
    if head == "login":
        await state.set_state(Login.login)
        return await edit(S.login_ask())
    if head == "register":
        if not ctx.settings.registration_open:
            return await say(ctx, q.message.chat.id, S.ERRORS["registration_closed"])
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
        return await edit(versions_screen(ctx, user, q.from_user.id))
    if head == "rel":
        return await rel_button(q, rest, state, ctx)
    if head == "post":
        return await post_button(q, rest, state, ctx)
    if head == "logout":
        if rest != "yes":
            return await edit(S.logout_ask())
        try:
            ctx.accounts.unlink_tg(user)
        except AccountError as err:
            return await say(ctx, msg.chat.id, S.ERRORS[err.code])
        await ctx.logs.event("🔚", "Выход из бота", q.from_user, [f"Аккаунт: <code>@{user.username}</code>"])
        return await edit(S.guest(ctx.settings))
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
    block = ctx.support.block_of(q.from_user.id)
    if block:
        return await ctx.shower.send(q.message.chat.id, S.report_blocked(block))
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


def versions_screen(ctx: Ctx, user: User, tg_id: int):
    """Актуальные версии — то, что выпущено на сайте (`builds`, канал релиз); раньше читалась старая таблица `releases`."""
    con = ctx.accounts.con
    return S.versions(ctx.settings, {p: builds.current(con, p, "release") for p in ("windows", "ios")},
                      owner=ctx.is_owner(tg_id))


# ---- проверенные версии: только владелец (BOT.md §2.12) ----

async def rel_button(q: CallbackQuery, rest: str, state: FSMContext, ctx: Ctx):
    if not ctx.is_owner(q.from_user.id) or ctx.releases is None:
        return None
    edit = lambda s: ctx.shower.edit(q.message, s)  # noqa: E731
    action, _, arg = rest.partition(":")
    rels = ctx.releases
    if action == "admin":
        await state.clear()
        return await edit(S.rel_admin({p: rels.current(p, None) for p in PLATFORMS}, ctx.settings))
    if action == "new" and arg in PLATFORMS:
        await state.clear()
        await state.set_state(RelAdd.url)
        await state.update_data(platform=arg)
        return await edit(S.rel_ask_url(arg))
    if action == "ver":
        d = await state.get_data()
        if "url" not in d:
            return None
        await state.update_data(version=version_from_url(d["url"]) or "")
        await state.set_state(RelAdd.notes)
        return await edit(S.rel_ask_notes())
    if action == "nonotes":
        await state.update_data(notes="")
        await state.set_state(None)
        return await edit(S.rel_ask_audience())
    if action == "aud" and arg in ("all", "only", "except"):
        await state.update_data(audience=arg, targets=[])
        if arg == "all":
            return await edit(S.rel_confirm(await state.get_data()))
        await state.set_state(RelAdd.targets)
        return await edit(S.rel_ask_targets(arg))
    if action == "save":
        d = await state.get_data()
        await state.clear()
        try:
            rel = rels.add(d["platform"], d.get("version", ""), d["url"], d.get("notes", ""), d.get("audience", "all"),
                           d.get("targets") or [])
        except (ReleaseError, KeyError) as err:
            await q.answer(getattr(err, "text", "Не хватает данных — начни заново"), show_alert=True)
            return await edit(S.rel_admin({p: rels.current(p, None) for p in PLATFORMS}, ctx.settings))
        await ctx.logs.event("📦", f"Версия {rel.platform_name} {rel.version}", q.from_user, [rel.url])
        if arg == "1":
            await send_alert(ctx, q, rel)
        return await edit(S.rel_item(rel, len(rels.recipients(rel))))
    if action == "list" and arg in PLATFORMS:
        return await edit(S.rel_list(arg, rels.history(arg)))
    if action == "item" and arg.isdigit() and (rel := rels.get(int(arg))):
        return await edit(S.rel_item(rel, len(rels.recipients(rel))))
    if action == "toggle" and arg.isdigit() and (rel := rels.get(int(arg))):
        rel = rels.set_active(rel.id, not rel.active)
        return await edit(S.rel_item(rel, len(rels.recipients(rel))))
    if action == "alert" and arg.isdigit() and (rel := rels.get(int(arg))):
        await send_alert(ctx, q, rel)
        return await edit(S.rel_item(rels.get(rel.id), len(rels.recipients(rel))))
    return None


# ---- пост в канал: только владелец ----

def preset_url(ctx: Ctx, platform: str) -> str:
    rel = ctx.releases.current(platform, None) if ctx.releases else None
    if rel:
        return rel.url
    return ctx.settings.download_url if platform == "windows" else ctx.settings.download_url_ios


def post_markup(d: Draft):
    return Screen(html="", kb=[[Btn(t, url=u) for t, u in row] for row in d.rows()]).markup()


async def post_button(q: CallbackQuery, rest: str, state: FSMContext, ctx: Ctx):
    if not ctx.is_owner(q.from_user.id):
        return None
    edit = lambda s: ctx.shower.edit(q.message, s)  # noqa: E731
    action, _, arg = rest.partition(":")
    channel = ctx.settings.channel
    if action == "new":
        await state.clear()
        await state.set_state(Post.message)
        return await edit(S.post_ask(channel))
    d = Draft.of((await state.get_data()).get("post"))
    if not d.ready:
        await q.answer("Начни заново: пришли пост", show_alert=True)
        await state.set_state(Post.message)
        return await edit(S.post_ask(channel))

    async def save_and_show():
        await state.update_data(post=d.dump())
        await state.set_state(None)
        return await edit(S.post_builder(d, channel))

    if action == "add":
        await state.set_state(Post.button_text)
        return await edit(S.post_ask_button_text())
    if action == "preset" and arg in PLATFORMS:
        try:
            d.add(PLATFORMS[arg], preset_url(ctx, arg))
        except ReleaseError as err:
            await q.answer(err.text, show_alert=True)
        return await save_and_show()
    if action == "row":
        d.cycle_row()
        return await save_and_show()
    if action == "pop":
        d.pop()
        return await save_and_show()
    if action == "back":
        return await save_and_show()
    if action == "preview":
        await ctx.bot.copy_message(q.message.chat.id, d.chat_id, d.message_id, reply_markup=post_markup(d))
        return await ctx.shower.send(q.message.chat.id, S.post_builder(d, channel))
    if action == "ask":
        return await edit(S.post_confirm(channel, len(d.buttons)))
    if action == "publish":
        try:
            sent = await ctx.bot.copy_message(channel, d.chat_id, d.message_id, reply_markup=post_markup(d))
        except Exception as err:  # noqa: BLE001 — бот не админ канала, канал не найден
            await q.answer(f"Не вышло: {err}"[:190], show_alert=True)
            return await edit(S.post_builder(d, channel))
        await state.clear()
        await ctx.logs.event("📢", f"Пост в {channel}", q.from_user, [f"Кнопок: {len(d.buttons)} · id {sent.message_id}"])
        await q.answer("Опубликовано")
        return await edit(S.rel_admin({p: ctx.releases.current(p, None) for p in PLATFORMS}, ctx.settings))
    return None


@router.message(Post.message)
async def post_message(msg: Message, state: FSMContext, ctx: Ctx):
    if not ctx.is_owner(msg.from_user.id):
        return
    d = Draft(chat_id=msg.chat.id, message_id=msg.message_id)
    await state.update_data(post=d.dump())
    await state.set_state(None)
    await ctx.shower.send(msg.chat.id, S.post_builder(d, ctx.settings.channel))


@router.message(Post.button_text, F.text)
async def post_button_text(msg: Message, state: FSMContext, ctx: Ctx):
    if not ctx.is_owner(msg.from_user.id):
        return
    await state.update_data(button_text=msg.text.strip()[:40])
    await state.set_state(Post.button_url)
    await ctx.shower.send(msg.chat.id, S.post_ask_button_url(msg.text.strip()[:40]))


@router.message(Post.button_url, F.text)
async def post_button_url(msg: Message, state: FSMContext, ctx: Ctx):
    if not ctx.is_owner(msg.from_user.id):
        return
    data = await state.get_data()
    d = Draft.of(data.get("post"))
    try:
        d.add(data.get("button_text", "Ссылка"), msg.text)
    except ReleaseError as err:
        return await say(ctx, msg.chat.id, f"{e('cancel')} {err.text}")
    await state.update_data(post=d.dump())
    await state.set_state(None)
    await ctx.shower.send(msg.chat.id, S.post_builder(d, ctx.settings.channel))


async def send_alert(ctx: Ctx, q: CallbackQuery, rel) -> None:
    """Сообщение о версии всем, кому она видна; 20 в секунду — в лимитах Telegram."""
    if not rel.active:
        await q.answer("Версия снята — алерт не отправлен", show_alert=True)
        return
    users = ctx.releases.recipients(rel)
    sent = failed = 0
    for u in users:
        try:
            await ctx.shower.send(u.tg_id, S.rel_alert(rel))
            sent += 1
        except Exception:  # noqa: BLE001 — заблокировал бота, удалил чат: просто не дошло
            failed += 1
        await asyncio.sleep(0.05)
    ctx.releases.mark_alerted(rel.id)
    await ctx.logs.event("📣", f"Алерт {rel.platform_name} {rel.version}", q.from_user, [f"Доставлено: {sent} · не дошло: {failed}"])
    await say(ctx, q.message.chat.id, f"{e('sent')} Алерт: доставлено <b>{sent}</b>" + (f", не дошло {failed}" if failed else ""))


@router.message(RelAdd.url, F.text)
async def rel_url(msg: Message, state: FSMContext, ctx: Ctx):
    if not ctx.is_owner(msg.from_user.id):
        return
    try:
        url = check_url(msg.text)
    except ReleaseError as err:
        return await say(ctx, msg.chat.id, f"{e('cancel')} {err.text}")
    d = await state.get_data()
    await state.update_data(url=url)
    await state.set_state(RelAdd.version)
    await ctx.shower.send(msg.chat.id, S.rel_ask_version(d["platform"], version_from_url(url)))


@router.message(RelAdd.version, F.text)
async def rel_version(msg: Message, state: FSMContext, ctx: Ctx):
    if not ctx.is_owner(msg.from_user.id):
        return
    await state.update_data(version=msg.text.strip()[:60])
    await state.set_state(RelAdd.notes)
    await ctx.shower.send(msg.chat.id, S.rel_ask_notes())


@router.message(RelAdd.notes, F.text)
async def rel_notes(msg: Message, state: FSMContext, ctx: Ctx):
    if not ctx.is_owner(msg.from_user.id):
        return
    await state.update_data(notes=msg.text.strip()[:1500])
    await state.set_state(None)
    await ctx.shower.send(msg.chat.id, S.rel_ask_audience())


@router.message(RelAdd.targets, F.text)
async def rel_targets(msg: Message, state: FSMContext, ctx: Ctx):
    if not ctx.is_owner(msg.from_user.id):
        return
    targets = parse_targets(msg.text)
    if not targets:
        return await say(ctx, msg.chat.id, f"{e('cancel')} Не нашёл ни одного аккаунта — пришли ещё раз")
    await state.update_data(targets=targets)
    await state.set_state(None)
    await ctx.shower.send(msg.chat.id, S.rel_confirm(await state.get_data()))


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
        user = await ctx.accounts.verify(data.get("login", ""), msg.text, tg_id=msg.from_user.id)
    except AccountError as err:
        if err.code in ("too_many", "no_user"):
            await state.clear()
        return await say(ctx, msg.chat.id, S.ERRORS.get(err.code, S.ERRORS["bad_password"]))
    await state.clear()
    user = ctx.accounts.link_tg(user, msg.from_user.id, msg.from_user.username)
    await ctx.logs.event("🔑", "Вход в боте", msg.from_user, [f"Аккаунт: <code>@{user.username}</code> · #{user.number}"])
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
    if not ctx.settings.registration_open:
        await state.clear()
        return await say(ctx, msg.chat.id, S.ERRORS["registration_closed"])
    try:
        user = await ctx.accounts.register(data["login"], msg.text, referred_code=data.get("ref"))
    except AccountError as err:
        await state.set_state(Reg.login)
        return await say(ctx, msg.chat.id, S.ERRORS[err.code])
    await state.clear()
    user = ctx.accounts.link_tg(user, msg.from_user.id, msg.from_user.username)
    await ctx.logs.event("👋", "Регистрация", msg.from_user, [f"Аккаунт: <code>@{user.username}</code> · #{user.number}",
                                                            "По приглашению" if data.get("ref") else None])
    await ctx.shower.send(msg.chat.id, S.registered(user.login, ctx.settings))
    await asyncio.sleep(1.5)
    await ctx.shower.send(msg.chat.id, S.main(user, ctx.settings))



# ---- свой пак премиум-эмодзи (brand/emoji/badges) — только владелец ----

PACK_EMOJI = {"logo_sonar": "🎧", "windows": "💻", "iphone": "📱", "android": "🤖", "music": "🎶",
              "diamond": "💎", "heart": "❤️", "bug": "🐞", "wave": "🌊"}


@router.message(Command("emoji_pack"))
async def cmd_emoji_pack(msg: Message, ctx: Ctx):
    """Создаёт (или дополняет) пак «Sonar» из brand/emoji/badges и присылает ключ → custom_emoji_id."""
    from aiogram.types import FSInputFile, InputSticker
    from ..config import REPO_DIR
    from ..db import kv_set
    if not ctx.is_owner(msg.from_user.id):
        return
    folder = REPO_DIR / "brand" / "emoji" / "badges"
    name = f"sonar_icons_by_{ctx.bot_username}"
    have: dict[str, str] = {}
    try:
        existing = await ctx.bot.get_sticker_set(name)
        have = {s.emoji: s.custom_emoji_id for s in existing.stickers}
    except TelegramBadRequest:
        existing = None
    todo = [(k, e) for k, e in PACK_EMOJI.items() if (folder / f"{k}.png").exists()]
    stickers = [InputSticker(sticker=FSInputFile(folder / f"{k}.png"), format="static", emoji_list=[e]) for k, e in todo]
    if existing is None:
        await ctx.bot.create_new_sticker_set(user_id=msg.from_user.id, name=name, title="Sonar", stickers=stickers,
                                             sticker_type="custom_emoji", needs_repainting=True)
    # Пак уже есть — свои значки не трогаем (в нём ещё и скопированные эмодзи), дописываем только новые PNG.
    from ..db import kv_get
    for k, e in todo:
        if existing is not None and not kv_get(ctx.accounts.con, f"pack:{k}"):
            await ctx.bot.add_sticker_to_set(user_id=msg.from_user.id, name=name,
                                             sticker=InputSticker(sticker=FSInputFile(folder / f"{k}.png"), format="static", emoji_list=[e]))
            kv_set(ctx.accounts.con, f"pack:{k}", (await ctx.bot.get_sticker_set(name)).stickers[-1].custom_emoji_id)
        elif existing is None:
            created = await ctx.bot.get_sticker_set(name)
            kv_set(ctx.accounts.con, f"pack:{k}", next(s.custom_emoji_id for s in created.stickers if s.emoji == e))
    lines = []
    for k, e in todo:
        cid = kv_get(ctx.accounts.con, f"pack:{k}")
        if cid:
            lines.append(f'<tg-emoji emoji-id="{cid}">{e}</tg-emoji> <code>{k}</code> — <code>{cid}</code>')
    await swap_badges(ctx, msg.from_user.id, name)
    lines = [f'<tg-emoji emoji-id="{kv_get(ctx.accounts.con, f"pack:{k}")}">{e}</tg-emoji> <code>{k}</code> — '
             f'<code>{kv_get(ctx.accounts.con, f"pack:{k}")}</code>' for k, e in todo if kv_get(ctx.accounts.con, f"pack:{k}")]
    lines += await copy_picked(ctx, msg.from_user.id, name)
    removed = await drop_unused(ctx, [name, f"sonar_logos_by_{ctx.bot_username}"])
    if removed:
        lines.append(f"Убрано дублей: {removed}")
    text = f"Паки: https://t.me/addemoji/{name} · https://t.me/addemoji/sonar_logos_by_{ctx.bot_username}\n\n"
    for i in range(0, len(lines), 40):  # 4096 знаков на сообщение
        await msg.answer((text if i == 0 else "") + "\n".join(lines[i:i + 40]), parse_mode="HTML",
                         link_preview_options={"is_disabled": True})


# Нарисованные кодом значки заменены готовыми одноцветными из других паков (решение владельца 2026-11-15):
# ключ → исходный custom_emoji_id (tgiosicons, ATechnologyEmoji, developeremojis, vector_icons_by_fStikBot).
BADGE_SRC = {"windows": "5406785190490027556", "iphone": "5775870512127283512", "android": "5415685659807470630",
             "music": "5938473438468378529", "diamond": "6037083366438737901", "heart": "5938368005611195877",
             "bug": "5452051336881271172", "wave": "6044117517847236354"}


async def swap_badges(ctx: Ctx, owner_id: int, name: str) -> None:
    from aiogram.types import InputSticker
    from ..db import kv_get, kv_set
    con = ctx.accounts.con
    for k, src in BADGE_SRC.items():
        if kv_get(con, f"packbadge:{k}") == src:
            continue
        old_id = kv_get(con, f"pack:{k}")
        pack = await ctx.bot.get_sticker_set(name)
        old = next((s for s in pack.stickers if s.custom_emoji_id == old_id), None)
        copy = kv_get(con, f"packsrc:{src}")
        if copy and copy != "?":          # такой эмодзи уже скопирован — просто ссылаемся на него
            if old:
                await ctx.bot.delete_sticker_from_set(sticker=old.file_id)
            new_id = copy
        else:
            st = (await ctx.bot.get_custom_emoji_stickers(custom_emoji_ids=[src]))[0]
            fmt = "video" if st.is_video else "animated" if st.is_animated else "static"
            inp = InputSticker(sticker=st.file_id, format=fmt, emoji_list=[st.emoji or "⭐"])
            if old:
                pos = [s.custom_emoji_id for s in pack.stickers].index(old_id)
                await ctx.bot.replace_sticker_in_set(user_id=owner_id, name=name, old_sticker=old.file_id, sticker=inp)
                new_id = (await ctx.bot.get_sticker_set(name)).stickers[pos].custom_emoji_id
            else:
                await ctx.bot.add_sticker_to_set(user_id=owner_id, name=name, sticker=inp)
                new_id = (await ctx.bot.get_sticker_set(name)).stickers[-1].custom_emoji_id
            kv_set(con, f"packsrc:{src}", new_id)
        kv_set(con, f"pack:{k}", new_id)
        kv_set(con, f"packbadge:{k}", src)


async def patient(call, **kw):
    """Вызов Bot API с ожиданием при флуд-контроле: Telegram сам говорит, сколько ждать (лимит не поднять)."""
    from aiogram.exceptions import TelegramRetryAfter
    for _ in range(10):
        try:
            return await call(**kw)
        except TelegramRetryAfter as e:
            await asyncio.sleep(e.retry_after + 1)
    return await call(**kw)


async def own_ids(ctx: Ctx, names: list[str]) -> set[str]:
    out: set[str] = set()
    for n in names:
        try:
            out |= {st.custom_emoji_id for st in (await ctx.bot.get_sticker_set(n)).stickers}
        except TelegramBadRequest:
            pass
    return out


async def drop_unused(ctx: Ctx, names: list[str]) -> int:
    """Убирает из своих паков то, на что не ссылается ни таблица emoji.py, ни свои значки (дубли)."""
    from .emoji import EMOJI
    con = ctx.accounts.con
    used = {cid for _, cid in EMOJI.values() if cid}
    used |= {r["value"] for r in con.execute("SELECT value FROM kv WHERE key LIKE 'pack:%'")}
    n = 0
    for name in names:
        try:
            pack = await ctx.bot.get_sticker_set(name)
        except TelegramBadRequest:
            continue
        for st in pack.stickers:
            if st.custom_emoji_id not in used:
                await patient(ctx.bot.delete_sticker_from_set, sticker=st.file_id)
                n += 1
    return n


async def copy_picked(ctx: Ctx, owner_id: int, icons_set: str) -> list[str]:
    """Подобранные премиум-эмодзи (таблица emoji.py) — копиями в свои паки по file_id.

    Одноцветные (needs_repainting) → «Sonar», цветные логотипы → «Sonar Logos» (иначе Telegram их обесцветит).
    Соответствие «исходный id → наш id» — в kv packsrc:<исходный id>; повторный запуск копирует только новые.
    """
    from aiogram.types import InputSticker
    from ..db import kv_get, kv_set
    from .emoji import EMOJI
    con = ctx.accounts.con
    src: dict[str, list[str]] = {}
    for key, (_, cid) in EMOJI.items():
        if cid and not key.startswith("badge_") and key != "logo_sonar":
            src.setdefault(cid, []).append(key)
    logos = f"sonar_logos_by_{ctx.bot_username}"
    ours = await own_ids(ctx, [icons_set, logos])
    todo = [cid for cid in src if cid not in ours and not kv_get(con, f"packsrc:{cid}")]
    for i in range(0, len(todo), 200):
        for st in await ctx.bot.get_custom_emoji_stickers(custom_emoji_ids=todo[i:i + 200]):
            fmt = "video" if st.is_video else "animated" if st.is_animated else "static"
            inp = InputSticker(sticker=st.file_id, format=fmt, emoji_list=[st.emoji or "⭐"])
            target = icons_set if st.needs_repainting else logos
            try:
                await patient(ctx.bot.add_sticker_to_set, user_id=owner_id, name=target, sticker=inp)
            except TelegramBadRequest as e:
                if target == logos and "STICKERSET_INVALID" in str(e):
                    await ctx.bot.create_new_sticker_set(user_id=owner_id, name=logos, title="Sonar Logos", stickers=[inp],
                                                         sticker_type="custom_emoji", needs_repainting=False)
                else:
                    await ctx.logs.error("Эмодзи не скопирован в пак", e)
                    continue
            pack = await ctx.bot.get_sticker_set(target)
            kv_set(con, f"packsrc:{st.custom_emoji_id}", pack.stickers[-1].custom_emoji_id)
    out = []
    for cid, keys in src.items():
        new = cid if cid in ours else kv_get(con, f"packsrc:{cid}")
        if new:
            out.append(f'<tg-emoji emoji-id="{new}">{EMOJI[keys[0]][0]}</tg-emoji> <code>{",".join(keys)}</code> — <code>{new}</code>')
    return out


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
    block = ctx.support.block_of(msg.from_user.id)
    if block:      # заблокировали, пока человек писал
        return await ctx.shower.send(msg.chat.id, S.report_blocked(block))
    user = ctx.accounts.by_tg(msg.from_user.id)
    tid = await ctx.support.create(user, msg, data.get("kind", "bug"), data.get("platform", "windows"))
    kind = data.get("kind", "bug")
    await ctx.logs.event("🔧" if kind == "bug" else "💡", "Новое обращение", msg.from_user,
                         [f"<code>#{tid}</code> · {S.PLATFORMS.get(data.get('platform', 'windows'))}"])
    await ctx.shower.send(msg.chat.id, S.ticket_opened(tid))


# ---- /pack: владелец сам докидывает значки в свои паки ----

PACK_HELP = ("Пришли значок — по одному сообщением:\n"
             "• картинку (фото или файлом PNG) — впишу в 100×100; белая/серая → пак «Sonar» (красится под текст),"
             " цветная → «Sonar Logos»;\n"
             "• премиум-эмодзи или стикер — скопирую.\n"
             "Подпись к картинке — обычный эмодзи-заменитель (иначе ⭐). Закончить — /done.")


@router.message(Command("pack"))
async def cmd_pack(msg: Message, state: FSMContext, ctx: Ctx):
    if not ctx.is_owner(msg.from_user.id):
        return
    await state.set_state(PackAdd.wait)
    await msg.answer(f"{e('success')} " + PACK_HELP, parse_mode="HTML")


@router.message(PackAdd.wait, Command("done"))
async def pack_done(msg: Message, state: FSMContext, ctx: Ctx):
    await state.clear()
    await msg.answer(f"{e('confirm')} Готово. Паки: https://t.me/addemoji/sonar_icons_by_{ctx.bot_username}"
                     f" · https://t.me/addemoji/sonar_logos_by_{ctx.bot_username}", parse_mode="HTML",
                     link_preview_options={"is_disabled": True})


def _placeholder(text: str | None) -> str:
    """Эмодзи-заменитель из подписи: первый символ не буква и не цифра, иначе ⭐."""
    s = (text or "").strip()
    return s.split()[0][:8] if s and not s[0].isalnum() else "⭐"


@router.message(PackAdd.wait)
async def pack_add(msg: Message, ctx: Ctx):
    from html import escape

    from aiogram.types import BufferedInputFile, InputSticker
    from .packimg import to_badge
    if not ctx.is_owner(msg.from_user.id):
        return
    icons, logos = f"sonar_icons_by_{ctx.bot_username}", f"sonar_logos_by_{ctx.bot_username}"
    custom = next((x.custom_emoji_id for x in (msg.entities or []) if x.type == "custom_emoji"), None)
    try:
        if custom or msg.sticker:
            st = (await ctx.bot.get_custom_emoji_stickers(custom_emoji_ids=[custom]))[0] if custom else msg.sticker
            fmt = "video" if st.is_video else "animated" if st.is_animated else "static"
            inp = InputSticker(sticker=st.file_id, format=fmt, emoji_list=[st.emoji or "⭐"])
            target = icons if (custom and st.needs_repainting) else logos
        else:
            file = msg.photo[-1] if msg.photo else msg.document if (msg.document and (msg.document.mime_type or "").startswith("image/")) else None
            if file is None:
                return await msg.answer("Нужна картинка, стикер или премиум-эмодзи. Закончить — /done.")
            raw = (await ctx.bot.download(file)).read()
            png, mono = to_badge(raw)
            inp = InputSticker(sticker=BufferedInputFile(png, "badge.png"), format="static",
                               emoji_list=[_placeholder(msg.caption)])
            target = icons if mono else logos
        await patient(ctx.bot.add_sticker_to_set, user_id=msg.from_user.id, name=target, sticker=inp)
        new = (await ctx.bot.get_sticker_set(target)).stickers[-1]
    except TelegramBadRequest as err:
        return await msg.answer(f"{e('cancel')} Не добавилось: <code>{escape(err.message)}</code>", parse_mode="HTML")
    pack = "Sonar" if target == icons else "Sonar Logos"
    await msg.answer(f'<tg-emoji emoji-id="{new.custom_emoji_id}">{new.emoji or "⭐"}</tg-emoji> в «{pack}» — '
                     f"<code>{new.custom_emoji_id}</code>\nСледующий или /done.", parse_mode="HTML")


@router.message(F.chat.type == "private")
async def any_message(msg: Message, ctx: Ctx):
    # Ответ владельца на пересланное обращение (пока нет группы поддержки).
    t = ctx.support.ticket_for_staff_message(msg)
    if t:
        await ctx.support.reply(t, msg)
        return await say(ctx, msg.chat.id, f"{e('sent')} Ушло пользователю", reply_to=msg.message_id)
    t = ctx.support.open_ticket(msg.from_user.id)
    if t:
        block = ctx.support.block_of(msg.from_user.id)
        if block:   # спам в открытое обращение: дальше не пересылаем
            return await ctx.shower.send(msg.chat.id, S.report_blocked(block))
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

