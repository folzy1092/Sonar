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
  import { byId } from '../../lib/services'
  import { settings } from '../../lib/settings.svelte'
  import { t } from '../../lib/i18n.svelte'

  const enabled = $derived(settings.get('audio.fallback'))
  const order = $derived(fallbackOrder(settings.get('audio.fallback_order')))

  let dragFrom = $state<number | null>(null)
  let dragOver = $state<number | null>(null)

  function drop(to: number) {
    const from = dragFrom
    dragFrom = dragOver = null
    if (from === null || from === to) return
    settings.set('audio.fallback_order', moveItem(order, from, to))
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
    <div class="list" role="list" aria-label={t('Порядок резервных сервисов')} use:cascade={'fallback'}>
      {#each order as id, i (id)}
        {@const info = byId(id)}
        <div
          class="row"
          class:over={dragOver === i && dragFrom !== i}
          class:dragging={dragFrom === i}
          role="listitem"
          draggable={enabled}
          animate:glide
          ondragstart={(e) => {
            dragFrom = i
            e.dataTransfer?.setData('text/plain', id)
          }}
          ondragover={(e) => {
            if (dragFrom === null) return
            e.preventDefault()
            dragOver = i
          }}
          ondragend={() => (dragFrom = dragOver = null)}
          ondrop={(e) => (e.preventDefault(), drop(i))}
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
    border-top: 2px solid transparent;
    cursor: grab;
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
  .row.over {
    border-top-color: var(--accent);
  }
  .row.dragging {
    opacity: 0.5;
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
