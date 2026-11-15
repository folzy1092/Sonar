"""Баннеры бота @SonarMusicApp (BOT.md §0): JPEG 1280×640 — тёмный градиент, значок + слово.

Всё рисуется здесь же (знак Sonar — из brand/logo.svg, значки — простые фигуры), чужих картинок нет.
Запуск: python server/tools/make_banners.py  →  server/sonar/bot/assets/*.jpg
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "server", "sonar", "bot", "assets")
sys.path.insert(0, os.path.join(ROOT, "brand", "emoji"))
from make_badges import logo_polys  # noqa: E402

W, H = 1280, 640
FG = (242, 242, 242)
FONTS = ["seguisb.ttf", "segoeuib.ttf", "DejaVuSans-Bold.ttf", "arialbd.ttf"]


def font(size):
    for name in FONTS:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    raise SystemExit("нет жирного шрифта (Segoe UI / DejaVu Sans)")


def background():
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    # линейный градиент 160°: #26292e → #0b0c0f
    t = np.clip((x * math.sin(math.radians(20)) + y * math.cos(math.radians(20))) / (W * 0.34 + H * 0.94), 0, 1)[..., None]
    c = np.array([38, 41, 46], np.float32) * (1 - t) + np.array([11, 12, 15], np.float32) * t

    def glow(cx, cy, rx, ry, col, k):
        d = np.sqrt(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2)
        a = np.clip(1 - d, 0, 1)[..., None] ** 1.6 * k
        return a * (np.array(col, np.float32) - c)

    c = c + glow(W * .30, H * .20, W * .70, H * .90, (58, 63, 71), .9)
    c = c + glow(W * .85, H * 1.0, W * .60, H * .80, (36, 40, 46), .6)
    c = c * (1 - np.clip((y - H * .6) / (H * .4), 0, 1)[..., None] * .25)  # низ темнее
    noise = np.random.default_rng(7).normal(0, 1.4, (H, W, 1))            # без полос на градиенте
    return Image.fromarray(np.clip(c + noise, 0, 255).astype(np.uint8), "RGB")


# ---- значки: маска s×s (255 — закрашено) ----

def icon_logo(s):
    acc = np.zeros((s, s), bool)
    for p in logo_polys(s, s * 0.98):
        t = Image.new("L", (s, s), 0)
        ImageDraw.Draw(t).polygon(p, fill=255)
        acc ^= np.array(t) > 127
    return Image.fromarray((acc * 255).astype(np.uint8))


def icon_profile(s):
    m = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(m)
    d.ellipse([s * .30, s * .06, s * .70, s * .46], fill=255)
    d.pieslice([s * .10, s * .54, s * .90, s * 1.34], 180, 360, fill=255)
    return m


def icon_login(s):
    m = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(m)
    w = int(s * .085)
    d.arc([s * .27, s * .06, s * .73, s * .62], 180, 360, fill=255, width=w)
    d.rectangle([s * .27, s * .33, s * .27 + w, s * .46], fill=255)
    d.rectangle([s * .73 - w, s * .33, s * .73, s * .46], fill=255)
    d.rounded_rectangle([s * .14, s * .44, s * .86, s * .94], s * .1, fill=255)
    d.ellipse([s * .44, s * .58, s * .56, s * .70], fill=0)
    d.rectangle([s * .475, s * .66, s * .525, s * .80], fill=0)
    return m


def icon_register(s):
    m = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(m)
    w = int(s * .08)
    d.rounded_rectangle([s * .08, s * .16, s * .78, s * .92], s * .1, outline=255, width=w)
    d.rectangle([s * .44, s * .02, s * 1.0, s * .54], fill=0)
    d.polygon([(s * .86, s * .06), (s * .98, s * .18), (s * .50, s * .66), (s * .36, s * .70), (s * .40, s * .56)], fill=255)
    return m


def icon_stats(s):
    m = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(m)
    for i, h in enumerate((.42, .78, .58, .96)):
        x0 = s * (.06 + i * .235)
        d.rounded_rectangle([x0, s * (1 - h), x0 + s * .17, s * .98], s * .05, fill=255)
    return m


def icon_support(s):
    m = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([s * .04, s * .08, s * .96, s * .74], s * .2, fill=255)
    d.polygon([(s * .22, s * .66), (s * .44, s * .70), (s * .16, s * .94)], fill=255)
    for cx in (.30, .50, .70):
        d.ellipse([s * (cx - .06), s * .35, s * (cx + .06), s * .47], fill=0)
    return m


BANNERS = {
    "main": (icon_logo, "Sonar"),
    "profile": (icon_profile, "Профиль"),
    "login": (icon_login, "Вход"),
    "register": (icon_register, "Регистрация"),
    "stats": (icon_stats, "Статистика"),
    "support": (icon_support, "Поддержка"),
}


def render(icon, word):
    img = background()
    f = font(128)
    size = 176 if icon is icon_logo else 140
    gap = 44
    bb = f.getbbox(word)
    total = size + gap + (bb[2] - bb[0])
    x0 = (W - total) // 2
    m = icon(size * 4).resize((size, size), Image.LANCZOS)  # рисуем в 4× — гладкие края
    iy = (H - size) // 2 + (0 if icon is icon_logo else 8)
    ty = (H - (bb[3] - bb[1])) // 2 - bb[1]
    tx = x0 + size + gap - bb[0]
    # мягкая тень под значком и словом
    shadow = Image.new("L", (W, H), 0)
    shadow.paste(m, (x0, iy + 6))
    ImageDraw.Draw(shadow).text((tx, ty + 6), word, font=f, fill=255)
    img.paste((0, 0, 0), (0, 0), shadow.filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v * .45)))
    img.paste(FG, (x0, iy), m)
    ImageDraw.Draw(img).text((tx, ty), word, font=f, fill=FG)
    return img


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, (icon, word) in BANNERS.items():
        render(icon, word).save(os.path.join(OUT, f"{name}.jpg"), quality=92, optimize=True)  # PNG с шумом — 700 КБ
        print(name)
