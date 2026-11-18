"""Значки Sonar для премиум-эмодзи (свой пак): простые одноцветные знаки (без розетки — решение 2026-11-15).

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


def server(d):
    """Сервер (статус «Основной»): три стойки-юнита, слева огоньки, справа щель."""
    w, h, gap = 236, 60, 16
    top = C - (3 * h + 2 * gap) / 2
    for i in range(3):
        y = top + i * (h + gap)
        d.rounded_rectangle([C - w / 2, y, C + w / 2, y + h], 16, fill=0)
        cy = y + h / 2
        for k in range(2):                                  # два огонька
            cx = C - w / 2 + 34 + k * 30
            d.ellipse([cx - 9, cy - 9, cx + 9, cy + 9], fill=255)
        d.rounded_rectangle([C + 10, cy - 6, C + w / 2 - 28, cy + 6], 6, fill=255)  # щель


def logo_polys(size, box, cx=None, cy=None):
    """Контуры знака Sonar из brand/logo.svg (только M/C/L/Z), вписанные в квадрат box с центром (cx, cy)."""
    import re
    svg = open(os.path.join(os.path.dirname(OUT), "..", "logo.svg"), encoding="utf-8").read()
    vb = [float(v) for v in re.search(r'viewBox="([^"]+)"', svg).group(1).split()]
    k = box / max(vb[2], vb[3])
    cx = size / 2 if cx is None else cx
    cy = size / 2 if cy is None else cy
    ox, oy = cx - vb[2] * k / 2 - vb[0] * k, cy - vb[3] * k / 2 - vb[1] * k
    polys = []
    for d in re.findall(r'\sd="([^"]+)"', svg):
        toks = re.findall(r"[MCLZ]|-?\d+(?:\.\d+)?", d)
        i, cur, poly = 0, (0, 0), []
        while i < len(toks):
            t = toks[i]; i += 1
            if t == "M":
                if poly: polys.append(poly)
                cur = (float(toks[i]), float(toks[i + 1])); i += 2; poly = [cur]
            elif t == "L":
                cur = (float(toks[i]), float(toks[i + 1])); i += 2; poly.append(cur)
            elif t == "C":
                a, b, e = [(float(toks[i + j]), float(toks[i + j + 1])) for j in (0, 2, 4)]; i += 6
                for n in range(1, 13):
                    u = n / 12; v = 1 - u
                    poly.append((v**3 * cur[0] + 3 * v * v * u * a[0] + 3 * v * u * u * b[0] + u**3 * e[0],
                                 v**3 * cur[1] + 3 * v * v * u * a[1] + 3 * v * u * u * b[1] + u**3 * e[1]))
                cur = e
            elif t == "Z":
                if poly: polys.append(poly); poly = []
            else:
                i -= 1; cur = (float(toks[i]), float(toks[i + 1])); i += 2; poly.append(cur)  # неявный повтор команды
        if poly: polys.append(poly)
    return [[(ox + x * k, oy + y * k) for x, y in p] for p in polys]


def logo_mask(size, box, fill):
    """Маска знака с правилом even-odd (дырки в букве остаются дырками)."""
    import numpy as np
    acc = np.zeros((size, size), dtype=bool)
    for p in logo_polys(size, box):
        m = Image.new("L", (size, size), 0)
        ImageDraw.Draw(m).polygon(p, fill=255)
        acc ^= np.array(m) > 127
    return acc


def sonar(d):
    import numpy as np
    acc = logo_mask(S, 236, 0)
    arr = np.array(d._image)
    arr[acc] = 0
    d._image.paste(Image.fromarray(arr))


BADGES = {"windows": windows, "iphone": iphone, "android": android, "music": music,
          "diamond": diamond, "heart": heart, "bug": bug, "wave": wave, "server": server, "sonar": sonar}

def plain(glyph, size=100, pad=0.06):
    """Просто знак без розетки (решение владельца 2026-11-15): белый на прозрачном, вписан в квадрат."""
    m = Image.new("L", (S, S), 255)
    glyph(ImageDraw.Draw(m))
    m = Image.eval(m, lambda v: 255 - v)          # знак рисовали «дыркой» в белом — переворачиваем
    box = m.getbbox()
    m = m.crop(box)
    side = max(m.size)
    sq = Image.new("L", (side, side), 0)
    sq.paste(m, ((side - m.size[0]) // 2, (side - m.size[1]) // 2))
    inner = int(size * (1 - 2 * pad))
    sq = sq.resize((inner * 4, inner * 4), Image.LANCZOS).resize((inner, inner), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    a = Image.new("L", (size, size), 0)
    a.paste(sq, ((size - inner) // 2, (size - inner) // 2))
    out.putalpha(a)
    return out


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, glyph in BADGES.items():
        if name == "sonar":
            continue
        plain(glyph).save(os.path.join(OUT, f"{name}.png"))
        print(name)
    import numpy as np
    m = Image.fromarray((logo_mask(S, 360, 255) * 255).astype("uint8"))
    img = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    img.putalpha(m)
    img.resize((100, 100), Image.LANCZOS).save(os.path.join(OUT, "logo_sonar.png"))
    print("logo_sonar")
