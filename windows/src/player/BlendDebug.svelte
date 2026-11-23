<script lang="ts">
  // Отладочная карточка сведения (docs/BLEND.md §10.3): только для подписки Dev и с включённой
  // «Отладкой сведения» (`audio.blend_debug`). Числа анализа обоих треков, фаза перехода, очередь анализа,
  // план с баллами — и та же строка оценки, что в кнопке.
  import { t } from '../lib/i18n.svelte'
  import { pop } from '../lib/motion'
  import { settings } from '../lib/settings.svelte'
  import { subscriptionOf } from '../lib/subscription'
  import type { Track } from '../lib/api'
  import BlendRate from './BlendRate.svelte'
  import { blendAnalysis } from './blend/analyze.svelte'
  import { analysisLine, minus, PART_TEXT, PHASE_TEXT, scoreParts } from './blend/debug-view'
  import { KIND_TEXT } from './blend/view'
  import { player } from './player.svelte'

  const dev = $derived(subscriptionOf({ username: settings.get('profile.username') }).tier === 'dev')
  const shown = $derived(dev && settings.get('audio.blend_debug') && player.blendOn)

  const blend = $derived(player.blend)
  const plan = $derived(blend.current?.plan ?? blend.next?.plan ?? null)
  const nextTrack = $derived<Track | null>(blend.next?.to ?? player.upNext[0] ?? null)
  const mem = $derived(blendAnalysis.stats())

  function about(track: Track): string {
    const a = blendAnalysis.peek(track.ref)
    if (a) return `${analysisLine(a)} · ${a.gridStable ? t('сетка стабильна') : t('сетка плавает')}`
    const state = blendAnalysis.state(track.ref)
    if (state === 'pending') return t('считается…')
    if (state === 'failed') return blendAnalysis.failure(track.ref) ?? t('анализ не удался')
    return t('нет анализа')
  }
</script>

{#if shown}
  <aside class="debug" aria-label={t('Отладочная панель')} transition:pop>
    <h3>{t('Отладочная панель')}</h3>
    <dl>
      {#each [{ label: t('Отладка::сейчас'), track: player.current }, { label: t('Отладка::следующий'), track: nextTrack }] as row (row.label)}
        <dt>{row.label}</dt>
        <dd>
          {#if row.track}
            <b>{row.track.artist} — {row.track.title}</b>
            <code>{about(row.track)}</code>
          {:else}
            <code>—</code>
          {/if}
        </dd>
      {/each}

      <dt>{t('Отладка::переход')}</dt>
      <dd><code>{t(PHASE_TEXT[blend.phase])} · {t('фаза {ms} мс', { ms: minus(blend.phaseErrMs) })}</code></dd>

      <dt>{t('Отладка::память')}</dt>
      <dd>
        <code>
          {t('анализов {ready} · в очереди {waiting} · считается {running} · ошибок {failed} · посчитано {computed}', mem)}
        </code>
      </dd>

      <dt>{t('Отладка::план')}</dt>
      <dd>
        {#if plan}
          <code>
            {t(KIND_TEXT[plan.kind].name)}{#if blend.next}
              · {t('момент {rank} из {total}', { rank: blend.next.rank, total: blend.next.total })}{/if}
          </code>
          <span class="parts">
            {#each scoreParts(plan.parts) as p (p.part)}
              <span>{t(PART_TEXT[p.part])} <b>{p.value}</b></span>
            {/each}
          </span>
        {:else}
          <code>—</code>
        {/if}
      </dd>
    </dl>
    <BlendRate />
  </aside>
{/if}

<style>
  .debug {
    position: fixed;
    right: 16px;
    bottom: calc(var(--player-h) + 22px);
    z-index: 60;
    display: grid;
    gap: 8px;
    width: min(380px, calc(100vw - 32px));
    padding: 12px;
    border-radius: 14px;
    background: var(--surface-3);
    border: 1px solid var(--border-strong);
    box-shadow: 0 12px 32px rgb(0 0 0 / 0.35);
    color: var(--text);
    font-size: calc(12px * var(--fs, 1));
  }
  h3 {
    margin: 0;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 700;
    color: var(--text-2);
  }
  dl {
    display: grid;
    grid-template-columns: auto 1fr;
    gap: 6px 10px;
    margin: 0;
  }
  dt {
    color: var(--text-2);
  }
  dd {
    display: grid;
    gap: 2px;
    min-width: 0;
    margin: 0;
  }
  dd b {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-weight: 600;
  }
  code {
    font-family: ui-monospace, 'Cascadia Mono', Consolas, monospace;
    font-size: calc(11px * var(--fs, 1));
    color: var(--text-2);
    overflow-wrap: anywhere;
  }
  .parts {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    margin-top: 2px;
  }
  .parts span {
    padding: 2px 6px;
    border-radius: 6px;
    background: var(--plate);
    color: var(--text-2);
    font-size: calc(11px * var(--fs, 1));
  }
  .parts b {
    color: var(--text);
    font-weight: 600;
  }
</style>
