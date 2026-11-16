<script lang="ts">
  // Горизонтальная «палочка» прокрутки (решение владельца 2026-11-16, Любимые и плейлисты): вместо
  // вертикальной полосы справа — тонкая дорожка под кнопками, по ней едет маленькая палочка: где
  // она, там и ты в списке. Палочку можно тянуть, клик по дорожке — прыжок туда. Список короткий и не
  // прокручивается — дорожки нет.
  interface Props {
    target: HTMLElement | undefined
  }
  let { target }: Props = $props()

  let progress = $state(0)
  let scrollable = $state(false)
  let track: HTMLDivElement | undefined = $state()
  let stick: HTMLSpanElement | undefined = $state()
  let dragging = $state(false)
  let raf = 0

  const STICK = 34

  $effect(() => {
    const el = target
    if (!el) return
    // палочка идёт за прокруткой кадр в кадр: transform прямо в DOM, без перехода (переход на
    // каждый шаг колеса перезапускался и давал рывки)
    const update = () => {
      cancelAnimationFrame(raf)
      raf = requestAnimationFrame(() => {
        const max = el.scrollHeight - el.clientHeight
        const p = max > 0 ? el.scrollTop / max : 0
        if (scrollable !== max > 4) scrollable = max > 4
        progress = p
        if (stick && track) stick.style.transform = `translate(${p * (track.clientWidth - STICK)}px, -50%)`
      })
    }
    update()
    el.addEventListener('scroll', update, { passive: true })
    const ro = new ResizeObserver(update)
    ro.observe(el)
    const mo = new MutationObserver(update)
    mo.observe(el, { childList: true, subtree: true })
    return () => {
      cancelAnimationFrame(raf)
      el.removeEventListener('scroll', update)
      ro.disconnect()
      mo.disconnect()
    }
  })

  function scrollTo(clientX: number, smooth: boolean) {
    if (!track || !target) return
    const r = track.getBoundingClientRect()
    const t = Math.min(1, Math.max(0, (clientX - r.left - STICK / 2) / (r.width - STICK)))
    const max = target.scrollHeight - target.clientHeight
    target.scrollTo({ top: t * max, behavior: smooth ? 'smooth' : 'auto' })
  }

  function down(e: PointerEvent) {
    ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
    dragging = true
    scrollTo(e.clientX, false)
  }
</script>

<div
  class="stick-track"
  class:show={scrollable}
  class:dragging
  bind:this={track}
  role="scrollbar"
  aria-controls="tracks"
  aria-valuenow={Math.round(progress * 100)}
  aria-orientation="horizontal"
  tabindex="-1"
  onpointerdown={down}
  onpointermove={(e) => dragging && scrollTo(e.clientX, false)}
  onpointerup={() => (dragging = false)}
>
  <span class="stick" bind:this={stick} style:--w="{STICK}px"></span>
</div>

<style>
  .stick-track {
    position: relative;
    height: 14px;
    margin: 2px 0 4px;
    cursor: pointer;
    opacity: 0;
    pointer-events: none;
    transition: opacity var(--normal) var(--ease);
    touch-action: none;
  }
  .stick-track.show {
    opacity: 1;
    pointer-events: auto;
  }
  /* сама дорожка — едва заметная линия */
  .stick-track::before {
    content: '';
    position: absolute;
    left: 0;
    right: 0;
    top: 50%;
    height: 2px;
    translate: 0 -50%;
    border-radius: 2px;
    background: color-mix(in srgb, var(--text) 8%, transparent);
  }
  .stick {
    position: absolute;
    top: 50%;
    left: 0;
    width: var(--w);
    height: 4px;
    transform: translate(0, -50%);
    will-change: transform;
    border-radius: 4px;
    background: color-mix(in srgb, var(--text) 55%, transparent);
    transition:
      height var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .stick-track.dragging .stick {
    transition:
      height var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .stick-track:hover .stick,
  .stick-track.dragging .stick {
    height: 6px;
    background: var(--text);
  }
</style>
