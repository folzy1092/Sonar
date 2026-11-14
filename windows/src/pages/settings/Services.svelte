<script lang="ts">
  // Сервисы: SoundCloud (client_id + OAuth) и Яндекс Музыка (токен). Хранятся в Диспетчере
  // учётных данных Windows (Rust, keyring), в интерфейс обратно не отдаются.
  import { onMount } from 'svelte'
  import Icon from '../../components/Icon.svelte'
  import { api, errorText, type ServicesStatus } from '../../lib/api'

  let status = $state<ServicesStatus | null>(null)
  let loadError = $state<string | null>(null)

  let scClientId = $state('')
  let scToken = $state('')
  let ymToken = $state('')
  let busy = $state<'sc' | 'ym' | null>(null)
  let scError = $state<string | null>(null)
  let ymError = $state<string | null>(null)

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
    <span class="logo sc">SC</span>
    <div>
      <h2>SoundCloud</h2>
      <p>
        {#if status?.soundcloud.connected}
          Подключён{status.soundcloud.name ? ` как ${status.soundcloud.name}` : ' (без входа — только открытые треки)'}
        {:else}
          Не подключён
        {/if}
      </p>
    </div>
    {#if status?.soundcloud.connected}
      <button class="ghost" onclick={() => disconnect('soundcloud')}>Отключить</button>
    {/if}
  </header>

  <form onsubmit={connectSc}>
    <label>
      <span>client_id</span>
      <input bind:value={scClientId} placeholder="32 символа" autocomplete="off" spellcheck="false" required />
    </label>
    <label>
      <span>OAuth-токен <em>необязательно</em></span>
      <input bind:value={scToken} type="password" placeholder="2-123456-…" autocomplete="off" spellcheck="false" />
    </label>
    <p class="hint">
      soundcloud.com → F12 → Сеть → любой запрос к api-v2: <code>client_id</code> в адресе, токен — в
      заголовке <code>Authorization: OAuth …</code>.
    </p>
    {#if scError}<p class="error">{scError}</p>{/if}
    <button class="primary" disabled={busy !== null || !scClientId.trim()}>
      {busy === 'sc' ? 'Проверяю…' : status?.soundcloud.connected ? 'Заменить ключи' : 'Подключить'}
    </button>
  </form>
</section>

<section class="svc">
  <header>
    <span class="logo ym">Я</span>
    <div>
      <h2>Яндекс Музыка</h2>
      <p>
        {#if status?.yandex.connected}
          Подключена{status.yandex.name ? ` как ${status.yandex.name}` : ''}
        {:else}
          Не подключена
        {/if}
      </p>
    </div>
    {#if status?.yandex.connected}
      <button class="ghost" onclick={() => disconnect('yandex')}>Отключить</button>
    {/if}
  </header>

  <form onsubmit={connectYm}>
    <label>
      <span>Токен</span>
      <input bind:value={ymToken} type="password" placeholder="y0_…" autocomplete="off" spellcheck="false" required />
    </label>
    <p class="hint">Токен вида <code>y0_…</code> (подходит и старый <code>AQAAAA…</code>). Вход «в один клик» — позже.</p>
    {#if ymError}<p class="error">{ymError}</p>{/if}
    <button class="primary" disabled={busy !== null || !ymToken.trim()}>
      {busy === 'ym' ? 'Проверяю…' : status?.yandex.connected ? 'Заменить токен' : 'Подключить'}
    </button>
  </form>
</section>

<p class="safe"><Icon name="key" size={16} /> Ключи хранятся в Диспетчере учётных данных Windows и никуда не отправляются.</p>

<style>
  .svc {
    max-width: 620px;
    padding: 18px 20px 20px;
    margin-bottom: 12px;
    border-radius: var(--radius-l);
    background: var(--plate);
    border: 1px solid var(--border);
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
    font-size: 17px;
    font-weight: 700;
  }
  header p {
    margin: 2px 0 0;
    font-size: 13px;
    color: var(--text-3);
  }
  .logo {
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    border-radius: var(--radius-m);
    font-weight: 800;
    font-size: 13px;
  }
  .logo.sc {
    background: #ff5500;
    color: #fff;
  }
  .logo.ym {
    background: #ffcc00;
    color: #111;
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
    font-size: 13px;
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
    border: 1px solid var(--border);
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
    font-size: 12px;
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
    font-size: 13px;
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
    font-size: 12px;
  }
  .note {
    color: var(--text-3);
  }
</style>
