<script lang="ts">
  import Icon from './Icon.svelte'
  import { xfade } from '../lib/motion'

  interface Props {
    url: string | null | undefined
    size: number
    radius?: string
    /** Значок источника в углу: sc / ym по ref трека. */
    source?: string | null
  }

  let { url, size, radius = 'var(--radius-s)', source = null }: Props = $props()
  let failed = $state(false)
  const src = $derived(source?.startsWith('sc:') ? 'sc' : source?.startsWith('ym:') ? 'ym' : null)

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
        src={url}
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
    <span class="src {src}" title={src === 'sc' ? 'SoundCloud' : 'Яндекс Музыка'}>{src === 'sc' ? 'SC' : 'Я'}</span>
  {/if}
</div>

<style>
  .cover {
    position: relative;
    display: grid;
    place-items: center;
    flex-shrink: 0;
    overflow: hidden;
    background: linear-gradient(135deg, var(--surface-3), var(--surface-2));
    color: var(--text-3);
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
    min-width: 15px;
    height: 15px;
    padding: 0 3px;
    border-radius: 4px;
    font-size: 8px;
    font-weight: 800;
    line-height: 15px;
    text-align: center;
    color: #fff;
  }
  .src.sc {
    background: #ff5500;
  }
  .src.ym {
    color: #111;
    background: #ffcc00;
  }
</style>
