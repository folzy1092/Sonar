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
  import { api, errorText, type ServiceStatus, type ServicesStatus } from '../../lib/api'
  import { ACCOUNT_SERVICES, statusOf, type ServiceInfo } from '../../lib/services'
  import { listen } from '@tauri-apps/api/event'
  import { isTauri } from '../../lib/tauri'
  import { cascade } from '../../lib/cascade'
  import { offline } from '../../lib/offline.svelte'

  let status = $state<ServicesStatus | null>(null)
  let loadError = $state<string | null>(null)
  let lock = $state<ServiceLock>(FREE_LOCK)

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
</style>
