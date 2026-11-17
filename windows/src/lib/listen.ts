// Кнопка «Слушать» в шапке плейлиста, Любимых, альбома и исполнителя (components/ListenButton.svelte):
// если сейчас играет эта же подборка (контекст плеера совпал), кнопка становится «Пауза», а после
// паузы — снова «Слушать», но продолжает с того же места, а не начинает список заново.

/** Что сделает нажатие: поставить на паузу, продолжить с места или начать подборку с начала. */
export type ListenAction = 'pause' | 'resume' | 'start'

export interface ListenState {
  /** `player.context` — откуда играет очередь (`playlist:<id>`, `favorites`, `album:<ref>`…). */
  context: string | null
  playing: boolean
  /** В плеере есть текущий трек. */
  hasCurrent: boolean
}

/** Действие кнопки «Слушать» страницы с контекстом `page` (нет контекста — всегда «начать»). */
export function listenAction(page: string | null | undefined, { context, playing, hasCurrent }: ListenState): ListenAction {
  const ours = !!page && page === context && hasCurrent
  if (!ours) return 'start'
  return playing ? 'pause' : 'resume'
}
