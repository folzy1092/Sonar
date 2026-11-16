<script lang="ts">
  import { hscroll } from '../lib/hscroll'
  import { edges } from '../lib/edges'
  // Панель настроек слева (reference/pc/Screenshot_30..32): вкладки разделов сверху, под ними
  // капсулы подразделов (docs/PLATFORMS.md «Настройки — одинаковые разделы»). Панель выезжает
  // слева одновременно с уходом окна вглубь (App.svelte) — как в Dotify.
  import Icon from '../components/Icon.svelte'
  import Services from './settings/Services.svelte'
  import Stats from './settings/Stats.svelte'
  import Audio from './settings/Audio.svelte'
  import Look from './settings/Look.svelte'
  import PlayerView from './settings/PlayerView.svelte'
  import Integrations from './settings/Integrations.svelte'
  import General from './settings/General.svelte'
  import Storage from './settings/Storage.svelte'
  import Update from './settings/Update.svelte'
  import TabsView from './settings/TabsView.svelte'
  import Queue from './settings/Queue.svelte'
  import Mini from './settings/Mini.svelte'
  import { settingsPanel, SUBS, TABS } from './settings-section.svelte'
  import { indicator } from '../lib/indicator'

  let scroller: HTMLDivElement | undefined = $state()
  let tabsEl: HTMLElement | undefined = $state()
  /** Есть ли вкладки за краем строки — тогда край затухает и появляется стрелка (как у подразделов). */
  let more = $state({ l: false, r: false })
  const nudge = (dir: 1 | -1) => tabsEl?.scrollBy({ left: dir * 160, behavior: 'smooth' })
  const subs = $derived(SUBS[settingsPanel.tab])
  const sub = $derived(settingsPanel.sub)

  $effect(() => {
    settingsPanel.tab
    settingsPanel.sub
    scroller?.scrollTo({ top: 0 })
  })
</script>

<aside class="panel" class:open={settingsPanel.open} inert={!settingsPanel.open} aria-label="Настройки">
  <div class="tabs-wrap">
  <nav
    class="tabs"
    data-tauri-drag-region
    bind:this={tabsEl}
    use:indicator={{ key: settingsPanel.tab }}
    use:hscroll
    use:edges={(l, r) => (more = { l, r })}
  >
    {#each TABS as t (t.id)}
      <button
        class:on={settingsPanel.tab === t.id}
        onclick={(e) => {
          settingsPanel.show(t.id)
          e.currentTarget.scrollIntoView({ inline: 'nearest', block: 'nearest', behavior: 'smooth' })
        }}>{t.title}</button
      >
    {/each}
  </nav>
    <button class="more l" class:show={more.l} tabindex="-1" aria-label="Вкладки левее" onclick={() => nudge(-1)}>
      <Icon name="chevronLeft" size={16} />
    </button>
    <button class="more r" class:show={more.r} tabindex="-1" aria-label="Ещё вкладки" onclick={() => nudge(1)}>
      <Icon name="chevronRight" size={16} />
    </button>
  </div>

  {#if subs.length > 1}
    {#key settingsPanel.tab}
      <div class="subs tab-in" use:indicator={{ key: sub, kind: 'pill' }} use:hscroll use:edges>
        {#each subs as s (s.id)}
          <button
            class="sub"
            class:on={sub === s.id}
            class:off={s.soon || s.lock}
            disabled={s.soon || s.lock}
            title={s.lock ? `${s.title} — в разработке` : s.soon ? `${s.title} — скоро, вместе с сервером` : s.title}
            onclick={(e) => {
              settingsPanel.sub = s.id
              e.currentTarget.scrollIntoView({ inline: 'nearest', block: 'nearest', behavior: 'smooth' })
            }}
          >
            <Icon name={s.lock ? 'lock' : s.icon} size={15} /> {s.title}
          </button>
        {/each}
      </div>
    {/key}
  {/if}

  <div class="scroll" bind:this={scroller}>
    {#key `${settingsPanel.tab}:${sub}`}
      <div class="tab-in">
        {#if sub === 'stats'}
          <Stats />
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
        {:else if sub === 'storage'}
          <Storage />
        {:else if sub === 'update'}
          <Update />
        {/if}
      </div>
    {/key}
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
  .more {
    position: absolute;
    top: 13px;
    display: grid;
    place-items: center;
    width: 26px;
    height: 26px;
    border-radius: 50%;
    background: var(--surface-2);
    border: 1px solid var(--border-strong);
    color: var(--text-2);
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
    opacity: 1;
    scale: 1;
    pointer-events: auto;
  }
  .more:hover {
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
    border: 1px solid var(--border);
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
  .sub:hover:not(:disabled) {
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
    padding: 16px 16px 32px;
  }
</style>
