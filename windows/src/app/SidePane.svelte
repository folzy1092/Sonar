<script lang="ts">
  // Правая панель «Очередь / Текст» (app/side-pane.svelte.ts). Очередь — те же строки, что в плеере
  // (queueView / queueItems), текст — LyricsView в уменьшенном масштабе. Выезжает справа, закрывается
  // крайней кнопкой мини-плеера. Есть текст — сверху капсулы «Текст · Очередь», нет — только очередь.
  import { untrack } from 'svelte'
  import TrackRow from '../components/TrackRow.svelte'
  import Switch from '../components/settings/Switch.svelte'
  import LyricsView from '../lyrics/LyricsView.svelte'
  import { lyrics } from '../lyrics/lyrics.svelte'
  import { cascade } from '../lib/cascade'
  import { indicator } from '../lib/indicator'
  import { glide, reducedMotion, rise, xfade, fly, slide } from '../lib/motion'
  import { t } from '../lib/i18n.svelte'
  import { player } from '../player/player.svelte'
  import { growLimit, QUEUE_WINDOW, queueItems, queueView } from '../player/queue-view'
  import { isPartyContext } from '../player/blend/party-core'
  import { nearEnd } from '../lib/near-end'
  import { WAVE_CONTEXT } from '../player/my-wave.svelte'
  import { autoplay } from '../player/autoplay.svelte'
  import { knownLyrics, lyricsAvail, sidePane, type PaneMode } from './side-pane.svelte'

  const ref = $derived(player.current?.ref ?? null)
  const avail = $derived(lyricsAvail(lyrics.status, lyrics.ref, ref))
  // новый трек с текстом — текст, без текста — очередь; выбор руками держится до смены трека
  $effect(() => sidePane.sync(ref, avail))
  const mode = $derived(sidePane.shown(avail))
  // переключатель — только когда текст есть; пока текст следующего трека ищется, не прячется и не мигает
  let hasText = $state(false)
  $effect.pre(() => {
    const a = avail
    hasText = untrack(() => knownLyrics(a, hasText))
  })
  const modes: PaneMode[] = ['lyrics', 'queue']
  const queue = $derived(
    queueView({ tracks: player.tracks, order: player.order, pos: player.pos, ids: player.entryIds, autoRefs: player.autoRefs }),
  )
  // окно очереди: сразу — {QUEUE_WINDOW} треков после текущего, дальше догружаются при прокрутке (nearEnd);
  // новая очередь (другой источник) — окно снова маленькое
  let limit = $state(QUEUE_WINDOW)
  $effect.pre(() => {
    void player.context
    limit = QUEUE_WINDOW
  })
  const rows = $derived(queueItems(queue, { autoSection: player.context !== WAVE_CONTEXT, autoOn: autoplay.on, limit, party: isPartyContext(player.context) }))
  const queueTotal = $derived(queue.own.length + queue.auto.length)

  /** Переключатель появляется и прячется по высоте; «Меньше движения» — только прозрачность. */
  function reveal(node: Element) {
    return reducedMotion() ? xfade(node, { duration: 160 }) : slide(node, { duration: 220 })
  }
</script>

<aside class="pane" transition:fly={{ x: reducedMotion() ? 0 : 40, duration: 260 }} aria-label={mode === 'lyrics' ? t('Текст песни') : t('Очередь')}>
  {#if hasText}
    <div class="switch-row" transition:reveal>
      <div class="switch" role="tablist" aria-label={t('Вид панели')} use:indicator={{ key: mode, kind: 'pill' }}>
        {#each modes as m (m)}
          <button class="seg press" class:on={mode === m} role="tab" aria-selected={mode === m} onclick={() => sidePane.pick(m)}>
            {m === 'lyrics' ? t('Текст') : t('Очередь')}
          </button>
        {/each}
      </div>
    </div>
  {/if}
  {#key mode}
    <div class="body" in:fly={{ y: reducedMotion() ? 0 : 8, duration: 220 }}>
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
              {:else if row.kind === 'divider'}
                <p class="auto-line">{t('Пошли похожие')}</p>
              {:else if row.kind === 'switch'}
                <!-- граница: дальше не твоя очередь, а похожие автоплея (как в «Очереди» плеера) -->
                <div class="auto">
                  <Switch title={t('Авто похожие')} hint={autoplay.on ? (autoplay.loading && !queue.auto.length ? t('Подбираю похожие…') : t('После очереди играют похожие треки')) : t('Очередь доиграет и остановится')} on={autoplay.on} onchange={(v) => autoplay.set(v)} />
                </div>
              {:else if row.kind === 'more'}
                <div class="more" use:nearEnd={{ key: limit, onreach: () => (limit = growLimit(limit, queueTotal)) }}></div>
              {:else if row.kind === 'party'}
                <p class="empty">{t('остальное — по ходу')}</p>
              {:else if row.kind === 'empty'}
                <p class="empty">{t('Очередь пуста — включи трек из поиска.')}</p>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    </div>
  {/key}
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
  /* сторож окна очереди — невидимая строка в самом низу */
  .more {
    height: 1px;
  }
  /* строки вне экрана не раскладываются и не рисуются — прокрутка и скрытие элементов не тормозят */
  .row-slot {
    content-visibility: auto;
    contain-intrinsic-size: auto 56px;
  }
  .auto {
    margin: 10px 6px 4px;
    padding-top: 6px;
    border-top: 1px solid color-mix(in srgb, var(--text) 8%, transparent);
    font-size: calc(13px * var(--fs, 1));
  }
  .auto-line {
    margin: 8px 6px 2px;
    padding-top: 6px;
    border-top: 1px solid color-mix(in srgb, var(--text) 8%, transparent);
    font-size: calc(12px * var(--fs, 1));
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
  /* «Текст · Очередь» — две капсулы сверху, выбранную подсвечивает переезжающий индикатор */
  .switch-row {
    flex: none;
  }
  .switch {
    display: flex;
    gap: 4px;
    margin: 10px 10px 2px;
    padding: 3px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--card-line);
  }
  .seg {
    flex: 1;
    height: 30px;
    padding: 0 14px;
    border-radius: 999px;
    color: var(--text-2);
    font-weight: 600;
    font-size: calc(13px * var(--fs, 1));
    transition:
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .seg:hover:not(.on) {
    color: var(--text);
  }
  .seg.on {
    color: var(--accent-ink);
  }
  .switch :global(.tab-ind.pill) {
    background: var(--accent);
  }
</style>
