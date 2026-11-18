<script lang="ts">
  // Выбор места витрины (Аккаунт → Профиль → Витрина): «Медиатека» — свои плейлисты (кроме скрытых «от
  // других»), «Поиск» — треки, альбомы и исполнители сервиса, который стоит первым в едином поиске
  // (`search.preferred`). Нажал на строку — место добавлено, список не закрывается: можно взять ещё.
  import { onDestroy, onMount } from 'svelte'
  import { fly } from 'svelte/transition'
  import Choice from '../../components/settings/Choice.svelte'
  import Icon from '../../components/Icon.svelte'
  import { api } from '../../lib/api'
  import { tracksText } from '../../lib/format'
  import { t } from '../../lib/i18n.svelte'
  import { cascade } from '../../lib/cascade'
  import { settings } from '../../lib/settings.svelte'
  import { canShowcase, showcaseAlbum, showcaseArtist, showcasePlaylist, showcaseTrack, type ShowcaseItem } from '../../lib/profile-look'

  interface Props {
    /** Что уже в витрине — такие строки отмечены. */
    taken: readonly ShowcaseItem[]
    onpick: (item: ShowcaseItem) => void
  }
  let { taken, onpick }: Props = $props()

  const SEARCH_DELAY_MS = 350
  const PER_GROUP = 6

  let tab = $state<'library' | 'search'>('library')
  let library = $state<ShowcaseItem[] | null>(null)
  let libraryError = $state(false)
  let query = $state('')
  let found = $state<{ title: string; items: ShowcaseItem[] }[]>([])
  let searching = $state(false)
  let searchError = $state(false)
  let timer: ReturnType<typeof setTimeout> | undefined
  let seq = 0

  const hidden = $derived(settings.get('privacy.hidden_playlists'))
  const isTaken = (i: ShowcaseItem) => taken.some((x) => x.kind === i.kind && x.ref === i.ref)

  onMount(async () => {
    try {
      const pls = await api.playlists()
      library = pls.map((p) => showcasePlaylist(p, tracksText(p.track_count)))
    } catch (e) {
      console.warn('витрина: плейлисты не загрузились', e)
      libraryError = true
    }
  })
  onDestroy(() => clearTimeout(timer))

  function onInput() {
    clearTimeout(timer)
    timer = setTimeout(search, SEARCH_DELAY_MS)
  }

  async function search() {
    const q = query.trim()
    const my = ++seq
    if (!q) {
      found = []
      return
    }
    searching = true
    searchError = false
    const src = settings.get('search.preferred')
    try {
      const [tracks, more] = await Promise.all([api.search(q, src, PER_GROUP), api.searchMore(q, src, PER_GROUP)])
      if (my !== seq) return
      found = [
        { title: t('Треки'), items: tracks.slice(0, PER_GROUP).map(showcaseTrack) },
        { title: t('Альбомы'), items: more.albums.slice(0, PER_GROUP).map(showcaseAlbum) },
        { title: t('Исполнители'), items: more.artists.slice(0, PER_GROUP).map(showcaseArtist) },
      ].filter((g) => g.items.length)
    } catch (e) {
      console.warn('витрина: поиск не удался', e)
      if (my === seq) searchError = true
    } finally {
      if (my === seq) searching = false
    }
  }
</script>

{#snippet row(item: ShowcaseItem)}
  {@const on = isTaken(item)}
  {@const allowed = canShowcase(item, hidden)}
  <button class="row" class:on disabled={on || !allowed} onclick={() => onpick(item)} title={allowed ? '' : t('Плейлист скрыт от других — в витрину не ставится')}>
    <span class="art" class:round={item.kind === 'artist'}>
      {#if item.cover_url}<img src={item.cover_url} alt="" loading="lazy" draggable="false" />{:else}<Icon name={item.kind === 'playlist' ? 'playlist' : 'music'} size={16} />{/if}
    </span>
    <span class="meta"><b>{item.title}</b>{#if item.subtitle || !allowed}<small>{allowed ? item.subtitle : t('Скрыт от других')}</small>{/if}</span>
    <span class="mark"><Icon name={on ? 'check' : allowed ? 'plus' : 'lock'} size={16} /></span>
  </button>
{/snippet}

<div class="picker" transition:fly={{ y: -6, duration: 180 }}>
  <Choice
    title={t('Откуда взять')}
    value={tab}
    options={[
      { id: 'library', label: t('Медиатека') },
      { id: 'search', label: t('Поиск') },
    ]}
    onchange={(v) => (tab = v)}
  />
  {#if tab === 'library'}
    {#if libraryError}
      <p class="note">{t('Плейлисты не загрузились — попробуй поиск')}</p>
    {:else if library === null}
      <p class="note">{t('Загружаю…')}</p>
    {:else if !library.length}
      <p class="note">{t('Своих плейлистов пока нет — найди трек, альбом или исполнителя в поиске')}</p>
    {:else}
      <div class="list" use:cascade={library.length}>{#each library as item (item.ref)}{@render row(item)}{/each}</div>
    {/if}
  {:else}
    <!-- svelte-ignore a11y_autofocus -->
    <input class="q" placeholder={t('Трек, альбом или исполнитель')} bind:value={query} oninput={onInput} autofocus />
    {#if searchError}
      <p class="note">{t('Поиск не удался — проверь подключение сервиса')}</p>
    {:else if searching && !found.length}
      <p class="note">{t('Ищу…')}</p>
    {:else if query.trim() && !found.length}
      <p class="note">{t('Ничего не нашлось')}</p>
    {/if}
    {#each found as g (g.title)}
      <small class="group">{g.title}</small>
      <div class="list" use:cascade={g.items.length}>{#each g.items as item (item.kind + item.ref)}{@render row(item)}{/each}</div>
    {/each}
  {/if}
</div>

<style>
  .picker {
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding: 6px 0 10px;
  }
  .q {
    height: 34px;
    margin: 4px 0;
    padding: 0 12px;
    border-radius: var(--radius-m);
    border: 1px solid var(--border);
    background: var(--surface-1);
    color: var(--text);
    font: inherit;
  }
  .q:focus {
    outline: none;
    border-color: var(--accent);
  }
  .group {
    margin: 8px 0 2px;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-3);
  }
  .list {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 4px;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 10px;
    min-width: 0;
    padding: 6px 8px;
    border-radius: var(--radius-m);
    text-align: left;
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .row:hover:not(:disabled) {
    background: var(--surface-3);
  }
  .row:active:not(:disabled) {
    transform: scale(0.98);
  }
  .row:disabled {
    cursor: default;
    opacity: 0.55;
  }
  .row.on {
    opacity: 1;
    color: var(--accent);
  }
  .art {
    flex-shrink: 0;
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    border-radius: 6px;
    overflow: hidden;
    background: var(--surface-3);
    color: var(--text-3);
  }
  .art.round {
    border-radius: 50%;
  }
  .art img {
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
  .meta small {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .meta b {
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    color: var(--text);
  }
  .meta small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .mark {
    flex-shrink: 0;
    color: var(--text-3);
  }
  .on .mark {
    color: var(--accent);
  }
  .note {
    margin: 6px 0;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
</style>
