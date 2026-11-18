// Тексты карты исполнителей: «почему рядом» и название кучки. Числа — через tn.
import { t, tn } from '../i18n.svelte'
import type { MapReasons } from './api'

/** Причины связи одной строкой: «4 фита с cowboyclicker · подписаны друг на друга». */
export function whyText(r: MapReasons, other: string): string {
  const parts: string[] = []
  if (r.feats > 0) {
    parts.push(t('{n} {feats} с {name}', { n: r.feats, feats: tn(r.feats, ['фит', 'фита', 'фитов']), name: other }))
  }
  if (r.prods > 0) {
    parts.push(t('продакшн в {n} {tracks}', { n: r.prods, tracks: tn(r.prods, ['треке', 'треках', 'треках']) }))
  }
  if (r.follow === 'mutual') parts.push(t('подписаны друг на друга'))
  else if (r.follow === 'one_way') parts.push(t('подписка на SoundCloud'))
  if (r.common_count > 0) parts.push(commonText(r))
  if (r.similar > 0) parts.push(t('похожи по сервисам'))
  return parts.join(' · ')
}

function commonText(r: MapReasons): string {
  const names = r.common.join(', ')
  const more = r.common_count - r.common.length
  const head = r.common_count === 1 ? t('общий соавтор: {names}', { names }) : t('общие соавторы: {names}', { names })
  return more > 0 ? t('{text} и ещё {n}', { text: head, n: more }) : head
}

/** Подпись связи в карточке исполнителя: сильная · средняя · слабая. */
export function strengthLabel(weight: number): string {
  if (weight >= 3) return t('сильная связь')
  if (weight >= 1.2) return t('заметная связь')
  return t('слабая связь')
}

/** Название плейлиста по кучке — по самому весомому исполнителю. */
export function clusterTitle(topName: string): string {
  return t('Вокруг {name}', { name: topName })
}

/** «12 исполнителей» — подпись кучки и счётчик карты. */
export function artistsCount(n: number): string {
  return `${n} ${tn(n, ['исполнитель', 'исполнителя', 'исполнителей'])}`
}
