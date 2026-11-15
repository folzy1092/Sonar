<script lang="ts">
  import NavIcon from '../components/NavIcon.svelte'
  import type { NavIconName } from '../components/nav-icons'
  import { router, type Page } from './router.svelte'
  import logo from '../assets/logo-mark.svg'
  import { settingsPanel } from '../pages/settings-section.svelte'

  const middle: { page: Page; icon: NavIconName; label: string }[] = [
    { page: 'player', icon: 'player', label: 'Плеер' },
    { page: 'search', icon: 'search', label: 'Поиск' },
    { page: 'library', icon: 'library', label: 'Медиатека' },
  ]
</script>

{#snippet item(page: Page, icon: NavIconName, label: string)}
  {@const on = router.page === page || (page === 'library' && ['playlist', 'artist', 'album'].includes(router.page))}
  <button
    class="item"
    class:active={on}
    aria-label={label}
    title={label}
    aria-current={on ? 'page' : undefined}
    onclick={() => {
      settingsPanel.close()
      router.go(page)
    }}
  >
    <NavIcon name={icon} active={on} />
  </button>
{/snippet}

<nav class="rail" data-tauri-drag-region>
  <div class="group" data-tauri-drag-region>
    <img class="logo" src={logo} alt="Sonar" draggable="false" />
    {@render item('home', 'home', 'Главная')}
  </div>

  <div class="group" data-tauri-drag-region>
    {#each middle as m (m.page)}
      {@render item(m.page, m.icon, m.label)}
    {/each}
  </div>

  <div class="group" data-tauri-drag-region>
    <button
      class="item"
      class:active={settingsPanel.open}
      aria-label="Настройки"
      title="Настройки"
      aria-expanded={settingsPanel.open}
      onclick={() => settingsPanel.toggle()}
    >
      <NavIcon name="settings" active={settingsPanel.open} />
    </button>
    <button class="avatar" aria-label="Профиль" title="Профиль — вход появится вместе с сервером">
      <NavIcon name="user" size={20} />
      <span class="online" aria-hidden="true"></span>
    </button>
  </div>
</nav>

<style>
  .rail {
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    align-items: center;
    padding: 14px 0 12px;
    height: 100%;
  }
  .group {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
  }
  .logo {
    width: 34px;
    height: 34px;
    border-radius: 50%;
    margin-bottom: 10px;
    pointer-events: none;
  }
  .item {
    position: relative;
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    color: var(--text-2);
    transition:
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .item:hover {
    color: var(--text);
  }
  .item:active {
    transform: scale(0.9);
  }
  .avatar {
    position: relative;
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    margin-top: 8px;
    border-radius: 50%;
    background: var(--surface-3);
    color: var(--text-2);
    transition: transform var(--fast) var(--ease);
  }
  .avatar:hover {
    transform: scale(1.06);
  }
  .online {
    position: absolute;
    right: -1px;
    bottom: -1px;
    width: 11px;
    height: 11px;
    border-radius: 50%;
    background: var(--online);
    border: 2px solid var(--bg);
  }
</style>
