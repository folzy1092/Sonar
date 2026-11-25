<script lang="ts">
  // Плеер → Вкус (docs/TASTE_ROOMS_PROMPT.md §1): артисты «Чаще · Реже · Никогда» (`wave.artist_prefs`) и треки с 👎.
  // Отмечают артиста в меню трека и на странице исполнителя, здесь — посмотреть всё разом и поправить.
  import Icon from '../../components/Icon.svelte'
  import Cover from '../../components/Cover.svelte'
  import Group from '../../components/settings/Group.svelte'
  import ArtistTasteSeg from '../../components/ArtistTasteSeg.svelte'
  import { cascade } from '../../lib/cascade'
  import { t, tn } from '../../lib/i18n.svelte'
  import { api, type Track } from '../../lib/api'
  import { artistTaste } from '../../lib/artist-prefs.svelte'
  import { prefList } from '../../lib/artist-prefs-core'
  import { wave } from '../../player/my-wave.svelte'

  let query = $state('')
  const all = $derived(prefList(artistTaste.prefs))
  const shown = $derived(prefList(artistTaste.prefs, query))

  /** Треки с 👎: из кэша метаданных; снятые пропадают из списка сразу (`wave.disliked`). */
  let loaded = $state<Track[] | null>(null)
  const disliked = $derived((loaded ?? []).filter((tr) => wave.isDisliked(tr.ref)))

  $effect(() => {
    void api
      .dislikedRefs()
      .then((refs) => (refs.length ? api.cachedTracks(refs) : []))
      .then((list) => (loaded = list))
      .catch(() => (loaded = []))
  })
</script>

<Group title={t('Артисты')} hint={t('«Никогда» — артиста нет в Sonar Mix и похожих, «Чаще» и «Реже» двигают его в Sonar Mix')}>
  {#if all.length > 6}
    <label class="find">
      <Icon name="search" size={15} />
      <input placeholder={t('Найти артиста')} bind:value={query} spellcheck="false" />
    </label>
  {/if}
  {#if !all.length}
    <p class="none">{t('Пока никого. Открой меню трека или страницу исполнителя и выбери «Чаще», «Реже» или «Никогда».')}</p>
  {:else if !shown.length}
    <p class="none">{t('Никого не нашлось')}</p>
  {:else}
    <ul use:cascade={query}>
      {#each shown as a (a.key)}
        <li class="set-row">
          <span class="set-text"><b>{a.name}</b></span>
          <div class="set-ctl">
            <ArtistTasteSeg name={a.name} quiet />
            <button class="x" title={t('Убрать')} aria-label={t('Убрать')} onclick={() => artistTaste.set(a.name, null, true)}>
              <Icon name="x" size={15} />
            </button>
          </div>
        </li>
      {/each}
    </ul>
  {/if}
</Group>

<Group title={t('Не нравится')} hint={t('Треки с 👎 не попадают в Sonar Mix и похожие')}>
  {#if loaded === null}
    <p class="none">{t('Загружаю…')}</p>
  {:else if !disliked.length}
    <p class="none">{t('Таких треков нет')}</p>
  {:else}
    <p class="count">{disliked.length} {tn(disliked.length, ['трек', 'трека', 'треков'])}</p>
    <ul use:cascade>
      {#each disliked as tr (tr.ref)}
        <li class="track">
          <Cover url={tr.cover_url} size={36} source={tr.ref} />
          <span class="meta"><b>{tr.title}</b><small>{tr.artist}</small></span>
          <button class="back" onclick={() => wave.dislike(tr)}>{t('Вернуть')}</button>
        </li>
      {/each}
    </ul>
  {/if}
</Group>

<style>
  ul {
    margin: 0;
    padding: 0;
    list-style: none;
  }
  .set-ctl {
    align-items: center;
    gap: 8px;
    justify-content: flex-end;
  }
  .find {
    display: flex;
    align-items: center;
    gap: 8px;
    height: 34px;
    margin: 6px 0 4px;
    padding: 0 12px;
    border-radius: 999px;
    border: 1px solid var(--border-strong);
    color: var(--text-3);
  }
  .find:focus-within {
    border-color: var(--accent);
  }
  .find input {
    flex: 1;
    min-width: 0;
    border: 0;
    outline: 0;
    background: none;
    color: var(--text);
    font: inherit;
  }
  .none,
  .count {
    margin: 8px 0;
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-3);
  }
  .count {
    margin-bottom: 2px;
  }
  .x {
    display: grid;
    place-items: center;
    width: 30px;
    height: 30px;
    border-radius: 999px;
    color: var(--text-3);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .x:hover {
    background: var(--hover);
    color: var(--text);
  }
  .track {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 6px 0;
  }
  .meta {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .meta b,
  .meta small {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .meta small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .back {
    height: 30px;
    padding: 0 14px;
    border-radius: 999px;
    border: 1px solid var(--border-strong);
    color: var(--text-2);
    font-weight: 600;
    transition: background var(--fast) var(--ease);
  }
  .back:hover {
    background: var(--hover);
    color: var(--text);
  }
</style>
