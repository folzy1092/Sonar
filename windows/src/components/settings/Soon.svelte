<script lang="ts">
  // Пометка «Скоро» (ещё не сделано или нужен сервер) или замок «В разработке» (приватность).
  import Icon from '../Icon.svelte'
  import { t } from '../../lib/i18n.svelte'
  let { lock = false }: { lock?: boolean } = $props()
</script>

<span class="soon" title={lock ? t('В разработке') : t('Скоро')}>
  {#if lock}<Icon name="lock" size={11} /> {t('В разработке')}{:else}{t('Скоро')}{/if}
</span>

<style>
  .soon {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    height: 18px;
    padding: 0 7px;
    margin-left: 8px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--border);
    font-size: calc(10px * var(--fs, 1));
    font-weight: 600;
    letter-spacing: 0.02em;
    color: var(--text-3);
    vertical-align: 2px;
    white-space: nowrap;
  }
</style>
