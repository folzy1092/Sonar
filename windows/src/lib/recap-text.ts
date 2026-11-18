// Подписи карточек итогов на языке интерфейса — одни и те же для экрана (RecapViewer) и картинки (recap-draw).
import { dateLong, durationText, tracksText } from './format'
import { lang, t, tn } from './i18n.svelte'
import { byId } from './services'
import { partOfDay, type RecapCard, type RecapRef } from './recap-core'

/** Месяцы в именительном падеже — один ключ словаря на все 12. */
const MONTHS = 'Январь|Февраль|Март|Апрель|Май|Июнь|Июль|Август|Сентябрь|Октябрь|Ноябрь|Декабрь'

/** «Ноябрь 2026» или «2026». */
export function periodTitle(ref: RecapRef): string {
  if (ref.kind === 'year' || !ref.month) return String(ref.year)
  const name = t(MONTHS).split('|')[ref.month - 1] ?? ''
  return `${name} ${ref.year}`
}

/** «Итоги месяца» / «Итоги года». */
export const recapKindTitle = (ref: RecapRef) => (ref.kind === 'year' ? t('Итоги года') : t('Итоги месяца'))

const LOCALES = { ru: 'ru-RU', en: 'en-US', uk: 'uk-UA' } as const

/** Число с разделителями разрядов языка интерфейса. */
export function numberText(n: number): string {
  return Math.round(n).toLocaleString(LOCALES[lang()])
}

const hourText = (h: number) => `${String(h).padStart(2, '0')}:00`

/** Подпись части суток по любимому часу. */
function partText(hour: number): string {
  return [t('Ночной слушатель'), t('Утренний слушатель'), t('Дневной слушатель'), t('Вечерний слушатель')][partOfDay(hour)]
}

/** Что написано на карточке: надзаголовок, заголовок, большое число с подписью и строки под ним.
 *  Списки (топы, сервисы) и столбики часов карточка рисует сама. */
export interface CardText {
  eyebrow: string
  title: string
  value: number | null
  unit: string
  lines: string[]
}

const text = (eyebrow: string, title: string, over: Partial<CardText> = {}): CardText => ({
  eyebrow,
  title,
  value: null,
  unit: '',
  lines: [],
  ...over,
})

function deltaText(delta: number | null): string | null {
  if (delta === null || delta === 0) return null
  return delta > 0
    ? t('На {n}% больше, чем в прошлый раз', { n: delta })
    : t('На {n}% меньше, чем в прошлый раз', { n: Math.abs(delta) })
}

/** Имя сервиса по id из реестра (переведённое). */
export const serviceTitle = (id: string) => {
  const s = byId(id)
  return s ? t(s.name) : id
}

export function cardText(card: RecapCard, ref: RecapRef): CardText {
  switch (card.kind) {
    case 'intro':
      return text(recapKindTitle(ref), periodTitle(ref), {
        lines: [ref.kind === 'year' ? t('Твой год в музыке — листай карточки') : t('Твой месяц в музыке — листай карточки')],
      })
    case 'minutes': {
      const days = `${card.days} ${tn(card.days, ['день', 'дня', 'дней'])}`
      const plays = `${numberText(card.plays)} ${tn(card.plays, ['прослушивание', 'прослушивания', 'прослушиваний'])}`
      const lines = [deltaText(card.delta), t('{days} с музыкой · {plays}', { days, plays })]
      return text(t('Время с музыкой'), '', {
        value: card.minutes,
        unit: tn(card.minutes, ['минута', 'минуты', 'минут']),
        lines: lines.filter((l): l is string => !!l),
      })
    }
    case 'tracks':
      return text(t('Топ-5 треков'), card.items[0]?.title ?? '')
    case 'artists':
      return text(t('Топ-5 артистов'), card.items[0]?.name ?? '')
    case 'new_artist':
      return text(t('Новый артист'), card.artist.name, {
        lines: [t('Первое прослушивание — {date}', { date: dateLong(card.firstPlayed) }), durationText(card.artist.ms)],
      })
    case 'hour':
      return text(t('Любимый час'), `${hourText(card.hour)}–${hourText((card.hour + 1) % 24)}`, { lines: [partText(card.hour)] })
    case 'day':
      return text(t('Самый длинный день'), dateLong(card.date), {
        value: card.minutes,
        unit: tn(card.minutes, ['минута', 'минуты', 'минут']),
        lines: [t('{tracks} за день', { tracks: tracksText(card.plays) })],
      })
    case 'repeat':
      return text(t('На повторе'), card.track.title, {
        value: card.count,
        unit: tn(card.count, ['раз за день', 'раза за день', 'раз за день']),
        lines: [card.track.artist, dateLong(card.date)],
      })
    case 'services':
      return text(t('Сервисы'), serviceTitle(card.items[0]?.service ?? ''), {
        lines: [t('{pct}% времени — здесь', { pct: card.items[0]?.pct ?? 0 })],
      })
  }
}
