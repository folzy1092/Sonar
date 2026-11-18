<script lang="ts">
  import { hscroll } from '../lib/hscroll'
  import { edges } from '../lib/edges'
  // Панель настроек (reference/pc/Screenshot_30..32): сверху поиск по настройкам, вкладки разделов,
  // под ними капсулы подразделов (docs/PLATFORMS.md «Настройки — одинаковые разделы»). Вкладки окна
  // сбоку — панель выезжает с той же стороны, а окно уходит вглубь (App.svelte), как в Dotify; сверху
  // или снизу — панель шторкой опускается (поднимается), окно стоит под вуалью (NEXT_PROMPT «Этап 0» п. 7).
  // Ширина — во всё окно с полями, содержимое в 1–2 колонки по ширине (п. 6).
  import { tick } from 'svelte'
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
  import PlayerView from './settings/PlayerView.svelte'
  import Integrations from './settings/Integrations.svelte'
  import General from './settings/General.svelte'
  import Hotkeys from './settings/Hotkeys.svelte'
  import Remote from './settings/Remote.svelte'
  import Storage from './settings/Storage.svelte'
  import Update from './settings/Update.svelte'
  import TabsView from './settings/TabsView.svelte'
  import Queue from './settings/Queue.svelte'
  import Mini from './settings/Mini.svelte'
  import { settingsPanel, SUBS, TABS } from './settings-section.svelte'
  import { indicator } from '../lib/indicator'
  import { t } from '../lib/i18n.svelte'

  let scroller: HTMLDivElement | undefined = $state()
  let tabsEl: HTMLElement | undefined = $state()
  /** Есть ли вкладки за краем строки — тогда край затухает и появляется стрелка (как у подразделов). */
  let more = $state({ l: false, r: false })
  /** Стрелка: плавно до другого конца строки вкладок (свой кадровый переезд — без smooth-скролла). */
  let slideRaf = 0
  function nudge(dir: 1 | -1) {
    const el = tabsEl
    if (!el) return
    cancelAnimationFrame(slideRaf)
    const from = el.scrollLeft
    const to = dir > 0 ? el.scrollWidth - el.clientWidth : 0
    const t0 = performance.now()
    const step = (now: number) => {
      const t = Math.min(1, (now - t0) / 420)
      const e = 1 - Math.pow(1 - t, 3)
      el.scrollLeft = from + (to - from) * e
      if (t < 1) slideRaf = requestAnimationFrame(step)
    }
    slideRaf = requestAnimationFrame(step)
  }
  const subs = $derived(SUBS[settingsPanel.tab])
  const sub = $derived(settingsPanel.sub)
  /** Страницы из строк настроек — в широкой панели раскладываются в две колонки. */
  const COLUMN_SUBS = ['look', 'tabs', 'audio', 'view', 'queue', 'mini', 'general']

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
  <div class="find-row" data-tauri-drag-region>
    <SettingsSearch bind:query />
  </div>
  <div class="tabs-wrap">
  <nav
    class="tabs"
    data-tauri-drag-region
    bind:this={tabsEl}
    use:indicator={{ key: settingsPanel.tab }}
    use:hscroll={{ wheel: true }}
    use:edges={(l, r) => (more = { l, r })}
  >
    {#each TABS as tb (tb.id)}
      <button
        class:on={settingsPanel.tab === tb.id}
        onclick={(e) => {
          query = ''
          settingsPanel.show(tb.id)
          e.currentTarget.scrollIntoView({ inline: 'nearest', block: 'nearest', behavior: 'smooth' })
        }}>{t(tb.title)}</button
      >
    {/each}
  </nav>
    <button class="more l" class:show={more.l} tabindex="-1" aria-label={t('Вкладки левее')} onclick={() => nudge(-1)}>
      <Icon name="chevronLeft" size={16} />
    </button>
    <button class="more r" class:show={more.r} tabindex="-1" aria-label={t('Ещё вкладки')} onclick={() => nudge(1)}>
      <Icon name="chevronRight" size={16} />
    </button>
  </div>

  {#if subs.length > 1 && !searching}
    {#key settingsPanel.tab}
      <div class="subs tab-in" use:indicator={{ key: sub, kind: 'pill' }} use:hscroll={{ wheel: true }} use:edges>
        {#each subs as s (s.id)}
          <button
            class="sub"
            class:on={sub === s.id}
            class:off={s.soon || s.lock}
            disabled={s.soon || s.lock}
            title={s.lock ? t('{title} — в разработке', { title: t(s.title) }) : s.soon ? t('{title} — скоро, вместе с сервером', { title: t(s.title) }) : t(s.title)}
            onclick={(e) => {
              query = ''
              settingsPanel.sub = s.id
              e.currentTarget.scrollIntoView({ inline: 'nearest', block: 'nearest', behavior: 'smooth' })
            }}
          >
            <Icon name={s.lock ? 'lock' : s.icon} size={15} /> {t(s.title)}
          </button>
        {/each}
      </div>
    {/key}
  {/if}

  <div class="scroll" bind:this={scroller}>
    {#if searching}
      <SearchResults query={query.trim()} onpick={pick} />
    {:else}
      {#key `${settingsPanel.tab}:${sub}`}
        <div class="tab-in page">
          {#if SUB_LEADS[sub]}<p class="lead">{t(SUB_LEADS[sub])}</p>{/if}
          <div class="body" class:cols={COLUMN_SUBS.includes(sub)}>
            {#if sub === 'stats'}
              <Stats />
            {:else if sub === 'profile'}
              <Profile />
            {:else if sub === 'style'}
              <Style />
            {:else if sub === 'look'}
              <Look />
            {:else if sub === 'tabs'}
              <TabsView />
            {:else if sub === 'queue'}
              <Queue />
            {:else if sub === 'mini'}
              <Mini />
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
            {/if}
          </div>
        </div>
      {/key}
    {/if}
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
  .find-row {
    display: flex;
    justify-content: center;
    padding: 14px 16px 2px;
  }
  .tabs-wrap {
    position: relative;
    border-bottom: 1px solid var(--border);
  }
  .tabs {
    --fade: 64px;
    display: flex;
    gap: 18px;
    padding: 14px 16px 0;
    overflow-x: auto;
    scrollbar-width: none;
  }
  .tabs :global(.tab-ind.line) {
    bottom: 0;
  }
  /* стрелка у края, за которым ещё вкладки: появляется вместе с затуханием */
  /* просто стрелка — видна, но не спорит с вкладками: без кружка и заливки */
  .more {
    position: absolute;
    top: 14px;
    z-index: 2;
    display: grid;
    place-items: center;
    width: 22px;
    height: 24px;
    color: var(--text-3);
    opacity: 0;
    scale: 0.7;
    pointer-events: none;
    transition:
      opacity var(--normal) var(--ease),
      scale var(--normal) var(--ease),
      color var(--fast) var(--ease);
  }
  .more.l {
    left: 8px;
  }
  .more.r {
    right: 8px;
  }
  .more.show {
    opacity: 0.8;
    scale: 1;
    pointer-events: auto;
  }
  .more:hover {
    opacity: 1;
    color: var(--text);
  }
  .tabs button {
    padding: 4px 0 12px;
    font-size: calc(15px * var(--fs, 1));
    color: var(--text-3);
    white-space: nowrap;
    transition: color var(--fast) var(--ease);
  }
  .tabs button:hover {
    color: var(--text-2);
  }
  .tabs button.on {
    color: var(--text);
    font-weight: 700;
  }
  .subs {
    display: flex;
    gap: 4px;
    margin: 14px 16px 0;
    padding: 4px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    overflow-x: auto;
    scrollbar-width: none;
  }
  .sub {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 7px;
    flex: 1 0 auto;
    height: 34px;
    padding: 0 12px;
    border-radius: 999px;
    color: var(--text-2);
    font-size: calc(13px * var(--fs, 1));
    white-space: nowrap;
    transition: color var(--fast) var(--ease);
  }
  /* выбранный — тёмный текст на светлой капсуле, наведение его не перекрашивает */
  .sub:hover:not(:disabled):not(.on) {
    color: var(--text);
  }
  .sub.off {
    opacity: 0.45;
    cursor: default;
  }
  .sub.on {
    color: var(--on-text);
    font-weight: 600;
  }
  .subs :global(.tab-ind.pill) {
    background: var(--text);
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
