<script lang="ts">
  // Шапка плейлиста / Любимых / альбома / исполнителя (pc/Screenshot_28, 19): крупная обложка
  // слева, справа название и подписи; ниже — Слушать · перемешать · В очередь и свои кнопки.
  import Icon from './Icon.svelte'
  import type { IconName } from './icons'
  import type { Snippet } from 'svelte'

  interface Props {
    title: string
    subtitle?: Snippet
    meta?: string
    image?: string | null
    covers?: string[]
    icon?: IconName
    round?: boolean
    disabled?: boolean
    onplay: () => void
    onshuffle: () => void
    onqueue: () => void
    /** Кнопки после «В очередь» (лайк альбома, перенос в Sonar…). */
    actions?: Snippet
    /** Правая часть строки кнопок (правка, сортировка, поиск). */
    tools?: Snippet
  }

  let { title, subtitle, meta, image = null, covers = [], icon = 'music', round = false, disabled = false, onplay, onshuffle, onqueue, actions, tools }: Props = $props()
  let failed = $state(false)
</script>

<header class="head">
  <div class="cover" class:round class:heart={icon === 'heart'}>
    {#if image && !failed}
      <img src={image} alt="" draggable="false" onerror={() => (failed = true)} />
    {:else if covers.length >= 4}
      <span class="collage">{#each covers.slice(0, 4) as c, i (i)}<img src={c} alt="" draggable="false" />{/each}</span>
    {:else if covers.length}
      <img src={covers[0]} alt="" draggable="false" />
    {:else}
      <Icon name={icon} size={56} filled={icon === 'heart'} stroke={1.5} />
    {/if}
  </div>
  <div class="text">
    <h1 class="selectable" {title}>{title}</h1>
    {#if subtitle}<p class="sub">{@render subtitle()}</p>{/if}
    {#if meta}<p class="meta">{meta}</p>{/if}
  </div>
</header>

<div class="bar">
  <button class="listen" {disabled} onclick={onplay}><Icon name="play" size={16} filled /> Слушать</button>
  <button class="round-btn" aria-label="Перемешать" title="Перемешать" {disabled} onclick={onshuffle}><Icon name="shuffle" size={17} /></button>
  <button class="pill" {disabled} onclick={onqueue}><Icon name="queue" size={16} /> В очередь</button>
  {#if actions}{@render actions()}{/if}
  <span class="spacer"></span>
  {#if tools}{@render tools()}{/if}
</div>

<style>
  .head {
    display: flex;
    align-items: center;
    gap: 26px;
    padding: 8px 0 22px;
  }
  .cover {
    display: grid;
    place-items: center;
    flex-shrink: 0;
    width: 168px;
    height: 168px;
    overflow: hidden;
    border-radius: var(--radius-l);
    background: var(--plate);
    border: 1px solid var(--border);
    color: var(--text-2);
    box-shadow: 0 18px 40px rgba(0, 0, 0, 0.35);
  }
  .cover.round {
    border-radius: 50%;
  }
  /* сердце Любимых — в цвет темы, как у Dotify */
  .cover.heart {
    color: var(--accent);
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
  .text {
    min-width: 0;
  }
  h1 {
    font-size: calc(44px * var(--fs, 1));
    font-weight: 800;
    line-height: 1.1;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .sub {
    margin: 8px 0 0;
    color: var(--text-2);
  }
  .meta {
    margin: 4px 0 0;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .bar {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 12px;
  }
  .spacer {
    flex: 1;
  }
  .listen,
  .pill,
  .round-btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    height: 34px;
    border-radius: 999px;
    font-weight: 600;
    transition:
      transform var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  /* «Слушать» — белая, как у Dotify (не в цвет темы) */
  .listen {
    padding: 0 20px;
    border-radius: 10px;
    background: var(--text);
    color: var(--on-text);
  }
  .pill {
    padding: 0 16px;
    border: 1px solid var(--border-strong);
    color: var(--text);
  }
  .round-btn {
    width: 34px;
    border: 1px solid var(--border-strong);
    color: var(--text-2);
  }
  .pill:hover:not(:disabled),
  .round-btn:hover:not(:disabled) {
    background: var(--hover);
    color: var(--text);
  }
  button:active:not(:disabled) {
    transform: scale(0.95);
  }
  button:disabled {
    opacity: 0.4;
    cursor: default;
  }
  .bar :global(.tool) {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    min-width: 34px;
    height: 34px;
    padding: 0 8px;
    border-radius: 999px;
    border: 1px solid var(--border-strong);
    color: var(--text-2);
    font-weight: 600;
    transition: background var(--fast) var(--ease);
  }
  .bar :global(.tool:hover) {
    background: var(--hover);
    color: var(--text);
  }
  .bar :global(.tool.on) {
    color: var(--text);
  }
  .bar :global(.tool.plain) {
    border-color: transparent;
  }
</style>
