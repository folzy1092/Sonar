<script lang="ts">
  import SourceIcon from './SourceIcon.svelte'
  import Icon from './Icon.svelte'
  import { xfade } from '../lib/motion'
  import { refKind, serviceOf } from '../lib/services'
  import { offline } from '../lib/offline.svelte'

  interface Props {
    url: string | null | undefined
    size: number
    radius?: string
    /** Значок источника в углу: сервис по ref трека (lib/services). */
    source?: string | null
  }

  let { url, size, radius = 'var(--radius-s)', source = null }: Props = $props()
  let failed = $state(false)
  const src = $derived(refKind(source) === 'track' ? serviceOf(source) : null)

  $effect(() => {
    url
    failed = false
  })
</script>

<div class="cover" style:width="{size}px" style:height="{size}px" style:border-radius={radius}>
  <!-- смена обложки — кроссфейд: старая гаснет, новая проявляется, когда загрузится -->
  {#key url && !failed ? url : ''}
    {#if url && !failed}
      <img
        src={offline.src(url, size)}
        alt=""
        loading="lazy"
        draggable="false"
        onload={(e) => e.currentTarget.classList.add('loaded')}
        onerror={() => (failed = true)}
        out:xfade={{ duration: 380 }}
      />
    {:else}
      <span class="ph" in:xfade><Icon name="music" size={Math.round(size * 0.42)} stroke={1.6} /></span>
    {/if}
  {/key}
  {#if src}
    <span class="src"><SourceIcon service={src} size={Math.max(12, Math.min(18, Math.round(size * 0.24)))} /></span>
  {/if}
</div>

<style>
  .cover {
    position: relative;
    display: grid;
    place-items: center;
    flex-shrink: 0;
    overflow: hidden;
    /* заглушка без картинки — в оттенке темы (palette.ts `--ph-wash` / `--ph-ink`; «Спокойно» — серая) */
    background:
      linear-gradient(var(--ph-wash), var(--ph-wash)),
      linear-gradient(135deg, var(--surface-3), var(--surface-2));
    color: var(--ph-ink);
  }
  .cover > img,
  .ph {
    grid-area: 1 / 1;
  }
  .ph {
    display: grid;
    place-items: center;
  }
  img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    opacity: 0;
    transition: opacity 0.32s var(--ease);
  }
  img:global(.loaded) {
    opacity: 1;
  }
  .src {
    position: absolute;
    right: 3px;
    bottom: 3px;
    display: grid;
    line-height: 0;
  }
</style>
