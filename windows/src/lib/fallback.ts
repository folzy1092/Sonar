// Резервный сервис (NEXT_PROMPT этап 4, services/fallback.rs): свой сервис трек не играет — тот же
// трек из другого, по порядку `audio.fallback_order`. Здесь — то, что нужно интерфейсу: порядок
// по реестру (как parse_order в Rust), перестановка перетаскиванием и текст всплывашки.
import { t } from './i18n.svelte'
import { byId, SERVICES, type ServiceId, type ServiceInfo } from './services'

/** Почему трек играет не со своего сервиса (`Reason` в providers/unplayable.rs). */
export type FallbackReason = 'unavailable' | 'preview' | 'premium' | 'failed' | 'preferred'

/** Поле `via` ответа `stream_url`: что играет вместо трека, откуда и почему. */
export interface Via {
  ref: string
  service: ServiceId
  from: ServiceId
  reason: FallbackReason
}

/** Может быть резервом: работает в Sonar, ищет и отдаёт поток (Spotify без потока и локальные файлы — нет). */
export const canBackUp = (s: ServiceInfo): boolean => s.implemented && s.caps.search && s.caps.stream

/** Порядок по умолчанию — порядок реестра. */
export const defaultFallbackOrder = (): ServiceId[] => SERVICES.filter(canBackUp).map((s) => s.id)

/** Сохранённый порядок → список: неизвестные и повторы — прочь, забытые сервисы — в конец
 *  в порядке реестра (новый сервис сам встаёт в очередь). */
export function fallbackOrder(saved: unknown): ServiceId[] {
  const out: ServiceId[] = []
  for (const v of Array.isArray(saved) ? saved : []) {
    const s = typeof v === 'string' ? byId(v) : null
    if (s && canBackUp(s) && !out.includes(s.id)) out.push(s.id)
  }
  for (const id of defaultFallbackOrder()) if (!out.includes(id)) out.push(id)
  return out
}

/** Перетаскивание: новый список, где элемент `from` стоит на месте `to`. */
export function moveItem<T>(list: readonly T[], from: number, to: number): T[] {
  if (from === to || from < 0 || to < 0 || from >= list.length || to >= list.length) return [...list]
  const next = list.filter((_, i) => i !== from)
  next.splice(to, 0, list[from])
  return next
}

/** Всплывашка «Играет из YouTube Music — в SoundCloud недоступен». «SoundCloud через Яндекс» —
 *  настройка, а не беда: без всплывашки (null). */
export function fallbackToast(via: Via | null | undefined): string | null {
  if (!via || via.reason === 'preferred') return null
  const to = byId(via.service)
  const from = byId(via.from)
  if (!to || !from) return null
  const params = { to: t(to.name), from: t(from.nameIn) }
  if (via.reason === 'preview') return t('Играет из {to} — в {from} только отрывок', params)
  if (via.reason === 'premium') return t('Играет из {to} — в {from} нужна подписка', params)
  return t('Играет из {to} — в {from} недоступен', params)
}

/** Сколько держится всплывашка резерва: разовое уведомление, не постоянная деталь (TASTE_ROOMS_PROMPT §5). */
export const FALLBACK_TOAST_MS = 4000

/** Всплывашка резерва — одна на трек: что сказать на поток трека `ref` (null — молчать) и новая память
 *  `shown` — трек, для которого уже сказали. Повторная загрузка того же трека (свежая ссылка, резерв после
 *  сбоя, смена качества) молчит; трек без резерва сбрасывает память — вернулись к треку с резервом, скажем
 *  снова. Зеркало `FallbackNotice` в iPhone `Fallback.swift`. */
export function fallbackNotice(via: Via | null | undefined, ref: string, shown: string | null): { text: string | null; shown: string | null } {
  if (ref === shown) return { text: null, shown }
  const text = fallbackToast(via)
  return { text, shown: text ? ref : null }
}

/** Плашка качества: что реально играет, а при замене — ещё и откуда («MP3 320 · Яндекс Музыка»). */
export function qualityLabel(quality: string, via: Via | null | undefined): string {
  const label = t(quality)
  const to = via ? byId(via.service) : null
  return to ? `${label} · ${t(to.name)}` : label
}
