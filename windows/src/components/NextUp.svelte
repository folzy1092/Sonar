<script lang="ts">
  // «Дальше» (Плеер → Очередь → Предпросмотр следующего трека, queue.preview): за 10 с до конца
  // трека выезжает карточка со следующим треком — у мини-плеера (`float`) или на странице плеера.
  // У мини-плеера карточка — прямой ребёнок его подложки: отступ от правого края и зазор до плеера —
  // --next-inset / --next-gap (владелец 2026-11-19: при var(--gap) карточка липла к краям), в узком окне
  // не шире плеера. Сверху окна / в верхней половине
  // (плавающий) — под плеером, иначе над ним (next-up.ts).
  // Открыта правая панель (очередь / текст) — у мини-плеера не показывается: следующий трек и так виден.
  import Cover from './Cover.svelte'
  import { sidePane } from '../app/side-pane.svelte'
  import { player } from '../player/player.svelte'
  import { settings } from '../lib/settings.svelte'
  import { pop } from '../lib/motion'
  import { t } from '../lib/i18n.svelte'
  import { nextUpRise, nextUpSide } from './next-up'

  let { float = false }: { float?: boolean } = $props()

  const next = $derived(player.upNext[0] ?? null)
  const left = $derived((player.durationMs || player.current?.duration_ms || 0) - player.positionMs)
  const shown = $derived(settings.get('queue.preview') && !(float && sidePane.open) && !!next && player.playing && left > 0 && left <= 10_000)
  const side = $derived(float ? nextUpSide(settings.get('mini.position'), settings.get('mini.float_y')) : 'above')
  const rise = $derived(nextUpRise(side))
</script>

{#if shown && next}
  <div class="next" data-no-seek class:float class:below={side === 'below'} in:pop={{ y: rise, duration: 240 }} out:pop={{ y: rise, duration: 240 }}>
    <Cover url={next.cover_url} size={32} radius="8px" />
    <span class="meta">
      <small>{t('Дальше')}</small>
      <b>{next.title}</b>
      <span class="artist">{next.artist}</span>
    </span>
  </div>
{/if}

<style>
  .next {
    display: inline-flex;
    align-items: center;
    gap: 12px;
    max-width: 320px;
    min-width: 0;
    padding: 8px 16px 8px 8px;
    border-radius: 14px;
    background: var(--surface-2);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  .next.float {
    /* у мини-плеера: зазор до его подложки (border 1px + --next-gap) и отступ от правого края —
       с воздухом, не впритык; не шире самого плеера */
    --next-gap: 12px;
    --next-inset: 20px;
    position: absolute;
    right: var(--next-inset);
    bottom: calc(100% + 1px + var(--next-gap));
    max-width: min(320px, calc(100% - 2 * var(--next-inset)));
    z-index: 5;
    transform-origin: right bottom;
    box-shadow:
      0 12px 30px oklch(0 0 0 / 0.4),
      var(--sheen);
  }
  .next.float.below {
    top: calc(100% + 1px + var(--next-gap));
    bottom: auto;
    transform-origin: right top;
  }
  .meta {
    display: flex;
    flex-direction: column;
    min-width: 0;
    line-height: 1.25;
  }
  small {
    font-size: calc(11px * var(--fs, 1));
    font-weight: 600;
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
