"""Блокировки в боте: команды владельца и фильтр для заблокированных (BOT.md §2.12г).

Команды (скрытые, только владелец; в меню их нет, `/admin` даёт кнопки и подсказку):
    /who <кто>                      карточка: статус бана и блока обращений, быстрые кнопки
    /ban <кто> [срок] [причина]     бан аккаунта; срок не указан — навсегда
    /unban <кто>
    /rban <кто> [срок] [причина]    блок обращений «Баг / Идея» (спам в топики поддержки)
    /runban <кто>
    /banned                         кто сейчас заблокирован и кому закрыты обращения
«кто» — логин, @username, #номер или Telegram ID. Срок — `30м`, `2ч`, `3д`, `1н` или `навсегда`.

Заблокированный на любое сообщение и любую кнопку получает «Учётная запись заблокирована»: срок и причина (`ban_gate`).
Роутер подключается **раньше** основного: там есть «поймать всё» для личных сообщений.
"""
from __future__ import annotations

import sqlite3

from aiogram import F, Router
from aiogram.filters import Command, CommandObject
from aiogram.types import CallbackQuery, Message

from .. import bans
from . import screens as S
from .emoji import e, h
from .ui import Btn, Screen, quote

router = Router()
PRESETS = {"1d": bans.DAY, "7d": 7 * bans.DAY, "perm": None}
PRESET_NAMES = {"1d": "1 дн", "7d": "7 дн", "perm": "навсегда"}


def _rows(buttons: list[Btn], per_row: int = 2) -> list[list[Btn]]:
    """Кнопки по две в ряд: три подписи вроде «Бан · навсегда» в одну строку Telegram обрезает."""
    return [buttons[i:i + per_row] for i in range(0, len(buttons), per_row)]
HELP = (f"{e('info')} <b>Блокировки</b>\n" + quote(
    "<code>/who кто</code> — карточка с кнопками\n"
    "<code>/ban кто [срок] [причина]</code> — бан аккаунта\n"
    "<code>/unban кто</code>\n"
    "<code>/rban кто [срок] [причина]</code> — закрыть баги и идеи (спам в поддержку)\n"
    "<code>/runban кто</code>\n"
    "<code>/banned</code> — списки\n\n"
    "кто: логин, <code>@username</code>, <code>#номер</code> или Telegram ID. "
    "Срок: <code>30м</code> <code>2ч</code> <code>3д</code> <code>1н</code> <code>навсегда</code>; не указан — навсегда."))


# ---- заблокированному: на всё одно и то же ----

async def ban_gate(handler, event, data):
    """Outer-middleware: заблокированный (кроме владельца) в личке получает экран бана и дальше не проходит."""
    ctx = data["ctx"]
    user = getattr(event, "from_user", None)
    chat = getattr(event, "chat", None) or getattr(getattr(event, "message", None), "chat", None)   # сообщение или кнопка
    if user is None or chat is None or chat.type != "private" or ctx.is_owner(user.id):
        return await handler(event, data)
    ban = bans.of_tg(ctx.accounts.con, user.id)
    if ban is None:
        return await handler(event, data)
    if getattr(event, "data", None) is not None:   # кнопка: убрать «часики»
        await event.answer()
    await ctx.shower.send(chat.id, S.banned(ban))
    return None


router.message.outer_middleware(ban_gate)
router.callback_query.outer_middleware(ban_gate)


# ---- поиск и карточка ----

def _tgref(tg_id: int) -> str:
    return f"tg{tg_id}"


def _resolve(con: sqlite3.Connection, ref: str) -> tuple[sqlite3.Row | None, int | None]:
    """Ссылка из кнопки (`u_…` или `tg<id>`) → (пользователь, tg_id для блока обращений)."""
    if ref.startswith("tg") and ref[2:].isdigit():
        tg_id = int(ref[2:])
        row = con.execute("SELECT * FROM users WHERE tg_id = ?", (tg_id,)).fetchone()
        return row, tg_id
    row = con.execute("SELECT * FROM users WHERE id = ?", (ref,)).fetchone()
    return row, (row["tg_id"] if row else None)


def _find(con: sqlite3.Connection, query: str) -> tuple[sqlite3.Row | None, int | None]:
    row = bans.find(con, query)
    if row is not None:
        return row, row["tg_id"]
    q = query.strip()
    return None, int(q) if q.isdigit() else None   # голый Telegram ID без аккаунта — для блока обращений


def card(ctx, row: sqlite3.Row | None, tg_id: int | None) -> Screen:
    con = ctx.accounts.con
    lines = []
    if row is not None:
        lines.append(f"<b>{h(row['display_name'])}</b> · <code>{h(row['login'])}</code> · @{h(row['username'])} · #{row['number']}")
        tg = f"{row['tg_id']}" + (f" (@{h(row['tg_username'])})" if row["tg_username"] else "") if row["tg_id"] else "не привязан"
        lines.append(f"Telegram: {tg}")
        devices = con.execute("SELECT COUNT(*) FROM sessions WHERE user_id = ?", (row["id"],)).fetchone()[0]
        lines.append(f"Устройств: {devices}")
        ban = bans.of_user(con, row["id"])
        lines.append(f"{e('cancel')} <b>Заблокирован {h(S._when(ban.until))}</b>" + (f" — {h(ban.reason)}" if ban.reason else "")
                     if ban else f"{e('ok')} Аккаунт не заблокирован")
    else:
        lines.append(f"Аккаунта нет, Telegram ID <code>{tg_id}</code>")
    block = bans.report_block_of(con, tg_id) if tg_id else None
    if tg_id:
        lines.append(f"{e('warning')} <b>Обращения закрыты {h(S._when(block.until))}</b>" + (f" — {h(block.reason)}" if block.reason else "")
                     if block else "Обращения (баги и идеи): открыты")
    ref = row["id"] if row is not None else _tgref(tg_id)
    kb: list[list[Btn]] = []
    if row is not None:
        if bans.of_user(con, row["id"]):
            kb.append([Btn("Разбанить", "confirm", f"mod:unban:{ref}")])
        else:
            kb += _rows([Btn(f"Бан {PRESET_NAMES[k]}", "cancel", f"mod:ban:{ref}:{k}") for k in PRESETS])
    if tg_id:
        if block:
            kb.append([Btn("Открыть репорты", "confirm", f"mod:rub:{ref}")])
        else:
            kb += _rows([Btn(f"Репорты {PRESET_NAMES[k]}", "bug", f"mod:rb:{ref}:{k}") for k in PRESETS])
    kb.append([Btn("Назад", "back", "adm:menu")])
    return Screen(html=f"{e('profile')} <b>Пользователь</b>\n" + quote("\n".join(lines)), kb=kb)


def _is_owner_account(ctx, row: sqlite3.Row | None, tg_id: int | None) -> bool:
    owner = ctx.settings.owner_tg_id
    return bool(owner) and (tg_id == owner or (row is not None and row["tg_id"] == owner))


def _nope(text: str) -> Screen:
    return Screen(html=f"{e('cancel')} {text}")


def _done(ctx, text: str, row, tg_id) -> Screen:
    c = card(ctx, row, tg_id)
    return Screen(html=f"{e('ok')} {text}\n\n" + c.html, kb=c.kb)


# ---- команды ----

def _owner(ctx, msg: Message) -> bool:
    return ctx.is_owner(msg.from_user.id)


@router.message(Command("who"))
async def cmd_who(msg: Message, command: CommandObject, ctx):
    if not _owner(ctx, msg):
        return
    if not command.args:
        return await ctx.shower.send(msg.chat.id, Screen(html=HELP))
    row, tg_id = _find(ctx.accounts.con, command.args.split()[0])
    if row is None and tg_id is None:
        return await ctx.shower.send(msg.chat.id, _nope("Такого пользователя нет."))
    await ctx.shower.send(msg.chat.id, card(ctx, row, tg_id))


@router.message(Command("ban"))
async def cmd_ban(msg: Message, command: CommandObject, ctx):
    if not _owner(ctx, msg):
        return
    who, duration, reason = bans.split_args(command.args)
    row, tg_id = _find(ctx.accounts.con, who)
    if not who or row is None:
        return await ctx.shower.send(msg.chat.id, Screen(html=HELP) if not who else _nope("Аккаунт не найден."))
    if _is_owner_account(ctx, row, tg_id):
        return await ctx.shower.send(msg.chat.id, _nope("Владельца не блокирую."))
    until = bans.until_from(duration)
    bans.ban(ctx.accounts.con, f"telegram:{msg.from_user.id}", row["id"], reason, until)
    await ctx.shower.send(msg.chat.id, _done(ctx, f"Заблокирован <code>{h(row['login'])}</code> {h(S._when(until))}", row, tg_id))


@router.message(Command("unban"))
async def cmd_unban(msg: Message, command: CommandObject, ctx):
    if not _owner(ctx, msg):
        return
    row, tg_id = _find(ctx.accounts.con, (command.args or "").split()[0] if command.args else "")
    if row is None:
        return await ctx.shower.send(msg.chat.id, Screen(html=HELP) if not command.args else _nope("Аккаунт не найден."))
    try:
        bans.unban(ctx.accounts.con, f"telegram:{msg.from_user.id}", row["id"])
    except bans.ModerationError:
        return await ctx.shower.send(msg.chat.id, _nope("Он и так не заблокирован."))
    await ctx.shower.send(msg.chat.id, _done(ctx, f"Разбанен <code>{h(row['login'])}</code>", row, tg_id))


@router.message(Command("rban"))
async def cmd_rban(msg: Message, command: CommandObject, ctx):
    if not _owner(ctx, msg):
        return
    who, duration, reason = bans.split_args(command.args)
    if not who:
        return await ctx.shower.send(msg.chat.id, Screen(html=HELP))
    row, tg_id = _find(ctx.accounts.con, who)
    if tg_id is None:
        return await ctx.shower.send(msg.chat.id, _nope("Аккаунт не найден, а у найденного нет привязанного Telegram: "
                                                         "обращения идут только через бота, закрывать нечего."))
    if _is_owner_account(ctx, row, tg_id):
        return await ctx.shower.send(msg.chat.id, _nope("Владельца не блокирую."))
    until = bans.until_from(duration)
    bans.report_block(ctx.accounts.con, f"telegram:{msg.from_user.id}", tg_id, reason, until)
    await ctx.shower.send(msg.chat.id, _done(ctx, f"Обращения закрыты {h(S._when(until))}", row, tg_id))


@router.message(Command("runban"))
async def cmd_runban(msg: Message, command: CommandObject, ctx):
    if not _owner(ctx, msg):
        return
    row, tg_id = _find(ctx.accounts.con, (command.args or "").split()[0] if command.args else "")
    if tg_id is None:
        return await ctx.shower.send(msg.chat.id, Screen(html=HELP) if not command.args else _nope("Не нашёл."))
    try:
        bans.report_unblock(ctx.accounts.con, f"telegram:{msg.from_user.id}", tg_id)
    except bans.ModerationError:
        return await ctx.shower.send(msg.chat.id, _nope("Обращения у него и так открыты."))
    await ctx.shower.send(msg.chat.id, _done(ctx, "Обращения снова открыты", row, tg_id))


@router.message(Command("banned"))
async def cmd_banned(msg: Message, ctx):
    if not _owner(ctx, msg):
        return
    await ctx.shower.send(msg.chat.id, banned_list(ctx))


def banned_list(ctx) -> Screen:
    con = ctx.accounts.con
    users = bans.banned_list(con)
    blocks = bans.report_blocks(con)
    out = [f"{e('cancel')} <b>Заблокированы</b>: {len(users)}"]
    out += [f"• <code>{h(u['login'])}</code> {h(S._when(u['ban_until']))}" + (f" — {h(u['ban_reason'])}" if u["ban_reason"] else "")
            for u in users] or ["Никого."]
    out += ["", f"{e('warning')} <b>Обращения закрыты</b>: {len(blocks)}"]
    out += [f"• <code>{h(b['login'] or b['tg_id'])}</code> {h(S._when(b['until'] or None))}" + (f" — {h(b['reason'])}" if b["reason"] else "")
            for b in blocks] or ["Никому."]
    out += ["", "Команды: /who /ban /unban /rban /runban — подробности в /admin"]
    return Screen(html="\n".join(out), kb=[[Btn("Назад", "back", "adm:menu")]])


# ---- кнопки ----

@router.callback_query(F.data.startswith("mod:"))
async def mod_button(q: CallbackQuery, ctx):
    if not ctx.is_owner(q.from_user.id):
        return await q.answer("Только для владельца", show_alert=True)
    await q.answer()
    parts = (q.data or "").split(":")
    act, ref = parts[1], parts[2] if len(parts) > 2 else ""
    arg = parts[3] if len(parts) > 3 else ""
    con = ctx.accounts.con
    row, tg_id = _resolve(con, ref)
    edit = lambda s: ctx.shower.edit(q.message, s)  # noqa: E731
    if act == "list":
        return await edit(banned_list(ctx))
    if row is None and tg_id is None:
        return await edit(_nope("Пользователь пропал."))
    who = f"telegram:{q.from_user.id}"
    if act in ("ban", "rb") and _is_owner_account(ctx, row, tg_id):
        return await edit(_nope("Владельца не блокирую."))
    try:
        if act == "ban" and row is not None and arg in PRESETS:
            until = bans.until_from(PRESETS[arg])
            bans.ban(con, who, row["id"], "", until)
            return await edit(_done(ctx, f"Заблокирован {h(S._when(until))}", row, tg_id))
        if act == "unban" and row is not None:
            bans.unban(con, who, row["id"])
            return await edit(_done(ctx, "Разбанен", row, tg_id))
        if act == "rb" and tg_id and arg in PRESETS:
            until = bans.until_from(PRESETS[arg])
            bans.report_block(con, who, tg_id, "", until)
            return await edit(_done(ctx, f"Обращения закрыты {h(S._when(until))}", row, tg_id))
        if act == "rub" and tg_id:
            bans.report_unblock(con, who, tg_id)
            return await edit(_done(ctx, "Обращения снова открыты", row, tg_id))
    except bans.ModerationError:
        pass
    return await edit(card(ctx, row, tg_id))
