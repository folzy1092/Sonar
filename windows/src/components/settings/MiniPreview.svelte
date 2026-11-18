<script lang="ts">
  // Живой пример мини плеера (NEXT_PROMPT «Этап 0» п. 4): настоящий MiniPlayer, а не рисунок —
  // стиль, фон и прогресс меняются в нём сразу. Пока тянут ползунки формы и обложки, их значение
  // подставляется сюда до сохранения. Нажать в примере ничего нельзя — он только показывает.
  // `data-fx-skip`: кольца и дуга смены трека от примера не рисуются (fx-layer.ts `visible`).
  import MiniPlayer from '../../app/MiniPlayer.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { t } from '../../lib/i18n.svelte'

  let { shape, cover }: { shape: number; cover: number } = $props()
  const off = $derived(settings.get('mini.style') === 'off')
</script>

<figure class="preview" aria-label={t('Так выглядит мини плеер')}>
  {#if off}
    <div class="off">{t('Мини плеер выключен')}</div>
  {:else}
    <div class="live" inert data-fx-skip style:--cap-k={shape / 100} style:--cover-k={cover / 100}>
      <MiniPlayer preview />
    </div>
  {/if}
  <figcaption>{t('Так выглядит мини плеер')}</figcaption>
</figure>

<style>
  .preview {
    column-span: all;
    margin: 4px 0 10px;
    padding: 14px;
    border-radius: 16px;
    background: var(--plate);
    border: 1px solid var(--card-line);
  }
  .live {
    pointer-events: none;
    user-select: none;
  }
  .off {
    display: grid;
    place-items: center;
    height: var(--player-h);
    border-radius: 999px;
    border: 1px dashed var(--border);
    color: var(--text-3);
    font-size: calc(13px * var(--fs, 1));
  }
  figcaption {
    margin-top: 10px;
    text-align: center;
    font-size: calc(11px * var(--fs, 1));
    color: var(--text-3);
  }
</style>
