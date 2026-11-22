<script lang="ts">
  // Плашка «Свой звук · x0.85 · Reverb» у играющего трека со своим звуком («Для этого трека», решение
  // владельца 2026-11-22: точку на кнопке скорости не замечали). Только то, что отличается от обычного
  // звука (`ownSoundParts`). Клик — всплывашка скорости (`SpeedButton.show`). Мини-плеер, страница плеера
  // и полноэкранный; появление и уход — `pop` («Меньше движения» — только прозрачность).
  import Icon from '../components/Icon.svelte'
  import { t } from '../lib/i18n.svelte'
  import { pop } from '../lib/motion'
  import { tempo } from './tempo.svelte'

  let { onopen }: { onopen: () => void } = $props()

  const label = $derived([t('Свой звук'), ...tempo.ownParts].join(' · '))
</script>

{#if tempo.perTrack}
  <button class="own" title={t('Свой звук трека')} onclick={onopen} in:pop={{ y: 4, scale: 0.9 }} out:pop={{ y: 4, scale: 0.9 }}>
    <Icon name="adjustments" size={11} />
    {#key label}<span class="text">{label}</span>{/key}
  </button>
{/if}

<style>
  /* в стиле плашки качества «AAC 160», но цветом акцента */
  .own {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    flex-shrink: 0;
    max-width: 100%;
    padding: 1px 7px;
    border-radius: 999px;
    border: 1px solid color-mix(in srgb, var(--accent) 45%, transparent);
    background: color-mix(in srgb, var(--accent) 12%, transparent);
    color: var(--accent);
    font-size: calc(10px * var(--fs, 1));
    font-weight: 600;
    letter-spacing: 0.02em;
    line-height: 1.5;
    white-space: nowrap;
    cursor: pointer;
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .own:hover {
    background: color-mix(in srgb, var(--accent) 22%, transparent);
  }
  .own:active {
    transform: scale(0.96);
  }
  .text {
    overflow: hidden;
    text-overflow: ellipsis;
    animation: tab-in var(--normal) var(--ease);
  }
</style>
