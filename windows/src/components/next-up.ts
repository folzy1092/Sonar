// Где карточка «Дальше» (components/NextUp.svelte) у мини-плеера: над ним или под ним.
// Мини-плеер сверху окна — карточка под ним (над ним места нет); плавающий в верхней половине окна —
// тоже под ним; иначе — над ним. По горизонтали карточка всегда вровень с капсулой кнопок справа.
export type MiniPosition = 'top' | 'bottom' | 'bottom_full' | 'floating'
export type NextUpSide = 'above' | 'below'

/** Плавающий мини-плеер выше этой доли окна — карточка уходит вниз. */
const FLOAT_UPPER_HALF = 0.5

export function nextUpSide(position: MiniPosition, floatY: number): NextUpSide {
  if (position === 'top') return 'below'
  if (position === 'floating' && floatY < FLOAT_UPPER_HALF) return 'below'
  return 'above'
}

/** Сдвиг появления по Y: карточка выезжает от мини-плеера — над ним снизу вверх, под ним сверху вниз. */
export function nextUpRise(side: NextUpSide, px = 8): number {
  return side === 'above' ? px : -px
}
