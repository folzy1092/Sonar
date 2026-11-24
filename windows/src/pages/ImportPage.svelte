<script lang="ts">
  // Перенос плейлиста по ссылке (NEXT_PROMPT этап 5): Spotify, YouTube Music, VK, Яндекс, SoundCloud
  // или Apple Music → каждому треку пара в подключённых сервисах (сверка резервного сервиса, этап 4).
  // Строки появляются каскадом и оживают по мере поиска (событие `import:progress`), сверху —
  // «Нашлось N из M»; ненайденные — отдельным списком с «Искать вручную»; внизу — «Создать плейлист».
  // Состояние — lib/import.svelte: из поиска «назад» возвращает к тому же импорту.
  import Cover from '../components/Cover.svelte'
  import EmptyState from '../components/EmptyState.svelte'
  import Icon from '../components/Icon.svelte'
  import SourceIcon from '../components/SourceIcon.svelte'
  import type { Track } from '../lib/api'
  import { errorText } from '../lib/api'
  import { cascade } from '../lib/cascade'
  import { pop } from '../lib/motion'
  import { importJob } from '../lib/import.svelte'
  import { APPLE_MUSIC, importSummary, manualQuery, progressShare, unreadCount, type ImportService, type ImportStep } from '../lib/import'
  import { library } from '../lib/library.svelte'
  import { toast } from '../lib/toast.svelte'
  import { tracksText } from '../lib/format'
  import { byId, serviceOf, type ServiceId } from '../lib/services'
  import { router } from '../app/router.svelte'
  import { search } from '../app/search.svelte'
  import { t, tn } from '../lib/i18n.svelte'

  const link = router.param ?? ''
  void importJob.start(link)

  const job = importJob
  const head = $derived(job.state.head)
  const summary = $derived(importSummary(job.state))
  const unread = $derived(unreadCount(job.state))
  const missingTracks = $derived(summary.missing.map((i) => ({ index: i, track: job.state.tracks[i] })))
  let name = $state('')
  let saving = $state(false)

  const serviceName = (s: ImportService) => (s === APPLE_MUSIC ? 'Apple Music' : t(byId(s as ServiceId)?.name ?? ''))
  const foundText = (n: number, total: number) =>
    tn(n, ['Нашёлся {n} из {total}', 'Нашлось {n} из {total}', 'Нашлось {n} из {total}']).replace('{n}', String(n)).replace('{total}', String(total))

  function manual(track: Track) {
    search.query = manualQuery(track)
    router.go('search')
  }

  async function create() {
    if (!head || saving) return
    if (job.saved) return router.go('playlist', job.saved.id)
    saving = true
    try {
      const p = await job.create(name.trim() || head.title)
      await library.refreshPlaylists()
      toast.show(t('Плейлист «{name}» теперь в медиатеке', { name: p.name }))
    } catch (e) {
      toast.show(errorText(e))
    } finally {
      saving = false
    }
  }

  /** Что показать в строке: найденная пара другого сервиса — её название, если оно другое. */
  function pairOf(step: ImportStep | null, src: Track): Track | null {
    return step?.status === 'found' && step.track && step.track.ref !== src.ref ? step.track : null
  }
</script>

{#if job.error}
  <EmptyState icon="link" title={t('Не открылось')} text={job.error} />
  <div class="retry"><button class="btn press" onclick={() => importJob.start(link, true)}><Icon name="refresh" size={16} /> {t('Повторить')}</button></div>
{:else if !head}
  <div class="card skel-card" aria-label={t('Читаю список треков…')}>
    <div class="skel cov"></div>
    <div class="lines"><div class="skel l1"></div><div class="skel l2"></div></div>
  </div>
  <p class="hint">{t('Читаю список треков…')}</p>
{:else}
  <header class="card">
    <Cover url={head.cover_url} size={120} radius="var(--radius-l)" />
    <div class="info">
      <span class="kind"><SourceIcon service={head.service} size={14} /> {serviceName(head.service)} · {head.album ? t('Альбом') : t('Плейлист')}</span>
      <h1 class="selectable" title={head.title}>{head.title}</h1>
      <small>{head.owner ? `${head.owner} · ` : ''}{tracksText(head.total)}</small>
    </div>
  </header>

  <section class="sum" aria-live="polite">
    <div class="sum-top">
      <b>{foundText(summary.matched, summary.total)}</b>
      {#if job.running}
        <span class="muted">{t('Ищу пары в подключённых сервисах…')}</span>
        <button class="btn ghost press" onclick={() => importJob.stop()}>{t('Остановить')}</button>
      {:else if summary.missing.length}
        <span class="muted">{summary.missing.length} {tn(summary.missing.length, ['трек не нашёлся', 'трека не нашлись', 'треков не нашлись'])}</span>
      {/if}
    </div>
    <div class="bar"><span style:width="{progressShare(summary) * 100}%" class:done={!job.running}></span></div>
    {#if unread}
      <p class="hint">{t('Apple Music показывает на странице не все треки: ещё {n} не прочитались.', { n: unread })}</p>
    {/if}
  </section>

  <form class="save" onsubmit={(e) => (e.preventDefault(), create())}>
    <input placeholder={head.title} bind:value={name} spellcheck="false" aria-label={t('Название')} disabled={!!job.saved} />
    <button type="submit" class="btn primary press" class:done={!!job.saved} disabled={saving || job.running || (!summary.matched && !job.saved)}>
      {#key !!job.saved}
        <span class="lbl" in:pop={{ y: 4 }}>
          {#if job.saved}<Icon name="check" size={16} /> {t('Открыть плейлист')}{:else}<Icon name="playlistAdd" size={16} /> {t('Создать плейлист')}{/if}
        </span>
      {/key}
    </button>
  </form>

  {#if missingTracks.length && !job.running}
    <section class="block" in:pop={{ y: 8 }}>
      <h2>{t('Не нашлись')}</h2>
      <div class="list" use:cascade={summary.missing.length}>
        {#each missingTracks as m (m.index)}
          <div class="row">
            <Cover url={m.track.cover_url} size={40} />
            <div class="names">
              <span class="title selectable">{m.track.title}</span>
              <span class="artist selectable">{m.track.artist}</span>
            </div>
            <button class="btn small press" onclick={() => manual(m.track)}><Icon name="search" size={14} /> {t('Искать вручную')}</button>
          </div>
        {/each}
      </div>
    </section>
  {/if}

  <section class="block">
    <h2>{head.album ? t('Треки альбома') : t('Треки плейлиста')}</h2>
    <div class="list" use:cascade={head.source}>
      {#each job.state.tracks as tr, i (i)}
        {@const step = job.state.steps[i]}
        {@const pair = pairOf(step, tr)}
        <div class="row" class:miss={step?.status === 'missing'}>
          <span class="num">{i + 1}</span>
          <Cover url={tr.cover_url} size={40} source={tr.ref} />
          <div class="names">
            <span class="title">{tr.title}</span>
            <span class="artist">{tr.artist}</span>
          </div>
          <span class="state">
            {#key step?.status ?? 'wait'}
              <span class="st" in:pop={{ y: 4 }}>
                {#if !step}
                  <span class="dot" class:idle={!job.running} aria-label={t('Ищу…')}></span>
                {:else if step.status === 'missing'}
                  <Icon name="x" size={15} /> {t('Не нашёлся')}
                {:else if pair}
                  {@const svc = serviceOf(pair.ref)}
                  {#if svc}<SourceIcon service={svc} size={14} />{/if}
                  <span class="pair" title={`${pair.artist} — ${pair.title}`}>{pair.artist} — {pair.title}</span>
                {:else}
                  <Icon name="check" size={15} /> {t('Как есть')}
                {/if}
              </span>
            {/key}
          </span>
        </div>
      {/each}
    </div>
  </section>
{/if}

<style>
  .card {
    display: flex;
    align-items: center;
    gap: 22px;
    margin-top: 22px;
    padding: 18px;
    border-radius: var(--radius-xl);
    background: linear-gradient(135deg, var(--plate), transparent);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    animation: card-in var(--normal) var(--ease);
  }
  @keyframes card-in {
    from {
      opacity: 0;
      transform: translateY(8px) scale(0.98);
    }
  }
  .info {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }
  .kind {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  h1 {
    margin: 0;
    font-family: var(--font-display);
    font-size: calc(26px * var(--fs, 1));
    font-weight: 800;
    letter-spacing: -0.01em;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  small {
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-2);
  }
  .sum {
    margin-top: 22px;
  }
  .sum-top {
    display: flex;
    align-items: center;
    gap: 12px;
    flex-wrap: wrap;
  }
  .sum-top b {
    font-family: var(--font-display);
    font-size: calc(20px * var(--fs, 1));
    font-weight: 800;
  }
  .muted {
    color: var(--text-3);
    font-size: calc(13px * var(--fs, 1));
  }
  .bar {
    height: 4px;
    margin-top: 12px;
    border-radius: 2px;
    background: var(--surface-3);
    overflow: hidden;
  }
  .bar span {
    display: block;
    height: 100%;
    border-radius: inherit;
    background: var(--accent);
    transition:
      width var(--normal) var(--ease),
      background var(--normal) var(--ease);
  }
  .bar span.done {
    background: var(--online);
  }
  .hint {
    margin: 12px 0 0;
    color: var(--text-3);
    font-size: calc(13px * var(--fs, 1));
  }
  .save {
    display: flex;
    gap: 8px;
    margin-top: 18px;
    max-width: 520px;
  }
  .save input {
    flex: 1;
    min-width: 0;
    height: 38px;
    padding: 0 12px;
    border-radius: 12px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    outline: none;
    user-select: text;
    transition: border-color var(--fast) var(--ease);
  }
  .save input:focus {
    border-color: var(--border-strong);
  }
  .btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    height: 38px;
    padding: 0 16px;
    border-radius: 12px;
    background: var(--surface-3);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    white-space: nowrap;
    transition:
      background var(--normal) var(--ease),
      color var(--normal) var(--ease),
      opacity var(--fast) var(--ease);
  }
  .btn:hover:not(:disabled) {
    background: var(--hover);
  }
  .btn.primary {
    background: var(--text);
    color: var(--on-text);
  }
  .btn.primary.done {
    background: color-mix(in srgb, var(--online) 22%, var(--surface-2));
    color: var(--text);
  }
  .btn:disabled {
    opacity: 0.45;
    cursor: default;
  }
  .btn.ghost {
    height: 30px;
    padding: 0 12px;
    background: transparent;
    color: var(--text-2);
  }
  .btn.small {
    height: 30px;
    padding: 0 12px;
    border-radius: 10px;
    font-size: calc(12px * var(--fs, 1));
  }
  .lbl {
    display: inline-flex;
    align-items: center;
    gap: 6px;
  }
  .block {
    margin-top: 28px;
  }
  h2 {
    margin: 0 0 10px;
    font-size: calc(17px * var(--fs, 1));
    font-weight: 700;
  }
  .list {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 6px 10px;
    border-radius: var(--radius-m);
    transition:
      background var(--fast) var(--ease),
      opacity var(--normal) var(--ease);
  }
  .row:hover {
    background: var(--hover);
  }
  .row.miss {
    opacity: 0.6;
  }
  .num {
    width: 24px;
    text-align: right;
    color: var(--text-3);
    font-size: calc(12px * var(--fs, 1));
    font-variant-numeric: tabular-nums;
  }
  .names {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .title,
  .artist {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .title {
    font-size: calc(14px * var(--fs, 1));
  }
  .artist {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-2);
  }
  .state {
    display: flex;
    justify-content: flex-end;
    width: 38%;
    min-width: 0;
    color: var(--text-3);
    font-size: calc(12px * var(--fs, 1));
  }
  .st {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
  }
  .pair {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
    color: var(--text-2);
  }
  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--text-3);
    animation: breathe 1.1s var(--ease) infinite alternate;
  }
  .dot.idle {
    animation: none;
    opacity: 0.3;
  }
  @keyframes breathe {
    from {
      opacity: 0.25;
      transform: scale(0.8);
    }
  }
  .retry {
    display: flex;
    justify-content: center;
  }
  .skel-card .cov {
    width: 120px;
    height: 120px;
    border-radius: var(--radius-l);
  }
  .lines {
    flex: 1;
    display: grid;
    gap: 10px;
  }
  .l1 {
    width: 60%;
    height: 20px;
    border-radius: 8px;
  }
  .l2 {
    width: 35%;
    height: 14px;
    border-radius: 8px;
  }
</style>
