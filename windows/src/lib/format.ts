// Подписи с числами на языке интерфейса (lib/i18n.svelte.ts): «217 треков, 6 часов 51 мин», «9.4K подписчиков».
import { t, tn } from './i18n.svelte'

/** Форма слова для числа: plural(5, ['трек', 'трека', 'треков']) → 'треков' (на английском — «tracks»). */
export function plural(n: number, forms: [string, string, string]): string {
  return tn(n, forms)
}

export const tracksText = (n: number) => `${n} ${tn(n, ['трек', 'трека', 'треков'])}`

const hoursText = (h: number) => `${h} ${tn(h, ['час', 'часа', 'часов'])}`

/** Длительность списка: «51 мин», «6 часов 51 мин». */
export function durationText(ms: number): string {
  const min = Math.round(ms / 60_000)
  const h = Math.floor(min / 60)
  const m = min % 60
  if (!h) return t('{m} мин', { m })
  return `${hoursText(h)}${m ? ` ${t('{m} мин', { m })}` : ''}`
}

/** Длительность альбома: «20 мин 44 сек», «1 час 3 мин». */
export function durationLong(ms: number): string {
  const s = Math.round(ms / 1000)
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = s % 60
  if (h) return `${hoursText(h)}${m ? ` ${t('{m} мин', { m })}` : ''}`
  return `${t('{m} мин', { m })}${sec ? ` ${t('{s} сек', { s: sec })}` : ''}`
}

/** Месяцы в родительном падеже — один ключ словаря на все 12 («мая» отдельно — уже сокращение на главной). */
const MONTHS = 'января|февраля|марта|апреля|мая|июня|июля|августа|сентября|октября|ноября|декабря'

/** «2025-06-20» → «20 июня 2025» (на английском — «June 20, 2025»). */
export function dateLong(iso: string): string {
  const [y, mo, d] = iso.split('-').map(Number)
  const month = t(MONTHS).split('|')[mo - 1]
  if (!y || !month || !d) return iso
  return t('{d} {month} {y}', { d, month, y })
}

/** 9400 → «9.4K», 1600000 → «1.6M». */
export function compact(n: number): string {
  if (n < 1000) return String(n)
  if (n < 1_000_000) return `${+(n / 1000).toFixed(n < 10_000 ? 1 : 0)}K`
  return `${+(n / 1_000_000).toFixed(1)}M`
}
