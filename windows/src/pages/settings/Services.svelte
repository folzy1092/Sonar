<script lang="ts">
  import SourceIcon from '../../components/SourceIcon.svelte'
  // Сервисы: вход в один клик (окно входа самого сервиса, ключи Sonar забирает сам — login.rs) или
  // вручную: SoundCloud (client_id + OAuth), Яндекс Музыка (токен). Хранятся в Диспетчере учётных
  // данных Windows (Rust, keyring), в интерфейс обратно не отдаются.
  import { slide } from 'svelte/transition'
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
  /** Ручной ввод ключей раскрыт. */
  let manual = $state<{ sc: boolean; ym: boolean }>({ sc: false, ym: false })
  let waiting = $state<'sc' | 'ym' | null>(null)

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
    }
  }

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
          Подключён{status.soundcloud.name ? ` как ${status.soundcloud.name}` : ' (без входа — только открытые треки)'}
        {:else}
          Без входа: поиск и открытые треки работают сами
        {/if}
      </p>
    </div>
    {#if status?.soundcloud.connected}
      <button class="ghost" onclick={() => disconnect('soundcloud')}>Отключить</button>
    {/if}
  </header>

  <div class="one">
    <button class="primary big" disabled={waiting !== null} onclick={() => login('soundcloud')}>
      {waiting === 'sc' ? 'Войди в открывшемся окне…' : status?.soundcloud.name ? 'Войти заново' : 'Войти через SoundCloud'}
    </button>
    <button class="toggle" class:on={manual.sc} onclick={() => (manual.sc = !manual.sc)}>Вручную</button>
  </div>
  {#if scError && !manual.sc}<p class="error">{scError}</p>{/if}
  {#if manual.sc}
  <div transition:slide={{ duration: 260 }}>
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
      Ключи нужны, чтобы играли и твои закрытые треки, а в W3 — подтянуть лайки и плейлисты.
      soundcloud.com → F12 → Сеть → любой запрос к api-v2: <code>client_id</code> в адресе, токен — в
      заголовке <code>Authorization: OAuth …</code>.
    </p>
    {#if scError}<p class="error">{scError}</p>{/if}
    <button class="primary" disabled={busy !== null || !scClientId.trim()}>
      {busy === 'sc' ? 'Проверяю…' : status?.soundcloud.connected ? 'Заменить ключи' : 'Подключить'}
    </button>
  </form>
  </div>
  {/if}
</section>

<section class="svc">
  <header>
    <span class="logo ym"><SourceIcon kind="ym" size={26} plain /></span>
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

  <div class="one">
    <button class="primary big" disabled={waiting !== null} onclick={() => login('yandex')}>
      {waiting === 'ym' ? 'Войди в открывшемся окне…' : status?.yandex.connected ? 'Войти заново' : 'Войти через Яндекс'}
    </button>
    <button class="toggle" class:on={manual.ym} onclick={() => (manual.ym = !manual.ym)}>Вручную</button>
  </div>
  {#if ymError && !manual.ym}<p class="error">{ymError}</p>{/if}
  {#if manual.ym}
  <div transition:slide={{ duration: 260 }}>
  <form onsubmit={connectYm}>
    <label>
      <span>Токен</span>
      <input bind:value={ymToken} type="password" placeholder="y0_…" autocomplete="off" spellcheck="false" required />
    </label>
    <p class="hint">Токен вида <code>y0_…</code> (подходит и старый <code>AQAAAA…</code>). </p>
    {#if ymError}<p class="error">{ymError}</p>{/if}
    <button class="primary" disabled={busy !== null || !ymToken.trim()}>
      {busy === 'ym' ? 'Проверяю…' : status?.yandex.connected ? 'Заменить токен' : 'Подключить'}
    </button>
  </form>
  </div>
  {/if}
</section>

<p class="safe"><Icon name="key" size={16} /> Вход идёт на сайте самого сервиса — Sonar пароль не видит. Ключи хранятся в Диспетчере учётных данных Windows и никуда не отправляются.</p>

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
</style>
