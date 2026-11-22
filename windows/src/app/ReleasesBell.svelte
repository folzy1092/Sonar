<script lang="ts">
  // «Новинки» — колокольчик в чёлке рядом с историей (lib/new-releases.svelte.ts): число — сколько
  // свежих релизов любимых исполнителей ещё не открывали. Клик — всплывашка со списком за неделю,
  // клик по строке — альбом открывается, трек SoundCloud играет. Открывается и закрывается только кликом.
  import Icon from '../components/Icon.svelte'
  import Cover from '../components/Cover.svelte'
  import { pop } from '../lib/motion'
  import { cascade } from '../lib/cascade'
  import { newReleases } from '../lib/new-releases.svelte'
  import { releaseLabel } from '../pages/home-data.svelte'
  import { t } from '../lib/i18n.svelte'

  let open = $state(false)
  let root: HTMLElement | undefined = $state()

  function toggle() {
    open = !open
    if (open) newReleases.markSeen()
  }

  function outside(e: PointerEvent) {
    if (open && root && !root.contains(e.target as Node)) open = false
  }
</script>

<svelte:window onpointerdown={outside} onkeydown={(e) => e.key === 'Escape' && (open = false)} />

<div class="wrap" bind:this={root}>
  <button class="ctl press" class:on={open} aria-label={t('Новинки')} title={t('Новинки исполнителей')} aria-expanded={open} onclick={toggle}>
    <Icon name="bell" size={16} stroke={1.8} />
    {#if newReleases.unread > 0}<span class="badge" in:pop>{newReleases.unread > 9 ? '9+' : newReleases.unread}</span>{/if}
  </button>
  {#if open}
    <div class="pop" role="dialog" aria-label={t('Новинки')} in:pop={{ y: -6 }} out:pop={{ y: -6 }}>
      <b>{t('Новинки')}</b>
      {#if !newReleases.fresh.length}
        <p class="empty">{t('За неделю у любимых исполнителей ничего нового. Подпишись на исполнителя или лайкни его треки — его релизы появятся здесь.')}</p>
      {:else}
        <div class="rows app-scroll" use:cascade>
          {#each newReleases.fresh as r (r.ref)}
            <button class="row" onclick={() => ((open = false), newReleases.open(r))}>
              <Cover url={r.cover_url} size={36} source={r.ref} />
              <span class="txt"><span class="t">{r.title}</span><span class="a">{r.artist} · {releaseLabel(r.released) ?? r.released}</span></span>
              <Icon name={r.kind === 'track' ? 'play' : 'disc'} size={14} />
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
  .ctl {
    position: relative;
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
  .badge {
    position: absolute;
    top: 1px;
    right: 0;
    min-width: 14px;
    height: 14px;
    padding: 0 3px;
    border-radius: 7px;
    background: var(--accent);
    color: var(--accent-ink);
    font-size: 9px;
    font-weight: 700;
    line-height: 14px;
    text-align: center;
  }
  .pop {
    position: absolute;
    top: calc(100% + 8px);
    right: -100px;
    z-index: 40;
    width: 330px;
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
    color: var(--text-3);
    transition: background var(--fast) var(--ease);
  }
  .row:hover {
    background: var(--hover);
  }
  .txt {
    display: flex;
    flex: 1;
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
    color: var(--text);
  }
  .a {
    font-size: calc(12px * var(--fs, 1));
  }
  .empty {
    margin: 4px 2px 8px;
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.45;
    color: var(--text-3);
  }
</style>
