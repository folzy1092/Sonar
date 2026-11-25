<script lang="ts">
  import NavIcon from '../components/NavIcon.svelte'
  import type { NavIconName } from '../components/nav-icons'
  import { router, type Page } from './router.svelte'
  import LogoMark from '../components/LogoMark.svelte'
  import Cover from '../components/Cover.svelte'
  import Icon from '../components/Icon.svelte'
  import { settingsPanel } from '../pages/settings-section.svelte'
  import { settings } from '../lib/settings.svelte'
  import { t } from '../lib/i18n.svelte'
  import { floating } from '../lib/floating'
  import { offline } from '../lib/offline.svelte'
  import { library } from '../lib/library.svelte'
  import { isTrackRef } from '../lib/services'
  import { tracksText } from '../lib/format'
  import { railPins } from './rail-pins'

  // «Плавающий» стиль: панель — капсула над окном, её тянут куда угодно (lib/floating); за неё окно
  // не таскается. Лежит вдоль, если в «Позиции» выбрано сверху / снизу.
  const float = $derived(settings.get('tabs.style') === 'floating')
  const flat = $derived(float && ['top', 'bottom'].includes(settings.get('tabs.position')))
  const drag = $derived(float ? undefined : true)

  // Панель Sonar (основная с 2026-11-25, чтобы не быть копией колонки Dotify): слева и справа —
  // значки с подписями и плейлисты обложками; клик по знаку раскрывает её в полку с названиями.
  // Сверху и снизу — как обычная полоса значков.
  const sonar = $derived(settings.get('tabs.style') === 'sonar' && ['left', 'right'].includes(settings.get('tabs.position')))
  const open = $derived(sonar && settings.get('tabs.expanded'))
  const pins = $derived(sonar ? railPins(library.playlists) : [])
  const likedCount = $derived(sonar ? [...library.liked].filter(isTrackRef).length : 0)
  const name = $derived(settings.get('profile.name') || settings.get('profile.username') || t('Профиль'))

  // подписи — ключи перевода, t() — при выводе
  const middle: { page: Page; icon: NavIconName; label: string }[] = [
    { page: 'player', icon: 'player', label: 'Плеер' },
    { page: 'search', icon: 'search', label: 'Поиск' },
    { page: 'library', icon: 'library', label: 'Медиатека' },
  ]

  function go(page: Page, param: string | null = null) {
    settingsPanel.close()
    router.go(page, param)
  }
  const isOpenList = (id: string) => router.page === 'playlist' && router.param === id
  /** Открыт плейлист из панели — подсвечен он сам, «Медиатека» не загорается второй. */
  const pinOpen = $derived(sonar && (isOpenList('favorites') || pins.some((p) => isOpenList(p.id))))
</script>

{#snippet item(page: Page, icon: NavIconName, label: string)}
  {@const on = router.page === page || (page === 'home' && router.page === 'mix') || (page === 'library' && ['playlist', 'artist', 'album', 'import'].includes(router.page) && !pinOpen)}
  <button
    class="item"
    class:active={on}
    aria-label={label}
    title={sonar && !open ? null : label}
    aria-current={on ? 'page' : undefined}
    onclick={() => go(page)}
  >
    <NavIcon name={icon} active={on} />
    {#if sonar}<span class="label">{label}</span>{/if}
  </button>
{/snippet}

{#snippet pin(id: string, title: string, sub: string, cover: string | null, liked = false)}
  {@const on = isOpenList(id)}
  <button class="pin" class:on aria-label={title} title={open ? null : title} aria-current={on ? 'page' : undefined} onclick={() => go('playlist', id)}>
    {#if liked}
      <span class="liked"><NavIcon name="heart" active size={18} /></span>
    {:else}
      <Cover url={cover} size={40} radius="10px" />
    {/if}
    {#if open}
      <span class="pin-text">
        <b>{title}</b>
        <i>{sub}</i>
      </span>
    {/if}
  </button>
{/snippet}

<nav class="rail" class:float class:flat class:sonar class:open data-tauri-drag-region={drag} use:floating={{ on: float, key: 'tabs', grabButtons: true }}>
  <div class="group" data-tauri-drag-region={drag}>
    {#if sonar}
      <!-- знак — кнопка: раскрыть / свернуть полку (только кликом, без наведения) -->
      <button
        class="logo toggle"
        aria-label={open ? t('Свернуть панель') : t('Развернуть панель')}
        title={open ? t('Свернуть панель') : t('Развернуть панель')}
        aria-expanded={open}
        onclick={() => settings.set('tabs.expanded', !open)}
      >
        <LogoMark size={30} />
        {#if open}
          <span class="word">Sonar</span>
          <span class="chev"><Icon name="chevronLeft" size={16} /></span>
        {/if}
      </button>
    {:else}
      <!-- за лого окно тоже таскается, как за пустое место панели -->
      <span class="logo" role="img" aria-label="Sonar" data-tauri-drag-region={drag}><LogoMark size={30} /></span>
    {/if}
    {@render item('home', 'home', t('Главная'))}
    {#if sonar}
      {#each middle as m (m.page)}
        {@render item(m.page, m.icon, t(m.label))}
      {/each}
    {/if}
  </div>

  {#if sonar}
    <div class="pins">
      {#if open}<span class="cap">{t('Плейлисты')}</span>{:else}<span class="rule" aria-hidden="true"></span>{/if}
      {@render pin('favorites', t('Любимые'), tracksText(likedCount), null, true)}
      {#each pins as p (p.id)}
        {@render pin(p.id, p.name, tracksText(p.track_count), p.covers[0] ?? null)}
      {/each}
    </div>
  {:else}
    <div class="group" data-tauri-drag-region={drag}>
      {#each middle as m (m.page)}
        {@render item(m.page, m.icon, t(m.label))}
      {/each}
    </div>
  {/if}

  <div class="group foot" data-tauri-drag-region={drag}>
    <button
      class="item gear"
      class:active={settingsPanel.open}
      aria-label={t('Настройки')}
      title={t('Настройки')}
      aria-expanded={settingsPanel.open}
      onclick={() => settingsPanel.toggle()}
    >
      <NavIcon name="settings" active={settingsPanel.open} />
    </button>
    <button class="avatar" aria-label={t('Профиль')} title={open ? null : t('Профиль')} onclick={() => settingsPanel.show('account', 'profile')}>
      <span class="face">
        {#if settings.get('profile.avatar')}
          <img class="me" src={offline.src(settings.get('profile.avatar'))} alt="" />
        {:else}
          <NavIcon name="user" size={20} />
        {/if}
        <span class="online" aria-hidden="true"></span>
      </span>
      {#if open}<span class="who">{name}</span>{/if}
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
  :global(:root[data-nav='capsule']) .item,
  :global(:root[data-nav='inset']) .item {
    border-radius: 999px;
  }
  :global(:root[data-nav='capsule']) .item.active {
    background-color: var(--accent);
    color: var(--accent-ink);
    --knob-fill: var(--accent);
  }
  /* капсула — вытянута вдоль панели */
  :global(:root[data-nav='capsule']) .item {
    width: 38px;
    height: 50px;
  }
  :global(:root[data-nav='capsule'] .shell.tabs-top) .item,
  :global(:root[data-nav='capsule'] .shell.tabs-bottom) .item {
    width: 50px;
    height: 38px;
  }
  /* иконка на капсуле — цветом текста на акценте, иначе акцент на акценте сливается в пятно */
  :global(:root[data-nav='capsule']) .item.active :global(.ni) {
    --accent: var(--accent-ink);
  }
  :global(:root[data-nav='plate']) .item.active {
    background-color: var(--surface-2);
    box-shadow:
      inset 0 0 0 1px var(--border),
      inset 0 1px 0 oklch(1 0 0 / 0.07);
    --knob-fill: var(--surface-2);
  }
  :global(:root[data-nav='inset']) .item.active {
    background-color: color-mix(in oklch, var(--accent) 8%, var(--surface-1));
    box-shadow:
      inset 0 1px 3px oklch(0 0 0 / 0.45),
      inset 0 -1px 0 oklch(1 0 0 / 0.05);
    --knob-fill: color-mix(in oklch, var(--accent) 8%, var(--surface-1));
  }
  .item:active {
    transform: scale(0.9);
  }
  .avatar {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-top: 8px;
    border-radius: 999px;
    color: var(--text);
  }
  .face {
    position: relative;
    flex: none;
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
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
  .avatar:hover .face {
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
  /* плавающий — капсула над окном, стоит где поставили (lib/floating, tabs.float_x / _y) */
  .rail.float {
    position: fixed;
    z-index: 25;
    justify-content: center;
    gap: 22px;
    height: auto;
    margin: 0;
    padding: 12px 0;
    cursor: grab;
    touch-action: none;
    box-shadow:
      0 18px 40px oklch(0 0 0 / 0.35),
      var(--sheen);
  }
  .rail.float:global(.dragging) {
    cursor: grabbing;
    transition: none;
  }
  .rail.float.flat {
    flex-direction: row;
    width: auto;
    height: calc(var(--rail-w) - var(--gap));
    padding: 0 14px;
  }
  .rail.float.flat .group {
    flex-direction: row;
  }
  .rail.float.flat .logo {
    margin: 0 8px 0 0;
  }
  .rail.float.flat .avatar {
    margin: 0 0 0 8px;
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

  /* ---- панель Sonar (tabs.style = sonar, слева и справа) ---- */
  /* колонка шире прежней (84 px вместо 62), раскрытая полка — 244 px; ширина едет плавно (--rail-w) */
  :global(.shell.tstyle-sonar:is(.tabs-left, .tabs-right)) {
    --rail-w: 90px;
  }
  :global(.shell.tstyle-sonar:is(.tabs-left, .tabs-right):has(> .rail.open)) {
    --rail-w: 250px;
  }
  .rail.sonar {
    justify-content: flex-start;
    gap: 14px;
    overflow: hidden;
  }
  .rail.sonar .group {
    gap: 2px;
  }
  .rail.sonar .logo.toggle {
    display: flex;
    align-items: center;
    gap: 10px;
    width: auto;
    margin-bottom: 10px;
    padding: 0 5px;
    border-radius: 999px;
    cursor: pointer;
    color: var(--text);
  }
  .rail.sonar .word {
    font-size: 17px;
    font-weight: 700;
    letter-spacing: -0.01em;
  }
  .rail.sonar .chev {
    margin-left: auto;
    display: grid;
    color: var(--text-3);
    transition: color var(--fast) var(--ease);
  }
  .rail.sonar .logo.toggle:hover .chev {
    color: var(--text);
  }
  /* свёрнута: значок, под ним подпись */
  .rail.sonar .item {
    flex-direction: column;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 4px;
    width: 70px;
    height: 58px;
    border-radius: 14px;
  }
  .rail.sonar .label {
    max-width: 100%;
    overflow: hidden;
    font-size: 10.5px;
    font-weight: 500;
    line-height: 1.2;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .rail.sonar .item.gear {
    width: 44px;
    height: 44px;
  }
  /* плейлисты: Любимые и свои, свежие сверху; не влезли — прокрутка внутри, без полосы */
  .pins {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    width: 100%;
    padding: 4px 0 20px;
    overflow-y: auto;
    scrollbar-width: none;
    /* не влезли — нижние гаснут, а не режутся по краю */
    mask-image: linear-gradient(to bottom, #000 calc(100% - 28px), transparent);
  }
  .rule {
    flex: none;
    width: 32px;
    height: 1px;
    margin-bottom: 4px;
    background: var(--border);
  }
  .pin {
    position: relative;
    flex: none;
    display: flex;
    align-items: center;
    gap: 10px;
    border-radius: 12px;
    transition:
      transform var(--fast) var(--ease),
      background-color var(--fast) var(--ease);
  }
  .pin:active {
    transform: scale(0.94);
  }
  /* открытый плейлист — полоска у края панели и рамка вокруг обложки */
  .pin::before {
    content: '';
    position: absolute;
    left: -21px;
    top: 50%;
    width: 4px;
    height: 0;
    border-radius: 0 4px 4px 0;
    background: var(--accent);
    translate: 0 -50%;
    transition: height 0.32s cubic-bezier(0.22, 1, 0.36, 1);
  }
  .pin.on::before {
    height: 24px;
  }
  .pin :global(.cover),
  .liked {
    box-shadow: 0 0 0 0 transparent;
    transition: box-shadow var(--fast) var(--ease);
  }
  .pin.on :global(.cover),
  .pin.on .liked {
    box-shadow: 0 0 0 2px var(--bg), 0 0 0 3.5px var(--text-2);
  }
  .liked {
    flex: none;
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    border-radius: 10px;
    background: linear-gradient(135deg, var(--surface-3), var(--surface-2));
    color: var(--text);
    --accent: var(--text);
  }
  .rail.sonar .foot {
    margin-top: auto;
  }
  .rail.sonar .avatar {
    margin-top: 6px;
  }

  /* раскрыта: строки «значок · название», плейлисты с подписью, внизу профиль и шестерёнка в ряд */
  .rail.open {
    align-items: stretch;
    padding: 14px 10px 12px;
    border-radius: var(--radius-xl);
  }
  .rail.open .group {
    align-items: stretch;
  }
  .rail.open .logo.toggle {
    padding: 0 6px 0 5px;
    height: 40px;
  }
  .rail.open .item {
    flex-direction: row;
    justify-content: flex-start;
    gap: 12px;
    width: 100%;
    height: 40px;
    padding: 0 12px;
    border-radius: var(--radius-m);
  }
  .rail.open .label {
    font-size: 14px;
  }
  .rail.open .pins {
    align-items: stretch;
    gap: 2px;
  }
  .cap {
    flex: none;
    padding: 4px 8px 6px;
    font-size: 12px;
    font-weight: 500;
    color: var(--text-3);
  }
  .rail.open .pin {
    padding: 5px 6px;
    text-align: left;
  }
  .rail.open .pin:hover,
  .rail.open .pin.on {
    background-color: var(--surface-2);
  }
  .rail.open .pin::before {
    display: none;
  }
  .rail.open .pin.on :global(.cover),
  .rail.open .pin.on .liked {
    box-shadow: none;
  }
  .pin-text {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 1px;
  }
  .pin-text b,
  .pin-text i {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .pin-text b {
    font-size: 13px;
    font-weight: 500;
    color: var(--text);
  }
  .pin-text i {
    font-style: normal;
    font-size: 11.5px;
    color: var(--text-3);
  }
  .rail.open .foot {
    flex-direction: row-reverse;
    justify-content: space-between;
    align-items: center;
    padding: 10px 2px 0 4px;
    border-top: 1px solid var(--border);
  }
  .rail.open .avatar {
    min-width: 0;
    margin: 0;
    padding-right: 8px;
  }
  .who {
    overflow: hidden;
    font-size: 13px;
    font-weight: 500;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .rail.open .item.gear {
    width: 40px;
    padding: 0;
    justify-content: center;
  }
  /* подписи проявляются, когда полка уже почти раскрылась, — не лезут поверх едущей ширины */
  .rail.open :is(.label, .word, .chev, .cap, .pin-text, .who) {
    animation: rail-text 0.26s var(--ease) 0.12s both;
  }
  @keyframes rail-text {
    from {
      opacity: 0;
      translate: -4px 0;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .rail.open :is(.label, .word, .chev, .cap, .pin-text, .who) {
      animation-name: rail-fade;
    }
    @keyframes rail-fade {
      from {
        opacity: 0;
      }
    }
  }
  /* справа — полоска открытого плейлиста у правого края */
  :global(.shell.tabs-right) .pin::before {
    left: auto;
    right: -21px;
    border-radius: 4px 0 0 4px;
  }
</style>
