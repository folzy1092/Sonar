<script lang="ts">
  // Плеер → Аудио → «Резервный сервис» (NEXT_PROMPT этап 4): включатель и порядок, в котором Sonar
  // ищет тот же трек в других сервисах. Список — из реестра (lib/fallback.ts), порядок меняется
  // перетаскиванием; пишется в `audio.fallback_order`, его же читает Rust (services/fallback.rs).
  import Group from './Group.svelte'
  import Switch from './Switch.svelte'
  import Icon from '../Icon.svelte'
  import SourceIcon from '../SourceIcon.svelte'
  import { cascade } from '../../lib/cascade'
  import { glide } from '../../lib/motion'
  import { fallbackOrder, moveItem } from '../../lib/fallback'
  import { byId, type ServiceId } from '../../lib/services'
  import { settings } from '../../lib/settings.svelte'
  import { t } from '../../lib/i18n.svelte'

  const enabled = $derived(settings.get('audio.fallback'))
  const order = $derived(fallbackOrder(settings.get('audio.fallback_order')))

  // Перетаскивание — на pointer-событиях: HTML5 drag-n-drop в WebView2 под Tauri не работает
  // (окно перехватывает перетаскивание файлов). Строка едет за курсором, остальные расступаются,
  // порядок сохраняется при отпускании.
  let live = $state<ServiceId[] | null>(null)
  let dragId = $state<ServiceId | null>(null)
  let shift = $state(0)
  let slots: { top: number; h: number }[] = []
  let grab = 0
  let listEl: HTMLDivElement | undefined = $state()

  const shown = $derived(live ?? order)

  function start(e: PointerEvent, id: ServiceId) {
    if (!enabled || e.button !== 0 || !listEl) return
    const rows = [...listEl.querySelectorAll<HTMLElement>('.row')]
    slots = rows.map((r) => {
      const b = r.getBoundingClientRect()
      return { top: b.top, h: b.height }
    })
    const i = order.indexOf(id)
    grab = e.clientY - slots[i].top
    live = [...order]
    dragId = id
    shift = 0
    ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
    e.preventDefault()
  }

  function move(e: PointerEvent) {
    if (!dragId || !live) return
    const top = e.clientY - grab
    const centre = top + slots[0].h / 2
    let to = 0
    for (let k = 0; k < slots.length; k++) if (centre > slots[k].top + slots[k].h / 2) to = k
    // за край списка не уезжаем дальше половины строки
    to = Math.max(0, Math.min(slots.length - 1, to))
    const cur = live.indexOf(dragId)
    if (to !== cur) live = moveItem(live, cur, to)
    const min = slots[0].top - slots[0].h / 2
    const max = slots[slots.length - 1].top + slots[slots.length - 1].h / 2
    shift = Math.max(min, Math.min(max, top)) - slots[live.indexOf(dragId)].top
  }

  function end() {
    if (!dragId || !live) return
    const next = live
    const changed = next.some((id, i) => id !== order[i])
    dragId = null
    shift = 0
    live = null
    if (changed) settings.set('audio.fallback_order', next)
  }

  /** С клавиатуры: Alt+↑ / Alt+↓ двигают сервис. */
  function key(e: KeyboardEvent, i: number) {
    if (!enabled || !e.altKey || (e.key !== 'ArrowUp' && e.key !== 'ArrowDown')) return
    const to = e.key === 'ArrowUp' ? i - 1 : i + 1
    if (to < 0 || to >= order.length) return
    e.preventDefault()
    settings.set('audio.fallback_order', moveItem(order, i, to))
    const target = e.currentTarget as HTMLElement
    requestAnimationFrame(() => (listEl?.querySelectorAll<HTMLElement>('.row')[to] ?? target).focus())
  }
</script>

<Group title={t('Резервный сервис')} hint={t('Трек не играет в своём сервисе — тот же трек из другого')}>
  <Switch
    title={t('Резервный сервис')}
    hint={t('Трек недоступен, есть только отрывок или нужна подписка — Sonar найдёт его в другом сервисе (исполнитель, название и длительность совпадают) и скажет, откуда играет.')}
    on={enabled}
    onchange={(v) => settings.set('audio.fallback', v)}
  />
  <div class="order" class:off={!enabled}>
    <p class="hint">{t('Где искать трек сначала — перетащи сервисы. Яндекс Музыка и VK Музыка ищутся, только если подключены.')}</p>
    <div class="list" role="listbox" aria-label={t('Порядок резервных сервисов')} bind:this={listEl} use:cascade={'fallback'}>
      {#each shown as id, i (id)}
        {@const info = byId(id)}
        <div
          class="row"
          class:dragging={dragId === id}
          style:transform={dragId === id ? `translateY(${shift}px) scale(1.02)` : null}
          role="option"
          aria-selected={dragId === id}
          tabindex={enabled ? 0 : -1}
          aria-keyshortcuts="Alt+ArrowUp Alt+ArrowDown"
          animate:glide={{ duration: dragId === id ? 0 : 220 }}
          onpointerdown={(e) => start(e, id)}
          onpointermove={move}
          onpointerup={end}
          onpointercancel={end}
          onlostpointercapture={end}
          onkeydown={(e) => key(e, i)}
        >
          <span class="n">{i + 1}</span>
          <SourceIcon service={id} size={18} />
          <span class="name">{info ? t(info.name) : id}</span>
          <span class="grip" title={t('Можно перетащить')}><Icon name="sort" size={15} /></span>
        </div>
      {/each}
    </div>
  </div>
</Group>

<style>
  .order {
    transition: opacity var(--fast) var(--ease);
  }
  .order.off {
    opacity: 0.45;
    pointer-events: none;
  }
  .hint {
    margin: 8px 0 8px;
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.45;
    color: var(--text-3);
  }
  .list {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 40px;
    padding: 0 10px 0 12px;
    border-radius: var(--radius-m);
    background: var(--plate);
    border: 1px solid var(--card-line);
    cursor: grab;
    user-select: none;
    touch-action: none;
    transition:
      background var(--fast) var(--ease),
      border-color var(--fast) var(--ease),
      opacity var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .row:hover {
    background: var(--hover);
  }
  .row:active {
    cursor: grabbing;
    transform: scale(0.99);
  }
  .row.dragging {
    position: relative;
    z-index: 2;
    cursor: grabbing;
    background: var(--hover);
    border-color: color-mix(in srgb, var(--accent) 45%, var(--card-line));
    box-shadow: 0 8px 24px rgb(0 0 0 / 0.35);
    transition:
      background var(--fast) var(--ease),
      border-color var(--fast) var(--ease),
      box-shadow var(--fast) var(--ease);
  }
  .row:focus-visible {
    outline: 2px solid var(--accent);
    outline-offset: 2px;
  }
  .n {
    width: 14px;
    font-size: calc(12px * var(--fs, 1));
    font-variant-numeric: tabular-nums;
    color: var(--text-3);
  }
  .name {
    flex: 1;
    min-width: 0;
    font-size: calc(13px * var(--fs, 1));
    color: var(--text);
  }
  .grip {
    display: grid;
    place-items: center;
    color: var(--text-3);
  }
  @media (prefers-reduced-motion: reduce) {
    .row:active {
      transform: none;
    }
  }
</style>
