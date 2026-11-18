<script lang="ts">
  // Правая панель «Очередь / Текст» (app/side-pane.svelte.ts). Очередь — те же строки, что в плеере
  // (queueView / queueItems), текст — LyricsView в уменьшенном масштабе. Выезжает справа, закрывается
  // крайней кнопкой мини-плеера.
  import { fly } from 'svelte/transition'
  import TrackRow from '../components/TrackRow.svelte'
  import IconButton from '../components/IconButton.svelte'
  import LyricsView from '../lyrics/LyricsView.svelte'
  import { lyrics } from '../lyrics/lyrics.svelte'
  import { cascade } from '../lib/cascade'
  import { glide, rise, xfade } from '../lib/motion'
  import { t } from '../lib/i18n.svelte'
  import { player } from '../player/player.svelte'
  import { queueItems, queueView } from '../player/queue-view'
  import { WAVE_CONTEXT } from '../player/my-wave.svelte'
  import { autoplay } from '../player/autoplay.svelte'
  import { sidePane } from './side-pane.svelte'

  const hasLyrics = $derived(!!player.current && lyrics.status === 'ready')
  /** Текст пропал (новый трек без текста) — панель сама показывает очередь. */
  const mode = $derived(sidePane.mode === 'lyrics' && hasLyrics ? 'lyrics' : 'queue')
  const queue = $derived(
    queueView({ tracks: player.tracks, order: player.order, pos: player.pos, ids: player.entryIds, autoRefs: player.autoRefs }),
  )
  const rows = $derived(queueItems(queue, { autoSection: player.context !== WAVE_CONTEXT, autoOn: autoplay.on }))
</script>

<aside class="pane" transition:fly={{ x: 40, duration: 260 }} aria-label={mode === 'lyrics' ? t('Текст песни') : t('Очередь')}>
  {#key mode}
    <div class="body" in:fly={{ y: 8, duration: 220 }}>
      {#if mode === 'lyrics'}
        <div class="lyr"><LyricsView /></div>
      {:else}
        <div class="rows" use:cascade>
          {#each rows as row (row.key)}
            <div class="row-slot" animate:glide in:rise={{ y: 6 }} out:xfade={{ duration: 140 }}>
              {#if row.kind === 'head'}
                <h3>{row.section === 'earlier' ? t('Ранее') : row.section === 'now' ? t('Сейчас играет') : t('Далее')}</h3>
              {:else if row.kind === 'track'}
                {@const entry = row.entry}
                <div class="dim" class:on={row.section === 'earlier'}>
                  {#if row.section === 'now'}
                    <TrackRow track={entry.track} variant="queue" onplay={() => player.toggle()} />
                  {:else}
                    <TrackRow track={entry.track} variant="queue" onplay={() => player.playPos(entry.pos)} />
                  {/if}
                </div>
              {:else if row.kind === 'empty'}
                <p class="empty">{t('Очередь пуста — включи трек из поиска.')}</p>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    </div>
  {/key}
  {#if hasLyrics}
    <div class="foot">
      <IconButton
        icon={mode === 'lyrics' ? 'queue' : 'letterT'}
        label={mode === 'lyrics' ? t('Очередь') : t('Текст песни')}
        size={17}
        onclick={() => (sidePane.mode = mode === 'lyrics' ? 'queue' : 'lyrics')}
      />
    </div>
  {/if}
</aside>

<style>
  .pane {
    display: flex;
    flex-direction: column;
    min-height: 0;
    border-radius: var(--radius-xl);
    background: var(--surface-0);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    overflow: hidden;
  }
  .body {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    padding: 10px 8px;
  }
  .lyr {
    height: 100%;
    /* текст в узкой панели — мельче, чем на весь экран */
    zoom: 0.62;
  }
  h3 {
    margin: 14px 6px 6px;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-3);
  }
  .empty {
    margin: 8px 6px;
    color: var(--text-3);
  }
  .dim {
    transition: opacity var(--fast) var(--ease);
  }
  .dim.on {
    opacity: 0.55;
  }
  .dim.on:hover,
  .dim.on:focus-within {
    opacity: 0.9;
  }
  .foot {
    display: flex;
    padding: 8px 10px 10px;
    border-top: 1px solid var(--border);
  }
</style>
