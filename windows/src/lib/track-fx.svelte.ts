// Анимация смены трека — «подпись» стиля (appearance.anim_track, STYLE_PROMPT §4). Играет на обложке
// героя «Моя волна», обложке страницы плеера и мини-плеера (`data-fx-cover`), на заголовках
// (`data-fx-title`), по краю мини-плеера и обложки плеера (`data-fx-frame`), на светодиодах мини-плеера
// (`data-fx-leds`) и столбиках волны (`player/Wave.svelte` читает `barsStartedAt`).
//   echo     — 3 кольца нового акцента расходятся от обложки, обложка .94→1, заголовок «дышит» по wdth;
//   signal   — столбики волны гаснут в линию и вырастают, обложка и заголовок проявляются;
//   edge     — световая дуга один раз обегает рамку, обложка проявляется .2→1;
//   tactile  — огонёк бежит по 5 светодиодам, обложка «встаёт в слот» сверху;
//   monolith — свечение за обложкой «разливается», заголовок поднимается на 8 px;
//   fade     — только обычный кроссфейд.
// Перезапуск — снятием и постановкой класса `fx-run` (см. fx-layer.ts `restart`). «Меньше движения» —
// только прозрачность: обложка проявляется, колец и дуги нет.
import { player } from '../player/player.svelte'
import { settings } from './settings.svelte'
import { reducedMotion } from './motion'
import { restart, spawn, visible } from './fx-layer'

/** Когда начать «рост» столбиков волны (signal) — performance.now(), 0 — не играть. */
export const fx = $state({ barsStartedAt: 0 })

/** Длительность анимации смены трека по стилю (для снятия класса). */
const DURATION: Record<string, number> = { echo: 620, signal: 520, edge: 640, tactile: 520, monolith: 600, fade: 0 }

export function trackChange() {
  const kind = settings.get('appearance.anim_track')
  document.documentElement.dataset.fxTrack = kind
  if (kind === 'fade') return
  const ms = DURATION[kind] ?? 600
  const calm = reducedMotion()
  for (const el of document.querySelectorAll('[data-fx-cover], [data-fx-title], [data-fx-leds]')) restart(el, 'fx-run', ms)
  if (calm) return
  if (kind === 'signal') fx.barsStartedAt = performance.now()
  if (kind === 'echo') {
    // три контурных кольца нового акцента от каждой видимой обложки
    for (const el of document.querySelectorAll('[data-fx-cover]')) {
      const r = visible(el)
      if (!r) continue
      const radius = getComputedStyle(el).borderRadius
      spawn(r, '<i></i><i></i><i></i>', 'fx-rings', 800, 0, { borderRadius: radius })
    }
  }
  if (kind === 'edge') {
    // световая дуга по рамке мини-плеера и обложки на странице плеера
    for (const el of document.querySelectorAll('[data-fx-frame]')) {
      const r = visible(el)
      if (!r) continue
      spawn(r, '', 'fx-arc', 640, 0, { borderRadius: getComputedStyle(el).borderRadius })
    }
  }
}

let started = false

/** Следить за сменой трека (зовётся один раз при запуске). */
export function initTrackFx() {
  if (started) return
  started = true
  let prev: string | null | undefined
  $effect.root(() => {
    $effect(() => {
      document.documentElement.dataset.fxTrack = settings.get('appearance.anim_track')
    })
    $effect(() => {
      const ref = player.current?.ref ?? null
      // первый трек после запуска — без анимации
      if (prev !== undefined && ref && ref !== prev) queueMicrotask(trackChange)
      prev = ref
    })
  })
}
