// Правая панель «Очередь / Текст» (идея владельца 2026-11-18): крайняя кнопка мини-плеера открывает её на
// пол-экрана справа. У трека есть текст — кнопка «Т» и панель с текстом, сверху капсулы «Текст · Очередь»;
// текста нет — значок очереди и очередь, без переключателя. Полноэкранный плеер — по клику на обложку.
//
// Панель сама идёт за треком (followTrack): новый трек с текстом — текст, без текста — очередь. Выбрал вид
// руками (капсулы, Ctrl+L / Ctrl+Q) — на этом треке панель его не перебивает, до смены трека.
export type PaneMode = 'queue' | 'lyrics'

/** Есть ли текст у текущего трека: да / нет / ещё ищется. */
export type LyricsAvail = 'yes' | 'no' | 'pending'

type LyricsStatus = 'idle' | 'loading' | 'ready' | 'none'

/** Признак текста из стора текста (lyrics.svelte.ts). Любой текст — синхронный, обычный, из lrclib или
 *  Genius — даёт `ready`; пока стор не догнал текущий трек (другой `ref`) — «ещё ищется». */
export function lyricsAvail(status: LyricsStatus, lyricsRef: string | null, currentRef: string | null): LyricsAvail {
  if (!currentRef || lyricsRef !== currentRef) return 'pending'
  if (status === 'ready') return 'yes'
  if (status === 'none') return 'no'
  return 'pending'
}

/** Что панель показывает на деле: выбран текст, а у трека его точно нет — очередь. Пока текст ищется,
 *  выбранный текст остаётся (без мигания «очередь → текст» на каждой смене трека). */
export function effectiveMode(mode: PaneMode, avail: LyricsAvail): PaneMode {
  return mode === 'lyrics' && avail !== 'no' ? 'lyrics' : 'queue'
}

/** Вид по тексту трека; пока текст ищется — прежний. */
export function autoMode(avail: LyricsAvail, current: PaneMode): PaneMode {
  if (avail === 'yes') return 'lyrics'
  if (avail === 'no') return 'queue'
  return current
}

/** Значок кнопки мини-плеера: «Т» — текст есть. Пока текст ищется — прежний значок, без мигания. */
export function knownLyrics(avail: LyricsAvail, before: boolean): boolean {
  if (avail === 'pending') return before
  return avail === 'yes'
}

export interface PaneState {
  mode: PaneMode
  /** Трек, к которому относится выбор. `undefined` — панель только что открыли: принять текущий трек. */
  ref: string | null | undefined
  /** Вид выбран руками — не перебивать до смены трека. */
  manual: boolean
}

/** Правило переключения: новый трек — вид по тексту; тот же трек — по тексту, если вид не выбран руками
 *  (текст догрузился позже — панель переключится). Ничего не поменялось — тот же объект. */
export function followTrack(prev: PaneState, ref: string | null, avail: LyricsAvail): PaneState {
  const sameTrack = prev.ref === undefined || prev.ref === ref
  const manual = sameTrack && prev.manual
  const mode = manual ? prev.mode : autoMode(avail, prev.mode)
  if (mode === prev.mode && manual === prev.manual && ref === prev.ref) return prev
  return { mode, ref, manual }
}

class SidePane {
  open = $state(false)
  state = $state.raw<PaneState>({ mode: 'queue', ref: undefined, manual: false })

  get mode(): PaneMode {
    return this.state.mode
  }

  /** Что панель показывает на деле. */
  shown(avail: LyricsAvail): PaneMode {
    return effectiveMode(this.state.mode, avail)
  }

  /** Панель сверяется с текущим треком (эффект в SidePane.svelte). */
  sync(ref: string | null, avail: LyricsAvail) {
    const next = followTrack(this.state, ref, avail)
    if (next !== this.state) this.state = next
  }

  /** Капсулы «Текст · Очередь» в панели — выбор руками. */
  pick(mode: PaneMode) {
    this.state = { ...this.state, mode, manual: true }
  }

  /** Кнопка мини-плеера и клавиши: та же панель в том же виде — закрыть, иначе открыть нужный вид.
   *  `manual` — выбор руками (Ctrl+L / Ctrl+Q); кнопка мини-плеера открывает вид по тексту — не руками. */
  toggle(mode: PaneMode, hasLyrics = true, manual = true) {
    const avail: LyricsAvail = hasLyrics ? 'yes' : 'no'
    if (this.open && this.shown(avail) === mode) {
      this.open = false
      return
    }
    // открыта — трек тот же, что уже сверен; закрыта — трек мог смениться, принять текущий
    const ref = this.open ? this.state.ref : undefined
    this.state = { mode, ref, manual }
    this.open = true
  }

  close() {
    this.open = false
  }
}

export const sidePane = new SidePane()
