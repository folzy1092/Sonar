"""Тексты и кнопки экранов бота по docs/BOT.md (вид сверен с макетом server/bot/mockup)."""
from __future__ import annotations

import json
from datetime import datetime, timezone

from ..accounts import User
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

def guest() -> Screen:
    return Screen(
        banner="main",
        html=f"Привет! Это <b>Sonar</b> — твой музыкальный плеер.\n"
             + quote("Аккаунт не привязан к Sonar\nВойди или зарегистрируйся, чтобы продолжить"),
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
                  kb=[[Btn("Скачать Sonar", "download", url=s.download_url)]])


def bye() -> Screen:
    return Screen(html=f"Ок, в другой раз {e('bye')}")


ERRORS = {
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
             + quote(f"Поддержка — кнопка {e('bug')} Баг / Идея ниже"),
        kb=[[Btn("Профиль", "profile", "profile"), Btn("Статистика", "stats", "stats:week")],
            [Btn("Сервисы", "services", "services"), Btn("Баг / Идея", "bug", "report")],
            [Btn("Скачать Sonar", "download", url=s.download_url)]],
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
    api = s.public_url or "https://sonar-api.folzy.ru"
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


def versions(s: Settings) -> Screen:
    rel = _latest_release()
    html = f"{e('versions')} <b>Тестирование</b>\n" + quote("Скачивай свежие сборки. Выбери файл для установки:")
    kb = []
    if rel:
        changes = "\n".join(f"• {h(c)}" for c in rel.get("changes", [])[:4])
        html += quote(f"{e('new')} <b>Что нового (v{h(rel['version'])}):</b>\n{changes}")
        kb.append([Btn(f"Windows (v{rel['version']})", "logo_windows", url=s.download_url)])
    kb.append([back("profile")])
    return Screen(html=html, kb=kb)


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
        parts.append(f"{i.ms} мс")
    if extra:
        parts.append(extra)
    return f"{e(icon)} " + " · ".join(parts)


def _mark(i: Item | None) -> str:
    if i is None:
        return e("partial")
    if i.state == PARTIAL and i.ms:
        return f"{e('partial')} {i.ms / 1000:.1f} с"
    return e({OK: "ok", PARTIAL: "partial", DOWN: "down"}[i.state])


def _tree(lines: list[str]) -> str:
    return "\n".join(("└ " if n == len(lines) - 1 else "├ ") + x for n, x in enumerate(lines))


def status(items: dict[str, Item], online: int, users: int, uptime: float | None, owner: bool,
           unset: set[str] = frozenset()) -> Screen:
    """unset — пункты, которые ещё ни разу не работали (сайт, туннель до запуска): «не настроен», шапку не портят."""
    items = {k: v for k, v in items.items() if k not in unset}
    g = items.get
    infra_keys = ["main", "media", "proxy", "bot", "site", "storage"] if owner else ["main", "storage"]
    bad = [k for k in infra_keys if g(k) and g(k).state == DOWN and k not in ("site", "proxy")]
    partial = any(i.state != OK for k, i in items.items() if k in infra_keys + ["soundcloud", "yandex"])
    names = {"main": "Основной", "media": "Медиа", "proxy": "Прокси", "bot": "Бот", "site": "Сайт", "storage": "Хранилище"}
    icons = {"main": "desktop", "media": "track", "proxy": "proxy", "bot": "bot", "site": "web", "storage": "storage"}
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
        extra = g(k).note if (k == "storage" and owner and g(k)) else ""
        infra.append(f"{e(icons[k])} {names[k]}: {_st(g(k), ms=owner and k != 'storage', extra=extra)}")
    up = "—" if uptime is None else f"{uptime:.2f}%"
    html = (f"{head}\n"
            + quote(f"{e('listening')} Слушают онлайн: <b>{online}</b>\n{e('users')} Пользователей: <b>{users}</b>\n"
                    f"{e('time')} Аптайм: <b>{up}</b>")
            + quote(_tree(infra), "Инфраструктура:")
            + quote(_tree([f"{e('logo_soundcloud')} SoundCloud: {_mark(g('soundcloud'))}",
                           f"{e('logo_yandex_music')} Яндекс Музыка: {_mark(g('yandex'))}"]), "Музыкальные платформы:"))
    if owner:
        other = [f"{e('lyrics')} lrclib: {_mark(g('lrclib'))} · Genius: {_mark(g('genius'))}"]
        tail = f"{e('logo_telegram')} Telegram: {_mark(g('telegram'))}"
        other.append((f"{e('logo_lastfm')} {LASTFM}: {_mark(g('lastfm'))} · " if g("lastfm") else "") + tail)
        html += quote(_tree(other), "Тексты и прочее:")
    return Screen(html=html, kb=[[Btn("Обновить", "refresh", "status"), Btn("Страница статуса", "web", url="https://sonar.folzy.ru/status")]])
