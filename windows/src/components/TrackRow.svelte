<script lang="ts">
  import Cover from './Cover.svelte'
  import Icon from './Icon.svelte'
  import type { Track } from '../lib/api'
  import { formatTime, player } from '../player/player.svelte'

  interface Props {
    track: Track
    index?: number
    /** list — поиск и списки (колонка альбома); queue — очередь плеера (❤ и длительность плашкой). */
    variant?: 'list' | 'queue'
    onplay: () => void
  }

  let { track, index, variant = 'list', onplay }: Props = $props()
  const isCurrent = $derived(player.current?.ref === track.ref)
</script>

<button class="row" class:queue={variant === 'queue'} class:current={isCurrent} class:off={!track.available} onclick={() => (isCurrent ? player.toggle() : onplay())}>
  {#if index !== undefined}
    <span class="num">
      {#if isCurrent && player.playing}
        <span class="eq" aria-label="Играет"><i></i><i></i><i></i></span>
      {:else}
        {index + 1}
      {/if}
    </span>
  {/if}
  <span class="art">
    <Cover url={track.cover_url} size={42} source={track.ref} />
    <span class="hover-play"><Icon name={isCurrent && player.playing ? 'pause' : 'play'} size={16} filled /></span>
  </span>
  <span class="meta">
    <span class="title">{track.title}{#if track.explicit}<span class="e" title="Нецензурная лексика">E</span>{/if}</span>
    <span class="artist">{track.artist}</span>
  </span>
  {#if variant === 'queue'}
    <span class="end">
      <span class="like" title="В Любимые — W3"><Icon name="heart" size={14} filled /></span>
      <span class="pill">
        {#if isCurrent && player.playing}
          <span class="eq small"><i></i><i></i><i></i></span>
        {:else}
          {formatTime(track.duration_ms)}
        {/if}
      </span>
    </span>
  {:else}
    <span class="album">{track.album?.title ?? ''}</span>
    <span class="dur">{formatTime(track.duration_ms)}</span>
  {/if}
</button>

<style>
  .row {
    display: grid;
    grid-template-columns: auto auto minmax(0, 2fr) minmax(0, 1fr) auto;
    align-items: center;
    gap: 14px;
    width: 100%;
    padding: 6px 14px 6px 8px;
    border-radius: var(--radius-m);
    text-align: left;
    transition: background var(--fast) var(--ease);
  }
  .row:not(:has(.num)) {
    grid-template-columns: auto minmax(0, 2fr) minmax(0, 1fr) auto;
  }
  .row.queue {
    grid-template-columns: auto minmax(0, 1fr) auto;
    padding: 6px 10px 6px 6px;
  }
  .end {
    display: flex;
    align-items: center;
    gap: 14px;
  }
  .like {
    display: grid;
    color: var(--text);
    opacity: 0.85;
  }
  .pill {
    display: grid;
    place-items: center;
    min-width: 40px;
    height: 24px;
    padding: 0 8px;
    border-radius: 999px;
    border: 1px solid var(--border-strong);
    font-size: 11px;
    color: var(--text-2);
    font-variant-numeric: tabular-nums;
  }
  .eq.small {
    height: 9px;
  }
  .row:hover {
    background: var(--hover);
  }
  .row.off {
    opacity: 0.45;
  }
  .num {
    width: 26px;
    text-align: center;
    font-variant-numeric: tabular-nums;
    color: var(--text-3);
  }
  .art {
    position: relative;
    border-radius: var(--radius-s);
    overflow: hidden;
  }
  .hover-play {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
    background: rgba(0, 0, 0, 0.5);
    color: #fff;
    opacity: 0;
    transition: opacity var(--fast) var(--ease);
  }
  .row:hover .hover-play {
    opacity: 1;
  }
  .meta {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .title,
  .artist,
  .album {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .title {
    font-weight: 600;
  }
  .current .title {
    color: var(--accent);
  }
  .e {
    display: inline-block;
    margin-left: 6px;
    padding: 0 4px;
    border-radius: 3px;
    background: var(--surface-3);
    color: var(--text-2);
    font-size: 10px;
    font-weight: 700;
    vertical-align: 2px;
  }
  .artist,
  .album {
    font-size: 13px;
    color: var(--text-3);
  }
  .dur {
    font-size: 13px;
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  .eq {
    display: inline-flex;
    align-items: flex-end;
    gap: 2px;
    height: 12px;
  }
  .eq i {
    width: 3px;
    background: var(--accent);
    border-radius: 1px;
    animation: eq 0.9s ease-in-out infinite;
  }
  .eq i:nth-child(2) {
    animation-delay: -0.3s;
  }
  .eq i:nth-child(3) {
    animation-delay: -0.6s;
  }
  @keyframes eq {
    0%,
    100% {
      height: 30%;
    }
    50% {
      height: 100%;
    }
  }
</style>
