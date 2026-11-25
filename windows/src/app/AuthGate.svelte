<script lang="ts">
  // Ворота входа (решение владельца 2026-11-25: на ПК вход обязателен). Встают поверх всего окна, только
  // когда сервер Sonar отвечает, а сессии нет (`account.gate`): офлайн-режим и недоступный сервер пускают
  // в плеер как раньше. Кнопки окна остаются доступны — окно можно свернуть или спрятать в трей.
  import SignIn from '../components/account/SignIn.svelte'
  import { account } from '../lib/account.svelte'
  import { offline } from '../lib/offline.svelte'
  import { fade } from 'svelte/transition'
  import { pop } from '../lib/motion'
  import WindowControls from './WindowControls.svelte'
  import { t } from '../lib/i18n.svelte'

  // Выключили офлайн-режим — заново спросить сервер: может, пора показать вход.
  $effect(() => {
    if (!offline.on && account.checked) void account.ping()
  })
</script>

{#if account.gate}
  <div class="gate" transition:fade={{ duration: 240 }} data-tauri-drag-region>
    <div class="controls"><WindowControls /></div>
    <div class="card" in:pop={{ duration: 280 }}>
      <img class="logo" src={offline.src('/logo-mark.svg')} alt="" draggable="false" />
      <h1>{t('Войди в Sonar')}</h1>
      <p class="lead">{t('Аккаунт хранит лайки, плейлисты и настройки и переносит их на телефон и другие компьютеры.')}</p>
      <SignIn />
      <button class="offline" onclick={() => offline.set(true)}>{t('Слушать офлайн без входа')}</button>
    </div>
  </div>
{/if}

<style>
  .gate {
    position: fixed;
    inset: 0;
    z-index: 900;
    display: grid;
    place-items: center;
    background: color-mix(in srgb, var(--bg, #000) 82%, transparent);
    backdrop-filter: blur(18px);
  }
  .controls {
    position: absolute;
    top: 8px;
    right: 8px;
  }
  .card {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--sp-3);
    width: min(420px, calc(100vw - 48px));
    padding: var(--sp-7) var(--sp-6) var(--sp-5);
    border-radius: 24px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  .logo {
    width: 56px;
    height: 56px;
  }
  h1 {
    margin: 0;
    font-size: var(--fs-h2);
  }
  .lead {
    margin: 0 0 var(--sp-2);
    max-width: 320px;
    text-align: center;
    font-size: var(--fs-meta);
    line-height: 1.5;
    color: var(--text-3);
  }
  .offline {
    margin-top: var(--sp-2);
    font-size: var(--fs-meta);
    color: var(--text-3);
    transition: color var(--fast) var(--ease);
  }
  .offline:hover {
    color: var(--text);
  }
</style>
