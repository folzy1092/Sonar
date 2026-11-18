<script lang="ts">
  // Итоги месяца и года (NEXT_PROMPT «Этап 11»): на весь экран поверх приложения, фон — из обложки
  // первого трека топа. Листают стрелками на экране, колесом и клавишами (← → ↑ ↓, PageUp/PageDown,
  // пробел, Home/End), Esc или крестик — закрыть. Карточка въезжает со стороны листания; «Меньше
  // движения» — только прозрачность. У каждой карточки — «Сохранить картинкой» и «Скопировать».
  import { tick } from 'svelte'
  import { fade } from 'svelte/transition'
  import { cubicIn } from 'svelte/easing'
  import Icon from '../components/Icon.svelte'
  import RecapCardBody from '../components/RecapCardBody.svelte'
  import { easeOutQuint, pop, reducedMotion } from '../lib/motion'
  import { t } from '../lib/i18n.svelte'
  import { css } from '../theme/palette'
  import { keyMove, WHEEL_GAP_MS, wheelMove } from '../lib/recap-core'
  import { periodTitle, recapKindTitle } from '../lib/recap-text'
  import { copyCard, saveCard } from '../lib/recap-share'
  import { recap } from '../lib/recap.svelte'
  import { quick } from '../lib/quick.svelte'

  const SLIDE_PX = 64

  let box: HTMLElement | undefined = $state()
  let busy = $state<'save' | 'copy' | null>(null)
  let lastWheel = 0
  /** Куда вернуть фокус после закрытия. */
  let before: HTMLElement | null = null

  const card = $derived(recap.cards[recap.index] ?? null)
  const palette = $derived(
    [
      `--rc-bg:${css(recap.colors.bg)}`,
      `--rc-bg2:${css(recap.colors.bg2)}`,
      `--rc-accent:${css(recap.colors.accent)}`,
      `--rc-glow:${css(recap.colors.accent, 0.3)}`,
      `--rc-ink:${css(recap.colors.ink)}`,
    ].join(';'),
  )

  $effect(() => {
    if (!recap.isOpen) return
    before = document.activeElement instanceof HTMLElement ? document.activeElement : null
    void tick().then(() => box?.focus())
    return () => before?.focus?.()
  })

  /** Карточка въезжает со стороны листания и уезжает в другую; «Меньше движения» — только прозрачность. */
  function slide(_node: Element, { out = false }: { out?: boolean } = {}) {
    const duration = out ? 200 : 360
    if (reducedMotion()) return { duration: duration * 0.6, css: (k: number) => `opacity:${k}` }
    const shift = (out ? -1 : 1) * recap.dir * SLIDE_PX
    return {
      duration,
      easing: out ? cubicIn : easeOutQuint,
      css: (k: number, u: number) => `opacity:${k};transform:translateX(${u * shift}px)`,
    }
  }

  function onWindowKey(e: KeyboardEvent) {
    if (!recap.isOpen || quick.open) return
    if (e.key === 'Escape') {
      e.preventDefault()
      e.stopPropagation()
      recap.close()
      return
    }
    if (e.ctrlKey || e.altKey || e.metaKey) return
    const move = keyMove(e.key)
    if (move === null) return
    e.preventDefault()
    e.stopPropagation()
    recap.go(move)
  }

  function onWheel(e: WheelEvent) {
    const now = performance.now()
    const move = wheelMove(e.deltaY, e.deltaX, now, lastWheel)
    // жест колеса — серия событий: пока она идёт, отсчёт паузы начинается заново
    if (move || now - lastWheel < WHEEL_GAP_MS) lastWheel = now
    if (move) recap.go(move)
  }

  async function share(kind: 'save' | 'copy') {
    const { data, ref } = recap
    if (!card || !data || !ref || busy) return
    busy = kind
    const shot = { card, index: recap.index, ref, data, colors: recap.colors }
    try {
      await (kind === 'save' ? saveCard(shot) : copyCard(shot))
    } finally {
      busy = null
    }
  }
</script>

<svelte:window onkeydowncapture={onWindowKey} />

{#if recap.isOpen && recap.ref}
  {@const ref = recap.ref}
  <div
    class="recap"
    style={palette}
    role="dialog"
    aria-modal="true"
    aria-label={`${recapKindTitle(ref)} · ${periodTitle(ref)}`}
    tabindex="-1"
    bind:this={box}
    onwheel={onWheel}
    transition:fade={{ duration: 220 }}
  >
    <header>
      <span class="brand">SONAR</span>
      <span class="period">{recapKindTitle(ref)} · {periodTitle(ref)}</span>
      <button class="round" onclick={() => recap.close()} aria-label={t('Закрыть')} title={t('Закрыть')}>
        <Icon name="x" size={20} />
      </button>
    </header>

    <main>
      {#if recap.loading}
        <p class="state" in:fade={{ duration: 200 }}>{t('Собираю итоги…')}</p>
      {:else if recap.error}
        <p class="state" in:fade={{ duration: 200 }}>{recap.error}</p>
      {:else if !card || !recap.data}
        <div class="state" in:pop={{ y: 0, scale: 0.98 }}>
          <Icon name="chart" size={28} />
          <p>{t('Мало данных за этот период — послушай ещё немного')}</p>
        </div>
      {:else}
        <button class="round side prev" onclick={() => recap.go(-1)} disabled={recap.index === 0} aria-label={t('Назад')}>
          <Icon name="chevronLeft" size={22} />
        </button>
        <div class="stage">
          {#key recap.index}
            <section class="card" in:slide out:slide={{ out: true }}>
              <RecapCardBody {card} {ref} data={recap.data} />
            </section>
          {/key}
        </div>
        <button
          class="round side next"
          onclick={() => recap.go(1)}
          disabled={recap.index >= recap.cards.length - 1}
          aria-label={t('Вперёд')}
        >
          <Icon name="chevronRight" size={22} />
        </button>
      {/if}
    </main>

    {#if card && recap.data}
      <footer in:fade={{ duration: 200 }}>
        <div class="dots" role="tablist" aria-label={t('Карточки')}>
          {#each recap.cards as c, i (c.kind)}
            <button
              class="dot"
              class:on={i === recap.index}
              role="tab"
              aria-selected={i === recap.index}
              aria-label={`${i + 1} / ${recap.cards.length}`}
              onclick={() => recap.go(i - recap.index)}
            ></button>
          {/each}
        </div>
        <div class="actions">
          <button class="pill" onclick={() => share('save')} disabled={busy !== null}>
            <Icon name="download" size={18} />{t('Сохранить картинкой')}
          </button>
          <button class="pill" onclick={() => share('copy')} disabled={busy !== null}>
            <Icon name="copy" size={18} />{t('Скопировать')}
          </button>
        </div>
      </footer>
    {/if}
  </div>
{/if}

<style>
  .recap {
    position: fixed;
    inset: 0;
    z-index: 59; /* над плеером и всплывашками (≤58), под тостами (60) и Ctrl+K (66) */
    display: grid;
    grid-template-rows: auto 1fr auto;
    color: var(--rc-ink);
    background:
      radial-gradient(circle at 85% 8%, var(--rc-glow), transparent 60%),
      linear-gradient(135deg, var(--rc-bg), var(--rc-bg2));
    transition: background 600ms var(--ease);
    outline: none;
    overflow: hidden;
  }
  header {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 18px 24px;
  }
  .brand {
    font-weight: 800;
    letter-spacing: 0.08em;
    color: var(--rc-accent);
  }
  .period {
    flex: 1;
    color: color-mix(in srgb, var(--rc-ink) 70%, transparent);
    font-size: calc(14px * var(--fs, 1));
  }
  main {
    display: grid;
    grid-template-columns: 64px minmax(0, 1fr) 64px;
    align-items: center;
    gap: 16px;
    padding: 0 24px;
    min-height: 0;
  }
  .stage {
    display: grid;
    justify-items: center;
    min-width: 0;
  }
  .card {
    grid-area: 1 / 1;
    width: min(560px, 100%);
    display: flex;
  }
  .state {
    grid-column: 1 / -1;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 12px;
    text-align: center;
    color: color-mix(in srgb, var(--rc-ink) 75%, transparent);
  }
  .state p {
    margin: 0;
  }
  .round {
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    border-radius: 50%;
    border: 0;
    color: var(--rc-ink);
    background: color-mix(in srgb, var(--rc-ink) 10%, transparent);
    cursor: pointer;
    transition:
      background var(--fast) var(--ease),
      opacity var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .round:hover:not(:disabled) {
    background: color-mix(in srgb, var(--rc-ink) 18%, transparent);
  }
  .round:active:not(:disabled) {
    transform: scale(0.94);
  }
  .round:disabled {
    opacity: 0.25;
    cursor: default;
  }
  .side {
    justify-self: center;
  }
  footer {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 16px;
    padding: 16px 24px 28px;
  }
  .dots {
    display: flex;
    gap: 8px;
  }
  .dot {
    width: 8px;
    height: 8px;
    padding: 0;
    border: 0;
    border-radius: 99px;
    background: color-mix(in srgb, var(--rc-ink) 30%, transparent);
    cursor: pointer;
    transition:
      width var(--normal, 240ms) var(--ease),
      background var(--fast) var(--ease);
  }
  .dot.on {
    width: 24px;
    background: var(--rc-accent);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    gap: 10px;
  }
  .pill {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 40px;
    padding: 0 18px;
    border-radius: 99px;
    border: 1px solid color-mix(in srgb, var(--rc-ink) 20%, transparent);
    color: var(--rc-ink);
    background: color-mix(in srgb, var(--rc-ink) 8%, transparent);
    font: inherit;
    font-weight: 600;
    cursor: pointer;
    transition:
      background var(--fast) var(--ease),
      opacity var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .pill:hover:not(:disabled) {
    background: color-mix(in srgb, var(--rc-ink) 16%, transparent);
  }
  .pill:active:not(:disabled) {
    transform: scale(0.97);
  }
  .pill:disabled {
    opacity: 0.5;
    cursor: progress;
  }
</style>
