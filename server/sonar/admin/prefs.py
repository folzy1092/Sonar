"""Настройки без деплоя: правятся в админке, лежат в `kv` под `setting:<ключ>`.

Приём из TG Store: один декларативный список (ключ, подпись, умолчание, тип, подсказка) — по нему
рисуется форма и проверяется ввод; нет строки в базе — действует умолчание (а не пусто). Из LenguBot —
разделы: безопасные переключатели и тексты отдельно, опасного (удаления, рассылки) здесь нет.
Ссылки и тексты сразу применяются к `Settings` работающего бота (`apply`).
"""
from __future__ import annotations

import sqlite3
from dataclasses import dataclass

from ..config import Settings
from ..db import kv_get, kv_set, tx


DISCORD_APP_ID = "1571615944449466510"  # то же, что вшито в клиент (discord.rs APP_ID), не секрет


@dataclass(frozen=True)
class Pref:
    key: str
    label: str
    default: str
    kind: str          # toggle | text | textarea | url
    hint: str = ""
    attr: str | None = None   # поле Settings, которое переопределяет


SECTIONS: list[tuple[str, list[Pref]]] = [
    ("Флаги", [
        Pref("registration_open", "Регистрация открыта", "1", "toggle",
             "Выключено — бот не регистрирует новых, GET /config отдаёт registration_open: false.", "registration_open"),
        Pref("maintenance", "Режим обслуживания", "0", "toggle",
             "Клиенты показывают текст ниже вместо ошибок (GET /config).", "maintenance"),
        Pref("maintenance_text", "Текст обслуживания", "Sonar обновляется, вернёмся через несколько минут", "text",
             "До 200 символов.", "maintenance_text"),
        Pref("yandex_enabled", "Яндекс Музыка доступна", "1", "toggle",
             "Аварийный выключатель (ADMIN.md §5): выключено — клиенты пишут «Яндекс временно недоступен».", "yandex_enabled"),
    ]),
    ("Тексты бота", [
        Pref("bot_notice", "Объявление в главном меню", "", "textarea",
             "Показывается цитатой под приветствием /start. Пусто — ничего. HTML Telegram не нужен — текст как есть.", "bot_notice"),
    ]),
    ("Ссылки", [
        Pref("site_url", "Сайт", "https://try-sonar.ru", "url", "Профили /@username и быстрый вход.", "site_url"),
        Pref("channel", "Канал новостей", "@SonarUpdates", "text", "Куда бот публикует посты.", "channel"),
        Pref("download_url", "Скачать для Windows", "https://try-sonar.ru/downloads/release/Sonar-setup.exe", "url",
             "Если в боте нет проверенной версии.", "download_url"),
        Pref("download_url_ios", "Скачать для iPhone",
             "https://try-sonar.ru/downloads/release/Sonar.ipa", "url", "", "download_url_ios"),
    ]),
]
ALL = {p.key: p for _, ps in SECTIONS for p in ps}
MAX_LEN = {"text": 200, "url": 300, "textarea": 1000}


class PrefError(Exception):
    def __init__(self, key: str, code: str):
        super().__init__(code)
        self.key, self.code = key, code


def get(con: sqlite3.Connection, key: str) -> str:
    v = kv_get(con, "setting:" + key)
    return ALL[key].default if v is None else v


def values(con: sqlite3.Connection) -> dict[str, str]:
    return {k: get(con, k) for k in ALL}


def parse(form: dict[str, str]) -> dict[str, str]:
    """Форма → новые значения. Галочки, которых нет в форме, — «выкл» (так браузер шлёт пустой checkbox)."""
    out = {}
    for k, p in ALL.items():
        if p.kind == "toggle":
            out[k] = "1" if form.get(k) else "0"
            continue
        v = (form.get(k) or "").strip().replace("\r\n", "\n")
        if len(v) > MAX_LEN[p.kind]:
            raise PrefError(k, "too_long")
        if p.kind == "url" and v and not v.startswith("https://"):
            raise PrefError(k, "not_https")
        if p.kind == "url" and not v:
            v = p.default
        out[k] = v
    return out


def save(con: sqlite3.Connection, new: dict[str, str]) -> list[str]:
    """Записать изменившиеся; вернуть их ключи."""
    changed = [k for k, v in new.items() if v != get(con, k)]
    with tx(con):
        for k in changed:
            kv_set(con, "setting:" + k, new[k])
    return changed


def apply(con: sqlite3.Connection, s: Settings) -> None:
    """Перенести настройки из базы в Settings процесса (бот читает их оттуда)."""
    for k, p in ALL.items():
        if p.attr and hasattr(s, p.attr):
            v = get(con, k)
            setattr(s, p.attr, v == "1" if p.kind == "toggle" else v)


def public_config(con: sqlite3.Connection) -> dict:
    """`GET /config` — что клиентам можно знать без входа."""
    v = values(con)
    channel = v["channel"].lstrip("@")
    return {"discord_app_id": DISCORD_APP_ID, "site_url": v["site_url"], "telegram_url": f"https://t.me/{channel}",
            "registration_open": v["registration_open"] == "1",
            "maintenance": {"on": v["maintenance"] == "1", "text": v["maintenance_text"]},
            "services": {"yandex": v["yandex_enabled"] == "1"},
            "links": {"site": v["site_url"], "channel": v["channel"], "windows": v["download_url"],
                      "ios": v["download_url_ios"]}}
