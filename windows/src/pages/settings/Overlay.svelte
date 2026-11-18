<script lang="ts">
  // Интерфейс → Оверлей (SETTINGS_NEXT «Оверлей», решение владельца 2026-11-18): плашка поверх других
  // программ и игр (mini.rs, окно `overlay`). Режим — живые превью, место — макет экрана с сеткой 3×3:
  // плашку можно перетащить, отпустили — прилипает к ближайшей клетке. Размер и прозрачность — ползунки,
  // макет меняется прямо под пальцем. Открыть — горячей клавишей, кнопкой или само, когда Sonar свёрнут.
  import Card from '../../components/settings/Card.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import PreviewTiles from '../../components/settings/PreviewTiles.svelte'
  import Slider from '../../components/settings/Slider.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Icon from '../../components/Icon.svelte'
  import { settings, type OverlayAnchor, type OverlayMode } from '../../lib/settings.svelte'
  import { OVERLAY_ANCHORS, OVERLAY_LIMITS, anchorAlign, nearestAnchor, overlayLayout } from '../../lib/overlay'
  import { comboLabel } from '../../lib/hotkeys-core'
  import { mini } from '../../lib/mini.svelte'
  import { player } from '../../player/player.svelte'
  import { isTauri } from '../../lib/tauri'
  import { t } from '../../lib/i18n.svelte'

  /** Ширина экрана, которую изображает макет, — логические пиксели обычного монитора. */
  const SCREEN_W = 1920

  type Num = 'opacity' | 'scale' | 'width' | 'height'
  // пока тянут ползунок — макет показывает значение под пальцем, отпустили — сохраняем
  let live = $state<Partial<Record<Num, number>>>({})
  const num = (k: Num) => live[k] ?? settings.get(`overlay.${k}`)

  const mode = $derived(settings.get('overlay.mode'))
  const shape = $derived(settings.get('overlay.shape'))
  const anchor = $derived(settings.get('overlay.position'))
  const cover = $derived(player.current?.cover_url ?? null)
  const off = $derived(mode === 'off')
  const layout = $derived(overlayLayout(mode === 'off' ? 'card' : mode, num('width'), num('height'), num('scale'), anchor))
  const combo = $derived(settings.get('hotkeys.map').overlay ?? '')

  // перетаскивание плашки по макету: доли 0…1 под курсором, пока тянут
  let screen = $state<HTMLDivElement>()
  let drag = $state<{ x: number; y: number } | null>(null)
  const align = $derived(drag ?? anchorAlign(anchor))

  function point(e: PointerEvent) {
    const r = screen!.getBoundingClientRect()
    const clamp = (v: number) => Math.min(1, Math.max(0, v))
    return { x: clamp((e.clientX - r.left) / r.width), y: clamp((e.clientY - r.top) / r.height) }
  }
  function grab(e: PointerEvent) {
    if (off || mode === 'fullscreen') return
    ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
    drag = point(e)
  }
  function move(e: PointerEvent) {
    if (drag) drag = point(e)
  }
  function drop() {
    if (!drag) return
    settings.set('overlay.position', nearestAnchor(drag.x, drag.y))
    drag = null
  }
  const setAnchor = (a: OverlayAnchor) => settings.set('overlay.position', a)

  /** Название клетки для экранного диктора: «Сверху слева»… */
  function cellName(a: OverlayAnchor) {
    const row = { t: t('Сверху'), m: t('Посередине'), b: t('Снизу') }[a[0] as 't' | 'm' | 'b']
    const col = { l: t('слева'), c: t('по центру'), r: t('справа') }[a[1] as 'l' | 'c' | 'r']
    return `${row} ${col}`
  }
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

<div class="dimmable" class:off>
  <Card title={t('Положение на экране')} hint={mode === 'fullscreen' ? t('Полноэкранный оверлей занимает весь экран — место не нужно') : t('Перетащи плашку или нажми точку — она встанет в ближайшую клетку')}>
    <div
      class="screen"
      class:full={mode === 'fullscreen'}
      bind:this={screen}
      style:--o={num('opacity') / 100}
    >
      {#each OVERLAY_ANCHORS as a (a)}
        {@const p = anchorAlign(a)}
        <button
          class="cell"
          class:on={a === anchor && !drag}
          style:--x={p.x}
          style:--y={p.y}
          aria-label={cellName(a)}
          disabled={mode === 'fullscreen'}
          onclick={() => setAnchor(a)}
        ></button>
      {/each}
      {#if mode === 'fullscreen'}
        <span class="big" class:sq={shape === 'square'} style:zoom={num('scale') / 100}><i class="art" style:--art={cover ? `url("${cover}")` : null}></i><i class="ln"></i><i class="ln short"></i></span>
      {:else}
        <span
          class="drag"
          class:dragging={!!drag}
          role="slider"
          tabindex="-1"
          aria-label={t('Положение на экране')}
          aria-valuetext={cellName(anchor)}
          aria-valuenow={OVERLAY_ANCHORS.indexOf(anchor)}
          style:--x={align.x}
          style:--y={align.y}
          style:--w={layout.width / SCREEN_W}
          style:--h={layout.height / SCREEN_W}
          onpointerdown={grab}
          onpointermove={move}
          onpointerup={drop}
          onpointercancel={drop}
        >
          {@render plaque(mode, shape === 'rounded')}
        </span>
      {/if}
    </div>
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

  /* ——— макет экрана с сеткой 3×3 ——— */
  .screen {
    --pad: 4%;
    position: relative;
    width: 100%;
    max-width: 560px;
    margin: 4px auto 12px;
    aspect-ratio: 16 / 9;
    border-radius: 10px;
    border: 1px solid var(--border-strong);
    background:
      radial-gradient(circle at 30% 20%, color-mix(in srgb, var(--accent) 22%, transparent), transparent 60%),
      linear-gradient(135deg, var(--surface-3), var(--surface-2));
    overflow: hidden;
    touch-action: none;
  }
  .screen.full {
    display: grid;
    place-items: center;
    background: linear-gradient(135deg, color-mix(in srgb, var(--surface-3) calc(100% - var(--o) * 60%), #000), color-mix(in srgb, var(--surface-2) calc(100% - var(--o) * 60%), #000));
  }
  .screen.full .big {
    width: 26%;
    animation: pop 0.35s var(--ease);
  }
  @keyframes pop {
    from {
      opacity: 0;
      scale: 0.9;
    }
  }
  .cell {
    position: absolute;
    left: calc(var(--pad) + (100% - 2 * var(--pad)) * var(--x));
    top: calc(var(--pad) + (100% - 2 * var(--pad)) * var(--y));
    width: 10px;
    height: 10px;
    margin: -5px 0 0 -5px;
    border-radius: 50%;
    background: var(--text-3);
    opacity: 0.45;
    transition:
      opacity 0.2s var(--ease),
      scale 0.25s var(--ease),
      background 0.2s var(--ease);
  }
  .cell:hover:not(:disabled) {
    opacity: 1;
    scale: 1.4;
  }
  /* выбранную клетку и так видно по плашке — точка под ней гаснет */
  .cell.on {
    opacity: 0;
  }
  .screen.full .cell {
    opacity: 0;
  }
  /* плашка: ширина и высота — доли экрана (высота тоже от ширины — так сохраняются пропорции окна) */
  .drag {
    --pw: calc(var(--w) * 100%);
    position: absolute;
    width: var(--pw);
    aspect-ratio: calc(var(--w) / var(--h));
    left: calc(var(--pad) + (100% - 2 * var(--pad) - var(--pw)) * var(--x));
    top: calc(var(--pad) + (100% - 2 * var(--pad)) * var(--y));
    translate: 0 calc(var(--y) * -100%);
    cursor: grab;
    transition:
      left 0.4s var(--ease),
      top 0.4s var(--ease),
      translate 0.4s var(--ease),
      width 0.25s var(--ease),
      aspect-ratio 0.25s var(--ease);
  }
  .drag.dragging {
    cursor: grabbing;
    transition:
      width 0.25s var(--ease),
      aspect-ratio 0.25s var(--ease);
  }
  .drag.dragging .pl {
    box-shadow: 0 8px 24px rgb(0 0 0 / 0.4);
    scale: 1.04;
  }
  .drag .pl {
    --o: inherit;
    padding: 0 4%;
    transition:
      scale 0.2s var(--ease),
      box-shadow 0.2s var(--ease),
      border-radius 0.3s var(--ease),
      background 0.3s var(--ease);
  }
  .drag .pl.island {
    width: 100%;
  }

  /* ——— строки «Как открыть» ——— */
  .row {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 11px 0;
  }
  .txt {
    display: flex;
    flex: 1;
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
  @media (prefers-reduced-motion: reduce) {
    .drag,
    .cell,
    .screen.full .big {
      transition: opacity 0.2s;
      animation: none;
    }
  }
</style>
