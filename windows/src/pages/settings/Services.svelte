<script lang="ts">
  import SourceIcon from '../../components/SourceIcon.svelte'
  // Сервисы: вход в один клик (ключи Sonar забирает сам — login.rs): Яндекс — в браузере по умолчанию
  // по коду (Sonar показывает код и открывает ya.ru/device), SoundCloud — окном входа SoundCloud; или
  // вручную: SoundCloud (client_id + OAuth), Яндекс Музыка (токен). Хранятся в Диспетчере учётных
  // данных Windows (Rust, keyring), в интерфейс обратно не отдаются.
  import { slide } from 'svelte/transition'
  import { onMount } from 'svelte'
  import Icon from '../../components/Icon.svelte'
  import { t } from '../../lib/i18n.svelte'
  import { api, errorText, type ServicesStatus } from '../../lib/api'
  import { listen } from '@tauri-apps/api/event'
  import { isTauri } from '../../lib/tauri'
  import { toast } from '../../lib/toast.svelte'

  let status = $state<ServicesStatus | null>(null)
  let loadError = $state<string | null>(null)

  let scClientId = $state('')
  let scToken = $state('')
  let ymToken = $state('')
  let busy = $state<'sc' | 'ym' | null>(null)
  let scError = $state<string | null>(null)
  let ymError = $state<string | null>(null)
  /** Ручной ввод ключей раскрыт. */
  let manual = $state<{ sc: boolean; ym: boolean }>({ sc: false, ym: false })
  let waiting = $state<'sc' | 'ym' | null>(null)
  /** Код для ya.ru/device, пока ждём вход в Яндекс через браузер. */
  let ymCode = $state<{ code: string; url: string } | null>(null)

  async function copyCode() {
    if (!ymCode) return
    try {
      await navigator.clipboard.writeText(ymCode.code)
      toast.show(t('Код скопирован'))
    } catch {
      toast.show(t('Не получилось скопировать'))
    }
  }

  async function login(svc: 'soundcloud' | 'yandex') {
    const key = svc === 'soundcloud' ? 'sc' : 'ym'
    waiting = key
    if (key === 'sc') scError = null
    else ymError = null
    try {
      const s = await api.loginService(svc)
      status = { ...status!, [svc]: s }
    } catch (e) {
      if (key === 'sc') scError = errorText(e)
      else ymError = errorText(e)
    } finally {
      waiting = null
      ymCode = null
    }
  }

  function cancelLogin() {
    void api.cancelLogin().catch(() => {})
  }

  onMount(() => {
    if (!isTauri) return
    const off = listen<{ service: string; code: string; url: string }>('login:code', (e) => {
      if (e.payload.service === 'yandex') ymCode = { code: e.payload.code, url: e.payload.url }
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

  async function connectSc(e: SubmitEvent) {
    e.preventDefault()
    busy = 'sc'
    scError = null
    try {
      const s = await api.connectSoundcloud(scClientId, scToken || null)
      status = { ...status!, soundcloud: s }
      scClientId = scToken = ''
    } catch (err) {
      scError = errorText(err)
    } finally {
      busy = null
    }
  }

  async function connectYm(e: SubmitEvent) {
    e.preventDefault()
    busy = 'ym'
    ymError = null
    try {
      const s = await api.connectYandex(ymToken)
      status = { ...status!, yandex: s }
      ymToken = ''
    } catch (err) {
      ymError = errorText(err)
    } finally {
      busy = null
    }
  }

  async function disconnect(svc: 'soundcloud' | 'yandex') {
    await api.disconnectService(svc).catch(() => {})
    status = { ...status!, [svc]: { connected: false, name: null, avatar_url: null } }
  }
</script>

{#if loadError}
  <p class="note">{loadError}</p>
{/if}

<section class="svc">
  <header>
    <span class="logo sc"><SourceIcon kind="sc" size={24} plain /></span>
    <div>
      <h2>SoundCloud</h2>
      <p>
        {#if status?.soundcloud.connected}
          {status.soundcloud.name ? t('Подключён как {name}', { name: status.soundcloud.name }) : t('Подключён (без входа — только открытые треки)')}
        {:else}
          {t('Без входа: поиск и открытые треки работают сами')}
        {/if}
      </p>
    </div>
    {#if status?.soundcloud.connected}
      <button class="ghost" onclick={() => disconnect('soundcloud')}>{t('Отключить')}</button>
    {/if}
  </header>

  <div class="one">
    <button class="primary big" disabled={waiting !== null} onclick={() => login('soundcloud')}>
      {waiting === 'sc' ? t('Войди в открывшемся окне…') : status?.soundcloud.name ? t('Войти заново') : t('Войти через SoundCloud')}
    </button>
    <button class="toggle" class:on={manual.sc} onclick={() => (manual.sc = !manual.sc)}>{t('Вручную')}</button>
  </div>
  {#if scError && !manual.sc}<p class="error">{scError}</p>{/if}
  {#if manual.sc}
  <div transition:slide={{ duration: 260 }}>
  <form onsubmit={connectSc}>
    <label>
      <span>client_id</span>
      <input bind:value={scClientId} placeholder={t('32 символа')} autocomplete="off" spellcheck="false" required />
    </label>
    <label>
      <span>{t('OAuth-токен')} <em>{t('необязательно')}</em></span>
      <input bind:value={scToken} type="password" placeholder="2-123456-…" autocomplete="off" spellcheck="false" />
    </label>
    <p class="hint">
      {t('Ключи нужны, чтобы играли и твои закрытые треки, а в W3 — подтянуть лайки и плейлисты.')}
      {t('soundcloud.com → F12 → Сеть → любой запрос к api-v2:')} <code>client_id</code> {t('в адресе, токен — в заголовке')}
      <code>Authorization: OAuth …</code>.
    </p>
    {#if scError}<p class="error">{scError}</p>{/if}
    <button class="primary" disabled={busy !== null || !scClientId.trim()}>
      {busy === 'sc' ? t('Проверяю…') : status?.soundcloud.connected ? t('Заменить ключи') : t('Подключить')}
    </button>
  </form>
  </div>
  {/if}
</section>

<section class="svc">
  <header>
    <span class="logo ym"><SourceIcon kind="ym" size={26} plain /></span>
    <div>
      <h2>{t('Яндекс Музыка')}</h2>
      <p>
        {#if status?.yandex.connected}
          {status.yandex.name ? t('Подключена как {name}', { name: status.yandex.name }) : t('Подключена')}
        {:else}
          {t('Не подключена')}
        {/if}
      </p>
    </div>
    {#if status?.yandex.connected}
      <button class="ghost" onclick={() => disconnect('yandex')}>{t('Отключить')}</button>
    {/if}
  </header>

  <div class="one">
    <button class="primary big" disabled={waiting !== null} onclick={() => login('yandex')}>
      {waiting === 'ym' ? t('Жду вход в браузере…') : status?.yandex.connected ? t('Войти заново') : t('Войти через Яндекс')}
    </button>
    <button class="toggle" class:on={manual.ym} onclick={() => (manual.ym = !manual.ym)}>{t('Вручную')}</button>
  </div>
  {#if waiting === 'ym' && ymCode}
    <!-- вход в браузере по умолчанию: код вводится на ya.ru/device, токен Sonar заберёт сам -->
    <div class="device" transition:slide={{ duration: 220 }}>
      <p>{t('В браузере открылась страница Яндекса — войди и введи код:')}</p>
      <button class="code" title={t('Скопировать код')} onclick={copyCode}>{ymCode.code}</button>
      <div class="device-actions">
        <button class="ghost" onclick={() => ymCode && api.openUrl(ymCode.url)}>{t('Открыть страницу снова')}</button>
        <button class="ghost" onclick={cancelLogin}>{t('Отмена')}</button>
      </div>
    </div>
  {/if}
  {#if ymError && !manual.ym}<p class="error">{ymError}</p>{/if}
  {#if manual.ym}
  <div transition:slide={{ duration: 260 }}>
  <form onsubmit={connectYm}>
    <label>
      <span>{t('Токен')}</span>
      <input bind:value={ymToken} type="password" placeholder="y0_…" autocomplete="off" spellcheck="false" required />
    </label>
    <p class="hint">{t('Токен вида')} <code>y0_…</code> ({t('подходит и старый')} <code>AQAAAA…</code>). </p>
    {#if ymError}<p class="error">{ymError}</p>{/if}
    <button class="primary" disabled={busy !== null || !ymToken.trim()}>
      {busy === 'ym' ? t('Проверяю…') : status?.yandex.connected ? t('Заменить токен') : t('Подключить')}
    </button>
  </form>
  </div>
  {/if}
</section>

<p class="safe"><Icon name="key" size={16} /> {t('Вход идёт на сайте самого сервиса — Sonar пароль не видит. Ключи хранятся в Диспетчере учётных данных Windows и никуда не отправляются.')}</p>

<style>
  .one {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 16px;
  }
  .primary.big {
    height: 40px;
    padding: 0 20px;
  }
  .toggle {
    height: 40px;
    padding: 0 14px;
    border-radius: 12px;
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-3);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .toggle:hover,
  .toggle.on {
    color: var(--text);
    background: var(--hover);
  }
  .svc {
    max-width: 620px;
    padding: 18px 20px 20px;
    margin-bottom: 12px;
    border-radius: var(--radius-l);
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  header {
    display: flex;
    align-items: center;
    gap: 14px;
  }
  header > div {
    flex: 1;
    min-width: 0;
  }
  h2 {
    font-size: calc(17px * var(--fs, 1));
    font-weight: 700;
  }
  header p {
    margin: 2px 0 0;
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-3);
  }
  .logo {
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    border-radius: var(--radius-m);
    font-weight: 800;
    font-size: calc(13px * var(--fs, 1));
  }
  .logo.sc,
  .logo.ym {
    background: var(--surface-3);
  }
  form {
    display: flex;
    flex-direction: column;
    gap: 12px;
    margin-top: 16px;
  }
  label {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  label span {
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
  }
  em {
    font-style: normal;
    font-weight: 400;
    color: var(--text-3);
  }
  input {
    height: 40px;
    padding: 0 14px;
    border-radius: var(--radius-m);
    background: var(--surface-1);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    color: var(--text);
    outline: none;
    user-select: text;
    transition: border-color var(--fast) var(--ease);
  }
  input:focus {
    border-color: var(--border-strong);
  }
  .hint {
    margin: 0;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  code {
    padding: 0 4px;
    border-radius: 4px;
    background: var(--surface-2);
    color: var(--text-2);
  }
  .error {
    margin: 0;
    font-size: calc(13px * var(--fs, 1));
    color: var(--danger);
  }
  .primary {
    align-self: flex-start;
    height: 38px;
    padding: 0 18px;
    border-radius: 999px;
    background: var(--accent);
    color: var(--accent-ink);
    font-weight: 700;
    transition: opacity var(--fast) var(--ease);
  }
  .primary:disabled {
    opacity: 0.4;
    cursor: default;
  }
  .ghost {
    height: 34px;
    padding: 0 14px;
    border-radius: 999px;
    border: 1px solid var(--border-strong);
    color: var(--text-2);
  }
  .ghost:hover {
    color: var(--text);
    background: var(--hover);
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
  .device {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 10px;
    margin-top: 12px;
    padding: 14px;
    border-radius: var(--radius-l);
    background: var(--surface-2);
    border: 1px solid var(--card-line);
  }
  .device p {
    margin: 0;
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-2);
  }
  .code {
    padding: 8px 16px;
    border-radius: var(--radius-m);
    background: var(--surface-3);
    font-family: var(--font-display);
    font-size: calc(26px * var(--fs, 1));
    font-weight: 700;
    letter-spacing: 0.18em;
    text-transform: uppercase;
    user-select: all;
    transition: transform var(--fast) var(--ease);
  }
  .code:active {
    transform: scale(0.97);
  }
  .device-actions {
    display: flex;
    gap: 8px;
  }
</style>
