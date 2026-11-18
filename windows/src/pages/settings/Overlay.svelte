<script lang="ts">
  // Интерфейс → Оверлей (SETTINGS_NEXT «Оверлей», решение владельца 2026-11-18): плашка поверх других
  // программ и игр (mini.rs, окно `overlay`). Режим — живые превью, место — схема всех мониторов, как они
  // стоят в Windows (MonitorScheme, lib/monitor-layout.ts): выбрал монитор, нажал точку или утащил плашку —
  // она прилипает к ближайшей клетке. Размер и прозрачность — ползунки, схема меняется прямо под пальцем.
  // Открыть — горячей клавишей, кнопкой или само, когда Sonar свёрнут.
  import { invoke } from '@tauri-apps/api/core'
  import Card from '../../components/settings/Card.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import MonitorScheme from '../../components/settings/MonitorScheme.svelte'
  import PreviewTiles from '../../components/settings/PreviewTiles.svelte'
  import Slider from '../../components/settings/Slider.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Icon from '../../components/Icon.svelte'
  import { settings, type OverlayAnchor, type OverlayMode } from '../../lib/settings.svelte'
  import { OVERLAY_LIMITS, overlayLayout } from '../../lib/overlay'
  import { BROWSER_MONITOR, monitorChoice, pickMonitor, type MonitorInfo } from '../../lib/monitor-layout'
  import { comboLabel } from '../../lib/hotkeys-core'
  import { mini } from '../../lib/mini.svelte'
  import { player } from '../../player/player.svelte'
  import { isTauri } from '../../lib/tauri'
  import { t } from '../../lib/i18n.svelte'
  import { pop } from '../../lib/motion'

  /** Как часто переспрашиваем мониторы, пока страница открыта: подключили или сняли — схема обновится. */
  const MONITORS_POLL_MS = 2500

  type Num = 'opacity' | 'scale' | 'width' | 'height'
  // пока тянут ползунок — схема показывает значение под пальцем, отпустили — сохраняем
  let live = $state<Partial<Record<Num, number>>>({})
  const num = (k: Num) => live[k] ?? settings.get(`overlay.${k}`)

  const mode = $derived(settings.get('overlay.mode'))
  const shape = $derived(settings.get('overlay.shape'))
  const anchor = $derived(settings.get('overlay.position'))
  const cover = $derived(player.current?.cover_url ?? null)
  const off = $derived(mode === 'off')
  const layout = $derived(overlayLayout(mode === 'off' ? 'card' : mode, num('width'), num('height'), num('scale'), anchor))
  const combo = $derived(settings.get('hotkeys.map').overlay ?? '')

  // мониторы: в приложении — из Rust (list_monitors), в браузере — один обычный 1920×1080
  let monitors = $state<MonitorInfo[]>(isTauri ? [] : [BROWSER_MONITOR])
  let monitorsFailed = $state(false)
  const shown = $derived(monitors.length ? monitors : monitorsFailed ? [BROWSER_MONITOR] : [])
  const picked = $derived(pickMonitor(shown, settings.get('overlay.monitor')))

  async function loadMonitors() {
    try {
      const list = await invoke<MonitorInfo[]>('list_monitors')
      monitorsFailed = false
      if (JSON.stringify(list) !== JSON.stringify(monitors)) monitors = list
    } catch (e) {
      // схема остаётся прежней; пусто — рисуем обычный экран и честно говорим об этом
      console.warn('оверлей: мониторы не получены', e)
      monitorsFailed = true
    }
  }

  $effect(() => {
    if (!isTauri) return
    void loadMonitors()
    const timer = setInterval(() => void loadMonitors(), MONITORS_POLL_MS)
    const onFocus = () => void loadMonitors()
    window.addEventListener('focus', onFocus)
    return () => {
      clearInterval(timer)
      window.removeEventListener('focus', onFocus)
    }
  })

  /** Выбрали монитор и клетку. Монитор пишем, только если его сменили: двигая плашку по основному,
   *  пока выбранный отключён, сохранённый выбор не теряем. */
  function place(m: MonitorInfo, a: OverlayAnchor) {
    if (m.id !== picked.monitor?.id) settings.set('overlay.monitor', monitorChoice(m))
    if (a !== anchor) settings.set('overlay.position', a)
  }

  /** Название клетки для экранного диктора: «Сверху слева»… */
  function cellName(a: OverlayAnchor) {
    const row = { t: t('Сверху'), m: t('Посередине'), b: t('Снизу') }[a[0] as 't' | 'm' | 'b']
    const col = { l: t('слева'), c: t('по центру'), r: t('справа') }[a[1] as 'l' | 'c' | 'r']
    return `${row} ${col}`
  }

  const positionHint = $derived(
    mode === 'fullscreen'
      ? t('Полноэкранный оверлей занимает весь монитор — нажми другой, чтобы перенести')
      : shown.length > 1
        ? t('Нажми монитор и точку — или перетащи плашку, хоть на другой монитор')
        : t('Перетащи плашку или нажми точку — она встанет в ближайшую клетку'),
  )
</script>

{#snippet plaque(m: OverlayMode, round: boolean)}
  {#if m === 'island'}
    <span class="pl island" class:sq={!round}><i class="art" style:--art={cover ? `url("${cover}")` : null}></i><i class="ln"></i><i class="dot"></i></span>
  {:else}
    <span class="pl card" class:sq={!round}><i class="art" style:--art={cover ? `url("${cover}")` : null}></i><span class="tx"><i class="ln"></i><i class="ln short"></i></span><i class="dot"></i></span>
  {/if}
{/snippet}

{#snippet modeTile(id: OverlayMode)}
  <span class="scr" class:dim={id === 'fullscreen'}>
    {#if id === 'off'}
      <span class="none"><Icon name="x" size={16} /></span>
    {:else if id === 'fullscreen'}
      <span class="big" class:sq={shape === 'square'}><i class="art" style:--art={cover ? `url("${cover}")` : null}></i><i class="ln"></i><i class="ln short"></i></span>
    {:else}
      <span class="top">{@render plaque(id, shape === 'rounded')}</span>
    {/if}
  </span>
{/snippet}

<Card>
  <PreviewTiles
    title={t('Режим')}
    hint={t('Как выглядит плашка поверх игр и других программ')}
    value={mode}
    options={[
      { id: 'off' as const, label: t('Отключен') },
      { id: 'fullscreen' as const, label: t('Полноэкранный') },
      { id: 'island' as const, label: t('Остров') },
      { id: 'card' as const, label: t('Карточка') },
    ]}
    tile={modeTile}
    onchange={(v) => settings.set('overlay.mode', v)}
  />
  <div class="dimmable" class:off>
    <Switch
      title={t('Появляться само')}
      hint={t('Свернул Sonar или спрятал в трей — оверлей показывается, вернул окно — прячется')}
      on={settings.get('overlay.auto')}
      onchange={(v) => settings.set('overlay.auto', v)}
    />
  </div>
</Card>

{#snippet schemePlaque()}
  <span class="fit">{@render plaque(mode === 'island' ? 'island' : 'card', shape === 'rounded')}</span>
{/snippet}

{#snippet schemeBig()}
  <span class="big fullcard" class:sq={shape === 'square'} style:--z={num('scale') / 100}><i class="art" style:--art={cover ? `url("${cover}")` : null}></i><i class="ln"></i><i class="ln short"></i></span>
{/snippet}

<div class="dimmable" class:off>
  <Card title={t('Положение на экране')} hint={positionHint}>
    {#if shown.length && picked.monitor}
      <MonitorScheme
        monitors={shown}
        selectedId={picked.monitor.id}
        {anchor}
        {layout}
        fullscreen={mode === 'fullscreen'}
        opacity={num('opacity') / 100}
        plaque={schemePlaque}
        big={schemeBig}
        {cellName}
        onplace={place}
      />
    {:else}
      <div class="loading" aria-busy="true"></div>
    {/if}
    {#if monitorsFailed}
      <p class="note" in:pop={{ y: 4 }}>
        <Icon name="monitor" size={14} />
        <span>{t('Не удалось узнать мониторы — показан обычный экран')}</span>
      </p>
    {:else if picked.missing}
      <p class="note" in:pop={{ y: 4 }}>
        <Icon name="monitor" size={14} />
        <span>{t('Выбранный монитор отключён — оверлей пока на основном. Подключишь — вернётся сам')}</span>
      </p>
    {/if}
  </Card>

  <Card title={t('Вид')}>
    <Choice
      title={t('Форма')}
      hint={t('Углы плашки')}
      value={shape}
      options={[
        { id: 'square', label: t('Квадратная') },
        { id: 'rounded', label: t('Скруглённая') },
      ]}
      onchange={(v) => settings.set('overlay.shape', v)}
    />
  </Card>

  <Card title={t('Размер и прозрачность')}>
    <Slider
      title={t('Непрозрачность')}
      value={num('opacity')}
      {...OVERLAY_LIMITS.opacity}
      unit="%"
      oninput={(v) => (live = { ...live, opacity: v })}
      onchange={(v) => {
        settings.set('overlay.opacity', v)
        live = { ...live, opacity: undefined }
      }}
    />
    <Slider
      title={t('Масштаб')}
      value={num('scale')}
      {...OVERLAY_LIMITS.scale}
      unit="%"
      oninput={(v) => (live = { ...live, scale: v })}
      onchange={(v) => {
        settings.set('overlay.scale', v)
        live = { ...live, scale: undefined }
      }}
    />
    <Slider
      title={t('Ширина')}
      hint={mode === 'island' ? t('Остров чуть уже карточки') : undefined}
      value={num('width')}
      {...OVERLAY_LIMITS.width}
      unit="px"
      oninput={(v) => (live = { ...live, width: v })}
      onchange={(v) => {
        settings.set('overlay.width', v)
        live = { ...live, width: undefined }
      }}
    />
    <Slider
      title={t('Высота')}
      value={num('height')}
      {...OVERLAY_LIMITS.height}
      unit="px"
      oninput={(v) => (live = { ...live, height: v })}
      onchange={(v) => {
        settings.set('overlay.height', v)
        live = { ...live, height: undefined }
      }}
    />
  </Card>

  <Card title={t('Как открыть')}>
    <div class="row">
      <span class="txt">
        <b>{t('Горячая клавиша')}</b>
        <small>{t('Меняется в «Клавиши». Поверх игр в окне без рамки видно, поверх эксклюзивного полного экрана — нет')}</small>
      </span>
      {#if combo}
        <span class="keys">{#each comboLabel(combo) as k, i (i)}<kbd>{k}</kbd>{/each}</span>
      {:else}
        <small class="nokey">{t('Не назначена')}</small>
      {/if}
    </div>
    <div class="row">
      <span class="txt">
        <b>{t('Показать сейчас')}</b>
        <small>{isTauri ? t('Открыть или закрыть оверлей, не сворачивая Sonar') : t('Работает в приложении Sonar')}</small>
      </span>
      <button class="show" class:on={mini.overlayOpen} disabled={!isTauri} onclick={() => mini.overlay()}>
        {mini.overlayOpen ? t('Закрыть') : t('Показать')}
      </button>
    </div>
  </Card>
</div>

<style>
  .dimmable {
    transition: opacity 0.3s var(--ease);
  }
  .dimmable.off {
    opacity: 0.4;
    pointer-events: none;
  }

  /* ——— рисунки: экран, плашки ——— */
  .scr {
    position: relative;
    display: grid;
    width: 100%;
    height: 100%;
    background: linear-gradient(135deg, var(--surface-3), var(--surface-2));
    overflow: hidden;
  }
  .scr.dim {
    background: linear-gradient(135deg, color-mix(in srgb, var(--surface-3) 50%, #000), color-mix(in srgb, var(--surface-2) 50%, #000));
    place-items: center;
  }
  .none {
    place-self: center;
    color: var(--text-3);
  }
  .top {
    position: absolute;
    top: 14%;
    left: 22%;
    width: 56%;
    height: 30%;
  }
  .pl {
    display: flex;
    align-items: center;
    gap: 6%;
    width: 100%;
    height: 100%;
    padding: 0 5%;
    border-radius: 6px;
    background: color-mix(in srgb, var(--surface-1) calc(var(--o, 0.9) * 100%), transparent);
    box-shadow: 0 2px 10px rgb(0 0 0 / 0.25);
    transition:
      border-radius 0.3s var(--ease),
      background 0.3s var(--ease);
  }
  .pl.island {
    width: 72%;
    margin: 0 auto;
    border-radius: 999px;
    background: color-mix(in srgb, #000 calc(var(--o, 0.9) * 100%), transparent);
  }
  .pl.sq {
    border-radius: 2px;
  }
  .art {
    flex: none;
    height: 72%;
    aspect-ratio: 1;
    border-radius: 3px;
    background: var(--art, var(--accent)) center / cover;
  }
  .island .art {
    border-radius: 50%;
  }
  .tx {
    display: grid;
    flex: 1;
    gap: 3px;
  }
  .ln {
    display: block;
    height: 3px;
    border-radius: 2px;
    background: var(--text-2);
  }
  .island .ln {
    flex: 1;
    background: rgb(255 255 255 / 0.8);
  }
  .ln.short {
    width: 55%;
    background: var(--text-3);
  }
  .dot {
    flex: none;
    width: 14%;
    max-width: 10px;
    aspect-ratio: 1;
    border-radius: 50%;
    background: var(--accent);
  }
  .big {
    display: grid;
    justify-items: center;
    gap: 4px;
    width: 22%;
    padding: 6% 4%;
    border-radius: 6px;
    background: var(--surface-1);
    box-shadow: 0 4px 16px rgb(0 0 0 / 0.4);
  }
  .big.sq {
    border-radius: 2px;
  }
  .big .art {
    width: 60%;
    height: auto;
  }
  .big .ln {
    width: 80%;
  }
  .big .ln.short {
    width: 50%;
  }

  /* ——— плашка и карточка на схеме мониторов (MonitorScheme) ——— */
  .fit {
    display: block;
    width: 100%;
    height: 100%;
  }
  .fit .pl {
    padding: 0 4%;
    gap: 5%;
  }
  .fit .pl.island {
    width: 100%;
  }
  .fullcard {
    width: clamp(36px, calc(26% * var(--z, 1)), 80%);
    gap: 3px;
    padding: 7% 4%;
    animation: pop 0.35s var(--ease);
  }
  @keyframes pop {
    from {
      opacity: 0;
      scale: 0.9;
    }
  }
  .loading {
    height: 150px;
    margin: 6px auto 14px;
    max-width: 420px;
    border-radius: 8px;
    background: linear-gradient(90deg, var(--surface-2), var(--surface-3), var(--surface-2)) 0 0 / 200% 100%;
    animation: shimmer 1.4s linear infinite;
  }
  @keyframes shimmer {
    to {
      background-position: -200% 0;
    }
  }
  .note {
    display: flex;
    align-items: flex-start;
    gap: 8px;
    margin: 0 0 12px;
    padding: 9px 12px;
    border-radius: 10px;
    background: color-mix(in srgb, var(--accent) 12%, transparent);
    color: var(--text-2);
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.45;
  }
  .note :global(svg) {
    flex: none;
    margin-top: 1px;
    color: var(--accent);
  }

  /* ——— строки «Как открыть» ——— */
  .row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 10px 14px;
    padding: 11px 0;
  }
  .txt {
    display: flex;
    flex: 1 1 220px;
    flex-direction: column;
    gap: 3px;
    min-width: 0;
  }
  .txt b {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  .txt small,
  .nokey {
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.45;
    color: var(--text-3);
  }
  .keys {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
  }
  kbd {
    min-width: 26px;
    padding: 4px 7px;
    border-radius: 7px;
    border: 1px solid var(--border-strong);
    background: var(--surface-3);
    font: inherit;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    text-align: center;
  }
  .show {
    flex: none;
    min-width: 96px;
    padding: 8px 16px;
    border-radius: 999px;
    background: var(--accent);
    color: var(--on-accent, #fff);
    font-weight: 600;
    font-size: calc(13px * var(--fs, 1));
    transition:
      background 0.25s var(--ease),
      scale 0.15s var(--ease),
      opacity 0.2s var(--ease);
  }
  .show:active:not(:disabled) {
    scale: 0.95;
  }
  .show.on {
    background: var(--surface-3);
    color: var(--text);
  }
  .show:disabled {
    opacity: 0.5;
  }
  /* узкое окно: кнопка и клавиши уходят под подпись во всю ширину, без прокрутки вбок */
  @container (max-width: 520px) {
    .row > :not(.txt) {
      flex-basis: 100%;
    }
    .show {
      width: 100%;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .fullcard,
    .loading {
      animation: none;
    }
  }
</style>
