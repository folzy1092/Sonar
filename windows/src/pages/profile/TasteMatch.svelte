<script lang="ts" module>
  import type { Track } from '../../lib/api'
  import type { TasteMatch } from '../../lib/taste-match'
  /** Кто с кем сравнивается: владелец профиля и тот, кто смотрит. */
  export interface TastePerson {
    name: string
    avatar_url: string | null
  }
  export interface TasteBlock {
    match: TasteMatch<Track>
    owner: TastePerson
    viewer: TastePerson
  }
</script>

<script lang="ts">
  // «Схожесть» в профиле друга (docs/NEXT_FRIEND.md §2): две колонки — слева аватары обоих, крупный
  // процент, подпись и общие треки (клик играет), справа общие исполнители (клик открывает страницу).
  // Считает `lib/taste-match.ts`; с сервером тот же объект придёт из `GET /users/{username}/taste`.
  import CountUp from '../../components/CountUp.svelte'
  import Icon from '../../components/Icon.svelte'
  import { openRef } from '../../app/router.svelte'
  import { cascade } from '../../lib/cascade'
  import { durationText } from '../../lib/format'
  import { t } from '../../lib/i18n.svelte'
  import { player } from '../../player/player.svelte'

  /** Сколько общих исполнителей видно. */
  const ARTISTS_SHOWN = 8

  let { taste }: { taste: TasteBlock } = $props()

  const caption = $derived(
    taste.match.level === 'very' ? t('Очень похожие вкусы') : taste.match.level === 'similar' ? t('Похожие вкусы') : t('Разные вкусы'),
  )
  const artists = $derived(taste.match.artists.slice(0, ARTISTS_SHOWN))
  const initial = (p: TastePerson) => [...(p.name.trim() || 'S')][0].toUpperCase()
  const loaded = (e: Event) => (e.currentTarget as HTMLElement).classList.add('loaded')
  const play = (i: number) => void player.playList(taste.match.tracks, i, null, t('Общие треки'))
</script>

{#snippet face(person: TastePerson)}
  <span class="face" title={person.name}>
    {#if person.avatar_url}<img src={person.avatar_url} alt="" draggable="false" class="fade-img" onload={loaded} />{:else}<span>{initial(person)}</span>{/if}
  </span>
{/snippet}

<section class="taste">
  <div class="col">
    <h2><Icon name="heart" size={18} />{t('Схожесть')}</h2>
    <div class="score">
      <span class="faces">{@render face(taste.owner)}{@render face(taste.viewer)}</span>
      <span class="pct" class:very={taste.match.level === 'very'}><b><CountUp value={taste.match.percent} /></b>%</span>
      <span class="caption">{caption}</span>
    </div>
    {#if taste.match.tracks.length}
      <h3>{t('Общие треки')}</h3>
      <ul class="tracks" use:cascade>
        {#each taste.match.tracks as track, i (track.ref)}
          <li>
            <button class="row" onclick={() => play(i)} title={t('Слушать')}>
              <span class="cover">
                {#if track.cover_url}<img src={track.cover_url} alt="" loading="lazy" draggable="false" class="fade-img" onload={loaded} />{:else}<Icon name="music" size={16} />{/if}
                <span class="hover-play"><Icon name="play" size={16} filled /></span>
              </span>
              <span class="meta"><b>{track.title}</b><small>{track.artist}</small></span>
              <span class="len">{durationText(track.duration_ms)}</span>
            </button>
          </li>
        {/each}
      </ul>
    {/if}
  </div>

  <div class="col">
    <h2><Icon name="user" size={18} />{t('Общие исполнители')}<small>{taste.match.artists.length}</small></h2>
    {#if artists.length}
      <ul class="artists" use:cascade>
        {#each artists as artist (artist.name)}
          <li>
            <button class="artist" disabled={!artist.ref} onclick={() => artist.ref && openRef(artist.ref)}>
              <span class="art">
                {#if artist.avatar_url}<img src={artist.avatar_url} alt="" loading="lazy" draggable="false" class="fade-img" onload={loaded} />{:else}<Icon name="user" size={22} />{/if}
              </span>
              <b>{artist.name}</b>
            </button>
          </li>
        {/each}
      </ul>
    {:else}
      <p class="none">{t('Общих исполнителей пока нет')}</p>
    {/if}
  </div>
</section>

<style>
  .taste {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
    gap: 18px;
  }
  @media (max-width: 900px) {
    .taste {
      grid-template-columns: minmax(0, 1fr);
    }
  }
  .col {
    display: flex;
    flex-direction: column;
    gap: 12px;
    min-width: 0;
    padding: 16px 18px;
    border-radius: var(--radius-l);
    border: 1px solid var(--card-line);
    background: var(--plate);
    box-shadow: var(--sheen);
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
  h3 {
    margin: 4px 0 0;
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-3);
  }
  .score {
    display: grid;
    grid-template-columns: auto 1fr;
    align-items: center;
    column-gap: 16px;
  }
  .faces {
    grid-row: span 2;
    display: flex;
  }
  .face {
    display: grid;
    place-items: center;
    width: 56px;
    height: 56px;
    border-radius: 50%;
    overflow: hidden;
    background: var(--surface-3);
    color: var(--text-2);
    font-size: calc(22px * var(--fs, 1));
    font-weight: 700;
    box-shadow: 0 0 0 3px var(--surface-2);
  }
  .face + .face {
    margin-left: -12px;
  }
  .face img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .pct {
    font-size: calc(22px * var(--fs, 1));
    font-weight: 700;
    color: var(--text-2);
    line-height: 1;
  }
  .pct b {
    font-size: calc(44px * var(--fs, 1));
    color: var(--text);
    font-variant-numeric: tabular-nums;
  }
  .pct.very b {
    color: var(--accent);
  }
  .caption {
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-2);
    font-weight: 600;
  }
  .tracks,
  .artists {
    margin: 0;
    padding: 0;
    list-style: none;
  }
  .tracks {
    margin: 0 -8px;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    padding: 6px 8px;
    border-radius: var(--radius-m);
    text-align: left;
    transition: background var(--fast) var(--ease);
  }
  .row:hover {
    background: var(--hover);
  }
  .cover {
    position: relative;
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
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
  .hover-play {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
    background: rgb(0 0 0 / 0.45);
    color: #fff;
    opacity: 0;
    transition: opacity var(--fast) var(--ease);
  }
  .row:hover .hover-play {
    opacity: 1;
  }
  .meta {
    display: flex;
    flex-direction: column;
    min-width: 0;
    flex: 1;
  }
  .meta b,
  .meta small,
  .artist b {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .meta b {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  .meta small,
  .len {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .len {
    font-variant-numeric: tabular-nums;
  }
  .artists {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(84px, 1fr));
    gap: 14px 10px;
  }
  .artist {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    width: 100%;
    min-width: 0;
    text-align: center;
  }
  .artist:disabled {
    cursor: default;
  }
  .art {
    display: grid;
    place-items: center;
    width: 72px;
    height: 72px;
    border-radius: 50%;
    overflow: hidden;
    background: var(--surface-3);
    color: var(--text-3);
    transition: transform var(--normal) var(--ease);
  }
  .artist:not(:disabled):hover .art {
    transform: translateY(-2px);
  }
  .art img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .artist b {
    max-width: 100%;
    font-size: calc(13px * var(--fs, 1));
  }
  .none {
    margin: 0;
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-3);
  }
</style>
