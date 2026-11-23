<script lang="ts">
  // Кнопка «Сведение» в плеере (docs/BLEND.md §10.1): включить, вид, длина, сколько можно срезать,
  // тональность и карточка «Следующий переход» с «Другой момент» / «К переходу». Включено — кнопка
  // подсвечена, на ней короткое имя вида. Открывается и закрывается только кликом, как SpeedButton.
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import BlendRate from './BlendRate.svelte'
  import Ruler from '../components/Ruler.svelte'
  import Switch from '../components/settings/Switch.svelte'
  import { t } from '../lib/i18n.svelte'
  import { indicator } from '../lib/indicator'
  import { pop, scale, slide } from '../lib/motion'
  import { settings } from '../lib/settings.svelte'
  import { blendAnalysis } from './blend/analyze.svelte'
  import { blendRatings } from './blend/ratings.svelte'
  import { party } from './blend/party.svelte'
  import { BLEND_LENGTHS, BLEND_TYPES, blendSettings, CUT_MAX_SEC, CUT_RECOMMENDED_SEC } from './blend/settings'
  import { buttonLabel, cardFor, KIND_TEXT, LENGTH_TEXT } from './blend/view'
  import { formatTime, player } from './player.svelte'
  import { tempo } from './tempo.svelte'

  let open = $state(false)
  let root: HTMLDivElement | undefined = $state()
  let down = $state(false)
  let room = $state(600)

  const on = $derived(player.blendOn)
  const opts = $derived(
    blendSettings({
      type: settings.get('audio.blend_type'),
      length: settings.get('audio.blend_length'),
      cut: settings.get('audio.blend_cut'),
      tempo: settings.get('audio.blend_tempo'),
      key: settings.get('audio.blend_key'),
    }),
  )
  const label = $derived(buttonLabel(on, opts.type))

  const a = $derived(player.current)
  const b = $derived(player.upNext[0] ?? null)
  const card = $derived.by(() => {
    const next = player.blend.next
    const refA = a?.ref ?? null
    const refB = b?.ref ?? null
    return cardFor({
      on,
      repeatOne: player.repeat === 'one',
      a: refA,
      b: refB,
      stateA: refA ? blendAnalysis.state(refA) : 'none',
      stateB: refB ? blendAnalysis.state(refB) : 'none',
      failed: !!refA && !!refB && player.blend.failedFor(refA, refB),
      next: next && { from: next.from.ref, to: next.to.ref, plan: next.plan, rank: next.rank, total: next.total },
      anA: refA ? (blendAnalysis.peek(refA) ?? null) : null,
      anB: refB ? (blendAnalysis.peek(refB) ?? null) : null,
      rateA: tempo.rate,
    })
  })

  const STATE_TEXT: Record<string, string> = {
    idle: 'Ничего не играет',
    repeat: 'Повтор трека — сведение не работает',
    last: 'Последний трек — перехода не будет',
    counting: 'Считаю следующий трек…',
    'no-analysis': 'Нет анализа — будет кроссфейд',
    'no-plan': 'Нет подходящего момента — будет кроссфейд',
    waiting: 'Подбираю момент…',
  }

  function place() {
    if (!root) return
    const r = root.getBoundingClientRect()
    const above = r.top - 16
    const below = window.innerHeight - r.bottom - 16
    down = below > above
    room = Math.max(220, down ? below : above)
  }

  function toggle() {
    if (!open) place()
    open = !open
  }

  /** Выключили на вечеринке — вечеринка кончается, очередь остаётся. */
  function setOn(v: boolean) {
    if (!v && party.active) party.end()
    settings.set('audio.blend', v)
  }

  function toTransition() {
    const ms = player.blend.previewAtMs()
    if (ms != null) player.seek(ms)
  }

  onMount(() => {
    const outside = (e: MouseEvent) => {
      if (open && root && !root.contains(e.target as Node)) open = false
    }
    window.addEventListener('mousedown', outside, true)
    return () => window.removeEventListener('mousedown', outside, true)
  })
</script>

<div class="wrap" bind:this={root}>
  <button
    class="blend"
    class:active={on}
    class:open
    title={on ? t('Сведение: {kind}', { kind: t(KIND_TEXT[opts.type].name) }) : t('Сведение')}
    aria-label={t('Сведение')}
    aria-expanded={open}
    onclick={toggle}
  >
    {#key label}
      <span class="face" class:badge={label !== ''}>
        {#if label}{t(label)}{:else}<Icon name="vinyl" size={17} />{/if}
      </span>
    {/key}
  </button>
  {#if blendRatings.ask && blendRatings.answer === null && !open}
    <i class="ask" aria-hidden="true" transition:scale={{ duration: 200, start: 0.4 }}></i>
  {/if}

  {#if open}
    <div class="pop" class:down style:max-height="{room}px" role="dialog" aria-label={t('Сведение')} in:pop={{ y: down ? -8 : 8 }} out:pop={{ y: down ? -8 : 8 }}>
      <Switch
        title={t('Сведение')}
        hint={t('Переход по долям, как у диджея, вместо кроссфейда')}
        {on}
        onchange={setOn}
      />
      <BlendRate />

      <span class="label">{t('Сведение::Вид')}</span>
      <div class="pills kinds" use:indicator={{ key: opts.type, kind: 'pill' }}>
        {#each BLEND_TYPES as k (k)}
          <button class:on={opts.type === k} onclick={() => settings.set('audio.blend_type', k)}>{t(KIND_TEXT[k].name)}</button>
        {/each}
      </div>
      {#key opts.type}<p class="about">{t(KIND_TEXT[opts.type].about)}</p>{/key}

      <span class="label">{t('Длина')}</span>
      <div class="pills lengths" use:indicator={{ key: opts.lengthSec, kind: 'pill' }}>
        {#each BLEND_LENGTHS as l (l)}
          <button class:on={opts.lengthSec === l} onclick={() => settings.set('audio.blend_length', l)}>{t(LENGTH_TEXT[l])}</button>
        {/each}
      </div>

      <div class="cut">
        <span class="label">{t('Можно срезать')}</span>
        <Ruler
          value={opts.cutSec}
          min={0}
          max={CUT_MAX_SEC}
          step={1}
          reset={CUT_RECOMMENDED_SEC}
          major={5}
          px={6}
          onchange={(v) => settings.set('audio.blend_cut', Math.round(v))}
        />
        <div class="cut-line">
          {#key opts.cutSec}<span class="val">{t('{n} с', { n: opts.cutSec })}</span>{/key}
          <small class:rec={opts.cutSec === CUT_RECOMMENDED_SEC}>{t('{n} с — рекомендуется', { n: CUT_RECOMMENDED_SEC })}</small>
        </div>
      </div>

      <Switch
        title={t('Подгонять тональность')}
        hint={t('Сдвигает тон следующего трека на время перехода, если тональности не дружат')}
        on={opts.keyShift}
        onchange={(v) => settings.set('audio.blend_key', v)}
      />

      {#if on}
        <div class="next" transition:slide={{ duration: 260 }}>
          <span class="label">{t('Следующий переход')}</span>
          {#key card.state === 'plan' ? `${card.kind}:${card.outMs}:${card.inMs}` : card.state}
            <div class="card">
              {#if card.state === 'plan'}
                <b>
                  {t(KIND_TEXT[card.kind].name)} · {card.sync ? t('бит в бит') : t('без бита')} · {t('{n} с', { n: card.sec })} ·
                  {t('момент {rank} из {total}', { rank: card.rank, total: card.total })}
                </b>
                <span>
                  {t('выход из «{a}» на {at}, вход в «{b}» с {from}', {
                    a: a?.title ?? '',
                    at: formatTime(card.outMs),
                    b: b?.title ?? '',
                    from: formatTime(card.inMs),
                  })}
                </span>
                <span>{t('темп {a} → {b} · тон {ka} → {kb}', { a: card.tempoA, b: card.tempoB, ka: card.keyA, kb: card.keyB })}</span>
              {:else}
                <span>{t(STATE_TEXT[card.state])}</span>
              {/if}
            </div>
          {/key}
          <div class="acts">
            <button class="act press" disabled={card.state !== 'plan' || card.total < 2} onclick={() => player.blend.another()}>
              <Icon name="refresh" size={15} />{t('Другой момент')}
            </button>
            <button class="act press" disabled={card.state !== 'plan'} onclick={toTransition}>
              <Icon name="next" size={15} />{t('К переходу')}
            </button>
          </div>
        </div>
      {/if}
    </div>
  {/if}
</div>

<style>
  .wrap {
    position: relative;
  }
  /* висит «Как прошлый переход?» — точка, пока не открыли */
  .ask {
    position: absolute;
    top: 2px;
    right: 2px;
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--accent);
    box-shadow: 0 0 0 2px var(--surface-1);
    pointer-events: none;
  }
  .blend {
    display: grid;
    place-items: center;
    min-width: 32px;
    height: 32px;
    padding: 0 6px;
    border-radius: 10px;
    color: var(--text-2);
    transition:
      color var(--normal) var(--ease),
      background var(--normal) var(--ease),
      box-shadow var(--normal) var(--ease);
  }
  .blend:hover,
  .blend.open {
    color: var(--text);
  }
  .blend.active {
    color: var(--text);
    background: color-mix(in srgb, var(--text) 14%, transparent);
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--text) 10%, transparent);
  }
  .face {
    display: inline-flex;
    animation: fade 180ms var(--ease);
  }
  .face.badge {
    font-size: calc(12px * var(--fs, 1));
    font-weight: 700;
  }
  @keyframes fade {
    from {
      opacity: 0;
      scale: 0.8;
    }
  }
  .pop {
    position: absolute;
    right: -8px;
    bottom: calc(100% + 10px);
    z-index: 20;
    width: 340px;
    padding: 6px 14px 12px;
    border-radius: 20px;
    background: color-mix(in srgb, var(--surface-1) 92%, var(--tint));
    border: 1px solid var(--border-strong);
    box-shadow: 0 22px 50px -12px rgba(0, 0, 0, 0.7);
    transform-origin: bottom right;
    overflow-y: auto;
    scrollbar-width: thin;
  }
  .pop.down {
    top: calc(100% + 10px);
    bottom: auto;
    transform-origin: top right;
  }
  .label {
    display: block;
    margin: 12px 0 6px;
    font-size: calc(14px * var(--fs, 1));
    font-weight: 700;
  }
  .pills {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 4px;
  }
  .pills :global(.tab-ind.pill) {
    border-radius: 9px;
    background: var(--text);
  }
  .pills button {
    height: 30px;
    border-radius: 9px;
    background: var(--plate);
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
    transition: color var(--normal) var(--ease);
  }
  .pills button:hover {
    color: var(--text);
  }
  .pills button.on {
    background: transparent;
    color: var(--on-text);
  }
  .about {
    margin: 6px 2px 0;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-2);
    animation: fade 180ms var(--ease);
  }
  .cut-line {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    margin-top: 6px;
  }
  .val {
    min-width: 64px;
    padding: 5px 12px;
    border-radius: 9px;
    background: var(--plate);
    text-align: center;
    font-size: calc(13px * var(--fs, 1));
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    animation: fade 160ms var(--ease);
  }
  .cut-line small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-2);
    transition: color var(--normal) var(--ease);
  }
  .cut-line small.rec {
    color: var(--accent);
  }
  .card {
    display: grid;
    gap: 3px;
    padding: 10px 12px;
    border-radius: 12px;
    background: var(--plate);
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-2);
    font-variant-numeric: tabular-nums;
    animation: fade 200ms var(--ease);
  }
  .card b {
    color: var(--text);
    font-size: calc(13px * var(--fs, 1));
  }
  .card span {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .acts {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 6px;
    margin-top: 8px;
  }
  .act {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    height: 32px;
    border-radius: 10px;
    background: var(--plate);
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text);
    transition:
      background var(--fast) var(--ease),
      opacity var(--normal) var(--ease);
  }
  .act:hover:not(:disabled) {
    background: var(--hover);
  }
  .act:disabled {
    opacity: 0.4;
    cursor: default;
  }
  @media (prefers-reduced-motion: reduce) {
    .face,
    .about,
    .val,
    .card {
      animation: none;
    }
  }
</style>
