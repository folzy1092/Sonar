<script lang="ts">
  // Текст песни (LYRICS.md): синхронный — караоке с автопрокруткой; прозрачность, стили и анимации —
  // формулы Dotify (core/motion.ts), «•••» на проигрышах, клик по строке — перемотка. Наведение строку
  // не подсвечивает и размытие не снимает — акцент только на текущей. Обычный (Genius, plain) — просто текст с прокруткой. Правый клик — меню текста.
  import { onMount, tick } from 'svelte'
  import { player } from '../player/player.svelte'
  import { Clock } from './core/clock'
  import { findLine } from './core/find'
  import { progress } from './core/progress'
  import { holdLook, lineLook, synthWords, wordLook, type TextAnim, type TextStyle } from './core/motion'
  import { reducedMotion } from '../lib/motion'
  import { lyrics, sizeRem } from './lyrics.svelte'
  import type { Word } from './core/types'

  interface Props {
    oncontextmenu?: (e: MouseEvent) => void
  }
  let { oncontextmenu }: Props = $props()

  const data = $derived(lyrics.data)
  const lines = $derived(data?.lines ?? [])
  const synced = $derived(!!data?.isSynced)
  /** Караоке по словам: настоящие тайминги, а где их нет — слова с временем по длине (как Dotify). */
  const wordsOn = $derived(lyrics.mode === 'words' && synced)
  const words = $derived<(Word[] | null)[]>(
    wordsOn ? lines.map((l, i) => (l.words?.length ? l.words : l.text ? synthWords(l, lines[i + 1]) : null)) : [],
  )
  const style = $derived(lyrics.style as TextStyle)
  const anim = $derived(lyrics.animation as TextAnim)

  let active = $state(-1)
  let scroller: HTMLDivElement | undefined = $state()
  const els: HTMLElement[] = $state([])
  /** Пользователь крутил колесо — автопрокрутка ждёт пару секунд. */
  let userScrollAt = 0
  const USER_SCROLL_PAUSE = 2500

  const clock = new Clock()
  const reduced = reducedMotion()
  /** Строка, слова которой сейчас раскрашены, — при смене строки стили слов снимаются. */
  let painted = -1

  $effect(() => {
    lyrics.line = active
  })

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
    glide(Math.max(0, top))
  })

  /** Плавный переезд к строке (~1 с, мягкий разгон и торможение) вместо резкого системного
   *  smooth-скролла: прошлый текст спокойно уходит вверх, новый подтягивается снизу. */
  let glideRaf = 0
  function glide(to: number) {
    const sc = scroller
    if (!sc) return
    cancelAnimationFrame(glideRaf)
    if (reduced) {
      sc.scrollTop = to
      return
    }
    const from = sc.scrollTop
    const dist = to - from
    if (Math.abs(dist) < 1) return
    const dur = Math.min(1300, 750 + Math.abs(dist) * 0.6)
    const t0 = performance.now()
    const ease = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2)
    const step = (now: number) => {
      const t = Math.min(1, (now - t0) / dur)
      sc.scrollTop = from + dist * ease(t)
      if (t < 1) glideRaf = requestAnimationFrame(step)
    }
    glideRaf = requestAnimationFrame(step)
  }

  function seekTo(time: number) {
    if (!synced) return
    userScrollAt = 0
    player.seek(Math.max(0, (time - lyrics.offset) * 1000))
    if (!player.playing) void player.play()
  }

  function clearWords(i: number) {
    const el = i >= 0 ? els[i] : null
    if (!el) return
    el.querySelectorAll<HTMLElement>('.w').forEach((w) => {
      w.removeAttribute('style')
      w.firstElementChild?.removeAttribute('style')
    })
  }

  /** Подсветка внутри текущей строки — прямо в DOM, без перерисовки Svelte на каждый кадр. */
  function paint(t: number) {
    const i = active
    if (painted !== i) {
      clearWords(painted)
      painted = i
    }
    const el = i >= 0 ? els[i] : null
    if (!el) return
    const line = lines[i]
    if (!line.text) {
      el.style.setProperty('--p', String(progress(line.time, line.duration, t)))
      return
    }
    const list = words[i]
    if (!list?.length) return
    const spans = el.querySelectorAll<HTMLElement>('.w')
    list.forEach((w, j) => {
      const span = spans[j]
      if (!span) return
      const p = progress(w.time, w.duration, t)
      const past = p >= 1
      const current = p > 0 && p < 1
      if (anim === 'normal') span.style.setProperty('--p', p.toFixed(4))
      else if (!reduced) {
        const look = wordLook(anim, p, past, current)
        span.style.opacity = look.opacity === undefined ? '' : String(look.opacity)
        span.style.transform = look.transform ?? ''
        span.style.filter = look.filter ?? ''
        span.style.transition = look.transition ?? ''
      } else span.style.opacity = String(past ? 1 : current ? 0.5 + 0.5 * p : 0.52)
      const hold = span.firstElementChild as HTMLElement | null
      if (hold && !reduced) {
        const h = holdLook(anim, p, w.duration, current)
        hold.style.transform = h.transform ?? ''
        hold.style.filter = h.filter ?? ''
      }
    })
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
  class="lyrics anim-{anim}"
  class:synced
  class:words={wordsOn}
  style:--lyrics-size="{sizeRem[lyrics.size]}rem"
  role="region"
  aria-label="Текст песни"
  {oncontextmenu}
>
  <div class="scroller" bind:this={scroller} onwheel={() => ((userScrollAt = performance.now()), cancelAnimationFrame(glideRaf))}>
    {#if synced}
      {#if intro}
        <div class="line pause intro" class:active={active === -1} style:opacity={active === -1 ? 1 : 0.42}>
          <span class="dots" aria-hidden="true"><i></i><i></i><i></i></span>
        </div>
      {/if}
      {#each lines as line, i (i)}
        {@const look = lineLook(style, anim, i - active, true, line.isBackground, reduced)}
        <button
          class="line"
          class:active={i === active}
          class:bg={line.isBackground}
          class:pause={!line.text}
          style:opacity={look.opacity}
          style:transform={look.transform}
          style:filter={look.filter}
          style:letter-spacing={look.letterSpacing}
          style:transition={look.transition}
          bind:this={els[i]}
          onclick={() => seekTo(line.time)}
        >
          {#if !line.text}
            <span class="dots" aria-label="Проигрыш"><i></i><i></i><i></i></span>
          {:else if words[i]?.length}
            {#each words[i] ?? [] as w, j (j)}<span class="w" class:bg={w.isBackground}><span class="h">{w.text}</span></span
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
    /* справа запас как у Dotify: текущая строка увеличивается до 108 % и не должна обрезаться */
    padding: 0.32em 9% 0.32em 0.25em;
    text-align: left;
    font: inherit;
    font-weight: 600;
    line-height: 1.32;
    letter-spacing: -0.02em;
    color: rgb(var(--ink));
    cursor: pointer;
    transform-origin: left center;
    will-change: transform, opacity;
    overflow-wrap: anywhere;
  }
  .line.bg,
  .w.bg {
    font-size: 0.84em;
    font-weight: 500;
    font-style: italic;
  }

  .w,
  .h {
    display: inline-block;
    white-space: pre;
    transform-origin: center bottom;
  }
  /* «Обычная»: слово заливается слева направо, будущие — 55 %, прошедшие — ярко */
  .anim-normal .line.active .w {
    --p: 0;
    color: transparent;
    background: linear-gradient(
      90deg,
      rgb(var(--ink)) calc(var(--p) * 114% - 14%),
      rgba(var(--ink), 0.55) calc(var(--p) * 114%)
    );
    -webkit-background-clip: text;
    background-clip: text;
  }

  /* проигрыш «•••» — точки загораются по очереди */
  .line.pause {
    --p: 0;
    cursor: default;
    height: 1.38em;
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
    font-size: calc(12px * var(--fs, 1));
    font-weight: 500;
    color: rgba(var(--ink), 0.35);
  }
  .lyrics:not(.synced) .scroller {
    padding-top: 12vh;
  }

  :global(.no-motion) .line,
  :global(.no-motion) .w,
  :global(.no-motion) .h {
    transform: none !important;
    filter: none !important;
  }
</style>
