<script lang="ts">
  // Кнопка эквалайзера в капсуле у громкости (страница плеера) и всплывашка под ней: «+» и пресеты
  // сверху, кривая на 12 полос (точки тянутся мышью, колесо над точкой — ±0.5 дБ), «Запомнить» —
  // кривая для этого трека. Открывается и закрывается только кликом (правило владельца).
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import { pop } from '../lib/motion'
  import { player } from './player.svelte'
  import { EQ_FREQS, EQ_MAX_DB, eq, freqLabel } from './eq.svelte'

  let open = $state(false)
  let root: HTMLDivElement | undefined = $state()
  let naming = $state(false)
  let newName = $state('')
  let svg: SVGSVGElement | undefined = $state()
  let drag = $state<number | null>(null)

  const W = 300
  const H = 120
  const PAD = 10
  const x = (i: number) => PAD + (i * (W - 2 * PAD)) / (EQ_FREQS.length - 1)
  const y = (db: number) => H / 2 - (db / EQ_MAX_DB) * (H / 2 - PAD)

  /** Плавная кривая через точки (Catmull-Rom → кубические Безье). */
  const path = $derived.by(() => {
    const p = eq.gains.map((g, i) => [x(i), y(g)])
    let d = `M${p[0][0]},${p[0][1]}`
    for (let i = 0; i < p.length - 1; i++) {
      const p0 = p[i - 1] ?? p[i]
      const p1 = p[i]
      const p2 = p[i + 1]
      const p3 = p[i + 2] ?? p2
      const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6]
      const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6]
      d += ` C${c1[0]},${c1[1]} ${c2[0]},${c2[1]} ${p2[0]},${p2[1]}`
    }
    return d
  })

  function dbAt(clientY: number): number {
    const r = svg!.getBoundingClientRect()
    const py = ((clientY - r.top) / r.height) * H
    return ((H / 2 - py) / (H / 2 - PAD)) * EQ_MAX_DB
  }

  function nearest(clientX: number): number {
    const r = svg!.getBoundingClientRect()
    const px = ((clientX - r.left) / r.width) * W
    let best = 0
    for (let i = 1; i < EQ_FREQS.length; i++) if (Math.abs(x(i) - px) < Math.abs(x(best) - px)) best = i
    return best
  }

  function down(e: PointerEvent) {
    if (!svg) return
    drag = nearest(e.clientX)
    svg.setPointerCapture(e.pointerId)
    eq.setBand(drag, dbAt(e.clientY))
  }

  function move(e: PointerEvent) {
    if (drag !== null) eq.setBand(drag, dbAt(e.clientY))
  }

  function wheel(e: WheelEvent) {
    e.preventDefault()
    const i = nearest(e.clientX)
    eq.setBand(i, eq.gains[i] + (e.deltaY < 0 ? 0.5 : -0.5))
  }

  function savePreset(e: SubmitEvent) {
    e.preventDefault()
    eq.addPreset(newName)
    newName = ''
    naming = false
  }

  onMount(() => {
    const outside = (e: MouseEvent) => {
      if (open && root && !root.contains(e.target as Node)) {
        open = false
        naming = false
      }
    }
    window.addEventListener('mousedown', outside, true)
    return () => window.removeEventListener('mousedown', outside, true)
  })
</script>

<div class="eq" bind:this={root}>
  <button
    class="icon-btn"
    class:active={open || eq.gains.some((g) => g !== 0)}
    aria-label="Эквалайзер"
    title="Эквалайзер"
    aria-expanded={open}
    onclick={() => {
      open = !open
      naming = false
    }}
  >
    <Icon name="adjustments" size={18} />
  </button>

  {#if open}
    <div class="pop" role="dialog" aria-label="Эквалайзер" in:pop={{ y: 8 }} out:pop={{ y: 8 }}>
      <div class="presets">
        {#if naming}
          <form class="name" onsubmit={savePreset}>
            <!-- svelte-ignore a11y_autofocus -->
            <input bind:value={newName} placeholder="Название пресета" maxlength="40" autofocus />
            <button type="submit" disabled={!newName.trim()}>Сохранить</button>
          </form>
        {:else}
          <button class="plus" aria-label="Сохранить как пресет" title="Сохранить как пресет" onclick={() => (naming = true)}>
            <Icon name="plus" size={16} />
          </button>
          <div class="chips">
            {#each eq.presets as p (p.name)}
              <span class="chip" class:on={eq.activePreset === p.name}>
                <button onclick={() => eq.set(p.gains)}>{p.name}</button>
                {#if !p.builtin && eq.activePreset === p.name}
                  <button class="del" aria-label="Удалить пресет" title="Удалить пресет" onclick={() => eq.removePreset(p.name)}>
                    <Icon name="x" size={12} />
                  </button>
                {/if}
              </span>
            {/each}
          </div>
        {/if}
      </div>

      <svg
        bind:this={svg}
        viewBox="0 0 {W} {H}"
        class="graph"
        role="slider"
        aria-label="Кривая эквалайзера"
        aria-valuenow={0}
        tabindex="-1"
        onpointerdown={down}
        onpointermove={move}
        onpointerup={() => (drag = null)}
        onwheel={wheel}
      >
        <line x1={PAD} x2={W - PAD} y1={H / 2} y2={H / 2} class="zero" />
        <path d={path} class="curve" />
        {#each eq.gains as g, i (i)}
          <circle cx={x(i)} cy={y(g)} r={drag === i ? 5 : 3.5} class="dot" />
        {/each}
      </svg>
      <div class="labels">
        {#each EQ_FREQS as f (f)}<span>{freqLabel(f)}</span>{/each}
      </div>

      <button
        class="remember"
        class:on={eq.remembered}
        disabled={!player.current}
        title={eq.remembered ? 'Вернуть общую кривую для этого трека' : 'Эта кривая будет включаться на этом треке'}
        onclick={() => eq.toggleRemember()}
      >
        {eq.remembered ? 'Запомнено для трека · забыть' : 'Запомнить'}
      </button>
    </div>
  {/if}
</div>

<style>
  .eq {
    position: relative;
  }
  .icon-btn {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
    border-radius: 999px;
    color: var(--text-2);
    transition: color var(--fast) var(--ease);
  }
  .icon-btn:hover,
  .icon-btn.active {
    color: var(--text);
  }
  .pop {
    position: absolute;
    right: -8px;
    bottom: calc(100% + 10px);
    z-index: 20;
    width: 324px;
    padding: 12px;
    border-radius: 16px;
    background: var(--surface-1);
    border: 1px solid var(--border-strong);
    box-shadow: 0 18px 44px -12px rgba(0, 0, 0, 0.7);
    transform-origin: bottom right;
  }
  .presets {
    display: flex;
    align-items: center;
    gap: 6px;
    min-height: 30px;
  }
  .plus {
    display: grid;
    place-items: center;
    flex-shrink: 0;
    width: 28px;
    height: 28px;
    border-radius: 50%;
    border: 1px solid var(--border-strong);
    color: var(--text-2);
  }
  .plus:hover {
    color: var(--text);
  }
  .chips {
    display: flex;
    gap: 6px;
    overflow-x: auto;
    scrollbar-width: none;
  }
  .chip {
    display: inline-flex;
    align-items: center;
    flex-shrink: 0;
    height: 28px;
    padding: 0 12px;
    border-radius: 999px;
    border: 1px solid var(--border-strong);
    font-size: 12px;
    font-weight: 600;
    color: var(--text-2);
    white-space: nowrap;
  }
  .chip.on {
    background: var(--text);
    border-color: var(--text);
    color: var(--accent-ink);
  }
  .chip .del {
    display: grid;
    place-items: center;
    margin: 0 -6px 0 6px;
    opacity: 0.6;
  }
  .chip .del:hover {
    opacity: 1;
  }
  .name {
    display: flex;
    gap: 6px;
    width: 100%;
  }
  .name input {
    flex: 1;
    min-width: 0;
    height: 30px;
    padding: 0 10px;
    border-radius: 10px;
    border: 1px solid var(--border-strong);
    background: var(--plate);
    color: var(--text);
    font: inherit;
    font-size: 13px;
    outline: none;
  }
  .name button {
    padding: 0 12px;
    border-radius: 10px;
    background: var(--text);
    color: var(--accent-ink);
    font-size: 12px;
    font-weight: 600;
  }
  .name button:disabled {
    opacity: 0.4;
  }
  .graph {
    display: block;
    width: 100%;
    height: auto;
    margin-top: 10px;
    cursor: ns-resize;
    touch-action: none;
  }
  .zero {
    stroke: var(--border-strong);
    stroke-dasharray: 3 4;
  }
  .curve {
    fill: none;
    stroke: var(--text);
    stroke-width: 2;
  }
  .dot {
    fill: var(--text);
  }
  .labels {
    display: flex;
    justify-content: space-between;
    padding: 4px 4px 0;
    font-size: 9px;
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  .remember {
    width: 100%;
    height: 34px;
    margin-top: 12px;
    border-radius: 10px;
    background: var(--text);
    color: var(--accent-ink);
    font-size: 13px;
    font-weight: 600;
  }
  .remember.on {
    background: var(--surface-3);
    color: var(--text);
  }
  .remember:disabled {
    opacity: 0.4;
  }
</style>
