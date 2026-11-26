"""Тексты и кнопки экранов бота по docs/BOT.md (вид сверен с макетом server/bot/mockup)."""
from __future__ import annotations

import json
from html import escape
from datetime import datetime, timezone

from ..accounts import User
from ..posts import Draft
from ..releases import AUDIENCES, PLATFORMS, Release, target_label
from ..config import REPO_DIR, Settings
from ..status import DOWN, OK, PARTIAL, Item
from .emoji import e, h
from .ui import Btn, Screen, code, quote

MONTHS = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
DAYS = ["воскресенье", "понедельник", "вторник", "среду", "четверг", "пятницу", "субботу"]
PERIODS = {"day": ("День", 1), "week": ("Неделя", 7), "month": ("Месяц", 30), "half": ("Полгода", 182), "year": ("Год", 365)}
# «Last.fm» Telegram сам делает ссылкой (как домен) — разрываем невидимым word joiner.
LASTFM = "Last⁠.fm"
PLATFORMS = {"windows": "Windows", "ios": "iOS", "android": "Android"}


def back(cb: str) -> Btn:
    return Btn("Назад", "back", cb)


def date_ru(ms: int) -> str:
    d = datetime.fromtimestamp(ms / 1000, tz=timezone.utc)
    return f"{d.day} {MONTHS[d.month - 1]} {d.year}"


# ---- без аккаунта, вход, регистрация ----

def notice(s: Settings | None) -> str:
    """Объявление из админки (Настройки → Тексты бота) цитатой; пусто — ничего."""
    return "\n" + quote(h(s.bot_notice)) if s and s.bot_notice.strip() else ""


def guest(s: Settings | None = None) -> Screen:
    return Screen(
        banner="main",
        html=f"Привет! Это <b>Sonar</b> — твой музыкальный плеер.\n"
             + quote("Аккаунт не привязан к Sonar\nВойди или зарегистрируйся, чтобы продолжить") + notice(s),
        kb=[[Btn("Войти", "login", "login"), Btn("Регистрация", "register", "register")]],
    )


def login_ask() -> Screen:
    return Screen(banner="login", html=f"<b>Вход</b> {e('login')}\n" + quote("Введи свой <b>логин</b>:"),
                  kb=[[Btn("Быстрая ссылка", "quick_link", "quick")], [Btn("Отмена", "cancel", "cancel")]])


def password_ask() -> Screen:
    return Screen(html=f"<b>Вход</b> {e('key')}\n" + quote("Теперь введи <b>пароль</b>:"),
                  kb=[[Btn("Отмена", "cancel", "cancel")]])


def no_user() -> Screen:
    return Screen(html=f"{e('cancel')} Такого аккаунта нет",
                  kb=[[Btn("Попробовать снова", "refresh", "login"), Btn("Регистрация", "register", "register")]])


def quick(url: str, until: str) -> Screen:
    return Screen(banner="login",
                  html=f"{e('quick_link')} <b>Быстрая ссылка</b>\n"
                       + quote(f"Открой на устройстве, где ты уже вошёл в Sonar. {e('wait')} Действует до <b>{until}</b>"),
                  kb=[[Btn("Открыть в Sonar", "logo_sonar", url=url)], [back("login")]])


def quick_expired() -> Screen:
    return Screen(banner="login", html=f"{e('wait')} <b>Ссылка истекла</b>\n" + quote("Ссылка живёт 5 минут. Сделай новую."),
                  kb=[[Btn("Новая ссылка", "refresh", "quick")], [back("login")]])


def success_linked(login: str) -> Screen:
    return Screen(html=f"<b>Успешно!</b> {e('success')}\n" + quote(f"Аккаунт {code(login)} теперь привязан к Telegram"))


def link_approve(login: str, who: str, ready: bool, code_: str) -> Screen:
    """Вход нового устройства через бота (BOT.md §3): «Разрешить» появляется через 3 секунды."""
    kb = ([[Btn("Разрешить", "confirm", f"lk:a:{code_}")]] if ready else []) + [[Btn("Отклонить", "cancel", f"lk:r:{code_}")]]
    return Screen(banner="login",
                  html=f"{e('status_down')} <b>Авторизация в аккаунт</b>\n"
                       + quote(f"Разрешить доступ к аккаунту {code('@' + login)} для: <b>{who}</b>")
                       + quote("Если тебе прислали эту ссылку и просят нажать — не разрешай. Так получают доступ к чужим аккаунтам."),
                  kb=kb)


def tg_link_confirm(login: str, code_: str) -> Screen:
    return Screen(banner="login",
                  html=f"{e('integration')} <b>Привязать Telegram</b>\n"
                       + quote(f"Привязать этот Telegram к аккаунту {code('@' + login)}? Через него можно будет входить в Sonar."),
                  kb=[[Btn("Привязать", "confirm", f"lk:t:{code_}")], [Btn("Отмена", "cancel", f"lk:r:{code_}")]])


def link_done(text: str, ok: bool = True) -> Screen:
    return Screen(html=(f"<b>Готово</b> {e('success')}\n" if ok else f"{e('cancel')} ") + quote(text))


def dotify_ask() -> Screen:
    return Screen(html=f"{e('like')} <b>Перенос из Dotify</b>\n"
                       + quote("Пришли файл <b>.dotifyplaylist</b> с Любимыми — в Dotify: Любимые → ⋯ → Экспорт. "
                               "Лайки добавятся в твой аккаунт Sonar без дублей."),
                  kb=[[Btn("Отмена", "cancel", "dot:no")]])


def dotify_preview(title: str, new: int, have: int, removed: int, unknown: int) -> Screen:
    lines = [f"Добавлю в Любимые: <b>{new}</b>", f"Уже в Любимых: <b>{have}</b>"]
    if removed:
        lines.append(f"Ты убрал их из Любимых сам — не верну: <b>{removed}</b>")
    if unknown:
        lines.append(f"Не SoundCloud и не Яндекс — пропущу: <b>{unknown}</b>")
    kb = ([[Btn(f"Добавить {new}", "confirm", "dot:ok")]] if new else []) + [[Btn("Отмена", "cancel", "dot:no")]]
    return Screen(html=f"{e('like')} <b>{escape(title)}</b> из Dotify\n" + quote("\n".join(lines)), kb=kb)


def dotify_done(new: int, have: int) -> Screen:
    return Screen(html=f"<b>Готово!</b> {e('success')}\n"
                       + quote(f"В Любимые добавлено: <b>{new}</b>, уже были: <b>{have}</b>. "
                               "На устройствах они появятся после синхронизации с сервером."))


def register_ask() -> Screen:
    return Screen(banner="register",
                  html=f"<b>Регистрация</b> {e('register')}\n" + quote("Придумай <b>логин</b>:\n3–24 символа: a-z, 0-9, _ и точка"),
                  kb=[[Btn("Отмена", "cancel", "cancel")]])


def register_password(login: str) -> Screen:
    return Screen(html=f"<b>Регистрация</b> {e('key')}\n"
                       + quote(f"Логин {code(login)} свободен. Придумай <b>пароль</b> (от 8 символов):"),
                  kb=[[Btn("Отмена", "cancel", "cancel")]])


def register_again() -> Screen:
    return Screen(html=f"<b>Регистрация</b> {e('key')}\n" + quote("Введи пароль <b>ещё раз</b>:"),
                  kb=[[Btn("Отмена", "cancel", "cancel")]])


def registered(login: str, s: Settings) -> Screen:
    return Screen(html=f"<b>Успешно!</b> {e('success')}\n" + quote(f"Аккаунт {code(login)} создан и привязан к Telegram"),
                  kb=[[Btn("Скачать Sonar", "download", "versions")]])


def bye() -> Screen:
    return Screen(html=f"Ок, в другой раз {e('bye')}")


ERRORS = {
    "registration_closed": f"{e('cancel')} Регистрация сейчас закрыта. Загляни позже.",
    "login_format": f"{e('cancel')} Логин — 3–24 символа: <code>a-z 0-9 _ .</code>",
    "login_taken": f"{e('cancel')} Такой логин уже занят. Придумай другой:",
    "password_short": f"{e('cancel')} Пароль — от 8 символов",
    "password_mismatch": f"{e('cancel')} Пароли не совпадают. Придумай пароль заново:",
    "bad_password": f"{e('cancel')} Неверный пароль",
    "too_many": f"{e('warning')} Слишком много попыток, попробуй через 15 минут",
    "no_password": f"{e('warning')} Сначала задай пароль в приложении — иначе потом не войдёшь.",
    "tg_taken": f"{e('warning')} Этот Telegram уже привязан к другому аккаунту.",
}


# ---- главное меню и профиль ----

def main(user: User, s: Settings) -> Screen:
    return Screen(
        banner="main",
        html=f"Привет, <b>{h(user.display_name)}</b>! {e('profile')}\n\nЧем я могу помочь?\n"
             + quote(f"Поддержка — кнопка {e('bug')} Баг / Идея ниже") + notice(s),
        kb=[[Btn("Профиль", "profile", "profile"), Btn("Статистика", "stats", "stats:week")],
            [Btn("Сервисы", "services", "services"), Btn("Баг / Идея", "bug", "report")],
            [Btn("Скачать Sonar", "download", "versions")]],
    )


def profile(user: User, services: dict[str, bool], week: tuple[int, int], s: Settings) -> Screen:
    mark = lambda ok: e("ok") if ok else e("down")  # noqa: E731
    svc = [f"{e('logo_soundcloud')} SoundCloud {mark(services['soundcloud'])}",
           f"{e('logo_yandex_music')} Яндекс Музыка {mark(services['yandex'])}"]
    if s.lastfm_api_key:
        svc.append(f"{e('logo_lastfm')} {LASTFM} {mark(services['lastfm'])}")
    html = (f"{e('profile')} <b>Твой профиль</b>\n"
            + quote(f"Имя: <a href=\"{s.site_url}/@{h(user.username)}\"><b>@{h(user.username)}</b></a>\n"
                    f"Логин: <tg-spoiler>{h(user.login)}</tg-spoiler> · {code(f'#{user.number}')}\n"
                    f"{e('date')} с {date_ru(user.created_at)}", "Аккаунт")
            + quote("\n".join(svc), "Сервисы")
            + quote(f"{e('time')} {week[0]} мин · {e('track')} {week[1]} треков", "Неделя"))
    return Screen(banner="profile", html=html, kb=[
        [Btn("Рефералка", "referral", "referral"), Btn("Интеграция", "integration", "integration")],
        [Btn("Выйти", "logout", "logout")],
        [Btn("Версии", "versions", "versions")],
        [back("main")],
    ])


def integration(token: str | None, s: Settings) -> Screen:
    head = f"{e('integration')} <b>Интеграция</b>\n\n"
    if not token:
        return Screen(html=head + quote("Токена нет. Он нужен selfbot и своим сервисам: «сейчас играет», профиль."),
                      kb=[[Btn("Создать токен", "success", "token:new")], [back("profile")]])
    api = (s.public_url or "https://try-sonar.ru") + "/api"
    return Screen(
        html=head
        + f"Сейчас играет {e('listening')}\n" + quote(f"GET {api}/oauth/now?token=...\nТекущий трек, обложка, тайминги") + "\n"
        + f"Профиль {e('profile')}\n" + quote(f"GET {api}/oauth/profile?token=...\nНикнейм и аватарка") + "\n"
        + f"{e('key')} Токен: <tg-spoiler>{code(token)}</tg-spoiler>",
        kb=[[Btn("Скопировать токен", "copy", copy=token)],
            [Btn("Обновить токен", "refresh", "token:ask_new")],
            [Btn("Отозвать токен", "revoke", "token:ask_revoke")],
            [back("profile")]],
    )


def ask(text: str, yes_cb: str, no_cb: str) -> Screen:
    return Screen(html=f"{e('warning')} <b>Точно?</b>\n" + quote(text),
                  kb=[[Btn("Да", "confirm", yes_cb), Btn("Назад", "back", no_cb)]])


def referral(user: User, invited: int, bot_username: str) -> Screen:
    link = f"https://t.me/{bot_username}?start=ref_{user.referral_code}"
    share = f"https://t.me/share/url?url={link}&text=Слушаю музыку в Sonar — заходи"
    return Screen(
        html=f"{e('referral')} <b>Рефералка</b>\n"
        + quote(f"{e('key')} Код: {code(user.referral_code)}\n{e('integration')} <a href=\"{link}\">Открыть ссылку</a>\n"
                f"{e('users')} Приглашено: <b>{invited}</b>")
        + quote(f"{e('info')} Приглашай друзей в Sonar — они зарегистрируются по твоей ссылке."),
        kb=[[Btn("Поделиться", "share", url=share)], [back("profile")]],
    )


def _latest_release() -> dict | None:
    try:
        items = json.loads((REPO_DIR / "updates" / "changelog.json").read_text(encoding="utf-8"))
        return items[0] if items else None
    except (OSError, ValueError):
        return None


def download_links(s: Settings, win: Release | None, ios: Release | None) -> list[list[Btn]]:
    """Кнопки скачивания: закреплённая проверенная версия, иначе — общая ссылка платформы."""
    return [[Btn("Windows", "logo_windows", url=win.url if win else s.download_url),
             Btn("iPhone", "logo_apple", url=ios.url if ios else s.download_url_ios)]]


def versions(s: Settings, win: Release | None = None, ios: Release | None = None, owner: bool = False,
             public: dict[str, Release | None] | None = None) -> Screen:
    rel = _latest_release()
    html = f"{e('versions')} <b>Версии</b>\n" + quote("Скачивай свежие сборки. Выбери платформу:")
    if public is not None:
        # последние актуальные релизы для всех (версии «только списку» — бета, не считаются)
        names = {"windows": "Windows", "ios": "iOS", "android": "Android"}
        html += quote("\n".join(f"{n}: <b>{h(public[k].version) if public.get(k) else '—'}</b>" for k, n in names.items()),
                      "Актуальные версии")
    lines = []
    for r in (win, ios):
        if r:
            lines.append(f"{e('logo_windows' if r.platform == 'windows' else 'logo_apple')} {r.platform_name}: <b>{h(r.version)}</b>")
    if lines:
        html += quote("\n".join(lines), "Проверенные")
    notes = next((r.notes for r in (ios, win) if r and r.notes), "")
    if notes:
        html += quote(f"{e('new')} <b>Что нового:</b>\n{h(notes)}")
    elif rel:
        changes = "\n".join(f"• {h(c)}" for c in rel.get("changes", [])[:4])
        html += quote(f"{e('new')} <b>Что нового:</b>\n{changes}")
    html += quote("iPhone: ставь IPA через ESign / Feather своей парой, дальше Sonar обновляется сам.")
    kb = download_links(s, win, ios)
    if owner:
        kb.append([Btn("Управление версиями", "integration", "rel:admin")])
    kb.append([back("profile")])
    return Screen(html=html, kb=kb)


# ---- управление версиями (только владелец, BOT.md §2.12) ----

def _audience(r: Release) -> str:
    if r.audience == "all":
        return "всем"
    names = ", ".join(target_label(t) for t in r.targets[:6]) + (" …" if len(r.targets) > 6 else "")
    return ("только: " if r.audience == "only" else "всем, кроме: ") + h(names)


def rel_admin(current: dict[str, Release | None], s: Settings) -> Screen:
    rows = []
    for key, name in PLATFORMS.items():
        r = current.get(key)
        fallback = s.download_url if key == "windows" else s.download_url_ios
        rows.append(f"<b>{name}</b>: " + (f"{h(r.version)} · {_audience(r)}" if r else f"общая ссылка ({h(fallback)})"))
    return Screen(
        html=f"{e('versions')} <b>Управление версиями</b>\n"
        + quote("\n".join(rows), "Сейчас у всех")
        + quote("Закрепи проверенную сборку ссылкой — её увидят в «Версии» и «Скачать». Можно показать только "
                "списку аккаунтов (тестерам) или скрыть от кого-то; алерт — сообщение всем, кому версия видна."),
        kb=[[Btn("+ Windows", "logo_windows", "rel:new:windows"), Btn("+ iPhone", "logo_apple", "rel:new:ios")],
            [Btn("История Windows", "logo_windows", "rel:list:windows"), Btn("История iPhone", "logo_apple", "rel:list:ios")],
            [Btn("Пост в канал", "sent", "post:new")],
            [back("versions")]],
    )


def rel_ask_url(platform: str) -> Screen:
    return Screen(html=f"{e('versions')} <b>Новая версия · {PLATFORMS[platform]}</b>\n"
                  + quote("Пришли ссылку на сборку: прямую на файл (.exe / .ipa) или на страницу релиза GitHub."),
                  kb=[[Btn("Отмена", "cancel", "rel:admin")]])


def rel_ask_version(platform: str, guess: str | None) -> Screen:
    return Screen(html=f"{e('versions')} <b>Номер версии · {PLATFORMS[platform]}</b>\n"
                  + quote("Как подписать версию? Например <code>0.1.42</code> или <code>build 229</code>."
                          + (f"\nИз ссылки: <code>{h(guess)}</code> — нажми кнопку, чтобы взять его." if guess else "")),
                  kb=([[Btn(guess, "confirm", "rel:ver")]] if guess else []) + [[Btn("Отмена", "cancel", "rel:admin")]])


def rel_ask_notes() -> Screen:
    return Screen(html=f"{e('new')} <b>Что нового</b>\n" + quote("Коротко, что в этой версии (покажется в «Версии» и в алерте)."),
                  kb=[[Btn("Без описания", "noop", "rel:nonotes")], [Btn("Отмена", "cancel", "rel:admin")]])


def rel_ask_audience() -> Screen:
    return Screen(html=f"{e('users')} <b>Кому видна версия?</b>\n"
                  + quote("«Только списку» — тестерам, остальные видят прошлую проверенную. «Всем, кроме» — спрятать от кого-то."),
                  kb=[[Btn(AUDIENCES["all"], "users", "rel:aud:all")],
                      [Btn(AUDIENCES["only"], "profile", "rel:aud:only")],
                      [Btn(AUDIENCES["except"], "warning", "rel:aud:except")],
                      [Btn("Отмена", "cancel", "rel:admin")]])


def rel_ask_targets(audience: str) -> Screen:
    what = "кому показать" if audience == "only" else "от кого спрятать"
    return Screen(html=f"{e('users')} <b>Список аккаунтов</b>\n"
                  + quote(f"Пришли, {what}: <code>@username</code>, логин, <code>#номер</code> или Telegram id — "
                          "через пробел, запятую или с новой строки."),
                  kb=[[Btn("Отмена", "cancel", "rel:admin")]])


def rel_confirm(d: dict) -> Screen:
    aud = AUDIENCES[d["audience"]] + (": " + ", ".join(target_label(t) for t in d.get("targets", [])) if d.get("targets") else "")
    return Screen(
        html=f"{e('versions')} <b>Проверь</b>\n"
        + quote(f"Платформа: <b>{PLATFORMS[d['platform']]}</b>\nВерсия: <b>{h(d['version'])}</b>\n"
                f"Ссылка: {h(d['url'])}\nКому: {h(aud)}" + (f"\n\n{h(d['notes'])}" if d.get("notes") else "")),
        kb=[[Btn("Сохранить", "confirm", "rel:save:0"), Btn("Сохранить и разослать", "sent", "rel:save:1")],
            [Btn("Отмена", "cancel", "rel:admin")]],
    )


def rel_list(platform: str, items: list[Release]) -> Screen:
    if not items:
        body = quote("Закреплённых версий пока нет — у всех общая ссылка.")
    else:
        body = quote("\n".join(f"{'🟢' if r.active else '⚪️'} <b>{h(r.version)}</b> · {date_ru(r.created_at)} · {_audience(r)}"
                                for r in items))
    kb = [[Btn(f"{'' if r.active else '(снята) '}{r.version}", "versions", f"rel:item:{r.id}")] for r in items]
    kb.append([back("rel:admin")])
    return Screen(html=f"{e('versions')} <b>История · {PLATFORMS[platform]}</b>\n" + body, kb=kb)


def rel_item(r: Release, recipients: int) -> Screen:
    state = "закреплена" if r.active else "снята"
    alerted = f"\nАлерт: {date_ru(r.alerted_at)}" if r.alerted_at else ""
    return Screen(
        html=f"{e('versions')} <b>{r.platform_name} · {h(r.version)}</b>\n"
        + quote(f"Статус: {state}\nКому: {_audience(r)}\nПолучат алерт: <b>{recipients}</b>{alerted}\nСсылка: {h(r.url)}")
        + (quote(h(r.notes)) if r.notes else ""),
        kb=[[Btn("Разослать алерт", "sent", f"rel:alert:{r.id}")],
            [Btn("Снять" if r.active else "Вернуть", "revoke" if r.active else "refresh", f"rel:toggle:{r.id}")],
            [back(f"rel:list:{r.platform}")]],
    )


# ---- пост в канал (только владелец, BOT.md §2.6д) ----

def post_ask(channel: str) -> Screen:
    return Screen(html=f"{e('sent')} <b>Пост в {h(channel)}</b>\n"
                  + quote("Пришли пост — текст, фото или видео с подписью, как его увидит канал. "
                          "Форматирование сохранится. Кнопки добавим дальше."),
                  kb=[[Btn("Отмена", "cancel", "rel:admin")]])


def post_builder(d: Draft, channel: str) -> Screen:
    if d.buttons:
        lines = "\n".join(f"{i}. <b>{h(t)}</b> → {h(u)}" for i, (t, u) in enumerate(d.buttons, 1))
    else:
        lines = "Кнопок пока нет — пост уйдёт без них."
    return Screen(
        html=f"{e('sent')} <b>Кнопки поста</b>\n" + quote(lines, f"В ряд по {d.per_row}")
        + quote(f"Канал: {h(channel)}. «Предпросмотр» пришлёт пост сюда — так он будет выглядеть."),
        kb=[[Btn("+ Своя кнопка", "success", "post:add")],
            [Btn("+ Windows", "logo_windows", "post:preset:windows"), Btn("+ iPhone", "logo_apple", "post:preset:ios")],
            [Btn(f"В ряд: {d.per_row}", "refresh", "post:row"), Btn("Убрать последнюю", "revoke", "post:pop")],
            [Btn("Предпросмотр", "versions", "post:preview"), Btn("Опубликовать", "confirm", "post:ask")],
            [Btn("Отмена", "cancel", "rel:admin")]],
    )


def post_ask_button_text() -> Screen:
    return Screen(html=f"{e('success')} <b>Текст кнопки</b>\n" + quote("Например: <code>Windows</code>, <code>как запустить…</code>"),
                  kb=[[Btn("Назад", "back", "post:back")]])


def post_ask_button_url(text: str) -> Screen:
    return Screen(html=f"{e('integration')} <b>Ссылка для «{h(text)}»</b>\n" + quote("Пришли ссылку https://…"),
                  kb=[[Btn("Назад", "back", "post:back")]])


def post_confirm(channel: str, buttons: int) -> Screen:
    return Screen(html=f"{e('warning')} <b>Опубликовать?</b>\n" + quote(f"Пост с {buttons} кнопк. уйдёт в {h(channel)} от имени бота."),
                  kb=[[Btn("Опубликовать", "confirm", "post:publish"), Btn("Назад", "back", "post:back")]])


def rel_alert(r: Release) -> Screen:
    """Само сообщение пользователю о новой версии."""
    return Screen(
        html=f"{e('new')} <b>Новая версия Sonar · {r.platform_name}</b>\n"
        + quote(f"<b>{h(r.version)}</b>" + (f"\n{h(r.notes)}" if r.notes else "")),
        kb=[[Btn("Скачать", "download", url=r.url)]],
    )


def logout_ask() -> Screen:
    return Screen(html=f"{e('logout')} <b>Выход</b>\n" + quote("Ты уверен, что хочешь выйти? Придётся авторизоваться заново."),
                  kb=[[Btn("Подтвердить", "confirm", "logout:yes")], [back("profile")]])


# ---- статистика и сервисы ----

def stats(period: str, st: dict) -> Screen:
    name, _ = PERIODS[period]
    per = lambda k: Btn(("• " if k == period else "") + PERIODS[k][0], None, f"stats:{k}")  # noqa: E731
    kb = [[per("day"), per("week"), per("month")], [per("half"), per("year")], [back("main")]]
    if not st["tracks"]:
        return Screen(banner="stats", kb=kb, html=f"{e('stats')} <b>Статистика · {name}</b>\n"
                      + quote(f"{e('info')} Пока нет прослушиваний за этот период — включи музыку в Sonar."))
    delta = "" if st["delta"] is None else f" · <b>{st['delta']:+d}%</b> к прошлому периоду"
    html = f"{e('stats')} <b>Статистика · {name}</b>\n" + quote(f"{e('time')} {st['minutes']} мин{delta}\n{e('track')} {st['tracks']} треков")
    if st["artists"]:
        html += quote("\n".join(f"{i}. {h(a)}" for i, a in enumerate(st["artists"], 1)), "Топ артистов")
    if st["top_tracks"]:
        html += quote("\n".join(f"{i}. {h(t)}" for i, t in enumerate(st["top_tracks"], 1)), "Топ треков")
    if st["day"] is not None:
        html += quote(f"{e('date')} Самый активный день: <b>{DAYS[st['day']]}</b>\n{e('time')} Самый активный час: <b>{st['hour']:02d}:00</b>")
    return Screen(banner="stats", html=html, kb=kb)


YM_HELP = ("1. Открой ссылку кнопкой ниже.\n2. Войди в Яндекс и нажми «Разрешить».\n"
           "3. Адрес станет вида music.yandex.ru/#access_token=…\n   Не успел — возьми его из истории (Ctrl+H).\n"
           "4. Токен — между access_token= и &amp;token_type.\n   Вставь в Sonar → Настройки → Сервисы.")
SC_HELP = ("1. Открой soundcloud.com и войди.\n2. OAuth-токен: F12 → Application → Cookies → oauth_token.\n"
           "3. client_id: F12 → Network → F5 → фильтр client_id → значение после client_id=.\n"
           "4. Вставь оба в Sonar → Настройки → Сервисы.")
YM_OAUTH = "https://oauth.yandex.ru/authorize?response_type=token&client_id=23cabbbdc6cd418abb4b39c32c41195d"


def services(tab: str | None = None) -> Screen:
    tabs = [Btn("Яндекс Музыка", "logo_yandex_music", "services:ym"), Btn("SoundCloud", "logo_soundcloud", "services:sc")]
    tail = "\n" + quote(f"{e('info')} Токены вставляй в приложении, не сюда — бот такие сообщения удаляет.")
    if tab == "ym":
        return Screen(banner="main", html=f"{e('logo_yandex_music')} <b>Яндекс Музыка</b>\n" + quote(YM_HELP)
                      + quote(f"{e('warning')} Никому не отправляй токен. В приложении есть вход в один клик — он делает то же самое сам.") + tail,
                      kb=[[Btn("Открыть ссылку Яндекса", "integration", url=YM_OAUTH)], tabs, [back("services")]])
    if tab == "sc":
        return Screen(banner="main", html=f"{e('logo_soundcloud')} <b>SoundCloud</b> (с компьютера)\n" + quote(SC_HELP)
                      + quote(f"{e('warning')} Никому не отправляй oauth_token — это доступ к твоему аккаунту.") + tail,
                      kb=[tabs, [back("services")]])
    return Screen(banner="main", html=f"{e('services')} <b>Сервисы</b>\n\nКак подключить музыку к Sonar. Выбери сервис:" + tail,
                  kb=[tabs, [back("main")]])


# ---- баг / идея ----

def report_kind() -> Screen:
    return Screen(banner="main", html=f"<b>Баг или идея?</b> {e('bug')}",
                  kb=[[Btn("Баг", "bug", "report:bug"), Btn("Идея", "idea", "report:idea")], [back("main")]])


def report_platform(kind: str) -> Screen:
    title = "Где произошёл баг?" if kind == "bug" else "В какое приложение добавить?"
    return Screen(banner="main", html=f"<b>{title}</b>", kb=[
        [Btn("Windows", "logo_windows", f"report:{kind}:windows"), Btn("iOS", "logo_apple", f"report:{kind}:ios")],
        [Btn("Android · в разработке", "logo_android", "android")],
        [back("report")],
    ])


def report_prompt(kind: str) -> Screen:
    html = "<b>Что случилось?</b>\nМожно приложить скриншот или видео." if kind == "bug" else "<b>Расскажи идею</b>\nМожно приложить картинку."
    return Screen(banner="main", html=html, kb=[[Btn("Отмена", "cancel", "cancel")]])


def ticket_opened(tid: str) -> Screen:
    return Screen(html=f"<b>Отправлено!</b> {e('success')}\n" + quote(f"Обращение {code('#' + tid)} создано. Пиши сюда — всё уйдёт в поддержку."),
                  kb=[[Btn("Закрыть обращение", "cancel", f"ticket:close:{tid}")]])


def ticket_closed(tid: str) -> str:
    return f"{e('closed')} Обращение {code('#' + tid)} закрыто.\n" + quote(f"Если вопрос не решён — открой новое: {e('bug')} Баг / Идея")


# ---- /status ----

STATE_TEXT = {OK: "Работает", PARTIAL: "С перебоями", DOWN: "Недоступен"}


def _st(i: Item | None, ms: bool = False, extra: str = "") -> str:
    if i is None:
        return f"{e('partial')} нет данных"
    icon = {OK: "ok", PARTIAL: "partial", DOWN: "down"}[i.state]
    parts = [STATE_TEXT[i.state]]
    if ms and i.ms is not None and i.state != DOWN:
        parts.append(f"{i.ms} мс" if i.ms else "&lt; 1 мс")
    if extra:
        parts.append(extra)
    return f"{e(icon)} " + " · ".join(parts)


def _mark(i: Item | None, why: bool = False) -> str:
    """why — владельцу: у ⚠️ / ❌ причина (HTTP-код, таймаут, медленно)."""
    if i is None:
        return e("partial")
    mark = e({OK: "ok", PARTIAL: "partial", DOWN: "down"}[i.state])
    if why and i.state != OK and i.note:
        return f"{mark} {i.note}"
    if i.state == PARTIAL and i.ms:
        return f"{mark} {i.ms / 1000:.1f} с"
    return mark


def _tree(lines: list[str]) -> str:
    return "\n".join(("└ " if n == len(lines) - 1 else "├ ") + x for n, x in enumerate(lines))


STATUS_PLATFORMS = [("soundcloud", "SoundCloud", "logo_soundcloud"), ("yandex", "Яндекс Музыка", "logo_yandex_music"),
                    ("youtube", "YouTube Music", "logo_youtube"), ("vk", "VK Музыка", "logo_vk_music"),
                    ("spotify", "Spotify", "logo_spotify"), ("apple", "Apple Music", "logo_apple_music")]


def status(items: dict[str, Item], online: int, users: int, uptime: float | None, owner: bool,
           unset: set[str] = frozenset(), day: int | None = None) -> Screen:
    """unset — пункты, которые ещё ни разу не работали (сайт, туннель до запуска): «не настроен», шапку не портят."""
    items = {k: v for k, v in items.items() if k not in unset}
    g = items.get
    # Хранилище и подробности — только владельцу (решение 2026-11-25); остальным — «Основной» и платформы.
    infra_keys = ["main", "media", "proxy", "bot", "site", "storage"] if owner else ["main"]
    bad = [k for k in infra_keys if g(k) and g(k).state == DOWN and k not in ("site", "proxy")]
    partial = any(i.state != OK for k, i in items.items() if k in infra_keys + ["soundcloud", "yandex"])
    names = {"main": "Основной", "media": "Медиа", "proxy": "Прокси", "bot": "Бот", "site": "Сайт", "storage": "Хранилище"}
    icons = {"main": "server", "media": "track", "proxy": "proxy", "bot": "bot", "site": "web", "storage": "storage"}
    if bad:
        head = f"{e('status_down')} <b>Сбой: {', '.join(names[k] for k in bad)}</b>"
    elif partial:
        head = f"{e('status_partial')} <b>Некоторые сервисы работают с перебоями</b>"
    else:
        head = f"{e('status_ok')} <b>Все системы работают штатно</b>"
    infra = []
    for k in infra_keys:
        if k in unset:
            infra.append(f"{e(icons[k])} {names[k]}: {e('info')} не настроен")
            continue
        if k == "proxy" and not g(k):
            continue
        i = g(k)
        extra = i.note if (owner and i and i.note and (k == "storage" or i.state != OK)) else ""
        infra.append(f"{e(icons[k])} {names[k]}: {_st(g(k), ms=k == 'main' or (owner and k != 'storage'), extra=extra)}")
    up = "—" if uptime is None else f"{uptime:.2f}%"
    people = [f"{e('listening')} Слушают онлайн: <b>{online}</b>"]
    if day is not None:
        people.append(f"{e('profile')} Слушателей за 24 часа: <b>{day}</b>")
    people += [f"{e('users')} Пользователей: <b>{users}</b>", f"{e('time')} Аптайм: <b>{up}</b>"]
    # SoundCloud и Яндекс — с чем Sonar работает; остальные — видит ли их сервер (подключатся позже).
    platforms = [f"{e(icon_key)} {name}: {_mark(g(k), owner)}" for k, name, icon_key in STATUS_PLATFORMS
                 if k in ("soundcloud", "yandex") or g(k)]
    html = (f"{head}\n"
            + quote("\n".join(people))
            + quote(_tree(infra), "Инфраструктура:")
            + quote(_tree(platforms), "Музыкальные платформы:"))
    if owner:
        other = [f"{e('lyrics')} lrclib: {_mark(g('lrclib'), True)}", f"{e('lyrics')} Genius: {_mark(g('genius'), True)}"]
        if g("lastfm"):
            other.append(f"{e('logo_lastfm')} {LASTFM}: {_mark(g('lastfm'), True)}")
        other.append(f"{e('logo_telegram')} Telegram: {_mark(g('telegram'), True)}")
        html += quote(_tree(other), "Тексты и прочее:")
    return Screen(html=html, kb=[[Btn("Обновить", "refresh", "status")], [Btn("Страница статуса", "web", url="https://try-sonar.ru/status")]])


# ---- обновление сервера: скрытая /update, только владелец (sonar/updater.py) ----

def _update_lines(st: dict) -> list[str]:
    err, code_, site_ = st.get("errors", {}), st.get("code"), st.get("site")
    lines = []
    if err.get("code") or code_ is None:
        lines.append(f"{e('warning')} Сервер: GitHub не ответил — <code>{h(err.get('code', '?'))}</code>")
    elif code_["changed"]:
        lines.append(f"{e('new')} <b>Сервер</b> (бот, API, админка): <code>{h(_sha(code_['have']))}</code> → "
                     f"<code>{h(_sha(code_['remote']))}</code>")
        for c in code_["commits"]:
            sha, _, subject = c.partition(" ")
            lines.append(f"• <code>{h(sha)}</code> {h(subject)}")
        if code_["deps"]:
            lines.append("Поменяются зависимости — поставятся при старте.")
        lines.append("Перезапуск займёт секунд 20–40: бот и API на это время недоступны.")
    elif code_["new"]:
        lines.append(f"{e('ok')} Сервер: актуален <code>{h(_sha(code_['have']))}</code> "
                     "(в репо есть новое, но не в <code>server/</code>)")
    else:
        lines.append(f"{e('ok')} Сервер: актуален <code>{h(_sha(code_['have']))}</code>")
    if err.get("site") or site_ is None:
        lines.append(f"{e('warning')} Сайт: GitHub не ответил — <code>{h(err.get('site', '?'))}</code>")
    elif not site_["remote"]:
        lines.append(f"{e('info')} Сайт: в релизе <code>site-latest</code> нет архива")
    elif site_["new"]:
        lines.append(f"{e('new')} <b>Сайт</b>: есть новая сборка — обновится на лету, без перезапуска")
    else:
        lines.append(f"{e('ok')} Сайт: актуален")
    return lines


def _sha(sha: str) -> str:
    return (sha or "")[:8] or "—"


def update_menu(st: dict) -> Screen:
    code_, site_ = st.get("code") or {}, st.get("site") or {}
    new_code, new_site = bool(code_.get("changed")), bool(site_.get("new"))
    kb: list[list[Btn]] = []
    if new_code and new_site:
        kb.append([Btn("Обновить всё", "download", "upd:all")])
    row = ([Btn("Только сервер", "download", "upd:server")] if new_code else []) \
        + ([Btn("Только сайт", "web", "upd:site")] if new_site else [])
    if row:
        kb.append(row)
    kb.append([Btn("Проверить снова", "refresh", "upd:chk"), Btn("Перезапустить", "logout", "upd:rst")])
    return Screen(html=f"{e('refresh')} <b>Обновление сервера</b>\n" + quote("\n".join(_update_lines(st))), kb=kb)


def update_checking() -> Screen:
    return Screen(html=f"{e('wait')} Проверяю GitHub…")


def update_unavailable() -> Screen:
    return Screen(html=f"{e('info')} <b>Обновление недоступно</b>\n"
                       + quote("Сервер запущен не через <code>sync.py</code> — обновлять нечем. "
                               "На хостинге Velt он запускается именно так."))


def update_pending(what: str, st: dict) -> Screen:
    title = {"server": "Обновляю сервер", "all": "Обновляю сервер и сайт", "restart": "Перезапускаю сервер"}[what]
    lines = _update_lines(st) if what != "restart" else []
    lines.append("Бот и API остановятся секунд на 20–40, потом это сообщение изменится на итог.")
    return Screen(html=f"{e('wait')} <b>{title}</b>\n" + quote("\n".join(lines)))


def update_confirm_restart() -> Screen:
    return Screen(html=f"{e('refresh')} <b>Перезапустить сервер?</b>\n"
                       + quote("Код и сайт не обновляются — только перезапуск (подхватит правки <code>.env</code>). "
                               "Бот и API недоступны секунд 20–40."),
                  kb=[[Btn("Да, перезапустить", "confirm", "upd:rst_yes"), Btn("Отмена", "cancel", "upd:menu")]])


def update_site_done(state: str) -> Screen:
    text = {"updated": f"{e('ok')} <b>Сайт обновлён</b> — перезапуск не понадобился",
            "same": f"{e('ok')} Сайт уже актуален",
            "none": f"{e('info')} В релизе <code>site-latest</code> нет архива сайта — ничего не менял",
            "failed": f"{e('cancel')} <b>Сайт не обновился</b> — остаётся прежний. Подробности в журнале сервера"}[state]
    return Screen(html=text, kb=[[Btn("К обновлению", "back", "upd:menu")]])


def update_done(r: dict) -> Screen:
    old, cur, target = _sha(r.get("old", "")), _sha(r.get("current", "")), _sha(r.get("target", ""))
    what = r.get("what")
    if what == "restart":
        head, tail = f"{e('ok')} <b>Сервер перезапущен</b>", f"<code>{cur}</code>"
    elif r.get("ok"):
        head, tail = f"{e('ok')} <b>Сервер обновлён</b>", f"<code>{old}</code> → <code>{cur}</code>"
    elif r.get("ok") is False:
        head = f"{e('cancel')} <b>Перезапущен, но версия не та</b>"
        tail = f"ждал <code>{target}</code>, стоит <code>{cur}</code> — смотри журнал <code>sync.py</code>"
    else:
        head = f"{e('info')} <b>Сервер перезапущен</b>"
        tail = f"<code>{cur}</code> (новую версию GitHub проверить не удалось)"
    return Screen(html=head + "\n" + quote(tail), kb=[[Btn("К обновлению", "refresh", "upd:menu")]])


# ---- /admin: команды владельца (скрытая, только владелец) ----

def admin_menu(admin_url: str = "") -> Screen:
    kb = [[Btn("Открыть админку", "web", url=admin_url)]] if admin_url else []
    kb += [[Btn("Сбросить пароль админки", "key", "adm:pw")],
           [Btn("Обновление сервера", "refresh", "upd:chk"), Btn("Статус", "status_ok", "status")]]
    return Screen(html=f"{e('warning')} <b>Админ</b>\n"
                       + quote("Команды только для владельца. Обновление и перезапуск сервера — по частям, "
                               "сброс пароля — если забыл вход в админку."), kb=kb)


def admin_reset_confirm(login: str) -> Screen:
    return Screen(html=f"{e('key')} <b>Сбросить пароль админки?</b>\n"
                       + quote(f"Для <code>{h(login)}</code> появится новый случайный пароль, старый перестанет работать, "
                               "все сессии админки закроются. После входа сайт сразу попросит придумать свой."),
                  kb=[[Btn("Да, сбросить", "confirm", "adm:pw_yes"), Btn("Отмена", "cancel", "adm:menu")]])


def admin_reset_done(login: str, password: str, url: str, minutes: int) -> Screen:
    link = f"\nВход: {h(url)}" if url else ""
    return Screen(html=f"{e('success')} <b>Новый пароль админки</b>\n"
                       + quote(f"Логин: <code>{h(login)}</code>\nПароль: <code>{h(password)}</code>{link}\n"
                               f"Сообщение удалится через {minutes} мин — сохрани пароль сейчас. "
                               "После входа придумай свой."))
