<script lang="ts">
  // Текст песни (LYRICS.md, iOS-скрин photo_5): синхронный — караоке с автопрокруткой, текущая строка
  // яркая, соседние приглушены (и размыты в стиле «Размытие»), «•••» на проигрышах, клик по строке —
  // перемотка. Обычный (Genius, plain) — просто текст с прокруткой. Правый клик — меню текста.
  import { onMount, tick } from 'svelte'
  import { player } from '../player/player.svelte'
  import { Clock } from './core/clock'
  import { findLine } from './core/find'
  import { LONG_WORD, progress, pulse } from './core/progress'
  import { lyrics, sizeRem } from './lyrics.svelte'

  interface Props {
    oncontextmenu?: (e: MouseEvent) => void
  }
  let { oncontextmenu }: Props = $props()

  const data = $derived(lyrics.data)
  const lines = $derived(data?.lines ?? [])
  const synced = $derived(!!data?.isSynced)
  const wordsOn = $derived(lyrics.mode === 'words' && lyrics.hasWords)

  let active = $state(-1)
  let scroller: HTMLDivElement | undefined = $state()
  const els: HTMLElement[] = $state([])
  /** Пользователь крутил колесо — автопрокрутка ждёт пару секунд. */
  let userScrollAt = 0
  const USER_SCROLL_PAUSE = 2500

  const clock = new Clock()
  const reduced =
    typeof matchMedia !== 'undefined' && matchMedia('(prefers-reduced-motion: reduce)').matches

  /** Перед первой строкой больше 2 с вступления — «•••» сверху. */
  const intro = $derived(synced && lines.length > 0 && lines[0].time > 2)

  // новый текст (другой трек) — с начала
  $effect(() => {
    data
    active = -1
    userScrollAt = 0
    const a = player.media
    if (a) clock.seek(a.currentTime)
    void tick().then(() => scroller?.scrollTo({ top: 0 }))
  })

  // смена строки — прокрутка к ней
  $effect(() => {
    const i = active
    if (!synced || !scroller) return
    if (performance.now() - userScrollAt < USER_SCROLL_PAUSE) return
    const el = i >= 0 ? els[i] : null
    const top = el ? el.offsetTop - scroller.clientHeight * 0.32 : 0
    scroller.scrollTo({ top: Math.max(0, top), behavior: reduced ? 'auto' : 'smooth' })
  })

  function seekTo(time: number) {
    if (!synced) return
    userScrollAt = 0
    player.seek(Math.max(0, (time - lyrics.offset) * 1000))
    if (!player.playing) void player.play()
  }

  /** Подсветка внутри текущей строки — прямо в DOM, без перерисовки Svelte на каждый кадр. */
  function paint(t: number) {
    const i = active
    const el = i >= 0 ? els[i] : null
    if (!el) return
    const line = lines[i]
    if (!line.text) {
      el.style.setProperty('--p', String(progress(line.time, line.duration, t)))
      return
    }
    if (wordsOn && line.words?.length) {
      const spans = el.querySelectorAll<HTMLElement>('.w')
      line.words.forEach((w, j) => {
        const s = spans[j]
        if (!s) return
        const p = progress(w.time, w.duration, t)
        s.style.setProperty('--p', String(p))
        if (!reduced && w.duration >= LONG_WORD && p > 0 && p < 1) {
          const k = pulse(p)
          s.style.transform = `scale(${1 + 0.04 * k})`
        } else if (s.style.transform) s.style.transform = ''
      })
    } else if (lyrics.mode === 'words') {
      el.style.setProperty('--p', String(progress(line.time, line.duration, t)))
    }
  }

  function introProgress(t: number) {
    const el = scroller?.querySelector<HTMLElement>('.intro')
    if (el && lines.length) el.style.setProperty('--p', String(progress(0, lines[0].time, t)))
  }

  onMount(() => {
    const a = player.media
    let raf = 0
    if (a) {
      clock.duration = Number.isFinite(a.duration) ? a.duration : Infinity
      if (a.paused) clock.hold(a.currentTime)
      else clock.play(a.currentTime, performance.now(), a.playbackRate)
    }
    const on: [string, () => void][] = a
      ? [
          ['timeupdate', () => clock.sample(a.currentTime, performance.now())],
          ['playing', () => clock.play(a.currentTime, performance.now(), a.playbackRate)],
          ['pause', () => clock.hold(a.currentTime)],
          ['waiting', () => clock.hold(a.currentTime)],
          ['seeking', () => clock.seek(a.currentTime)],
          [
            'seeked',
            () => (a.paused ? clock.hold(a.currentTime) : clock.play(a.currentTime, performance.now(), a.playbackRate)),
          ],
          ['ratechange', () => clock.setRate(a.playbackRate, a.currentTime, performance.now())],
          ['durationchange', () => (clock.duration = Number.isFinite(a.duration) ? a.duration : Infinity)],
        ]
      : []
    for (const [ev, fn] of on) a!.addEventListener(ev, fn)

    const frame = (ts: number) => {
      raf = requestAnimationFrame(frame)
      if (!synced || !lines.length || document.hidden) return
      const t = clock.read(ts) + lyrics.offset
      const i = findLine(lines, t, active)
      if (i !== active) active = i
      if (i === -1) introProgress(t)
      else paint(t)
    }
    raf = requestAnimationFrame(frame)

    return () => {
      cancelAnimationFrame(raf)
      for (const [ev, fn] of on) a!.removeEventListener(ev, fn)
    }
  })
</script>

<div
  class="lyrics style-{lyrics.style} anim-{lyrics.animation}"
  class:synced
  class:words={wordsOn}
  class:line-fill={lyrics.mode === 'words' && !wordsOn}
  style:--lyrics-size="{sizeRem[lyrics.size]}rem"
  role="region"
  aria-label="Текст песни"
  {oncontextmenu}
>
  <div class="scroller" bind:this={scroller} onwheel={() => (userScrollAt = performance.now())}>
    {#if synced}
      {#if intro}
        <div class="line pause intro" class:active={active === -1} style:--d={active === -1 ? 0 : 1}>
          <span class="dots" aria-hidden="true"><i></i><i></i><i></i></span>
        </div>
      {/if}
      {#each lines as line, i (i)}
        <button
          class="line"
          class:active={i === active}
          class:past={i < active}
          class:bg={line.isBackground}
          class:pause={!line.text}
          style:--d={Math.min(Math.abs(i - active), 5)}
          bind:this={els[i]}
          onclick={() => seekTo(line.time)}
        >
          {#if !line.text}
            <span class="dots" aria-label="Проигрыш"><i></i><i></i><i></i></span>
          {:else if wordsOn && line.words?.length}
            {#each line.words as w, j (j)}<span class="w" class:bg={w.isBackground}>{w.text}</span
              >{#if w.hasSpaceAfter}{' '}{/if}{/each}
          {:else}
            <span class="t">{line.text}</span>
          {/if}
        </button>
      {/each}
      <div class="tail" aria-hidden="true"></div>
    {:else}
      <div class="plain selectable">
        {#each lines as line, i (i)}
          {#if line.text}<p class:bg={line.isBackground}>{line.text}</p>{:else}<p class="gap"></p>{/if}
        {/each}
        {#if data?.source === 'genius'}<p class="src">Текст: Genius</p>{/if}
      </div>
    {/if}
  </div>
</div>

<style>
  .lyrics {
    --ink: 255, 255, 255;
    position: relative;
    height: 100%;
    min-height: 0;
    font-size: var(--lyrics-size);
    font-family: var(--font-display);
  }
  .scroller {
    position: relative;
    height: 100%;
    overflow-y: auto;
    overflow-x: hidden;
    padding: 30vh 8px 0 4px;
    scrollbar-width: none;
    mask-image: linear-gradient(to bottom, transparent 0, #000 12%, #000 82%, transparent 100%);
  }
  .scroller::-webkit-scrollbar {
    display: none;
  }
  .tail {
    height: 55vh;
  }

  .line {
    display: block;
    width: 100%;
    margin: 0;
    padding: 0.22em 0.25em;
    border-radius: 12px;
    text-align: left;
    font: inherit;
    font-weight: 700;
    line-height: 1.22;
    letter-spacing: -0.01em;
    color: rgba(var(--ink), 0.32);
    cursor: pointer;
    transform-origin: left center;
    transition:
      color 0.35s var(--ease),
      transform 0.45s var(--ease),
      filter 0.45s var(--ease),
      opacity 0.45s var(--ease);
    overflow-wrap: anywhere;
  }
  .line:hover {
    background: rgba(var(--ink), 0.05);
  }
  .line.active,
  .line.past.active {
    color: rgb(var(--ink));
  }
  .line.bg,
  .w.bg {
    font-size: 0.8em;
  }
  .line.bg {
    color: rgba(var(--ink), 0.22);
  }
  .line.bg.active {
    color: rgba(var(--ink), 0.6);
  }

  /* по словам: прошедшие — ярко, текущее — заливка слева направо, будущие — 35 % */
  .words .line.active .w,
  .line-fill .line.active .t {
    --p: 0;
    color: transparent;
    background: linear-gradient(
      90deg,
      rgb(var(--ink)) calc(var(--p) * 100% - 7%),
      rgba(var(--ink), 0.35) calc(var(--p) * 100% + 7%)
    );
    -webkit-background-clip: text;
    background-clip: text;
  }
  .words .line.active .w {
    display: inline-block;
    transform-origin: center bottom;
  }

  /* проигрыш «•••» — точки загораются по очереди */
  .line.pause {
    --p: 0;
    cursor: default;
    height: 1.2em;
  }
  .line.pause:hover {
    background: none;
  }
  .dots {
    display: inline-flex;
    gap: 0.28em;
    align-items: center;
    height: 100%;
  }
  .dots i {
    width: 0.32em;
    height: 0.32em;
    border-radius: 50%;
    background: rgb(var(--ink));
    opacity: 0.25;
    transition: opacity 0.2s linear;
  }
  .line.pause.active .dots i:nth-child(1) {
    opacity: clamp(0.25, calc(var(--p) * 3), 1);
  }
  .line.pause.active .dots i:nth-child(2) {
    opacity: clamp(0.25, calc(var(--p) * 3 - 1), 1);
  }
  .line.pause.active .dots i:nth-child(3) {
    opacity: clamp(0.25, calc(var(--p) * 3 - 2), 1);
  }
  .line.pause:not(.active) {
    opacity: 0.6;
  }

  /* стили подсветки (lyrics.style) */
  .style-blur .line:not(.active),
  .style-cinema .line:not(.active) {
    filter: blur(calc(var(--d) * 0.9px + 0.6px));
  }
  .style-blur .scroller:hover .line,
  .style-cinema .scroller:hover .line {
    filter: none;
  }
  .style-cinema .line:not(.active) {
    color: rgba(var(--ink), 0.22);
  }
  .style-cinema .line.active {
    text-shadow: 0 0 24px rgba(var(--ink), 0.35);
  }
  .style-scale .line {
    transform: scale(0.92);
  }
  .style-scale .line.active {
    transform: scale(1);
  }
  .style-shift .line.active {
    transform: translateX(0.35em);
  }

  /* анимация смены строки (lyrics.animation) */
  .anim-fade .line.active {
    animation: lyr-fade 0.5s var(--ease);
  }
  .anim-blur .line.active {
    animation: lyr-blur 0.5s var(--ease);
  }
  @keyframes lyr-fade {
    from {
      opacity: 0.2;
    }
  }
  @keyframes lyr-blur {
    from {
      filter: blur(6px);
    }
  }

  /* обычный текст */
  .plain {
    padding: 0 0.25em 40vh;
    font-size: 0.72em;
    font-weight: 650;
    line-height: 1.45;
    color: rgba(var(--ink), 0.82);
  }
  .plain p {
    margin: 0;
  }
  .plain .gap {
    height: 0.9em;
  }
  .plain .bg {
    color: rgba(var(--ink), 0.5);
  }
  .plain .src {
    margin-top: 1.5em;
    font-size: 12px;
    font-weight: 500;
    color: rgba(var(--ink), 0.35);
  }
  .lyrics:not(.synced) .scroller {
    padding-top: 12vh;
  }

  @media (prefers-reduced-motion: reduce) {
    .line {
      transition: color 0.2s linear;
      filter: none !important;
      transform: none !important;
      animation: none !important;
    }
  }
  :global(.no-animations) .line {
    transition: none;
    filter: none !important;
    transform: none !important;
    animation: none !important;
  }
</style>
