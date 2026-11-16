<script lang="ts">
  import NavIcon from '../components/NavIcon.svelte'
  import type { NavIconName } from '../components/nav-icons'
  import { router, type Page } from './router.svelte'
  import LogoMark from '../components/LogoMark.svelte'
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
    <!-- за лого окно тоже таскается, как за пустое место панели -->
    <span class="logo" role="img" aria-label="Sonar" data-tauri-drag-region><LogoMark size={30} /></span>
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
  /* панель — капсула, как мини-плеер: та же поверхность, рамка и скругление концов (--cap-k) */
  .rail {
    display: flex;
    flex-direction: column;
    justify-content: space-between;
    align-items: center;
    box-sizing: border-box;
    width: calc(var(--rail-w) - var(--gap));
    height: calc(100% - var(--gap));
    margin: var(--gap) 0 0 var(--gap);
    padding: 14px 0 12px;
    border-radius: max(var(--radius-l), calc((var(--rail-w) - var(--gap)) / 2 * var(--cap-k, 1)));
    background: var(--surface-1);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    transition:
      background 0.4s var(--ease),
      border-radius 0.4s var(--ease);
  }
  .group {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
  }
  .logo {
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    margin-bottom: 8px;
    cursor: default;
  }
  /* клик по знаку уходит в саму область перетаскивания; пол-оборота при наведении — от неё */
  .logo :global(*) {
    pointer-events: none;
  }
  .logo:hover :global(.mark.spin) {
    rotate: 180deg;
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
  /* Выбранный раздел (appearance.anim_nav): точка акцента слева / капсула акцента / плашка
     поверхности 2 с гранью и бликом / утопленная плашка. Сама иконка двигает деталь (NavIcon). */
  .item {
    border-radius: var(--radius-m);
    --knob-fill: var(--surface-1);
    transition:
      color var(--fast) var(--ease),
      background-color 0.32s cubic-bezier(0.22, 1, 0.36, 1),
      box-shadow 0.32s cubic-bezier(0.22, 1, 0.36, 1),
      transform var(--fast) var(--ease);
  }
  .item.active {
    color: var(--text);
  }
  .item::before {
    content: '';
    position: absolute;
    left: -5px;
    top: 50%;
    width: 5px;
    height: 5px;
    margin-top: -2.5px;
    border-radius: 50%;
    background: var(--accent);
    opacity: 0;
    scale: 0;
    transition:
      opacity 0.32s cubic-bezier(0.22, 1, 0.36, 1),
      scale 0.32s cubic-bezier(0.22, 1, 0.36, 1);
  }
  :global(:root[data-nav='dot']) .item.active::before {
    opacity: 1;
    scale: 1;
  }
  :global(:root[data-nav='capsule']) .item.active {
    background-color: var(--accent);
    color: var(--accent-ink);
    --knob-fill: var(--accent);
  }
  :global(:root[data-nav='plate']) .item.active {
    background-color: var(--surface-2);
    box-shadow:
      inset 0 0 0 1px var(--border),
      inset 0 1px 0 oklch(1 0 0 / 0.07);
    --knob-fill: var(--surface-2);
  }
  :global(:root[data-nav='inset']) .item.active {
    background-color: color-mix(in oklch, var(--surface-1) 70%, #000);
    box-shadow: inset 0 2px 4px oklch(0 0 0 / 0.5);
    --knob-fill: color-mix(in oklch, var(--surface-1) 70%, #000);
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
    border: 2px solid var(--surface-1);
  }
</style>
