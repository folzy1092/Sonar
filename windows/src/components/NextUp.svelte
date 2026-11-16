<script lang="ts">
  // «Дальше» (Плеер → Очередь → Предпросмотр следующего трека, queue.preview): за 10 с до конца
  // трека выезжает карточка со следующим треком — над мини-плеером (`float`) или на странице плеера.
  import Cover from './Cover.svelte'
  import { player } from '../player/player.svelte'
  import { settings } from '../lib/settings.svelte'
  import { fly } from 'svelte/transition'
  import { reducedMotion } from '../lib/motion'

  let { float = false }: { float?: boolean } = $props()

  const next = $derived(player.upNext[0] ?? null)
  const left = $derived((player.durationMs || player.current?.duration_ms || 0) - player.positionMs)
  const shown = $derived(settings.get('queue.preview') && !!next && player.playing && left > 0 && left <= 10_000)
</script>

{#if shown && next}
  <div class="next" class:float transition:fly={{ y: reducedMotion() ? 0 : 8, duration: 240 }}>
    <Cover url={next.cover_url} size={32} radius="8px" />
    <span class="meta">
      <small>Дальше</small>
      <b>{next.title}</b>
      <span class="artist">{next.artist}</span>
    </span>
  </div>
{/if}

<style>
  .next {
    display: inline-flex;
    align-items: center;
    gap: 10px;
    max-width: 320px;
    padding: 6px 12px 6px 6px;
    border-radius: 14px;
    background: var(--surface-2);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  .next.float {
    position: absolute;
    right: 12px;
    bottom: calc(100% + 8px);
    z-index: 5;
    box-shadow:
      0 12px 30px oklch(0 0 0 / 0.4),
      var(--sheen);
  }
  .meta {
    display: flex;
    flex-direction: column;
    min-width: 0;
    line-height: 1.25;
  }
  small {
    font-size: calc(10px * var(--fs, 1));
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--accent);
  }
  b,
  .artist {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  b {
    font-size: calc(13px * var(--fs, 1));
  }
  .artist {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
</style>
