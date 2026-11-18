<script lang="ts">
  // Панель настроек: слева боковое меню (решение владельца 2026-11-18 — вместо вкладок и капсул): карточка
  // профиля, группы Аккаунт · Приложение · Интерфейс (NAV), поиск внизу; справа заголовок и раздел. Вкладки окна
  // сбоку — панель выезжает с той же стороны, а окно уходит вглубь (App.svelte), как в Dotify; сверху
  // или снизу — панель шторкой опускается (поднимается), окно стоит под вуалью (NEXT_PROMPT «Этап 0» п. 7).
  // Ширина — во всё окно с полями, содержимое в 1–2 колонки по ширине (п. 6).
  import { tick } from 'svelte'
  import '../components/settings/settings-row.css'
  import SettingsSearch from '../components/settings/SettingsSearch.svelte'
  import SearchResults from '../components/settings/SearchResults.svelte'
  import { SUB_LEADS, type CatalogEntry } from '../lib/settings-catalog'
  import { jumpToSetting } from '../lib/settings-jump'
  import { SHUTTER_MS, isShutter, openMode, springEasing, veilClip, type Box } from '../lib/settings-open'
  import { settings } from '../lib/settings.svelte'
  import Icon from '../components/Icon.svelte'
  import Services from './settings/Services.svelte'
  import Stats from './settings/Stats.svelte'
  import Audio from './settings/Audio.svelte'
  import Look from './settings/Look.svelte'
  import Style from './settings/Style.svelte'
  import Profile from './settings/Profile.svelte'
  import Privacy from './settings/Privacy.svelte'
  import Notifications from './settings/Notifications.svelte'
  import Subscription from './settings/Subscription.svelte'
  import PlayerView from './settings/PlayerView.svelte'
  import Integrations from './settings/Integrations.svelte'
  import General from './settings/General.svelte'
  import Hotkeys from './settings/Hotkeys.svelte'
  import Remote from './settings/Remote.svelte'
  import Storage from './settings/Storage.svelte'
  import Update from './settings/Update.svelte'
  import About from './settings/About.svelte'
  import Mini from './settings/Mini.svelte'
  import Overlay from './settings/Overlay.svelte'
  import { NAV, navSub, settingsPanel, type SettingsTab } from './settings-section.svelte'
  import { profileInitial } from '../lib/public-profile'
  import { subscriptionOf } from '../lib/subscription'
  import DevBadge from '../components/profile/DevBadge.svelte'
  import { cleanUsername } from '../lib/avatar'
  import { t } from '../lib/i18n.svelte'

  let scroller: HTMLDivElement | undefined = $state()
  const sub = $derived(settingsPanel.sub)
  /** Страницы из строк настроек — в широкой панели раскладываются в две колонки. */
  const COLUMN_SUBS = ['look', 'audio', 'view', 'mini']

  const name = $derived(settings.get('profile.name').trim())
  const username = $derived(cleanUsername(settings.get('profile.username')))
  const avatar = $derived(settings.get('profile.avatar'))
  const dev = $derived(subscriptionOf({ username }).tier === 'dev')
  const initial = $derived(profileInitial({ display_name: name, username: username || null }))

  function go(tab: SettingsTab, s: string) {
    query = ''
    settingsPanel.show(tab, s)
  }

  let query = $state('')
  const searching = $derived(query.trim().length > 0)

  $effect(() => {
    settingsPanel.tab
    settingsPanel.sub
    scroller?.scrollTo({ top: 0 })
  })

  /** Пункт из поиска: открыть его раздел, дождаться страницы и докрутить до самой настройки. */
  async function pick(entry: CatalogEntry) {
    query = ''
    settingsPanel.show(entry.tab, entry.sub)
    await tick()
    requestAnimationFrame(() => scroller && void jumpToSetting(scroller, t(entry.title)))
  }

  // Шторка: вкладки окна сверху или снизу (плавающие — как слева)
  const shutter = $derived(isShutter(openMode(settings.get('tabs.position'), settings.get('tabs.style'))))
  const easing = springEasing()
  /** Где панель вкладок окна: шторка выходит из-под неё, вуаль её не затемняет. */
  let rail = $state<Box | null>(null)

  $effect(() => {
    settingsPanel.open
    settings.get('tabs.position')
    if (!shutter) return
    const el = document.querySelector<HTMLElement>('.shell .rail')
    if (!el) return
    const measure = () => {
      const r = el.getBoundingClientRect()
      rail = { left: r.left, top: r.top, right: r.right, bottom: r.bottom }
    }
    const raf = requestAnimationFrame(measure)
    const observer = new ResizeObserver(measure)
    observer.observe(el)
    window.addEventListener('resize', measure)
    return () => {
      cancelAnimationFrame(raf)
      observer.disconnect()
      window.removeEventListener('resize', measure)
    }
  })

  const edgeTop = $derived(rail && settings.get('tabs.position') === 'top' ? rail.bottom : 0)
  const edgeBottom = $derived(rail && settings.get('tabs.position') === 'bottom' ? window.innerHeight - rail.top : 0)
</script>

{#if shutter}
  <!-- вуаль над окном: оно не двигается, только темнеет и чуть размывается; клик — закрыть -->
  <button
    class="veil"
    class:open={settingsPanel.open}
    tabindex="-1"
    aria-label={t('Закрыть настройки')}
    style:clip-path={veilClip(rail)}
    onclick={() => settingsPanel.close()}
  ></button>
{/if}

<aside
  class="panel"
  class:open={settingsPanel.open}
  class:shutter
  class:from-top={shutter && settings.get('tabs.position') === 'top'}
  class:from-bottom={shutter && settings.get('tabs.position') === 'bottom'}
  style:--edge-top="{edgeTop}px"
  style:--edge-bottom="{edgeBottom}px"
  style:--shutter-t="{SHUTTER_MS}ms"
  style:--shutter-ease={easing}
  inert={!settingsPanel.open}
  data-fx-skip={settingsPanel.open ? undefined : ''}
  aria-label={t('Настройки')}
>
  <div class="layout">
  <nav class="side" aria-label={t('Разделы настроек')} data-tauri-drag-region>
    <button
      class="me press"
      class:on={!searching && settingsPanel.tab === 'account' && sub === 'profile'}
      onclick={() => go('account', 'profile')}
      title={t('Профиль')}
    >
      <span class="ava">
        {#if avatar}<img src={avatar} alt="" />{:else}{initial}{/if}
      </span>
      <span class="who">
        <b>{name || t('Без имени')}</b>
        <span class="handle">
          <small>{username ? `@${username}` : t('Задать @username')}</small>
          {#if dev}<DevBadge size={9.5} />{/if}
        </span>
      </span>
    </button>

    <div class="groups">
      {#each NAV as g (g.title)}
        <div class="group">
          <b class="gtitle">{t(g.title)}</b>
          <div class="items">
            {#each g.items as it (it.tab + it.sub)}
              {@const info = navSub(it.tab, it.sub)}
              {#if info}
                <button
                  class="item"
                  class:on={!searching && settingsPanel.tab === it.tab && sub === it.sub}
                  class:off={info.soon || info.lock}
                  disabled={info.soon || info.lock}
                  title={info.soon ? t('{title} — скоро, вместе с сервером', { title: t(info.title) }) : t(info.title)}
                  onclick={() => go(it.tab, it.sub)}
                >
                  <Icon name={info.icon} size={17} />
                  <span>{t(info.title)}</span>
                </button>
              {/if}
            {/each}
          </div>
        </div>
      {/each}
    </div>

    <div class="find-row">
      <SettingsSearch bind:query />
    </div>
  </nav>

  <div class="main">
  <div class="scroll" bind:this={scroller}>
    {#if searching}
      <SearchResults query={query.trim()} onpick={pick} />
    {:else}
      {#key `${settingsPanel.tab}:${sub}`}
        <div class="tab-in page">
          <h1 class="title">{t(navSub(settingsPanel.tab, sub)?.title ?? '')}</h1>
          {#if SUB_LEADS[sub]}<p class="lead">{t(SUB_LEADS[sub])}</p>{/if}
          <div class="body" class:cols={COLUMN_SUBS.includes(sub)}>
            {#if sub === 'stats'}
              <Stats />
            {:else if sub === 'profile'}
              <Profile />
            {:else if sub === 'privacy'}
              <Privacy />
            {:else if sub === 'plans'}
              <Subscription />
            {:else if sub === 'style'}
              <Style />
            {:else if sub === 'look'}
              <Look />
            {:else if sub === 'mini'}
              <Mini />
            {:else if sub === 'overlay'}
              <Overlay />
            {:else if sub === 'audio'}
              <Audio />
            {:else if sub === 'view'}
              <PlayerView />
            {:else if sub === 'services'}
              <Services />
            {:else if sub === 'apps'}
              <Integrations />
            {:else if sub === 'general'}
              <General />
            {:else if sub === 'hotkeys'}
              <Hotkeys />
            {:else if sub === 'remote'}
              <Remote />
            {:else if sub === 'storage'}
              <Storage />
            {:else if sub === 'update'}
              <Update />
            {:else if sub === 'notifications'}
              <Notifications />
            {:else if sub === 'about'}
              <About />
            {/if}
          </div>
        </div>
      {/key}
    {/if}
  </div>
  </div>
  </div>
</aside>

<style>
  .panel {
    position: fixed;
    inset: 0 auto 0 0;
    z-index: 30;
    display: flex;
    flex-direction: column;
    width: var(--settings-w);
    container-type: inline-size;
    background: var(--surface-0);
    border-right: 1px solid var(--border);
    /* как в Dotify: панель выезжает слева одновременно с уходом окна вглубь и так же уезжает */
    transform: translateX(-100%);
    transition: transform var(--settings-t) var(--settings-ease);
    will-change: transform;
  }
  .panel.open {
    transform: none;
  }
  /* Шторка (вкладки окна сверху или снизу): панель во всю ширину с полями выходит из-под панели
     вкладок — сверху вниз или снизу вверх, пружиной ~350 мс. Окно не двигается, лежит под вуалью. */
  .panel.shutter {
    --shutter-r: var(--radius-xl);
    z-index: 40;
    inset: calc(var(--edge-top) + var(--gap)) var(--gap) calc(var(--edge-bottom) + var(--gap));
    width: auto;
    border: 1px solid var(--card-line);
    border-radius: var(--shutter-r);
    box-shadow: 0 24px 70px rgba(0, 0, 0, 0.5);
    clip-path: inset(0 round var(--shutter-r));
    transform: none;
    opacity: 1;
    transition:
      clip-path var(--shutter-t) var(--shutter-ease),
      transform var(--shutter-t) var(--shutter-ease),
      opacity calc(var(--shutter-t) * 0.6) var(--ease);
    will-change: clip-path, transform;
  }
  .panel.shutter:not(.open) {
    opacity: 0;
    pointer-events: none;
  }
  .panel.from-top:not(.open) {
    clip-path: inset(0 0 100% 0 round var(--shutter-r));
    transform: translateY(-16px);
  }
  .panel.from-bottom:not(.open) {
    clip-path: inset(100% 0 0 0 round var(--shutter-r));
    transform: translateY(16px);
  }
  /* «Меньше движения» — шторка только проявляется, без сдвига и раскрытия */
  @media (prefers-reduced-motion: reduce) {
    .panel.shutter:not(.open) {
      clip-path: inset(0 round var(--shutter-r));
      transform: none;
    }
    .veil {
      backdrop-filter: none;
    }
  }
  :global(:root.no-motion) .panel.shutter:not(.open) {
    clip-path: inset(0 round var(--shutter-r));
    transform: none;
  }
  :global(:root.no-motion) .veil {
    backdrop-filter: none;
  }
  .veil {
    position: fixed;
    inset: 0;
    z-index: 35;
    background: rgba(0, 0, 0, 0.45);
    backdrop-filter: blur(3px) saturate(0.9);
    opacity: 0;
    pointer-events: none;
    cursor: pointer;
    transition: opacity var(--shutter-t, 350ms) var(--ease);
  }
  .veil.open {
    opacity: 1;
    pointer-events: auto;
  }
  /* панель вкладок справа — настройки зеркально выезжают справа (App.svelte, :root.side-right) */
  :global(:root.side-right) .panel {
    inset: 0 0 0 auto;
    border-right: 0;
    border-left: 1px solid var(--border);
    transform: translateX(100%);
  }
  :global(:root.side-right) .panel.open {
    transform: none;
  }
  .layout {
    flex: 1;
    min-height: 0;
    display: grid;
    grid-template-columns: 236px minmax(0, 1fr);
  }
  .side {
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-height: 0;
    padding: 14px 10px 12px 14px;
    border-right: 1px solid var(--border);
  }
  .me {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px;
    border-radius: 14px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    text-align: left;
    transition:
      background var(--fast) var(--ease),
      border-color var(--fast) var(--ease);
  }
  .me:hover {
    background: var(--hover);
  }
  .me.on {
    border-color: color-mix(in srgb, var(--accent) 50%, transparent);
  }
  .ava {
    display: grid;
    place-items: center;
    flex: none;
    width: 40px;
    height: 40px;
    overflow: hidden;
    border-radius: 50%;
    background: var(--accent);
    color: var(--accent-ink);
    font-weight: 800;
  }
  .ava img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .who {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .who b,
  .who small {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .who small {
    color: var(--text-3);
  }
  .handle {
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
  }
  .groups {
    --fade: 24px;
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    gap: 14px;
    overflow-y: auto;
    scrollbar-width: none;
  }
  .gtitle {
    display: block;
    margin: 0 4px 6px;
    font-size: calc(14px * var(--fs, 1));
  }
  .items {
    display: flex;
    flex-direction: column;
    padding: 4px;
    border-radius: 14px;
    background: var(--plate);
    border: 1px solid var(--card-line);
  }
  .item {
    display: flex;
    align-items: center;
    gap: 10px;
    height: 36px;
    padding: 0 10px;
    border-radius: 10px;
    color: var(--text-2);
    font-size: calc(13.5px * var(--fs, 1));
    text-align: left;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .item span {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .item:hover:not(:disabled) {
    background: var(--hover);
    color: var(--text);
  }
  .item.on {
    background: var(--hover);
    color: var(--text);
    font-weight: 700;
  }
  .item.off {
    opacity: 0.45;
    cursor: default;
  }
  .find-row {
    display: flex;
  }
  .find-row :global(.find) {
    flex: 1;
    max-width: none;
  }
  .main {
    display: flex;
    flex-direction: column;
    min-width: 0;
    min-height: 0;
  }
  .title {
    margin: 0 0 12px;
    font-size: calc(26px * var(--fs, 1));
    font-weight: 800;
    letter-spacing: -0.02em;
  }
  /* узкая панель — меню одними значками */
  @container (max-width: 640px) {
    .layout {
      grid-template-columns: 64px minmax(0, 1fr);
    }
    .who,
    .item span,
    .gtitle,
    .find-row {
      display: none;
    }
    .me,
    .item {
      justify-content: center;
      padding: 8px 0;
    }
  }
  .scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    /* поля растут с шириной окна; колонки считаются от ширины самой панели (container), а не окна */
    padding: 16px clamp(16px, 3vw, 48px) 32px;
    container-type: inline-size;
  }
  .page {
    max-width: 1240px;
    margin: 0 auto;
  }
  .lead {
    margin: 0 0 10px;
    color: var(--text-3);
    font-size: calc(13px * var(--fs, 1));
  }
  /* две колонки в широкой панели; блок целиком в одной колонке, «Ещё настройки» — на всю ширину */
  @container (min-width: 860px) {
    .cols,
    .cols :global([data-more] .inner) {
      column-count: 2;
      column-gap: 48px;
    }
  }
  .cols > :global(*),
  .cols :global([data-more] .inner > *) {
    break-inside: avoid;
  }
  /* найденный поиском пункт коротко подсвечен (lib/settings-jump.ts) */
  .scroll :global(.flash) {
    border-radius: 12px;
    transition: background-color 0.6s var(--ease) !important;
  }
  .scroll :global(.flash.found) {
    background-color: color-mix(in srgb, var(--accent) 16%, transparent);
  }
</style>
