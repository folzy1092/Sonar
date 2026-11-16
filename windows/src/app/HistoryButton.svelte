<script lang="ts">
  // История прослушивания (как часы у Dotify в углу окна): клик — всплывашка с последними треками,
  // клик по треку — играет история с него. Открывается и закрывается только кликом.
  import Icon from '../components/Icon.svelte'
  import Cover from '../components/Cover.svelte'
  import { api, type Track } from '../lib/api'
  import { pop } from '../lib/motion'
  import { cascade } from '../lib/cascade'
  import { player } from '../player/player.svelte'

  let open = $state(false)
  let list = $state<Track[] | null>(null)
  let root: HTMLElement | undefined = $state()

  async function toggle() {
    open = !open
    if (open) list = await api.recentTracks(30).catch(() => [])
  }

  function play(i: number) {
    if (!list) return
    void player.playList(list, i, 'recent', 'История')
    open = false
  }

  function outside(e: PointerEvent) {
    if (open && root && !root.contains(e.target as Node)) open = false
  }
</script>

<svelte:window onpointerdown={outside} onkeydown={(e) => e.key === 'Escape' && (open = false)} />

<div class="wrap" bind:this={root}>
  <button class="ctl press" class:on={open} aria-label="История прослушивания" title="История прослушивания" aria-expanded={open} onclick={toggle}>
    <Icon name="history" size={16} stroke={1.8} />
  </button>
  {#if open}
    <div class="pop" role="dialog" aria-label="История прослушивания" in:pop={{ y: -6 }} out:pop={{ y: -6 }}>
      <b>История</b>
      {#if list === null}
        <div class="skel ph"></div>
      {:else if !list.length}
        <p class="empty">Здесь появятся треки, которые ты слушал.</p>
      {:else}
        <div class="rows app-scroll" use:cascade>
          {#each list as t, i (t.ref + i)}
            <button class="row" class:now={player.current?.ref === t.ref} onclick={() => play(i)}>
              <Cover url={t.cover_url} size={36} source={t.ref} />
              <span class="txt"><span class="t">{t.title}</span><span class="a">{t.artist}</span></span>
            </button>
          {/each}
        </div>
      {/if}
    </div>
  {/if}
</div>

<style>
  .wrap {
    position: relative;
  }
  /* как кнопки окна в чёлке (Dotify): 28×28, без подложки, светлеет только значок */
  .ctl {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    border-radius: 8px;
    color: color-mix(in srgb, var(--text-2) 70%, transparent);
    transition:
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .ctl:hover,
  .ctl.on {
    color: var(--text);
  }
  .pop {
    position: absolute;
    top: calc(100% + 8px);
    right: -70px;
    z-index: 40;
    width: 320px;
    padding: 12px 6px 6px 12px;
    border-radius: 16px;
    background: var(--surface-2);
    border: 1px solid var(--border-strong);
    box-shadow: 0 18px 44px rgba(0, 0, 0, 0.5);
    transform-origin: top right;
  }
  .pop b {
    display: block;
    margin: 0 0 8px 2px;
    font-size: calc(14px * var(--fs, 1));
  }
  .rows {
    display: flex;
    flex-direction: column;
    max-height: 380px;
    overflow-y: auto;
    padding-right: 4px;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 5px 6px;
    border-radius: 10px;
    text-align: left;
    transition: background var(--fast) var(--ease);
  }
  .row:hover {
    background: var(--hover);
  }
  .txt {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .t,
  .a {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .t {
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
  }
  .row.now .t {
    color: var(--accent);
  }
  .a {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .empty {
    margin: 4px 2px 8px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .ph {
    height: 120px;
    margin: 0 6px 6px 0;
    border-radius: 12px;
  }
</style>
