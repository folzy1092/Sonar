<script lang="ts">
  // Текст песни (LYRICS.md): синхронный — караоке с автопрокруткой; прозрачность, стили и анимации —
  // формулы Dotify (core/motion.ts), «•••» на проигрышах, клик по строке — перемотка. Наведение строку
  // не подсвечивает и размытие не снимает — акцент только на текущей. Обычный (Genius, plain) — просто текст с прокруткой. Правый клик — меню текста.
  import { onMount, tick } from 'svelte'
  import { fade } from 'svelte/transition'
  import { player } from '../player/player.svelte'
  import { Clock } from './core/clock'
  import { findLine } from './core/find'
  import { progress } from './core/progress'
  import { shouldAutoScroll, shouldPaint } from './core/follow'
  import { holdLook, lineLook, synthWords, wordLook, type TextAnim, type TextStyle } from './core/motion'
  import { reducedMotion } from '../lib/motion'
  import { lyrics, sizeRem } from './lyrics.svelte'
  import type { Word } from './core/types'
  import { t } from '../lib/i18n.svelte'

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
  // «Лесенка» — это прокрутка; сами строки и слова в ней ведут себя как в «Обычной»
  const anim = $derived((lyrics.animation === 'ladder' ? 'normal' : lyrics.animation) as TextAnim)

  let active = $state(-1)
  let scroller: HTMLDivElement | undefined = $state()
  const els: HTMLElement[] = $state([])
  /** Пользователь крутил колесо — автопрокрутка ждёт пару секунд. */
  let userScrollAt = 0

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

  // смена строки — прокрутка к ней: в анимации «Лесенка» на шаг вперёд — «магнитом», иначе плавным переездом блоком
  let lastActive = -1

  /** Строка, у которой развёрнут свиток аннотации Genius (наведение; работает и на паузе, и на
   *  строках, которые уже ушли вверх). Курсор может перейти со строки на свиток — он не закроется. */
  let noteOpen = $state<number | null>(null)
  let noteTimer: ReturnType<typeof setTimeout> | undefined
  function noteEnter(i: number) {
    if (!lyrics.notes.has(i)) return
    clearTimeout(noteTimer)
    noteOpen = i
  }
  function noteLeave() {
    clearTimeout(noteTimer)
    noteTimer = setTimeout(() => (noteOpen = null), 260)
  }
  $effect(() => {
    const i = active
    const prev = lastActive
    lastActive = i
    // открыт свиток аннотации — текст не уезжает из-под курсора; свиток закрыли — эффект перезапустится
    // (noteOpen читается всегда) и прокрутка «примагнитится» к текущей строке
    const follow = shouldAutoScroll({ synced, sinceUserScroll: performance.now() - userScrollAt, noteOpen })
    if (!follow || !scroller) return
    const el = i >= 0 ? els[i] : null
    // конец песни (владелец 2026-11-18): прокрутка упирается, последняя строка встаёт на 80 % высоты,
    // а подсветка спускается по строкам вниз — под текстом не остаётся пустой полэкрана
    const last = els.findLast((x) => x)
    const floor = last ? last.offsetTop + last.offsetHeight - scroller.clientHeight * 0.8 : Infinity
    const top = Math.max(0, Math.min(el ? el.offsetTop - scroller.clientHeight * 0.32 : 0, floor))
    if (!reduced && lyrics.animation === 'ladder' && prev >= 0 && i > prev && i - prev <= 3) magnet(top, prev)
    else glide(top)
  })

  /** «Магнит» (идея владельца 2026-11-16, как в Liner): прокрутка встаёт на место сразу, а строки
   *  догоняют её сами — первой уходит только что спетая, каждая следующая на 45 мс позже и чуть
   *  быстрее (нижние строки не отстают — просьба владельца 2026-11-16), по кривой с мягким разгоном
   *  и торможением. Текст подтягивается вверх лесенкой, а не блоком.
   *  Двигается `translate` — он складывается со стилем строки (`transform`), не мешая ему. */
  const MAGNET_MS = 780
  const MAGNET_STEP = 45
  /** На сколько короче анимация каждой следующей строки и предел (нижние догоняют быстрее). */
  const MAGNET_SHORTEN = 40
  const MAGNET_MIN_MS = 540
  const MAGNET_EASE = 'cubic-bezier(0.6, 0, 0.25, 1)'
  function magnet(to: number, prev: number) {
    const sc = scroller
    if (!sc) return
    cancelAnimationFrame(glideRaf)
    const before = sc.scrollTop
    sc.scrollTop = to
    const moved = sc.scrollTop - before
    if (Math.abs(moved) < 1) return
    const view0 = sc.scrollTop - sc.clientHeight
    const view1 = sc.scrollTop + sc.clientHeight * 2
    els.forEach((line, j) => {
      if (!line) return
      // строка уже едет — продолжаем с того места, где она сейчас, без рывка
      const running = line.getAnimations().find((a) => a.id === 'magnet')
      let from = moved
      if (running) {
        const y = parseFloat(getComputedStyle(line).translate.split(' ')[1] ?? '0') || 0
        from += y
        running.cancel()
      }
      if (line.offsetTop + line.offsetHeight < view0 || line.offsetTop > view1) return
      const order = Math.min(Math.max(0, j - prev), 6)
      const a = line.animate([{ translate: `0 ${from}px` }, { translate: '0 0' }], {
        duration: Math.max(MAGNET_MIN_MS, MAGNET_MS - order * MAGNET_SHORTEN),
        delay: order * MAGNET_STEP,
        easing: MAGNET_EASE,
        fill: 'backwards',
      })
      a.id = 'magnet'
    })
  }

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
      countdown(el, line.time + line.duration - t)
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
    if (el && lines.length) {
      el.style.setProperty('--p', String(progress(0, lines[0].time, t)))
      countdown(el, lines[0].time - t)
    }
  }

  /** Отсчёт до строки (идея владельца 2026-11-18): за 3 с до неё точки сменяются цифрами 3 → 2 → 1.
   *  Прямо в DOM, как и подсветка: цифра меняется раз в секунду, Svelte на каждый кадр не трогаем. */
  const COUNT_FROM = 3
  function countdown(el: HTMLElement, left: number) {
    const n = left > 0 && left <= COUNT_FROM ? String(Math.ceil(left)) : ''
    if (el.dataset.count === n) return
    el.dataset.count = n
    el.classList.toggle('counting', n !== '')
    const box = el.querySelector<HTMLElement>('.count')
    if (!box) return
    box.textContent = n
    box.classList.remove('tick')
    void box.offsetWidth // перезапуск анимации появления цифры
    if (n) box.classList.add('tick')
  }

  // часы текста — от активного <audio>; после кроссфейда играет другой дек — переподписываемся
  $effect(() => {
    const a = player.media
    if (!a) return
    clock.duration = Number.isFinite(a.duration) ? a.duration : Infinity
    if (a.paused) clock.hold(a.currentTime)
    else clock.play(a.currentTime, performance.now(), a.playbackRate)
    const on: [string, () => void][] = [
      ['timeupdate', () => clock.sample(a.currentTime, performance.now())],
      ['playing', () => clock.play(a.currentTime, performance.now(), a.playbackRate)],
      ['pause', () => clock.hold(a.currentTime)],
      ['waiting', () => clock.hold(a.currentTime)],
      ['seeking', () => clock.seek(a.currentTime)],
      ['seeked', () => (a.paused ? clock.hold(a.currentTime) : clock.play(a.currentTime, performance.now(), a.playbackRate))],
      ['ratechange', () => clock.setRate(a.playbackRate, a.currentTime, performance.now())],
      ['durationchange', () => (clock.duration = Number.isFinite(a.duration) ? a.duration : Infinity)],
    ]
    for (const [ev, fn] of on) a.addEventListener(ev, fn)
    return () => {
      for (const [ev, fn] of on) a.removeEventListener(ev, fn)
    }
  })

  onMount(() => {
    let raf = 0

    const frame = (ts: number) => {
      raf = requestAnimationFrame(frame)
      // аннотацию Genius читают — подсветка строк и слов идёт дальше, стоит только прокрутка (core/follow.ts)
      if (!shouldPaint({ synced, lineCount: lines.length, hidden: document.hidden })) return
      const t = clock.read(ts) + lyrics.offset
      const i = findLine(lines, t, active)
      if (i !== active) active = i
      if (i === -1) introProgress(t)
      else paint(t)
    }
    raf = requestAnimationFrame(frame)

    return () => {
      cancelAnimationFrame(raf)
    }
  })
</script>

<div
  class="lyrics anim-{anim}"
  class:synced
  class:paused={!player.playing}
  class:words={wordsOn}
  style:--lyrics-size="{sizeRem[lyrics.size]}rem"
  role="region"
  aria-label={t('Текст песни')}
  {oncontextmenu}
>
  <div class="scroller" bind:this={scroller} onwheel={() => ((userScrollAt = performance.now()), cancelAnimationFrame(glideRaf))}>
    {#if synced}
      {#if intro}
        <!-- текст пошёл — точки вступления гаснут совсем (владелец 2026-11-22), место остаётся: строки не дёргаются -->
        <div class="line pause intro" class:active={active === -1} style:opacity={active === -1 ? 1 : 0} style:transition="opacity 0.4s var(--ease)">
          <span class="dots" aria-hidden="true"><i></i><i></i><i></i></span><span class="count" aria-hidden="true"></span>
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
          class:noted={noteOpen === i && i <= active}
          onmouseenter={() => noteEnter(i)}
          onmouseleave={noteLeave}
        >
          {#if !line.text}
            <span class="dots" aria-label={t('Проигрыш')}><i></i><i></i><i></i></span><span class="count" aria-hidden="true"></span>
          {:else if words[i]?.length}
            {#each words[i] ?? [] as w, j (j)}<span class="w" class:bg={w.isBackground}><span class="h">{w.text}</span></span
              >{#if w.hasSpaceAfter}{' '}{/if}{/each}
          {:else}
            <span class="t">{line.text}</span>
          {/if}
          {#if lyrics.translateOn && line.text && lyrics.translation?.[i]}<span class="tr" transition:fade={{ duration: 220 }}>{lyrics.translation[i]}</span>{/if}
          {#if lyrics.notes.has(i)}<sup class="note-mark" class:on={noteOpen === i} aria-label={t('Есть аннотация Genius')}>”</sup>{/if}
        </button>
        {#if lyrics.notes.has(i)}
          {@const n = lyrics.notes.get(i)!}
          <!-- свиток: разворачивается сверху вниз под строкой, пока на ней (или на нём) курсор -->
          <!-- строка ещё впереди — свиток так же размыт и приглушён, как она (стиль текста) -->
          <div
            class="note"
            class:open={noteOpen === i}
            role="note"
            style:filter={i > active ? look.filter : null}
            style:opacity={i > active ? look.opacity : null}
            onmouseenter={() => noteEnter(i)}
            onmouseleave={noteLeave}
          >
            <div class="note-in">
              <div class="note-body selectable">
                {n.body}
              </div>
            </div>
          </div>
        {/if}
      {/each}
      <div class="tail" aria-hidden="true"></div>
    {:else}
      <div class="plain selectable">
        {#each lines as line, i (i)}
          {#if line.text}<p class:bg={line.isBackground}>{line.text}{#if lyrics.translateOn && lyrics.translation?.[i]}<span class="tr">{lyrics.translation[i]}</span>{/if}</p>{:else}<p class="gap"></p>{/if}
        {/each}
        {#if data?.source === 'genius'}<p class="src">{t('Текст: Genius')}</p>{/if}
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

  /* перевод — под строкой, мельче и тише оригинала */
  .tr {
    display: block;
    margin-top: 0.18em;
    font-size: 0.56em;
    font-weight: 500;
    letter-spacing: 0;
    line-height: 1.3;
    opacity: 0.62;
  }
  .line {
    display: block;
    width: 100%;
    margin: 0;
    /* справа запас как у Dotify: текущая строка увеличивается до 108 % и не должна обрезаться */
    padding: 0.4em 9% 0.4em 0.25em;
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
  }
  /* слово светлеет по мере пения: без background-clip: text — в WebView2 под маской прокрутки и
     трансформациями строки он не рисовался, и текущая строка пропадала целиком */
  .anim-normal .line.active .w .h {
    color: rgba(var(--ink), calc(0.5 + 0.5 * var(--p)));
    transition: color 90ms linear;
  }

  /* проигрыш «•••» — точки плавно качаются волной; за 3 с до строки — отсчёт 3 · 2 · 1 */
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
  .line.pause {
    position: relative;
  }
  .line.pause.active .dots i {
    opacity: 0.85;
    animation: dot-wave 1.2s ease-in-out infinite;
  }
  /* трек на паузе — точки стоят ровно, а не продолжают «петь» */
  .paused .line.pause.active .dots i {
    animation: none;
    transform: none;
  }
  .line.pause.active .dots i:nth-child(2) {
    animation-delay: 0.15s;
  }
  .line.pause.active .dots i:nth-child(3) {
    animation-delay: 0.3s;
  }
  @keyframes dot-wave {
    0%,
    60%,
    100% {
      transform: translateY(0.12em);
    }
    30% {
      transform: translateY(-0.12em);
    }
  }
  .dots {
    transition: opacity 0.25s var(--ease);
  }
  .line.pause.active:global(.counting) .dots {
    opacity: 0;
  }
  .count {
    position: absolute;
    left: 0;
    top: 50%;
    translate: 0 -50%;
    font-weight: 800;
    font-size: 0.9em;
    line-height: 1;
    color: rgb(var(--ink));
    font-variant-numeric: tabular-nums;
    pointer-events: none;
  }
  .line.pause:not(.active) .count {
    display: none;
  }
  .count.tick {
    animation: count-in 0.45s var(--ease);
  }
  @keyframes count-in {
    from {
      opacity: 0;
      transform: translateY(0.3em) scale(0.85);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .line.pause.active .dots i {
      animation: none;
    }
    @keyframes count-in {
      from {
        opacity: 0;
      }
    }
  }

  /* обычный текст */
  .plain {
    padding: 0 0.25em 40vh;
    font-size: 0.72em;
    font-weight: 650;
    /* строки текста без времени — с воздухом между ними (владелец 2026-11-22: «вплотную») */
    line-height: 1.6;
    color: rgba(var(--ink), 0.82);
  }
  .plain p {
    margin: 0 0 0.28em;
  }
  .plain .gap {
    height: 1.1em;
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
  /* строка, чью аннотацию читают, — чёткая, даже если она не текущая */
  .line.noted {
    filter: none !important;
    opacity: 1 !important;
  }
  /* кавычки у строки с аннотацией Genius */
  .note-mark {
    margin-left: 0.15em;
    font-size: 0.55em;
    font-weight: 700;
    vertical-align: super;
    color: rgb(var(--ink));
    opacity: 0.55;
    transition:
      opacity 0.3s var(--ease),
      text-shadow 0.3s var(--ease);
  }
  .note-mark.on {
    opacity: 1;
    text-shadow: 0 0 10px rgba(255, 255, 255, 0.5);
  }
  /* свиток: высота 0 → по содержимому (grid 0fr → 1fr), сверху вниз проявляется текст */
  .note {
    transition:
      grid-template-rows 0.5s cubic-bezier(0.32, 0.72, 0, 1),
      filter 0.4s var(--ease),
      opacity 0.4s var(--ease);
    display: grid;
    grid-template-rows: 0fr;
    max-width: min(440px, 80%);
    margin: 0 0 0 0.25em;
  }
  .note.open {
    grid-template-rows: 1fr;
  }
  .note-in {
    min-height: 0;
    overflow: hidden;
  }
  .note-body {
    margin: 4px 0 14px;
    padding: 8px 0 8px 14px;
    border-left: 2px solid rgba(255, 255, 255, 0.35);
    font-size: max(13px, 0.36em);
    font-style: italic;
    font-weight: 500;
    line-height: 1.5;
    letter-spacing: 0;
    color: rgba(255, 255, 255, 0.72);
    white-space: pre-line;
    clip-path: inset(0 0 100% 0);
    transition: clip-path 0.55s cubic-bezier(0.32, 0.72, 0, 1) 0.05s;
  }
  .note.open .note-body {
    clip-path: inset(0 0 0 0);
  }
  @media (prefers-reduced-motion: reduce) {
    .note,
    .note-body {
      transition: opacity 0.2s linear;
    }
  }
</style>
