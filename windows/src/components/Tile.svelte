<script lang="ts">
  import SourceIcon from './SourceIcon.svelte'
  // Плитка медиатеки и каруселей (pc/Screenshot_21): квадратная (или круглая) обложка и подписи.
  // Обложка — картинка, коллаж из 4 обложек (плейлист Sonar) или значок.
  import Icon from './Icon.svelte'
  import type { IconName } from './icons'
  import type { Snippet } from 'svelte'
  import { byId, serviceOf } from '../lib/services'
  import { offline } from '../lib/offline.svelte'

  interface Props {
    title: string
    subtitle?: string
    meta?: string
    icon?: IconName
    image?: string | null
    covers?: string[]
    round?: boolean
    ghost?: boolean
    dim?: boolean
    source?: string | null
    onclick?: () => void
    oncontextmenu?: (e: MouseEvent) => void
    badge?: Snippet
    /** Своё содержимое пустой обложки (например, сердце «Любимых» цветом темы). */
    art?: Snippet
  }

  let {
    title,
    subtitle,
    meta,
    icon = 'music',
    image = null,
    covers = [],
    round = false,
    ghost = false,
    dim = false,
    source = null,
    onclick,
    oncontextmenu,
    badge,
    art,
  }: Props = $props()
  let failed = $state(false)
  const svc = $derived(byId(serviceOf(source)))
  const src = $derived(svc?.implemented ? svc.id : null)
</script>

<button class="tile" class:ghost class:dim {onclick} {oncontextmenu} title={title}>
  <span class="cover" class:round class:empty={!(image && !failed) && !covers.length}>
    {#if image && !failed}
      <img src={offline.src(image)} alt="" loading="lazy" draggable="false" class="fade-img" onload={(e) => e.currentTarget.classList.add('loaded')} onerror={() => (failed = true)} />
    {:else if covers.length >= 4}
      <span class="collage">
        {#each covers.slice(0, 4) as c, i (i)}<img src={offline.src(c)} alt="" loading="lazy" draggable="false" />{/each}
      </span>
    {:else if covers.length}
      <img src={offline.src(covers[0])} alt="" loading="lazy" draggable="false" />
    {:else if art}
      {@render art()}
    {:else}
      <!-- пустая обложка — значок цветом темы, как сердце «Любимых» -->
      <span class="ph"><Icon name={icon} size={40} filled /></span>
    {/if}
    {#if src}
      <span class="src"><SourceIcon service={src} size={18} /></span>
    {/if}
    {#if badge}<span class="badge">{@render badge()}</span>{/if}
  </span>
  <span class="text" class:center={round}>
    <span class="title">{title}</span>
    {#if subtitle}<span class="sub">{subtitle}</span>{/if}
    {#if meta}<span class="meta">{meta}</span>{/if}
  </span>
</button>

<style>
  .tile {
    display: flex;
    flex-direction: column;
    gap: var(--sp-2);
    width: var(--card-w);
    flex-shrink: 0;
    text-align: left;
  }
  .dim {
    opacity: 0.5;
  }
  .cover {
    position: relative;
    display: grid;
    place-items: center;
    width: 100%;
    aspect-ratio: 1;
    overflow: hidden;
    border-radius: var(--radius-l);
    background: var(--plate);
    color: var(--text-3);
    transition:
      transform var(--normal) var(--ease),
      background var(--normal) var(--ease),
      filter var(--normal) var(--ease);
  }
  /* пустая обложка (значок) — тёмная плашка с едва заметной рамкой, как у Dotify */
  .cover.empty {
    box-shadow: inset 0 0 0 1px var(--border);
  }
  .tile:hover .cover {
    transform: translateY(-2px);
  }
  .tile:hover .cover.empty {
    background: var(--hover);
  }
  .tile:hover .cover:not(.empty) {
    filter: brightness(1.06);
  }
  .tile:active .cover {
    transform: scale(0.97);
  }
  .cover.round {
    border-radius: 50%;
  }
  img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .collage {
    display: grid;
    grid-template-columns: 1fr 1fr;
    width: 100%;
    height: 100%;
  }
  .ghost .cover {
    box-shadow: inset 0 0 0 1px var(--border-strong);
    color: var(--text-3);
  }
  .src {
    position: absolute;
    right: 8px;
    bottom: 8px;
    display: grid;
    line-height: 0;
  }
  .badge {
    position: absolute;
    left: 8px;
    top: 8px;
    display: grid;
    place-items: center;
    width: 26px;
    height: 26px;
    border-radius: 8px;
    background: rgba(20, 20, 22, 0.7);
    color: #fff;
  }
  .text {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .text.center {
    align-items: center;
    text-align: center;
  }
  .title {
    max-width: 100%;
    font-size: calc(var(--fs-2) * var(--fs, 1));
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .sub {
    max-width: 100%;
    font-size: calc(var(--fs-meta) * var(--fs, 1));
    color: var(--text-2);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .meta {
    margin-top: 1px;
    font-size: calc(var(--fs-meta) * var(--fs, 1));
    color: var(--text-3);
  }
  .ph {
    display: grid;
    color: var(--accent);
    transition: color 0.6s var(--ease);
  }
</style>
