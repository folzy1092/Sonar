<script lang="ts">
  // Содержимое одной карточки итогов на экране: те же подписи, что на картинке (lib/recap-text.ts),
  // числа считаются (CountUp), списки появляются каскадом. Цвета — переменные `--rc-*` из RecapViewer.
  import Cover from './Cover.svelte'
  import CountUp from './CountUp.svelte'
  import { cascade } from '../lib/cascade'
  import { durationText } from '../lib/format'
  import type { Recap } from '../lib/api'
  import { byId } from '../lib/services'
  import { cardText, numberText, serviceTitle } from '../lib/recap-text'
  import type { RecapCard, RecapRef } from '../lib/recap-core'

  let { card, ref, data }: { card: RecapCard; ref: RecapRef; data: Recap } = $props()

  const text = $derived(cardText(card, ref))
  const ROW_COVER = 56
  const HERO_COVER = 200
  const peakMs = $derived(card.kind === 'hour' ? Math.max(1, ...card.hours) : 1)
</script>

{#snippet value()}
  {#if text.value !== null}
    <div class="value"><CountUp value={text.value} format={numberText} /></div>
    <div class="unit">{text.unit}</div>
  {/if}
{/snippet}

{#snippet lines()}
  {#each text.lines as line (line)}<p class="line">{line}</p>{/each}
{/snippet}

<div class="body">
  <p class="eyebrow">{text.eyebrow}</p>
  {#if card.kind === 'intro'}
    <div class="hero"><Cover url={data.top_tracks[0]?.cover_url} size={HERO_COVER} radius="var(--radius-l)" /></div>
    <h2 class="title big">{text.title}</h2>
    {@render lines()}
  {:else if card.kind === 'tracks' || card.kind === 'artists'}
    <ol class="rank" use:cascade>
      {#if card.kind === 'tracks'}
        {#each card.items as item, i (item.ref)}
          <li>
            <span class="n" class:first={i === 0}>{i + 1}</span>
            <Cover url={item.cover_url} size={ROW_COVER} source={item.ref} />
            <span class="names"><b>{item.title}</b><small>{item.artist}</small></span>
          </li>
        {/each}
      {:else}
        {#each card.items as item, i (item.name)}
          <li>
            <span class="n" class:first={i === 0}>{i + 1}</span>
            <Cover url={item.avatar_url} size={ROW_COVER} radius="50%" />
            <span class="names"><b>{item.name}</b><small>{durationText(item.ms)}</small></span>
          </li>
        {/each}
      {/if}
    </ol>
  {:else if card.kind === 'new_artist'}
    <div class="hero"><Cover url={card.artist.avatar_url} size={HERO_COVER} radius="50%" /></div>
    <h2 class="title big">{text.title}</h2>
    {@render lines()}
  {:else if card.kind === 'hour'}
    <h2 class="title huge">{text.title}</h2>
    {@render lines()}
    <div class="hours" aria-hidden="true">
      {#each card.hours as ms, h (h)}
        <span class="bar" class:peak={h === card.hour} style:--h={Math.max(0.04, ms / peakMs)} style:--i={h}></span>
      {/each}
    </div>
    <div class="ticks" aria-hidden="true"><span>0:00</span><span>6:00</span><span>12:00</span><span>18:00</span></div>
  {:else if card.kind === 'repeat'}
    <div class="hero small"><Cover url={card.track.cover_url} size={HERO_COVER * 0.7} source={card.track.ref} /></div>
    {@render value()}
    <h2 class="title">{text.title}</h2>
    {@render lines()}
  {:else if card.kind === 'services'}
    <h2 class="title big">{text.title}</h2>
    {@render lines()}
    <ul class="services" use:cascade>
      {#each card.items as item (item.service)}
        <li style:--w="{item.pct}%" style:--c={byId(item.service)?.color ?? 'var(--rc-accent)'}>
          <span class="svc"><b>{serviceTitle(item.service)}</b><b>{item.pct}%</b></span>
          <span class="track"><span class="fill"></span></span>
        </li>
      {/each}
    </ul>
  {:else}
    {@render value()}
    {#if text.title}<h2 class="title">{text.title}</h2>{/if}
    {@render lines()}
  {/if}
</div>

<style>
  .body {
    display: flex;
    flex-direction: column;
    gap: 10px;
    width: 100%;
    min-width: 0;
  }
  .eyebrow {
    margin: 0 0 8px;
    color: var(--rc-accent);
    font-size: calc(14px * var(--fs, 1));
    font-weight: 700;
    letter-spacing: 0.12em;
    text-transform: uppercase;
  }
  .hero {
    margin-bottom: 12px;
  }
  .title {
    margin: 0;
    font-size: calc(26px * var(--fs, 1));
    font-weight: 700;
    line-height: 1.15;
    overflow-wrap: anywhere;
  }
  .title.big {
    font-size: calc(40px * var(--fs, 1));
    font-weight: 800;
  }
  .title.huge {
    font-size: calc(64px * var(--fs, 1));
    font-weight: 800;
    font-variant-numeric: tabular-nums;
  }
  .value {
    color: var(--rc-accent);
    font-size: calc(96px * var(--fs, 1));
    font-weight: 800;
    line-height: 1;
    font-variant-numeric: tabular-nums;
    letter-spacing: -0.02em;
  }
  .unit {
    font-size: calc(22px * var(--fs, 1));
    font-weight: 600;
    margin-bottom: 6px;
  }
  .line {
    margin: 0;
    color: color-mix(in srgb, var(--rc-ink) 75%, transparent);
    font-size: calc(16px * var(--fs, 1));
  }
  .rank,
  .services {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: 14px;
  }
  .rank li {
    display: flex;
    align-items: center;
    gap: 14px;
    min-width: 0;
  }
  .n {
    width: 28px;
    flex: none;
    font-size: calc(24px * var(--fs, 1));
    font-weight: 800;
    color: color-mix(in srgb, var(--rc-ink) 50%, transparent);
    font-variant-numeric: tabular-nums;
  }
  .n.first {
    color: var(--rc-accent);
  }
  .names {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .names b,
  .names small {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .names b {
    font-size: calc(17px * var(--fs, 1));
  }
  .names small {
    color: color-mix(in srgb, var(--rc-ink) 65%, transparent);
    font-size: calc(14px * var(--fs, 1));
  }
  .hours {
    display: grid;
    grid-template-columns: repeat(24, 1fr);
    align-items: end;
    gap: 4px;
    height: 140px;
    margin-top: 24px;
  }
  .bar {
    height: calc(var(--h) * 100%);
    border-radius: 99px;
    background: color-mix(in srgb, var(--rc-ink) 22%, transparent);
    transform-origin: bottom;
    animation: grow 600ms var(--ease) both;
    animation-delay: calc(var(--i) * 18ms);
  }
  .bar.peak {
    background: var(--rc-accent);
  }
  .ticks {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    color: color-mix(in srgb, var(--rc-ink) 55%, transparent);
    font-size: calc(12px * var(--fs, 1));
  }
  .svc {
    display: flex;
    justify-content: space-between;
    font-size: calc(17px * var(--fs, 1));
    margin-bottom: 6px;
  }
  .track {
    display: block;
    height: 10px;
    border-radius: 99px;
    background: color-mix(in srgb, var(--rc-ink) 12%, transparent);
    overflow: hidden;
  }
  .fill {
    display: block;
    height: 100%;
    width: max(10px, var(--w));
    border-radius: inherit;
    background: var(--c);
    transform-origin: left;
    animation: stretch 700ms var(--ease) both;
  }
  @keyframes grow {
    from {
      transform: scaleY(0);
    }
  }
  @keyframes stretch {
    from {
      transform: scaleX(0);
    }
  }
  /* «Меньше движения» / анимации выключены: без роста столбиков */
  :global(.no-motion) .bar,
  :global(.no-motion) .fill {
    animation: none;
  }
  @media (prefers-reduced-motion: reduce) {
    .bar,
    .fill {
      animation: none;
    }
  }
</style>
