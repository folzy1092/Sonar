"""Картинка → значок для пака премиум-эмодзи (команда владельца /pack): PNG 100×100, прозрачный фон."""
from __future__ import annotations

import io

from PIL import Image

SIZE = 100  # статичный custom emoji — ровно 100×100 (Bot API)


def to_badge(data: bytes) -> tuple[bytes, bool]:
    """Вписывает картинку в квадрат 100×100 с прозрачными полями.

    Возвращает (PNG, одноцветный ли). Одноцветный (белый/серый знак) идёт в пак «Sonar» — Telegram
    перекрашивает его под цвет текста; цветной — в «Sonar Logos», иначе цвета пропадут.
    """
    img = Image.open(io.BytesIO(data)).convert("RGBA")
    box = img.getchannel("A").getbbox()
    if box:
        img = img.crop(box)
    side = max(img.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    out = square.resize((SIZE, SIZE), Image.LANCZOS)
    buf = io.BytesIO()
    out.save(buf, "PNG")
    return buf.getvalue(), is_mono(out)


def is_mono(img: Image.Image, max_saturation: int = 40) -> bool:
    """Почти без цвета: у видимых пикселей низкая насыщенность (HSV)."""
    alpha = img.getchannel("A")
    hsv = img.convert("RGB").convert("HSV")
    sats = [s for (_, s, _), a in zip(hsv.getdata(), alpha.getdata()) if a > 32]
    if not sats:
        return True
    sats.sort()
    return sats[int(len(sats) * 0.9)] <= max_saturation  # 90-й процентиль: блики и края не в счёт
