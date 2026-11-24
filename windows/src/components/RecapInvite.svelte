<script lang="ts">
  // Приглашение на итоги на Главной: первые дни месяца — прошлый месяц, весь декабрь — год
  // (lib/recap-core.ts `inviteFor`). Открыл или закрыл крестиком — больше не зовёт (`stats.recap_seen`).
  import { onMount } from 'svelte'
  import Icon from './Icon.svelte'
  import { api, type RecapPeriods } from '../lib/api'
  import { pop, rise } from '../lib/motion'
  import { t } from '../lib/i18n.svelte'
  import { settings } from '../lib/settings.svelte'
  import { inviteFor } from '../lib/recap-core'
  import { periodTitle, recapKindTitle } from '../lib/recap-text'
  import { recap } from '../lib/recap.svelte'

  let periods = $state<RecapPeriods | null>(null)
  const invite = $derived(periods ? inviteFor(new Date(), periods, settings.get('stats.recap_seen') || null) : null)

  onMount(() => {
    // без периодов приглашения просто нет: Главная не должна ломаться из-за статистики
    api.recapPeriods().then(
      (p) => (periods = p),
      () => (periods = null),
    )
  })
</script>

{#if invite}
  <section class="invite" in:rise={{ delay: 120 }} out:pop={{ y: 0, scale: 0.98 }}>
    <span class="mark"><Icon name="chart" size={26} /></span>
    <button class="text" onclick={() => recap.open(invite)}>
      <b>{recapKindTitle(invite)} · {periodTitle(invite)}</b>
      <small>{invite.kind === 'year' ? t('Твой год в музыке — листай карточки') : t('Твой месяц в музыке — листай карточки')}</small>
    </button>
    <button class="open" onclick={() => recap.open(invite)}>{t('Открыть')}</button>
    <button class="close" onclick={() => recap.dismiss(invite)} aria-label={t('Скрыть')} title={t('Скрыть')}>
      <Icon name="x" size={16} />
    </button>
  </section>
{/if}

<style>
  .invite {
    margin-top: 24px;
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 14px 14px 14px 18px;
    border-radius: var(--radius-l);
    background:
      radial-gradient(circle at 0% 0%, color-mix(in srgb, var(--accent) 45%, transparent), transparent 70%),
      color-mix(in srgb, var(--accent) 14%, var(--surface-2));
    border: 1px solid color-mix(in srgb, var(--accent) 35%, transparent);
  }
  .mark {
    display: grid;
    place-items: center;
    width: 48px;
    height: 48px;
    flex: none;
    border-radius: 50%;
    background: var(--accent);
    color: var(--accent-ink);
  }
  .text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 2px;
    padding: 0;
    border: 0;
    background: none;
    color: var(--text);
    font: inherit;
    text-align: left;
    cursor: pointer;
  }
  .text b {
    font-size: calc(17px * var(--fs, 1));
  }
  .text small {
    color: var(--text-2);
    font-size: calc(13px * var(--fs, 1));
  }
  .open {
    height: 36px;
    padding: 0 18px;
    border: 0;
    border-radius: 99px;
    background: var(--text);
    color: var(--bg, #000);
    font: inherit;
    font-weight: 700;
    cursor: pointer;
    transition: transform var(--fast) var(--ease);
  }
  .open:active {
    transform: scale(0.96);
  }
  .close {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
    border: 0;
    border-radius: 50%;
    background: none;
    color: var(--text-2);
    cursor: pointer;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .close:hover {
    background: var(--hover);
    color: var(--text);
  }
</style>
