// Значки позиции мини плеера (Интерфейс → Мини плеер): окно, левая панель и где плеер.
// Готовая разметка для Choice `svg` — рисуется цветом текста кнопки.

const frame = '<rect x="1.5" y="2.5" width="21" height="19" rx="3.5" fill="none" stroke="currentColor" stroke-width="1.6"/>'
const rail = (y: number, h: number) => `<rect x="4.5" y="${y}" width="3" height="${h}" rx="1.2" fill="currentColor" opacity=".45"/>`
const player = (x: number, y: number, w: number) => `<rect x="${x}" y="${y}" width="${w}" height="3.4" rx="1.7" fill="currentColor"/>`
const svg = (body: string) => `<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">${frame}${body}</svg>`

export const MINI_POSITION_GLYPHS = {
  top: svg(rail(5.5, 13) + player(9.5, 5.5, 10)),
  bottom: svg(rail(5.5, 13) + player(9.5, 15.1, 10)),
  bottom_full: svg(rail(5.5, 8.5) + player(4.5, 15.1, 15)),
  floating: svg(rail(5.5, 13) + player(12, 13.6, 7.5)),
} as const
