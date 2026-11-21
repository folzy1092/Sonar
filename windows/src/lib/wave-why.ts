// «Почему этот трек» — текст причины у треков Sonar Mix (wave.rs `why`). Общий для строки под
// артистом в плеере (`player/WhyLine.svelte`) и меню трека «⋮» (`app/TrackMenu.svelte`).
import type { WaveWhy } from './api'
import { t } from './i18n.svelte'

export function waveWhyText(w: WaveWhy | undefined | null): string {
  if (!w) return ''
  const seed = w.title ? (w.artist ? `«${w.title}» — ${w.artist}` : `«${w.title}»`) : ''
  switch (w.kind) {
    case 'liked':
      return t('Из твоих Любимых — давно не звучал')
    case 'artist':
      return w.artist ? t('Ты часто слушаешь {artist}', { artist: w.artist }) : t('Популярное у любимого артиста')
    case 'explore':
      return t('Разведка: новое рядом с твоим вкусом')
    case 'session':
      return seed ? t('Похоже на {seed} — он зашёл сейчас', { seed }) : t('Похоже на то, что зашло сейчас')
    case 'seed':
      return seed ? t('Sonar Mix по {seed}', { seed }) : t('Похоже на трек, с которого начался Sonar Mix')
    default:
      return seed ? t('Похоже на {seed}', { seed }) : t('Похоже на твои лайки')
  }
}
