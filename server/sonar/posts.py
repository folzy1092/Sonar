"""Посты в канал от имени бота (BOT.md §2.6д): владелец присылает боту сообщение (текст, фото, видео — как
есть, с форматированием), собирает кнопки-ссылки кнопками бота и публикует копию в канал (`@SonarUpdates`).
Кнопки — свой текст и ссылка; готовые: «Windows» / «iPhone» на проверенные версии (releases.py); по сколько
в ряд — 1, 2 или 3. Чистая логика — здесь, экраны — bot/screens.py, шаги — bot/handlers.py.
"""
from __future__ import annotations

from dataclasses import asdict, dataclass, field

from .releases import ReleaseError, check_url

MAX_BUTTONS = 12
MAX_TEXT = 40


@dataclass
class Draft:
    chat_id: int = 0
    message_id: int = 0
    buttons: list[list[str]] = field(default_factory=list)   # [текст, ссылка]
    per_row: int = 2

    @classmethod
    def of(cls, d: dict | None) -> "Draft":
        d = d or {}
        return cls(d.get("chat_id", 0), d.get("message_id", 0), [list(b) for b in d.get("buttons", [])], d.get("per_row", 2))

    def dump(self) -> dict:
        return asdict(self)

    @property
    def ready(self) -> bool:
        return bool(self.message_id)

    def add(self, text: str, url: str) -> None:
        text = text.strip()
        if not text:
            raise ReleaseError("Пустой текст кнопки")
        if len(self.buttons) >= MAX_BUTTONS:
            raise ReleaseError(f"Не больше {MAX_BUTTONS} кнопок")
        self.buttons.append([text[:MAX_TEXT], check_url(url)])

    def pop(self) -> None:
        if self.buttons:
            self.buttons.pop()

    def cycle_row(self) -> int:
        self.per_row = self.per_row % 3 + 1
        return self.per_row

    def rows(self) -> list[list[list[str]]]:
        """Кнопки рядами по `per_row`; нечётная последняя — одна во всю ширину (как у Liner)."""
        n = max(1, self.per_row)
        return [self.buttons[i:i + n] for i in range(0, len(self.buttons), n)]
