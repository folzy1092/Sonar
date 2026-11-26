"""Выпуск сборок из бота (BOT.md §2.12е): владелец без пароля админки выбирает сборку CI на GitHub и делает её релизом.

То же, что «Сборки» в админке (`builds.publish`): сервер скачивает файлы к себе, клиенты обновляются с сайта, а кнопки
«Скачать» отдают файл с try-sonar.ru. Описание берётся из заметок сборки (русское и английское — один текст; тонкая правка —
в админке). Кнопка «Убрать с сайта» отзывает релиз (`builds.set_revoked`: клиенты не видят, файл остаётся). Только канал «релиз»: бета идёт с GitHub напрямую и только владельцу (`api/updates.py`).
Роутер подключается раньше основного, как у `moderation.py`.
"""
from __future__ import annotations

import logging

from aiogram import F, Router
from aiogram.types import CallbackQuery

from .. import builds
from ..admin import users as admin_users
from ..admin.web import MESSAGES
from . import screens as S

router = Router()
log = logging.getLogger("sonar.publishing")
SHOWN = 3        # последних сборок на платформу


def _state(published: dict[str, builds.Build], tag: str) -> str:
    b = published.get(tag)
    return "new" if b is None else ("revoked" if b.revoked else "release")


async def _rows(ctx) -> list[dict]:
    """Последние сборки CI (Windows и iPhone) с отметкой, какие уже выпущены в релиз."""
    published = {b.tag: b for b in builds.listing(ctx.accounts.con) if b.channel == "release"}
    rows, count = [], {"windows": 0, "ios": 0}
    for rel in await ctx.github.releases():
        tag = rel.get("tag_name", "")
        platform = builds.platform_of(tag)
        if count[platform] >= SHOWN:
            continue
        count[platform] += 1
        rows.append({"tag": tag, "platform": platform, "version": rel.get("name", ""), "state": _state(published, tag)})
    return rows


def _notes(release: dict, tag: str) -> dict[str, str]:
    """Заметки сборки CI (для Windows — из changelog, для iPhone — список коммитов); русский и английский — один текст."""
    body = (release.get("body") or "").strip() or f"Сборка {tag}"
    return {"ru": body[:builds.NOTES_MAX], "en": body[:builds.NOTES_MAX]}


@router.callback_query(F.data.startswith("bld:"))
async def bld_button(q: CallbackQuery, ctx):
    if not ctx.is_owner(q.from_user.id):
        return await q.answer("Только для владельца", show_alert=True)
    await q.answer()
    edit = lambda s: ctx.shower.edit(q.message, s)  # noqa: E731
    if ctx.github is None:
        return await edit(S.build_failed("Выпуск недоступен: нет связи с GitHub у этого сервера."))
    act, _, arg = (q.data or "")[4:].partition(":")
    if act == "list":
        try:
            return await edit(S.builds_list(await _rows(ctx)))
        except builds.BuildError as err:
            return await edit(S.builds_list([], MESSAGES.get(err.code, err.code)))
    if act in ("rev", "res") and builds.TAG_RE.match(arg):
        found = builds.pinned(ctx.accounts.con, builds.platform_of(arg), "release", arg, any_state=True)
        if found is None:
            return await edit(S.build_failed("Такой сборки нет в релизе на сайте."))
        who = f"telegram:{q.from_user.id}"
        builds.set_revoked(ctx.accounts.con, found.id, act == "rev")
        admin_users.audit(ctx.accounts.con, who, "revoke_build" if act == "rev" else "restore_build", found.tag,
                          channel=found.channel, via="bot")
        try:
            return await edit(S.builds_list(await _rows(ctx)))
        except builds.BuildError as err:
            return await edit(S.builds_list([], MESSAGES.get(err.code, err.code)))
    if act == "pub" and builds.TAG_RE.match(arg):
        await edit(S.build_publishing(arg))
        who = f"telegram:{q.from_user.id}"
        try:
            release = await ctx.github.release(arg)
            b = await builds.publish(ctx.accounts.con, ctx.settings.data_dir, ctx.github, arg, "release", _notes(release, arg), who)
        except builds.BuildError as err:
            log.warning("выпуск %s из бота не вышел: %s", arg, err.code)
            return await edit(S.build_failed(MESSAGES.get(err.code, err.code)))
        admin_users.audit(ctx.accounts.con, who, "publish_build", b.tag, channel=b.channel, version=b.version, size=b.size,
                          sha256=b.sha256, via="bot")
        return await edit(S.build_published(b))
    return None
