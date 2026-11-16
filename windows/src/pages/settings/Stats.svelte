<script lang="ts">
  // Статистика (pc/Screenshot_32, SPEC §3.8): итоги из локальной таблицы plays — числа со счётом,
  // график по периоду, любимые артисты и треки. Клик по артисту/треку — открыть / включить.
  import CountUp from '../../components/CountUp.svelte'
  import Icon from '../../components/Icon.svelte'
  import { api, type Stats, type StatsPeriod } from '../../lib/api'
  import { plural } from '../../lib/format'
  import { cascade } from '../../lib/cascade'
  import { openRef } from '../../app/router.svelte'
  import { settingsPanel } from '../settings-section.svelte'
  import { player } from '../../player/player.svelte'

  const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']

  // экран как pc/Screenshot_32 — итоги за всё время
  const period: StatsPeriod = 'all'
  let stats = $state<Stats | null>(null)
  let error = $state<string | null>(null)

  $effect(() => {
    const p = period
    api
      .stats(p)
      .then((s) => {
        if (p === period) stats = s
        error = null
      })
      .catch(() => (error = 'Статистика есть только в приложении'))
  })

  const hours = (ms: number) => Math.floor(ms / 3_600_000)
  /** «57 часов» или, если меньше часа, «12 минут». */
  function timeText(ms: number) {
    const h = hours(ms)
    if (h) return `${h} ${plural(h, ['час', 'часа', 'часов'])}`
    const m = Math.round(ms / 60_000)
    return `${m} ${plural(m, ['минута', 'минуты', 'минут'])}`
  }
  const artists = $derived(stats ? [stats.top_artist, ...stats.more_artists].filter((a) => !!a) : [])

  function openArtist(ref: string | null) {
    if (!ref) return
    settingsPanel.close()
    openRef(ref)
  }

  async function playTop(i: number) {
    if (!stats) return
    const refs = stats.top_tracks.map((t) => t.ref)
    // полные данные треков — из локального кэша
    const list = await api.cachedTracks(refs).catch(() => [])
    const at = list.findIndex((t) => t.ref === refs[i])
    if (list.length) void player.playList(list, Math.max(0, at), 'stats', 'Любимые треки')
  }
</script>

{#if error}
  <p class="hint">{error}</p>
{:else if !stats}
  <div class="card skel big"></div>
{:else if !stats.plays}
  <div class="card empty">
    <Icon name="headphones" size={26} />
    <p>Пока пусто. Слушай музыку — засчитывается трек, прослушанный хотя бы наполовину (или 30 секунд).</p>
  </div>
{:else}
  <div class="card">
    <div class="main">
      <div><b><CountUp value={stats.plays} /></b><span>{plural(stats.plays, ['Прослушивание', 'Прослушивания', 'Прослушиваний'])}</span></div>
      <div><b><CountUp value={stats.tracks} /></b><span>{plural(stats.tracks, ['Трек', 'Трека', 'Треков'])}</span></div>
      {#if stats.total_ms >= 3_600_000}
        <div><b><CountUp value={hours(stats.total_ms)} /></b><span>{plural(hours(stats.total_ms), ['час', 'часа', 'часов'])}</span></div>
      {:else}
        <div><b><CountUp value={Math.round(stats.total_ms / 60_000)} /></b><span>{plural(Math.round(stats.total_ms / 60_000), ['минута', 'минуты', 'минут'])}</span></div>
      {/if}
    </div>
    <div class="minor">
      <div><b><CountUp value={stats.streak_days} /></b><span>{plural(stats.streak_days, ['день', 'дня', 'дней'])} подряд</span></div>
      <div><b>{stats.peak_hour != null ? `${String(stats.peak_hour).padStart(2, '0')}:00` : '—'}</b><span>пик прослушивания</span></div>
      <div><b><CountUp value={stats.per_day} /></b><span>{plural(stats.per_day, ['трек', 'трека', 'треков'])} в день</span></div>
      <div><b><CountUp value={stats.artists} /></b><span>{plural(stats.artists, ['артист', 'артиста', 'артистов'])} всего</span></div>
      <div><b>{stats.fav_weekday != null ? weekdays[stats.fav_weekday] : '—'}</b><span>любимый день недели</span></div>
      {#if stats.delta_pct != null}
        <div>
          <b class:up={stats.delta_pct > 0} class:down={stats.delta_pct < 0}>{stats.delta_pct > 0 ? '+' : ''}<CountUp value={stats.delta_pct} />%</b>
          <span>к прошлому периоду</span>
        </div>
      {/if}
    </div>
  </div>

  {#if artists.length}
    <h2>Любимые артисты</h2>
    <div class="artists" use:cascade={period}>
      {#each artists as a (a.name)}
        <button class="artist" onclick={() => openArtist(a.ref)} disabled={!a.ref}>
          <span class="av">
            {#if a.avatar_url}<img class="fade-img" src={a.avatar_url} alt="" onload={(e) => e.currentTarget.classList.add('loaded')} />{:else}<Icon name="user" size={34} />{/if}
          </span>
          <b>{a.name}</b>
          <small>{timeText(a.ms)}</small>
          <small>{a.plays} {plural(a.plays, ['раз', 'раза', 'раз'])}</small>
        </button>
      {/each}
    </div>
  {/if}

  {#if stats.top_tracks.length}
    <h2>Любимые треки</h2>
    <div class="tracks" use:cascade={period}>
      {#each stats.top_tracks as t, i (t.ref)}
        <button class="track" onclick={() => playTop(i)}>
          {#if t.cover_url}<img class="fade-img" src={t.cover_url} alt="" onload={(e) => e.currentTarget.classList.add('loaded')} />{:else}<span class="ph"></span>{/if}
          <span class="name"><span class="dim">{t.artist} —</span> {t.title}</span>
          <span class="n">{t.plays}</span>
        </button>
      {/each}
    </div>
  {/if}
{/if}

<style>
  .card {
    padding: 18px;
    border-radius: 16px;
    background: var(--plate);
    border: 1px solid var(--border);
  }
  .card.big {
    height: 260px;
  }
  .card.empty {
    display: flex;
    gap: 14px;
    align-items: center;
    color: var(--text-2);
  }
  .card.empty p {
    margin: 0;
    font-size: calc(13px * var(--fs, 1));
    line-height: 1.5;
  }
  .main,
  .minor {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 14px 10px;
  }
  .main {
    padding-bottom: 16px;
    border-bottom: 1px solid var(--border);
  }
  .minor {
    padding-top: 16px;
  }
  .main div,
  .minor div {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }
  .main b {
    font-family: var(--font-display);
    font-size: calc(28px * var(--fs, 1));
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
  .minor b {
    font-size: calc(16px * var(--fs, 1));
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
  .minor b.up {
    color: var(--online);
  }
  .minor b.down {
    color: var(--danger);
  }
  .main span,
  .minor span {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  h2 {
    margin: 26px 0 12px;
    font-size: calc(22px * var(--fs, 1));
    font-weight: 800;
  }
  .artists {
    display: flex;
    gap: 14px;
    overflow-x: auto;
    scrollbar-width: none;
  }
  .artist {
    display: flex;
    flex-direction: column;
    align-items: center;
    width: 104px;
    flex-shrink: 0;
    text-align: center;
  }
  .artist:disabled {
    cursor: default;
  }
  .av {
    display: grid;
    place-items: center;
    width: 100px;
    height: 100px;
    margin-bottom: 8px;
    overflow: hidden;
    border-radius: 50%;
    background: var(--surface-3);
    color: var(--text-3);
    transition: transform var(--normal) var(--ease);
  }
  .artist:hover:not(:disabled) .av {
    transform: scale(1.04);
  }
  .av img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .artist b {
    max-width: 100%;
    font-size: calc(13px * var(--fs, 1));
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .artist small {
    font-size: calc(11px * var(--fs, 1));
    color: var(--text-3);
  }
  .tracks {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .track {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 4px 6px;
    border-radius: 8px;
    text-align: left;
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    transition: background var(--fast) var(--ease);
  }
  .track:hover {
    background: var(--hover);
  }
  .track img,
  .ph {
    width: 18px;
    height: 18px;
    flex-shrink: 0;
    border-radius: 3px;
    object-fit: cover;
    background: var(--surface-3);
  }
  .name {
    flex: 1;
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .dim {
    color: var(--text-2);
    font-weight: 500;
  }
  .n {
    color: var(--text-3);
    font-weight: 500;
    font-variant-numeric: tabular-nums;
  }
  .hint {
    color: var(--text-3);
  }
</style>
