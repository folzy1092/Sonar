"""Значки Sonar для премиум-эмодзи (свой пак): волнистая «розетка» с вырезанным знаком.

Рисуется с нуля (PIL, 4× сглаживание) — ничего не скопировано из чужих паков.
Значок белый на прозрачном: в паке с needs_repainting Telegram красит его под цвет текста.
Запуск: python brand/emoji/make_badges.py  →  brand/emoji/badges/*.png (100×100, как требует Telegram).
"""
import math, os
from PIL import Image, ImageDraw

S = 400                      # рисуем в 4×, потом уменьшаем до 100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "badges")
C = S / 2


def rosette(d, lobes=10, r=176, amp=13):
    pts = []
    for i in range(720):
        a = 2 * math.pi * i / 720
        rr = r + amp * math.cos(lobes * a)
        pts.append((C + rr * math.cos(a), C + rr * math.sin(a)))
    d.polygon(pts, fill=255)


def windows(d):
    g, s = 12, 72
    for dx in (-1, 1):
        for dy in (-1, 1):
            x0 = C + (g / 2 if dx > 0 else -g / 2 - s)
            y0 = C + (g / 2 if dy > 0 else -g / 2 - s)
            d.rounded_rectangle([x0, y0, x0 + s, y0 + s], 10, fill=0)


def iphone(d):
    w, h = 116, 196
    d.rounded_rectangle([C - w / 2, C - h / 2, C + w / 2, C + h / 2], 30, fill=0)
    d.rounded_rectangle([C - w / 2 + 12, C - h / 2 + 12, C + w / 2 - 12, C + h / 2 - 12], 20, fill=255)
    d.rounded_rectangle([C - 24, C - h / 2 + 22, C + 24, C - h / 2 + 36], 7, fill=0)


def android(d):
    # голова-полукруг, глаза, антенны, туловище
    d.pieslice([C - 82, C - 104, C + 82, C + 60], 180, 360, fill=0)
    d.ellipse([C - 44, C - 46, C - 28, C - 30], fill=255)
    d.ellipse([C + 28, C - 46, C + 44, C - 30], fill=255)
    for sgn in (-1, 1):
        d.line([(C + sgn * 44, C - 86), (C + sgn * 64, C - 116)], fill=0, width=10)
    d.rounded_rectangle([C - 82, C - 4, C + 82, C + 100], 18, fill=0)


def music(d):
    d.ellipse([C - 76, C + 34, C - 20, C + 86], fill=0)
    d.ellipse([C + 24, C + 14, C + 80, C + 66], fill=0)
    d.rectangle([C - 34, C - 80, C - 20, C + 60], fill=0)
    d.rectangle([C + 66, C - 100, C + 80, C + 40], fill=0)
    d.polygon([(C - 34, C - 80), (C + 80, C - 100), (C + 80, C - 66), (C - 34, C - 46)], fill=0)


def diamond(d):
    top, mid, bot = C - 70, C - 28, C + 92
    d.polygon([(C - 54, top), (C + 54, top), (C + 96, mid), (C, bot), (C - 96, mid)], fill=0)
    d.line([(C - 96, mid), (C + 96, mid)], fill=255, width=9)
    d.line([(C - 22, top), (C - 36, mid), (C, bot)], fill=255, width=8)
    d.line([(C + 22, top), (C + 36, mid), (C, bot)], fill=255, width=8)


def heart(d):
    pts = []
    for i in range(400):
        t = 2 * math.pi * i / 400
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        pts.append((C + x * 6.2, C - y * 6.2 + 6))
    d.polygon(pts, fill=0)


def bug(d):
    d.ellipse([C - 56, C - 46, C + 56, C + 96], fill=0)
    d.pieslice([C - 36, C - 86, C + 36, C - 14], 180, 360, fill=0)
    d.line([(C, C - 30), (C, C + 92)], fill=255, width=8)
    for y in (C - 6, C + 30, C + 64):
        d.line([(C - 54, y), (C - 92, y - 14)], fill=0, width=10)
        d.line([(C + 54, y), (C + 92, y - 14)], fill=0, width=10)


def wave(d):
    xs = range(int(C - 100), int(C + 101), 2)
    pts = [(x, C + 56 * math.sin((x - C) / 100 * 2 * math.pi) * math.exp(-((x - C) / 110) ** 2)) for x in xs]
    d.line(pts, fill=0, width=18, joint="curve")


BADGES = {"windows": windows, "iphone": iphone, "android": android, "music": music,
          "diamond": diamond, "heart": heart, "bug": bug, "wave": wave}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, glyph in BADGES.items():
        m = Image.new("L", (S, S), 0)
        d = ImageDraw.Draw(m)
        rosette(d)
        glyph(d)
        img = Image.new("RGBA", (S, S), (255, 255, 255, 0))
        img.putalpha(m)
        img.resize((100, 100), Image.LANCZOS).save(os.path.join(OUT, f"{name}.png"))
        print(name)
