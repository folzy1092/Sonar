<script lang="ts">
  // Статистика → «Итоги»: годы и месяцы, за которые есть прослушивания; клик — итоги на весь экран
  // (app/RecapViewer.svelte). Свежие — первыми.
  import Icon from '../../components/Icon.svelte'
  import { api, type RecapPeriod, type RecapPeriods } from '../../lib/api'
  import { cascade } from '../../lib/cascade'
  import { t } from '../../lib/i18n.svelte'
  import { periodTitle } from '../../lib/recap-text'
  import { recap } from '../../lib/recap.svelte'

  /** Месяцев в списке — не больше года назад: старее открываются через итоги года. */
  const MAX_MONTHS = 12

  let periods = $state<RecapPeriods | null>(null)

  $effect(() => {
    api.recapPeriods().then(
      (p) => (periods = p),
      () => (periods = null),
    )
  })

  const years = $derived(periods?.years ?? [])
  const months = $derived((periods?.months ?? []).slice(0, MAX_MONTHS))

  const open = (p: RecapPeriod) => recap.open({ kind: p.kind, year: p.year, month: p.month })
</script>

{#if years.length || months.length}
  <h2>{t('Итоги')}</h2>
  <div class="chips" use:cascade>
    {#each years as p (`y${p.year}`)}
      <button class="chip year" onclick={() => open(p)}>
        <Icon name="chart" size={16} />{t('Итоги года')} · {periodTitle(p)}
      </button>
    {/each}
    {#each months as p (`m${p.year}-${p.month}`)}
      <button class="chip" onclick={() => open(p)}>{periodTitle(p)}</button>
    {/each}
  </div>
{/if}

<style>
  h2 {
    margin: 26px 0 12px;
    font-size: calc(22px * var(--fs, 1));
    font-weight: 800;
  }
  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .chip {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 34px;
    padding: 0 14px;
    border-radius: 99px;
    border: 1px solid var(--card-line);
    background: var(--plate);
    color: var(--text);
    font: inherit;
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    cursor: pointer;
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .chip:hover {
    background: var(--hover);
  }
  .chip:active {
    transform: scale(0.96);
  }
  .chip.year {
    border-color: color-mix(in srgb, var(--accent) 45%, transparent);
    background: color-mix(in srgb, var(--accent) 16%, var(--plate));
  }
</style>
