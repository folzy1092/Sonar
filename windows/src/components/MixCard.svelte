<script lang="ts">
  // Карточка подборки «Для тебя» на Главной: мозаика из четырёх обложек, название, 2–3 исполнителя
  // с аватарками и «и ещё N». Клик открывает страницу подборки (MixPage), а не очередь.
  import Icon from './Icon.svelte'
  import type { IconName } from './icons'
  import type { Track } from '../lib/api'
  import { artistsPreview } from '../lib/home-mixes'
  import { collage } from '../lib/covers'
  import { t } from '../lib/i18n.svelte'

  interface Props {
    title: string
    tracks: Track[]
    loading?: boolean
    /** Подпись вместо исполнителей, когда треков нет (например, «Выбери трек»). */
    hint?: string
    icon?: IconName
    onclick: () => void
  }
  let { title, tracks, loading = false, hint, icon = 'sparkles', onclick }: Props = $props()

  const covers = $derived(collage(tracks))
  const preview = $derived(artistsPreview(tracks))
  const names = $derived(preview.shown.map((a) => a.name).join(', '))
</script>

<button class="mix press" class:loading={loading && !tracks.length} {title} {onclick}>
  <span class="art">
    {#if covers.length >= 4}
      <span class="grid">
        {#each covers as c, i (c)}<img src={c} alt="" loading="lazy" draggable="false" style:--i={i} />{/each}
      </span>
    {:else if covers.length}
      <img class="one" src={covers[0]} alt="" loading="lazy" draggable="false" />
    {:else}
      <span class="ph"><Icon name={icon} size={40} /></span>
    {/if}
    <span class="go"><Icon name="chevronRight" size={18} /></span>
  </span>
  <span class="title">{title}</span>
  {#if preview.shown.length}
    <span class="who">
      <span class="faces">
        {#each preview.shown as a, i (a.name)}
          <span class="face" style:z-index={3 - i}>
            {#if a.avatar_url}<img src={a.avatar_url} alt="" loading="lazy" draggable="false" />{:else}{a.name.slice(0, 1).toUpperCase()}{/if}
          </span>
        {/each}
      </span>
      <span class="names">{names}{#if preview.more > 0}<span class="more"> {t('и ещё {n}', { n: preview.more })}</span>{/if}</span>
    </span>
  {:else if hint && !loading}
    <span class="who"><span class="names">{hint}</span></span>
  {:else}
    <span class="who"><span class="line skel"></span></span>
  {/if}
</button>

<style>
  .mix {
    display: flex;
    flex-direction: column;
    gap: 8px;
    width: 196px;
    flex-shrink: 0;
    text-align: left;
  }
  .art {
    position: relative;
    display: grid;
    place-items: center;
    width: 100%;
    aspect-ratio: 1;
    overflow: hidden;
    border-radius: var(--radius-l);
    background: var(--plate);
    box-shadow: inset 0 0 0 1px var(--card-line);
    transition:
      transform var(--normal) var(--ease),
      box-shadow var(--normal) var(--ease);
  }
  .mix:hover .art {
    transform: translateY(-3px);
    box-shadow:
      inset 0 0 0 1px var(--card-line),
      0 14px 30px rgba(0, 0, 0, 0.35);
  }
  .mix:active .art {
    transform: scale(0.97);
  }
  .grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 2px;
    width: 100%;
    height: 100%;
  }
  img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }
  .grid img {
    animation: tile-in var(--normal) var(--ease) both;
    animation-delay: calc(var(--i) * 40ms);
    transition: transform var(--slow, 0.5s) var(--ease);
  }
  .mix:hover .grid img {
    transform: scale(1.04);
  }
  .one {
    animation: tile-in var(--normal) var(--ease) both;
  }
  @keyframes tile-in {
    from {
      opacity: 0;
      transform: scale(1.06);
    }
  }
  .ph {
    display: grid;
    color: var(--accent);
    transition: color 0.6s var(--ease);
  }
  .loading .art {
    background: linear-gradient(90deg, var(--plate), var(--hover), var(--plate));
    background-size: 200% 100%;
    animation: shimmer 1.2s linear infinite;
  }
  .go {
    position: absolute;
    right: 10px;
    bottom: 10px;
    display: grid;
    place-items: center;
    width: 34px;
    height: 34px;
    border-radius: 50%;
    background: var(--text);
    color: var(--surface-0);
    box-shadow: 0 6px 16px rgba(0, 0, 0, 0.35);
    opacity: 0;
    translate: 0 6px;
    transition:
      opacity var(--fast) var(--ease),
      translate var(--fast) var(--ease);
  }
  .mix:hover .go,
  .mix:focus-visible .go {
    opacity: 1;
    translate: 0 0;
  }
  .title {
    font-weight: 700;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .who {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
    min-height: 22px;
  }
  .faces {
    display: flex;
    flex: none;
  }
  .face {
    position: relative;
    display: grid;
    place-items: center;
    width: 22px;
    height: 22px;
    margin-left: -6px;
    overflow: hidden;
    border-radius: 50%;
    background: var(--hover);
    box-shadow: 0 0 0 2px var(--surface-0);
    color: var(--text-2);
    font-size: 10px;
    font-weight: 700;
    transition: margin var(--fast) var(--ease);
  }
  .face:first-child {
    margin-left: 0;
  }
  .mix:hover .face:not(:first-child) {
    margin-left: -2px;
  }
  .names {
    min-width: 0;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-2);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .more {
    color: var(--text-3);
  }
  .line {
    width: 70%;
    height: 10px;
    border-radius: 5px;
  }
  @keyframes shimmer {
    to {
      background-position: -200% 0;
    }
  }
</style>
