<script lang="ts">
  // «Почему этот трек» — тихая строка под артистом у треков Sonar Mix (wave.rs `why`):
  // откуда трек пришёл в порцию. Выключается в Плеер → Вид. Смена трека — мягкая смена строки.
  import type { Track } from '../lib/api'
  import { settings } from '../lib/settings.svelte'
  import { t } from '../lib/i18n.svelte'
  import { WAVE_CONTEXT } from './my-wave.svelte'
  import { player } from './player.svelte'

  let { track }: { track: Track | null } = $props()

  const text = $derived.by(() => {
    const w = track?.why
    if (!w || player.context !== WAVE_CONTEXT || !settings.get('player.wave_why')) return ''
    const seed = w.title ? (w.artist ? `«${w.title}» — ${w.artist}` : `«${w.title}»`) : ''
    switch (w.kind) {
      case 'liked':
        return t('Из твоих Любимых — давно не звучал')
      case 'artist':
        return w.artist ? t('Ты часто слушаешь {artist}', { artist: w.artist }) : t('Популярное у любимого артиста')
      case 'explore':
        return t('Разведка: новое рядом с твоим вкусом')
      case 'session':
        return seed ? t('Похоже на {seed} — он зашёл сейчас', { seed }) : t('Похоже на то, что зашло сейчас')
      case 'seed':
        return seed ? t('Sonar Mix по {seed}', { seed }) : t('Похоже на трек, с которого начался Sonar Mix')
      default:
        return seed ? t('Похоже на {seed}', { seed }) : t('Похоже на твои лайки')
    }
  })
</script>

{#if text}
  {#key text}
    <p class="why" title={t('Почему этот трек')}>{text}</p>
  {/key}
{/if}

<style>
  .why {
    margin: 6px 0 0;
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    animation: why-in var(--normal) var(--ease);
  }
  @keyframes why-in {
    from {
      opacity: 0;
      translate: 0 3px;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .why {
      animation-name: why-fade;
    }
    @keyframes why-fade {
      from {
        opacity: 0;
      }
    }
  }
</style>
