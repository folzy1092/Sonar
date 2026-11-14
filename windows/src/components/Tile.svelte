<script lang="ts">
  import Icon from './Icon.svelte'
  import type { IconName } from './icons'

  interface Props {
    title: string
    subtitle?: string
    meta?: string
    icon?: IconName
    round?: boolean
    ghost?: boolean
  }

  let { title, subtitle, meta, icon = 'music', round = false, ghost = false }: Props = $props()
</script>

<div class="tile" class:ghost>
  <div class="cover" class:round>
    <Icon name={icon} size={36} stroke={1.6} />
  </div>
  <div class="text" class:center={round}>
    <span class="title">{title}</span>
    {#if subtitle}<span class="sub">{subtitle}</span>{/if}
    {#if meta}<span class="meta">{meta}</span>{/if}
  </div>
</div>

<style>
  .tile {
    display: flex;
    flex-direction: column;
    gap: 10px;
    width: 160px;
    flex-shrink: 0;
  }
  .cover {
    display: grid;
    place-items: center;
    aspect-ratio: 1;
    border-radius: var(--radius-l);
    background: var(--plate);
    border: 1px solid var(--border);
    color: var(--text-2);
    transition:
      transform var(--normal) var(--ease),
      background var(--normal) var(--ease);
  }
  .tile:hover .cover {
    transform: translateY(-2px);
    background: var(--hover);
  }
  .cover.round {
    border-radius: 50%;
  }
  .ghost .cover {
    border-style: dashed;
    color: var(--text-3);
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
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .sub {
    font-size: 12px;
    color: var(--text-2);
  }
  .meta {
    font-size: 11px;
    color: var(--text-3);
  }
</style>
