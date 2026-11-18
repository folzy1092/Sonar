<script lang="ts">
  // Подменю «Экспорт» в меню плейлиста и Любимых: назад и три формата файла. Строки появляются
  // каскадом (use:cascade), выбор — только кликом; что делать с выбранным форматом — решает меню.
  import Icon from '../components/Icon.svelte'
  import type { IconName } from '../components/icons'
  import { cascade } from '../lib/cascade'
  import type { ExportFormat } from '../lib/export'
  import { t } from '../lib/i18n.svelte'

  let { onback, onpick }: { onback: () => void; onpick: (format: ExportFormat) => void } = $props()

  const rows: { format: ExportFormat; icon: IconName; label: string; hint: string }[] = $derived([
    { format: 'm3u8', icon: 'playlist', label: 'M3U8', hint: t('для плееров') },
    { format: 'csv', icon: 'grid', label: 'CSV', hint: t('для таблиц') },
    { format: 'json', icon: 'database', label: 'JSON', hint: t('все поля') },
  ])
</script>

<div class="export" use:cascade>
  <button class="item back" role="menuitem" onclick={onback}>
    <Icon name="chevronLeft" size={17} />
    <span>{t('Экспорт')}</span>
  </button>
  {#each rows as row (row.format)}
    <button class="item" role="menuitem" onclick={() => onpick(row.format)}>
      <Icon name={row.icon} size={17} />
      <span>{row.label}</span>
      <small>{row.hint}</small>
    </button>
  {/each}
</div>

<style>
  .item {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    height: 36px;
    padding: 0 10px;
    border-radius: var(--radius-s);
    color: var(--text-2);
    text-align: left;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .item span {
    flex: 1;
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .item small {
    flex: none;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .item:hover {
    background: var(--hover);
    color: var(--text);
  }
  .back {
    color: var(--text);
    font-weight: 600;
  }
</style>
