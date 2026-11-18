<script lang="ts">
  // Баннер «Вот твоя музыкальная карта» в медиатеке: один раз — после первого переноса плейлистов
  // или когда на карте набралось 20 исполнителей. Клик ведёт на карту, крестик закрывает;
  // в обоих случаях больше не показывается (`library.map_banner_done`).
  import Icon from '../../components/Icon.svelte'
  import { t } from '../../lib/i18n.svelte'
  import { pop, rise } from '../../lib/motion'
  import { settings } from '../../lib/settings.svelte'
  import { mapApi } from '../../lib/artist-map/api'
  import { discoveredCount } from '../../lib/artist-map/graph'
  import { shouldOfferMap } from '../../lib/artist-map/banner'

  interface Props {
    /** В медиатеке уже есть перенесённые плейлисты сервисов. */
    imported: boolean
    onopen: () => void
  }

  let { imported, onopen }: Props = $props()

  const done = $derived(settings.get('library.map_banner_done'))
  let artists = $state(0)

  $effect(() => {
    if (done) return
    let alive = true
    mapApi
      .graph()
      .then((g) => {
        if (alive) artists = discoveredCount(g)
      })
      .catch(() => {
        // вне приложения или граф не собрался — просто без баннера
      })
    return () => {
      alive = false
    }
  })

  const show = $derived(shouldOfferMap({ done, artists, imported }))

  function open() {
    settings.set('library.map_banner_done', true)
    onopen()
  }

  function dismiss(e: MouseEvent) {
    e.stopPropagation()
    settings.set('library.map_banner_done', true)
  }
</script>

{#if show}
  <div class="banner" in:rise={{ y: 12 }} out:pop={{ y: 6 }}>
    <button class="body" onclick={open}>
      <span class="mark"><Icon name="sparkles" size={20} /></span>
      <span class="text">
        <b>{t('Вот твоя музыкальная карта')}</b>
        <small>{t('Кто с кем связан — по фитам, подпискам и общим соавторам')}</small>
      </span>
      <span class="go">{t('Открыть карту')} <Icon name="chevronRight" size={15} /></span>
    </button>
    <button class="close" aria-label={t('Закрыть')} onclick={dismiss}><Icon name="x" size={15} /></button>
  </div>
{/if}

<style>
  .banner {
    position: relative;
    margin-top: 20px;
    border-radius: var(--radius-l);
    background:
      radial-gradient(120% 160% at 0% 0%, color-mix(in srgb, var(--accent) 22%, transparent), transparent 60%),
      var(--surface-2);
    border: 1px solid var(--card-line);
    overflow: hidden;
  }
  .body {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 14px 52px 14px 16px;
    text-align: left;
    transition: transform var(--fast) var(--ease);
  }
  .body:active {
    transform: scale(0.99);
  }
  .mark {
    flex: none;
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    border-radius: 50%;
    background: var(--accent);
    color: var(--accent-ink);
  }
  .text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  b {
    font: 700 calc(15px * var(--fs, 1)) var(--font-display);
  }
  small {
    font-size: 12.5px;
    color: var(--text-3);
  }
  .go {
    flex: none;
    display: inline-flex;
    align-items: center;
    gap: 2px;
    font-size: 13px;
    font-weight: 600;
    color: var(--text-2);
    transition: color var(--fast) var(--ease), transform var(--fast) var(--ease);
  }
  .body:hover .go {
    color: var(--text);
    transform: translateX(2px);
  }
  .close {
    position: absolute;
    top: 50%;
    right: 12px;
    translate: 0 -50%;
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    border-radius: 50%;
    color: var(--text-3);
    transition: background var(--fast) var(--ease), color var(--fast) var(--ease);
  }
  .close:hover {
    background: var(--hover);
    color: var(--text);
  }
</style>
