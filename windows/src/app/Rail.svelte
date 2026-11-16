<script lang="ts">
  import NavIcon from '../components/NavIcon.svelte'
  import type { NavIconName } from '../components/nav-icons'
  import { router, type Page } from './router.svelte'
  import LogoMark from '../components/LogoMark.svelte'
  import { settingsPanel } from '../pages/settings-section.svelte'
  import { settings } from '../lib/settings.svelte'
  import { t } from '../lib/i18n.svelte'

  // подписи — ключи перевода, t() — при выводе
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
    {@render item('home', 'home', t('Главная'))}
  </div>

  <div class="group" data-tauri-drag-region>
    {#each middle as m (m.page)}
      {@render item(m.page, m.icon, t(m.label))}
    {/each}
  </div>

  <div class="group" data-tauri-drag-region>
    <button
      class="item"
      class:active={settingsPanel.open}
      aria-label={t('Настройки')}
      title={t('Настройки')}
      aria-expanded={settingsPanel.open}
      onclick={() => settingsPanel.toggle()}
    >
      <NavIcon name="settings" active={settingsPanel.open} />
    </button>
    <button class="avatar" aria-label={t('Профиль')} title={t('Профиль')} onclick={() => settingsPanel.show('account', 'profile')}>
      {#if settings.get('profile.avatar')}
        <img class="me" src={settings.get('profile.avatar')} alt="" />
      {:else}
        <NavIcon name="user" size={20} />
      {/if}
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
  /* Выбранный раздел (appearance.anim_nav): только залитая иконка (без точки — решение владельца
     2026-11-17) / капсула акцента / плашка поверхности 2 с гранью и бликом / утопленная плашка. */
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
  .avatar .me {
    width: 100%;
    height: 100%;
    border-radius: 50%;
    object-fit: cover;
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

  /* ---- позиция вкладок (tabs.position, сетка — App.svelte) ---- */
  :global(.shell.tabs-right) .rail {
    margin: var(--gap) var(--gap) 0 0;
  }
  :global(.shell.tabs-top) .rail,
  :global(.shell.tabs-bottom) .rail {
    flex-direction: row;
    width: 100%;
    height: calc(var(--rail-w) - var(--gap));
    padding: 0 14px;
    border-radius: max(var(--radius-l), calc((var(--rail-w) - var(--gap)) / 2 * var(--cap-k, 1)));
  }
  /* сверху и снизу — компактный островок из иконок по центру, без растяжки на всю ширину
     (решение владельца 2026-11-17); во всю ширину — только стиль «Полный» */
  :global(.shell.tabs-top:not(.tstyle-full)) .rail,
  :global(.shell.tabs-bottom:not(.tstyle-full)) .rail {
    position: relative;
    z-index: 1;
    justify-self: center;
    justify-content: center;
    width: auto;
    gap: 18px;
    padding: 0 12px;
  }
  :global(.shell.tabs-top) .rail {
    margin: var(--gap) 0 0;
  }
  :global(.shell.tstyle-full.tabs-top) .rail {
    /* правый конец — под кнопки окна */
    padding-right: 150px;
  }
  :global(.shell.tabs-bottom) .rail {
    margin: 0;
  }
  :global(.shell.tabs-top) .group,
  :global(.shell.tabs-bottom) .group {
    flex-direction: row;
  }
  :global(.shell.tabs-top) .logo,
  :global(.shell.tabs-bottom) .logo {
    margin: 0 8px 0 0;
  }
  :global(.shell.tabs-top) .avatar,
  :global(.shell.tabs-bottom) .avatar {
    margin: 0 0 0 8px;
  }
  /* ---- стиль вкладок (tabs.style) ---- */
  /* компактный — уже и плотнее */
  :global(.shell.tstyle-compact) {
    --rail-w: 56px;
  }
  :global(.shell.tstyle-compact) .item {
    width: 38px;
    height: 38px;
  }
  :global(.shell.tstyle-compact) .group {
    gap: 2px;
  }
  /* полный — во всю высоту окна, прижат к краю, без капсулы */
  :global(.shell.tstyle-full) .rail {
    margin: 0;
    height: 100%;
    border-radius: 0;
    border-width: 0 1px 0 0;
  }
  :global(.shell.tstyle-full.tabs-right) .rail {
    border-width: 0 0 0 1px;
  }
  :global(.shell.tstyle-full.tabs-top) .rail,
  :global(.shell.tstyle-full.tabs-bottom) .rail {
    width: calc(100% + 2 * var(--gap));
    height: calc(var(--rail-w) - var(--gap) / 2);
    margin: 0 calc(-1 * var(--gap));
    border-width: 0 0 1px;
  }
  :global(.shell.tstyle-full.tabs-bottom) .rail {
    border-width: 1px 0 0;
  }
  /* круглый — каждая вкладка в круге */
  :global(.shell.tstyle-round) .item {
    border-radius: 50%;
    background-color: var(--surface-2);
  }
  :global(.shell.tstyle-round) .item.active {
    border-radius: 50%;
  }
  /* плавающий — островок по размеру содержимого, парит над фоном */
  :global(.shell.tstyle-floating) .rail {
    align-self: center;
    justify-content: center;
    gap: 22px;
    height: auto;
    padding: 12px 0;
    margin-top: 0;
    box-shadow:
      0 18px 40px oklch(0 0 0 / 0.35),
      var(--sheen);
  }
  :global(.shell.tstyle-floating.tabs-top) .rail,
  :global(.shell.tstyle-floating.tabs-bottom) .rail {
    justify-self: center;
    width: auto;
    padding: 0 14px;
    gap: 22px;
  }

  /* подстраивать вкладки — цвет панели от страницы (подкраска обложки) */
  :global(:root.tabs-adapt) .rail {
    background: color-mix(in oklch, var(--tint) 55%, var(--surface-1));
  }
  /* скрытие элементов — мышь замерла: панель гаснет, наведение возвращает */
  .rail {
    transition:
      background 0.4s var(--ease),
      border-radius 0.4s var(--ease),
      opacity 0.4s var(--ease),
      translate 0.4s var(--ease);
  }
  :global(:root.tabs-autohide.ui-still) .rail:not(:hover) {
    opacity: 0;
    translate: -6px 0;
  }
  :global(:root.tabs-autohide.ui-still .shell.tabs-right) .rail:not(:hover) {
    translate: 6px 0;
  }
  :global(:root.tabs-autohide.ui-still .shell.tabs-top) .rail:not(:hover) {
    translate: 0 -6px;
  }
  :global(:root.tabs-autohide.ui-still .shell.tabs-bottom) .rail:not(:hover) {
    translate: 0 6px;
  }
</style>
