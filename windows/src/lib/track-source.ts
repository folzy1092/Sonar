// «Играть из» — сервис, закреплённый за треком (меню трека; Rust — store/track_source.rs, services/fallback.rs;
// iPhone — Core/Library/TrackSource.swift). «Авто» — как раньше: резерв и «SoundCloud через Яндекс» решают сами.
// Здесь — чистая часть для меню: какие варианты показать и как их подписать.
import type { TrackSources } from './api'
import { t } from './i18n.svelte'
import { byId, serviceOf, type ServiceId } from './services'

/** Вариант в меню: «Авто» или сервис. */
export type SourceChoice = 'auto' | ServiceId

/** Варианты «Играть из»: «Авто» и сервисы, где трек есть (свой первым — порядок реестра от Rust).
 *  Выбирать не из чего (трек нашёлся только у себя и ничего не закреплено) — пусто. */
export function sourceChoices(ref: string, s: TrackSources | null): SourceChoice[] {
  if (!s) return []
  const own = serviceOf(ref)
  const services = s.services.filter((id, i, all) => all.indexOf(id) === i)
  const hasOther = services.some((id) => id !== own)
  if (!hasOther && !s.pinned) return []
  return ['auto', ...services]
}

/** Подпись варианта: «Авто» или имя сервиса. */
export function sourceName(choice: SourceChoice): string {
  if (choice === 'auto') return t('Авто')
  const info = byId(choice)
  return info ? t(info.name) : choice
}

/** Вариант выбран сейчас: null у трека — «Авто». */
export const isChosen = (choice: SourceChoice, pinned: ServiceId | null): boolean =>
  choice === 'auto' ? pinned === null : pinned === choice

/** Значение для `set_track_source`: «Авто» — null. */
export const sourceValue = (choice: SourceChoice): ServiceId | null => (choice === 'auto' ? null : choice)
