<script lang="ts">
  // Сервисы: вход в один клик (ключи Sonar забирает сам — login.rs): Яндекс — в браузере по умолчанию
  // по коду (Sonar показывает код и открывает ya.ru/device), SoundCloud — окном входа SoundCloud; или
  // вручную (ключи/токен). Хранятся в Диспетчере учётных данных Windows (Rust, keyring), в интерфейс
  // обратно не отдаются. Карточки — из реестра (lib/services.ts, только реализованные), сама карточка —
  // ServiceCard.svelte.
  import { onMount } from 'svelte'
  import Icon from '../../components/Icon.svelte'
  import ServiceCard, { FREE_LOCK, type ServiceLock } from './ServiceCard.svelte'
  import { t } from '../../lib/i18n.svelte'
  import { api, errorText, type ServiceCheck, type ServiceStatus, type ServicesStatus } from '../../lib/api'
  import { slide } from '../../lib/motion'
  import { ACCOUNT_SERVICES, statusOf, type ServiceInfo } from '../../lib/services'
  import { listen } from '@tauri-apps/api/event'
  import { isTauri } from '../../lib/tauri'
  import { cascade } from '../../lib/cascade'
  import { offline } from '../../lib/offline.svelte'

  let status = $state<ServicesStatus | null>(null)
  let loadError = $state<string | null>(null)
  let lock = $state<ServiceLock>(FREE_LOCK)

  let checking = $state(false)
  let checks = $state<ServiceCheck[] | null>(null)
  let checkError = $state<string | null>(null)

  /** «Проверить сервисы»: каждый подключённый ищет одну строку — сразу видно, кто жив. */
  async function runCheck() {
    checking = true
    checkError = null
    try {
      checks = await api.checkServices()
    } catch (e) {
      checkError = errorText(e)
    } finally {
      checking = false
    }
  }
  const nameOf = (key: string) => ACCOUNT_SERVICES.find((s) => s.key === key)?.name ?? key
  const secText = (ms: number) => (ms / 1000).toFixed(1)

  function update(info: ServiceInfo, next: ServiceStatus) {
    status = { ...status!, [info.key]: next }
  }

  onMount(() => {
    if (!isTauri) return
    const off = listen<{ service: string; code: string; url: string }>('login:code', (e) => {
      lock = { ...lock, code: { service: e.payload.service, code: e.payload.code, url: e.payload.url } }
    })
    return () => void off.then((f) => f())
  })

  onMount(async () => {
    try {
      status = await api.servicesStatus()
    } catch (e) {
      loadError = errorText(e)
    }
  })
</script>

{#if loadError}
  <p class="note">{loadError}</p>
{/if}

{#if offline.on}
  <p class="offline"><Icon name="wifiOff" size={16} /> {t('Недоступно в офлайне')} — {t('вход в сервисы работает только с сетью.')}</p>
{/if}

<!-- офлайн: карточки видны, но не нажимаются — вход и проверка ключей ходят в сеть -->
<div class="cards" class:off={offline.on} inert={offline.on} use:cascade={ACCOUNT_SERVICES.length}>
  {#each ACCOUNT_SERVICES as s (s.id)}
    <ServiceCard info={s} state={statusOf(status, s)} onchange={(next) => update(s, next)} bind:lock />
  {/each}
</div>

<section class="check" class:off={offline.on} inert={offline.on}>
  <div class="check-head">
    <span>
      <b>{t('Проверка сервисов')}</b>
      <small>{t('Каждый подключённый сервис ищет одну строку — видно, жив ли ключ и отвечает ли сервис')}</small>
    </span>
    <button class="run press" disabled={checking} onclick={runCheck}>
      <Icon name="refresh" size={15} />
      {checking ? t('Проверяю…') : t('Проверить')}
    </button>
  </div>
  {#if checkError}
    <p class="bad" transition:slide={{ duration: 180 }}>{checkError}</p>
  {:else if checks && checks.length === 0}
    <p class="muted" transition:slide={{ duration: 180 }}>{t('Ни один сервис не подключён')}</p>
  {:else if checks}
    <ul use:cascade={checks.length} transition:slide={{ duration: 200 }}>
      {#each checks as c (c.service)}
        <li class:fail={!c.ok}>
          <i class="dot"></i>
          <b>{nameOf(c.service)}</b>
          {#if c.ok}
            <span>{t('Работает · {sec} с', { sec: secText(c.ms) })}</span>
          {:else}
            <span class="err">{c.error}</span>
          {/if}
        </li>
      {/each}
    </ul>
  {/if}
</section>

<p class="safe"><Icon name="key" size={16} /> {t('Вход идёт на сайте самого сервиса — Sonar пароль не видит. Ключи хранятся в Диспетчере учётных данных Windows и никуда не отправляются.')}</p>

<style>
  /* карточки сервисов — сетка: одна колонка в узкой панели, две — в широкой */
  .cards {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(min(100%, 420px), 1fr));
    align-items: start;
    gap: 12px;
    margin-bottom: 14px;
    transition: opacity 0.2s ease;
  }
  .cards.off {
    opacity: 0.5;
  }
  .offline {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 0 0 12px;
    color: var(--text-2);
    font-size: calc(13px * var(--fs, 1));
  }
  .safe {
    display: flex;
    align-items: center;
    gap: 8px;
    color: var(--text-3);
    font-size: calc(12px * var(--fs, 1));
  }
  .note {
    color: var(--text-3);
  }
  .check {
    margin-bottom: 14px;
    padding: 14px 16px;
    border-radius: 16px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    transition: opacity 0.2s ease;
  }
  .check.off {
    opacity: 0.5;
  }
  .check-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
  }
  .check-head span {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }
  .check-head b {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  .check-head small,
  .muted {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .run {
    flex: none;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 32px;
    padding: 0 12px;
    border-radius: 10px;
    background: var(--surface-3);
    color: var(--text);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    transition:
      background var(--fast) var(--ease),
      opacity var(--fast) var(--ease);
  }
  .run:hover:not(:disabled) {
    background: var(--hover);
  }
  .run:disabled {
    opacity: 0.6;
  }
  .check ul {
    display: flex;
    flex-direction: column;
    gap: 4px;
    margin: 12px 0 0;
    padding: 0;
    list-style: none;
  }
  .check li {
    display: grid;
    grid-template-columns: 8px 120px 1fr;
    align-items: baseline;
    gap: 10px;
    font-size: calc(13px * var(--fs, 1));
  }
  .check li span {
    color: var(--text-2);
    font-variant-numeric: tabular-nums;
  }
  .check .err,
  .bad {
    color: var(--danger, #e5484d);
  }
  .bad,
  .muted {
    margin: 10px 0 0;
  }
  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--online);
    align-self: center;
  }
  .fail .dot {
    background: var(--danger, #e5484d);
  }
</style>
