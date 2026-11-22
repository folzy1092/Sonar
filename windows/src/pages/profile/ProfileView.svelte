<script lang="ts" module>
  import type { NickEffect, ProfileLayout, ProfileLink, ShowcaseItem } from '../../lib/profile-look'
  /** Вид профиля (SETTINGS_NEXT «Профиль»): с ним шапка — та же карточка, что превью в настройках. */
  export interface ProfileLook {
    banner: string
    background: string
    color: string | null
    status: string
    bio: string
    links: readonly ProfileLink[]
    layout: ProfileLayout
    nickFont: string
    nickEffect: NickEffect
    nickColor2: string | null
    showcase: readonly ShowcaseItem[]
  }
</script>

<script lang="ts">
  // Страница публичного профиля — то, что гость увидит по ссылке `try-sonar.ru/@username`.
  // Рисует только `PublicProfile` (lib/public-profile.ts, тот же объект, что отдаст
  // `GET /public/users/{username}`), поэтому страница сайта `site/` повторяет эту раскладку один в один:
  // шапка (аватар, имя, @username · #номер · дата, «Открыть в Sonar») → «Сейчас слушает» → цифры
  // статистики → Любимые → плейлисты → чаще всего слушает. Только просмотр: у гостя ничего не играет.
  import CountUp from '../../components/CountUp.svelte'
  import Icon from '../../components/Icon.svelte'
  import DevBadge from '../../components/profile/DevBadge.svelte'
  import ProfileCard from '../../components/profile/ProfileCard.svelte'
  import TasteMatch, { type TasteBlock } from './TasteMatch.svelte'
  import { subscriptionOf } from '../../lib/subscription'
  import { cascade } from '../../lib/cascade'
  import { dateLong, durationText, tracksText } from '../../lib/format'
  import { t, tn } from '../../lib/i18n.svelte'
  import { formatHours, hoursPluralCount, profileInitial, type PublicProfile, type PublicTrack } from '../../lib/public-profile'

  const MS_PER_HOUR = 3_600_000

  let {
    profile,
    loading,
    look = null,
    taste = null,
  }: { profile: PublicProfile; loading: boolean; look?: ProfileLook | null; taste?: TasteBlock | null } = $props()

  const initial = $derived(profileInitial(profile))
  // значок «Dev» у ника разработчика; с сервером признак придёт в самом профиле
  const dev = $derived(subscriptionOf({ username: profile.username }).tier === 'dev')
  const since = $derived(profile.created_at ? dateLong(new Date(profile.created_at).toISOString().slice(0, 10)) : null)
  const moreLikes = $derived(profile.likes.count - profile.likes.tracks.length)
  const morePlaylists = $derived(profile.playlist_count - profile.playlists.length)
  const empty = $derived(!loading && !profile.stats && !profile.likes.count && !profile.playlist_count && !profile.now_playing)

  const loaded = (e: Event) => (e.currentTarget as HTMLElement).classList.add('loaded')
</script>

{#snippet cover(url: string | null, size: number)}
  <span class="cover" style:--size="{size}px">
    {#if url}<img src={url} alt="" loading="lazy" draggable="false" class="fade-img" onload={loaded} />{:else}<Icon name="music" size={Math.round(size / 2.4)} />{/if}
  </span>
{/snippet}

{#snippet trackRow(track: PublicTrack)}
  <li class="row">
    {@render cover(track.cover_url, 40)}
    <span class="meta"><b>{track.title}</b><small>{track.artist}</small></span>
    <span class="len">{durationText(track.duration_ms)}</span>
  </li>
{/snippet}

<article class="profile">
  {#if look}
    <div class="look">
      <ProfileCard name={profile.display_name} username={profile.username ?? ''} avatar={profile.avatar_url} {...look} />
      <button class="open" disabled title={t('Кнопка для гостей на сайте: открывает профиль в приложении')}>
        <Icon name="headphones" size={16} />{t('Открыть в Sonar')}
      </button>
    </div>
  {:else}
  <header class="hero">
    <span class="ava">
      {#if profile.avatar_url}<img src={profile.avatar_url} alt="" draggable="false" class="fade-img" onload={loaded} />{:else}<span class="initial">{initial}</span>{/if}
    </span>
    <div class="who">
      <span class="kind">{t('Профиль Sonar')}</span>
      <span class="name-line">
        <h1>{profile.display_name || t('Без имени')}</h1>
        {#if dev}<DevBadge size={13} />{/if}
      </span>
      <p class="handle">
        {#if profile.username}<span>@{profile.username}</span>{:else}<span class="muted">{t('без @username')}</span>{/if}
        {#if profile.number !== null}<span>#{profile.number}</span>{/if}
        {#if since}<span>{t('в Sonar с {date}', { date: since })}</span>{/if}
      </p>
      <button class="open" disabled title={t('Кнопка для гостей на сайте: открывает профиль в приложении')}>
        <Icon name="headphones" size={16} />{t('Открыть в Sonar')}
      </button>
    </div>
  </header>
  {/if}

  {#if loading}
    <div class="skels" aria-hidden="true">
      <div class="skel stat-skel"></div>
      {#each { length: 4 } as _, i (i)}<div class="skel row-skel"></div>{/each}
    </div>
  {:else if empty}
    <div class="empty">
      <Icon name="user2" size={28} />
      <b>{t('Профиль пока пуст')}</b>
      <small>{t('Лайкни треки и собери плейлисты — они появятся здесь')}</small>
    </div>
  {:else}
    <div class="sections" use:cascade={loading}>
      {#if profile.now_playing}
        <section class="now">
          {@render cover(profile.now_playing.cover_url, 56)}
          <span class="meta">
            <small class="label"><Icon name="waveform" size={14} />{t('Сейчас слушает')}</small>
            <b>{profile.now_playing.title}</b>
            <small>{profile.now_playing.artist}</small>
          </span>
        </section>
      {/if}

      {#if taste}<TasteMatch {taste} />{/if}

      {#if profile.stats}
        <section class="stats">
          <div><b><CountUp value={profile.stats.plays} /></b><span>{t('Прослушивания')}</span></div>
          <div><b><CountUp value={profile.stats.total_ms / MS_PER_HOUR} format={formatHours} /></b><span>{tn(hoursPluralCount(profile.stats.total_ms / MS_PER_HOUR), ['час музыки', 'часа музыки', 'часов музыки'])}</span></div>
          <div><b><CountUp value={profile.stats.tracks} /></b><span>{t('Треки')}</span></div>
          <div><b><CountUp value={profile.stats.artists} /></b><span>{t('Артисты')}</span></div>
          {#if profile.stats.streak_days > 1}
            <div><b><CountUp value={profile.stats.streak_days} /></b><span>{tn(profile.stats.streak_days, ['день подряд', 'дня подряд', 'дней подряд'])}</span></div>
          {/if}
        </section>
      {/if}

      {#if profile.likes.count}
        <section>
          <h2><Icon name="heart" size={18} filled />{t('Любимые')}<small>{tracksText(profile.likes.count)}</small></h2>
          <ul class="list" use:cascade>
            {#each profile.likes.tracks as track (track.ref)}{@render trackRow(track)}{/each}
          </ul>
          {#if moreLikes > 0}<p class="more">{t('и ещё {n}', { n: tracksText(moreLikes) })}</p>{/if}
        </section>
      {/if}

      {#if profile.playlist_count}
        <section>
          <h2><Icon name="playlist" size={18} />{t('Плейлисты')}<small>{profile.playlist_count}</small></h2>
          <ul class="grid" use:cascade>
            {#each profile.playlists as pl (pl.id)}
              <li class="card">
                <span class="collage" class:four={pl.covers.length >= 4}>
                  {#if pl.covers.length >= 4}
                    {#each pl.covers as url, i (i)}<img src={url} alt="" loading="lazy" draggable="false" class="fade-img" onload={loaded} />{/each}
                  {:else if pl.covers[0]}
                    <img src={pl.covers[0]} alt="" loading="lazy" draggable="false" class="fade-img" onload={loaded} />
                  {:else}
                    <Icon name="playlist" size={28} />
                  {/if}
                </span>
                <b>{pl.name}</b>
                <small>{tracksText(pl.track_count)}</small>
              </li>
            {/each}
          </ul>
          {#if morePlaylists > 0}<p class="more">{t('и ещё {n}', { n: `${morePlaylists} ${tn(morePlaylists, ['плейлист', 'плейлиста', 'плейлистов'])}` })}</p>{/if}
        </section>
      {/if}

      {#if profile.top_artists.length}
        <section>
          <h2><Icon name="user" size={18} />{t('Чаще всего слушает')}</h2>
          <ul class="artists" use:cascade>
            {#each profile.top_artists as artist (artist.name)}
              <li>
                <span class="art">
                  {#if artist.avatar_url}<img src={artist.avatar_url} alt="" loading="lazy" draggable="false" class="fade-img" onload={loaded} />{:else}<Icon name="user" size={26} />{/if}
                </span>
                <b>{artist.name}</b>
                <small>{artist.plays} {tn(artist.plays, ['прослушивание', 'прослушивания', 'прослушиваний'])}</small>
              </li>
            {/each}
          </ul>
        </section>
      {/if}
    </div>
  {/if}
</article>

<style>
  .profile {
    display: flex;
    flex-direction: column;
    gap: 26px;
  }
  .look {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .look .open {
    align-self: flex-start;
  }
  .hero {
    display: flex;
    align-items: flex-end;
    gap: 24px;
  }
  .ava {
    display: grid;
    place-items: center;
    width: 148px;
    height: 148px;
    flex-shrink: 0;
    border-radius: 50%;
    overflow: hidden;
    background: var(--surface-3);
    box-shadow: 0 10px 34px rgb(0 0 0 / 0.28);
  }
  .ava img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .initial {
    font-size: 60px;
    font-weight: 700;
    color: var(--text-2);
  }
  .who {
    display: flex;
    flex-direction: column;
    gap: 6px;
    min-width: 0;
  }
  .kind {
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-3);
  }
  .name-line {
    display: flex;
    align-items: center;
    gap: 12px;
    min-width: 0;
  }
  h1 {
    min-width: 0;
    margin: 0;
    font-size: calc(40px * var(--fs, 1));
    line-height: 1.1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .handle {
    display: flex;
    flex-wrap: wrap;
    gap: 6px 12px;
    margin: 0;
    color: var(--text-2);
    font-size: calc(14px * var(--fs, 1));
  }
  .muted {
    color: var(--text-3);
  }
  .open {
    align-self: flex-start;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 36px;
    margin-top: 8px;
    padding: 0 18px;
    border-radius: 999px;
    background: var(--accent);
    color: var(--accent-ink);
    font-weight: 600;
    font-size: calc(13px * var(--fs, 1));
  }
  .open:disabled {
    opacity: 0.6;
    cursor: default;
  }
  .sections {
    display: flex;
    flex-direction: column;
    gap: 26px;
  }
  section {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  h2 {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 0;
    font-size: calc(18px * var(--fs, 1));
  }
  h2 small {
    margin-left: 4px;
    font-size: calc(13px * var(--fs, 1));
    font-weight: 500;
    color: var(--text-3);
  }
  .now {
    flex-direction: row;
    align-items: center;
    gap: 14px;
    padding: 12px 16px;
    border-radius: var(--radius-l);
    border: 1px solid var(--card-line);
    background: var(--plate);
    box-shadow: var(--sheen);
  }
  .label {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    color: var(--accent) !important;
    font-weight: 600;
  }
  .stats {
    flex-direction: row;
    flex-wrap: wrap;
    gap: 12px;
  }
  .stats div {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 120px;
    padding: 14px 18px;
    border-radius: var(--radius-l);
    border: 1px solid var(--card-line);
    background: var(--plate);
    box-shadow: var(--sheen);
  }
  .stats b {
    font-size: calc(24px * var(--fs, 1));
    font-variant-numeric: tabular-nums;
  }
  .stats span {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .list,
  .grid,
  .artists {
    margin: 0;
    padding: 0;
    list-style: none;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 6px 8px;
    border-radius: var(--radius-m);
    transition: background var(--fast) var(--ease);
  }
  .row:hover {
    background: var(--hover);
  }
  .cover {
    display: grid;
    place-items: center;
    width: var(--size);
    height: var(--size);
    flex-shrink: 0;
    border-radius: 8px;
    overflow: hidden;
    background: var(--surface-3);
    color: var(--text-3);
  }
  .cover img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .meta {
    display: flex;
    flex-direction: column;
    min-width: 0;
    flex: 1;
  }
  .meta b,
  .meta small,
  .card b,
  .card small,
  .artists b {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .meta b {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  .meta small,
  .card small,
  .artists small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .len {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  .more {
    margin: 0 8px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
    gap: 18px;
  }
  .card {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }
  .collage {
    display: grid;
    place-items: center;
    aspect-ratio: 1;
    border-radius: var(--radius-l);
    overflow: hidden;
    background: var(--surface-3);
    color: var(--text-3);
    margin-bottom: 6px;
    transition: transform var(--normal) var(--ease);
  }
  .card:hover .collage {
    transform: translateY(-2px);
  }
  .collage.four {
    grid-template-columns: 1fr 1fr;
    grid-template-rows: 1fr 1fr;
  }
  .collage img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .artists {
    display: flex;
    flex-wrap: wrap;
    gap: 20px;
  }
  .artists li {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    width: 116px;
    text-align: center;
  }
  .artists b {
    max-width: 100%;
    font-size: calc(13px * var(--fs, 1));
  }
  .art {
    display: grid;
    place-items: center;
    width: 104px;
    height: 104px;
    margin-bottom: 4px;
    border-radius: 50%;
    overflow: hidden;
    background: var(--surface-3);
    color: var(--text-3);
  }
  .art img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    padding: 40px 0;
    color: var(--text-3);
    text-align: center;
    animation: tab-in var(--normal) var(--ease);
  }
  .empty b {
    color: var(--text);
  }
  .skels {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }
  .stat-skel {
    height: 72px;
    margin-bottom: 14px;
    border-radius: var(--radius-l);
  }
  .row-skel {
    height: 44px;
    border-radius: var(--radius-m);
  }
</style>
