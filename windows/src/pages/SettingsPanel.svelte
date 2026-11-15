<script lang="ts">
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
  import About from './settings/About.svelte'
  import { settingsPanel, SUBS, TABS } from './settings-section.svelte'
  import { indicator } from '../lib/indicator'

  let scroller: HTMLDivElement | undefined = $state()
  const subs = $derived(SUBS[settingsPanel.tab])
  const sub = $derived(settingsPanel.sub)

  $effect(() => {
    settingsPanel.tab
    settingsPanel.sub
    scroller?.scrollTo({ top: 0 })
  })
</script>

<aside class="panel" class:open={settingsPanel.open} inert={!settingsPanel.open} aria-label="Настройки">
  <nav
    class="tabs"
    data-tauri-drag-region
    use:indicator={{ key: settingsPanel.tab }}
    onwheel={(e) => {
      // колесо над вкладками листает их вбок — «Система» не прячется за краем
      if (e.deltaY) e.currentTarget.scrollBy({ left: e.deltaY, behavior: 'smooth' })
    }}
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

  {#if subs.length > 1}
    {#key settingsPanel.tab}
      <div class="subs tab-in" use:indicator={{ key: sub, kind: 'pill' }}>
        {#each subs as s (s.id)}
          <button class="sub" class:on={sub === s.id} onclick={() => (settingsPanel.sub = s.id)}><Icon name={s.icon} size={15} /> {s.title}</button>
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
        {:else if sub === 'about'}
          <About />
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
  .tabs {
    display: flex;
    gap: 18px;
    padding: 14px 16px 0;
    overflow-x: auto;
    scrollbar-width: none;
    border-bottom: 1px solid var(--border);
  }
  .tabs button {
    padding: 4px 0 12px;
    font-size: 15px;
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
  }
  .sub {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 7px;
    flex: 1;
    height: 34px;
    padding: 0 12px;
    border-radius: 999px;
    color: var(--text-2);
    font-size: 13px;
    white-space: nowrap;
    transition: color var(--fast) var(--ease);
  }
  .sub:hover {
    color: var(--text);
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
