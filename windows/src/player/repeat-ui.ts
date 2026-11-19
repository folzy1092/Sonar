// Значок и подпись кнопки повтора — одни на нижнюю панель, страницу плеера и полноэкранный плеер
// (docs/POLISH_PROMPT.md п. 5): «Повтор: выкл / всё / один трек».
import type { IconName } from '../components/icons'
import type { Repeat } from '../lib/api'
import { t } from '../lib/i18n.svelte'

export function repeatIcon(repeat: Repeat): IconName {
  if (repeat === 'one') return 'repeatOnce'
  return repeat === 'all' ? 'repeat' : 'repeatOff'
}

export function repeatLabel(repeat: Repeat): string {
  if (repeat === 'one') return t('Повтор: один трек')
  return repeat === 'all' ? t('Повтор: всё') : t('Повтор: выкл')
}

export function shuffleLabel(on: boolean): string {
  return on ? t('Перемешивание: вкл') : t('Перемешивание: выкл')
}
