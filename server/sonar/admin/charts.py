"""Графики дашборда — готовый SVG с сервера: без JS и без библиотек (CSP `script-src 'none'`)."""
from __future__ import annotations

from html import escape

from markupsafe import Markup

W, H, PAD_L, PAD_B, PAD_T = 720, 220, 36, 24, 12


def _nice(v: int) -> int:
    """Верх оси: 1, 2, 5 × 10ⁿ не меньше v (минимум 4, чтобы нули не рисовали линию под потолком)."""
    v = max(v, 4)
    m = 1
    while True:
        for k in (1, 2, 5):
            if k * m >= v:
                return k * m
        m *= 10


def _label(day: str) -> str:
    return f"{day[8:10]}.{day[5:7]}"


def lines(series: list[dict], keys: list[tuple[str, str, str]]) -> Markup:
    """Линии по дням: keys — (ключ, подпись, класс). Одна точка — рисуем точкой, а не пустотой."""
    n = len(series)
    top = _nice(max((d[k] for d in series for k, _, _ in keys), default=0))
    iw, ih = W - PAD_L - 8, H - PAD_B - PAD_T
    x = (lambda i: PAD_L + iw / 2) if n == 1 else (lambda i: PAD_L + i * iw / (n - 1))
    y = lambda v: PAD_T + ih - v * ih / top  # noqa: E731
    out = [f'<svg class="chart" viewBox="0 0 {W} {H}" role="img" aria-label="График по дням">']
    for t in range(5):
        v = top * t // 4
        out.append(f'<line class="grid" x1="{PAD_L}" x2="{W - 8}" y1="{y(v):.1f}" y2="{y(v):.1f}"/>'
                   f'<text class="axis" x="{PAD_L - 8}" y="{y(v) + 4:.1f}" text-anchor="end">{v}</text>')
    step = max(1, n // 8)
    for i in range(0, n, step):
        out.append(f'<text class="axis" x="{x(i):.1f}" y="{H - 6}" text-anchor="middle">{_label(series[i]["day"])}</text>')
    for k, name, cls in keys:
        pts = " ".join(f"{x(i):.1f},{y(d[k]):.1f}" for i, d in enumerate(series))
        out.append(f'<polyline class="line {cls}" points="{pts}"/>')
        for i, d in enumerate(series):
            out.append(f'<circle class="dot {cls}" cx="{x(i):.1f}" cy="{y(d[k]):.1f}" r="{3 if n <= 31 else 0}">'
                       f'<title>{_label(d["day"])} · {escape(name)}: {d[k]}</title></circle>')
    out.append("</svg>")
    return Markup("".join(out))


def bars(series: list[dict], key: str, name: str, h: int = 96) -> Markup:
    """Малые столбики (треков, регистраций, подписок по дням); последний день — акцентом."""
    n = max(len(series), 1)
    top = _nice(max((d[key] for d in series), default=0))
    w = 360
    bw = (w - 8) / n
    out = [f'<svg class="chart small" viewBox="0 0 {w} {h}" role="img" aria-label="{escape(name)} по дням">',
           f'<line class="grid" x1="0" x2="{w}" y1="{h - 1}" y2="{h - 1}"/>']
    for i, d in enumerate(series):
        bh = (h - 16) * d[key] / top
        cls = "bar last" if i == n - 1 else "bar"
        out.append(f'<rect class="{cls}" x="{4 + i * bw + bw * 0.15:.1f}" y="{h - 1 - bh:.1f}" width="{bw * 0.7:.1f}"'
                   f' height="{bh:.1f}" rx="2"><title>{_label(d["day"])} · {escape(name)}: {d[key]}</title></rect>')
    out.append(f'<text class="axis" x="{w - 4}" y="12" text-anchor="end">шкала до {top}</text></svg>')
    return Markup("".join(out))
