<script lang="ts">
  // Подписка → Sonar Deep (решение владельца 2026-11-18): тариф по числу мест (Ping · Echo · Pod · Fleet),
  // срок, что входит, и «Перейти к оплате» — оплата на сайте (`lib/subscription.ts` `payUrl`).
  // Цены — черновик до утверждения владельцем; оплата заработает вместе с сайтом и сервером.
  import Icon from '../../components/Icon.svelte'
  import { api } from '../../lib/api'
  import { cascade } from '../../lib/cascade'
  import { indicator } from '../../lib/indicator'
  import { t, tn } from '../../lib/i18n.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { cleanUsername } from '../../lib/avatar'
  import { PERIODS, PERKS, PLANS, SUB_NAME, payUrl, price, rub, savedPercent, type PeriodId, type PlanId } from '../../lib/subscription'
  import { toast } from '../../lib/toast.svelte'

  let planId = $state<PlanId>('ping')
  let periodId = $state<PeriodId>('1m')
  const plan = $derived(PLANS.find((p) => p.id === planId) ?? PLANS[0])
  const period = $derived(PERIODS.find((p) => p.id === periodId) ?? PERIODS[0])
  const total = $derived(price(plan, period))

  const periodLabel = (months: number) =>
    months === 12 ? t('1 год') : tn(months, ['{n} месяц', '{n} месяца', '{n} месяцев']).replace('{n}', String(months))
  const seatsLabel = (seats: number) =>
    seats === 1 ? t('Только ты') : tn(seats - 1, ['Ты и ещё {n} человек', 'Ты и ещё {n} человека', 'Ты и ещё {n} человек']).replace('{n}', String(seats - 1))

  function pay() {
    const url = payUrl(plan.id, period.id, cleanUsername(settings.get('profile.username')) || null)
    api.openUrl(url).catch(() => toast.show(url))
  }
</script>

<div class="sub">
  <div class="left">
    <div class="seg" role="radiogroup" aria-label={t('Тариф')} use:indicator={{ key: planId, kind: 'pill' }}>
      {#each PLANS as p (p.id)}
        <button class="seg-b" class:on={planId === p.id} role="radio" aria-checked={planId === p.id} onclick={() => (planId = p.id)}>
          {p.name}
        </button>
      {/each}
    </div>

    <b class="label">{t('Срок')}</b>
    <div class="periods" role="radiogroup" aria-label={t('Срок')}>
      {#each PERIODS as pr (pr.id)}
        <button class="period press" class:on={periodId === pr.id} role="radio" aria-checked={periodId === pr.id} onclick={() => (periodId = pr.id)}>
          <span class="top">
            {periodLabel(pr.months)}
            {#if periodId === pr.id}<Icon name="check" size={16} />{/if}
          </span>
          <span class="cost">
            <b>{rub(price(plan, pr))}</b>
            {#if savedPercent(plan, pr)}<small>−{savedPercent(plan, pr)}&nbsp;%</small>{/if}
          </span>
        </button>
      {/each}
    </div>
  </div>

  <aside class="card">
    <small class="muted">{t('Подписка на {period}', { period: periodLabel(period.months) })}</small>
    {#key planId}
      <h3 class="name">{SUB_NAME} {plan.name}</h3>
    {/key}
    <small class="muted">{seatsLabel(plan.seats)}</small>
    <ul class="perks" use:cascade={planId}>
      {#each PERKS as perk (perk)}
        <li><Icon name="check" size={15} />{t(perk)}</li>
      {/each}
    </ul>
    <p class="free">{t('Музыка, лайки, плейлисты, синхронизация и скачивание треков — бесплатно.')}</p>
    <b class="total">{rub(total)}</b>
    <button class="pay press" onclick={pay}>{t('Перейти к оплате')}<Icon name="link" size={15} /></button>
    <small class="muted">{t('Оплата откроется на сайте Sonar. Подписка придёт на аккаунт, с которого ты её оформил.')}</small>
  </aside>
</div>

<style>
  .sub {
    display: grid;
    grid-template-columns: minmax(0, 1.4fr) minmax(260px, 1fr);
    gap: 24px;
    align-items: start;
  }
  /* ширина панели настроек, не окна (окно не уже 960) */
  @container (max-width: 620px) {
    .sub {
      grid-template-columns: 1fr;
    }
  }
  .left {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .seg {
    position: relative;
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    padding: 4px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--card-line);
  }
  .seg-b {
    position: relative;
    z-index: 1;
    height: 36px;
    border-radius: 999px;
    color: var(--text-2);
    font-weight: 600;
    transition: color var(--fast) var(--ease);
  }
  .seg-b:hover {
    color: var(--text);
  }
  .seg-b.on {
    color: var(--accent-ink);
  }
  .seg :global(.tab-ind.pill) {
    background: var(--accent);
  }
  .label {
    margin-top: 8px;
    color: var(--text-2);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
  }
  .periods {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  .period {
    display: flex;
    flex-direction: column;
    gap: 14px;
    padding: 16px 18px;
    border-radius: 14px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    text-align: left;
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      border-color var(--fast) var(--ease),
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .period:hover {
    background: var(--hover);
    color: var(--text);
  }
  .period.on {
    color: var(--text);
    border-color: color-mix(in srgb, var(--accent) 55%, transparent);
    background: color-mix(in srgb, var(--accent) 10%, var(--plate));
  }
  .period:active {
    transform: scale(0.98);
  }
  .top {
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-weight: 600;
  }
  .cost {
    display: flex;
    align-items: baseline;
    gap: 8px;
  }
  .cost b {
    color: var(--text);
    font-size: calc(20px * var(--fs, 1));
    font-variant-numeric: tabular-nums;
  }
  .cost small {
    color: var(--text-2);
  }
  .card {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 22px;
    border-radius: 18px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  .muted {
    color: var(--text-2);
  }
  .name {
    margin: 2px 0 0;
    font-size: calc(26px * var(--fs, 1));
    font-weight: 800;
    letter-spacing: -0.02em;
    animation: name-in var(--normal, 0.24s) var(--ease) both;
  }
  @keyframes name-in {
    from {
      opacity: 0;
      transform: translateY(4px);
    }
  }
  .perks {
    display: flex;
    flex-direction: column;
    gap: 9px;
    max-height: 300px;
    margin: 14px 0 6px;
    padding: 0 6px 0 0;
    overflow-y: auto;
    list-style: none;
    scrollbar-width: thin;
  }
  .perks li {
    display: flex;
    gap: 10px;
    align-items: flex-start;
    font-weight: 500;
  }
  .perks :global(svg) {
    flex: none;
    margin-top: 2px;
    color: var(--accent);
  }
  .free {
    margin: 4px 0 8px;
    color: var(--text-2);
    font-size: calc(12px * var(--fs, 1));
  }
  .total {
    font-size: calc(30px * var(--fs, 1));
    font-weight: 800;
    font-variant-numeric: tabular-nums;
  }
  .pay {
    display: inline-flex;
    justify-content: center;
    align-items: center;
    gap: 8px;
    height: 44px;
    margin: 8px 0 4px;
    border-radius: 12px;
    background: var(--accent);
    color: var(--accent-ink);
    font-weight: 700;
    transition:
      filter var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .pay:hover {
    filter: brightness(1.08);
  }
  .pay:active {
    transform: scale(0.98);
  }
  @media (prefers-reduced-motion: reduce) {
    .name {
      animation: none;
    }
    .period:active,
    .pay:active {
      transform: none;
    }
  }
</style>
