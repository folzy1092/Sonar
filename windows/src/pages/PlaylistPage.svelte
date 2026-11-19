<script lang="ts">
  import ScrollStick from '../components/ScrollStick.svelte'
  import { cascade } from '../lib/cascade'
  // Плейлист / Любимые (pc/Screenshot_28). Параметр роутера:
  //   favorites — свои лайки; pl_… — плейлист Sonar (правка, скрыть, удалить, порядок перетаскиванием);
  //   scpl:… / ympl:… — плейлист сервиса «фантомом», с кнопкой «Перенести в Sonar»;
  //   local — файлы из «Папок с музыкой» (Система → Хранилище), обновляется сам после скана.
  import CollectionHeader from '../components/CollectionHeader.svelte'
  import EmptyState from '../components/EmptyState.svelte'
  import Icon from '../components/Icon.svelte'
  import TrackRow from '../components/TrackRow.svelte'
  import { api, errorText, onLocalFilesChanged, type ListTrack, type Track } from '../lib/api'
  import { durationText, tracksText } from '../lib/format'
  import { library } from '../lib/library.svelte'
  import { openImport } from '../lib/import.svelte'
  import { toast } from '../lib/toast.svelte'
  import { router } from '../app/router.svelte'
  import { player } from '../player/player.svelte'
  import { t } from '../lib/i18n.svelte'
  import { byId, serviceOf } from '../lib/services'
  import { settingsPanel } from './settings-section.svelte'
  import { onDestroy } from 'svelte'
  import { collage } from '../lib/covers'

  const id = router.param ?? 'favorites'
  const kind: 'favorites' | 'own' | 'service' | 'local' =
    id === 'favorites' ? 'favorites' : id === 'local' ? 'local' : id.startsWith('pl_') ? 'own' : 'service'

  let title = $state('')
  /** Заголовок на экране: «Любимые» и «На этом компьютере» переводятся на лету, остальное — как есть. */
  const heading = $derived(kind === 'favorites' ? t('Любимые') : kind === 'local' ? t('На этом компьютере') : title)
  let owner = $state('')
  let covers = $state<string[]>([])
  let image = $state<string | null>(null)
  let hidden = $state(false)
  let items = $state<(Track & Partial<ListTrack>)[]>([])
  let loading = $state(true)
  let error = $state<string | null>(null)

  const sorts = [
    { id: 'custom', label: kind === 'favorites' ? 'Сначала новые' : kind === 'local' ? 'По исполнителю' : 'По порядку' },
    { id: 'title', label: 'По названию' },
    { id: 'artist', label: 'По исполнителю' },
    { id: 'duration', label: 'По длительности' },
  ] as const
  let sortIdx = $state(0)
  let filter = $state('')
  let editing = $state(false)
  let newName = $state('')
  let confirmDelete = $state(false)
  let importing = $state(false)

  const sort = $derived(sorts[sortIdx])
  const visible = $derived.by(() => {
    const q = filter.trim().toLowerCase()
    let list = q ? items.filter((t) => `${t.title} ${t.artist}`.toLowerCase().includes(q)) : items.slice()
    if (sort.id === 'title') list.sort((a, b) => a.title.localeCompare(b.title, 'ru'))
    else if (sort.id === 'artist') list.sort((a, b) => a.artist.localeCompare(b.artist, 'ru'))
    else if (sort.id === 'duration') list.sort((a, b) => a.duration_ms - b.duration_ms)
    return list
  })
  const total = $derived(items.reduce((s, t) => s + t.duration_ms, 0))
  const context = kind === 'favorites' ? 'favorites' : kind === 'local' ? 'local' : `playlist:${id}`
  const canReorder = $derived(kind === 'own' && sort.id === 'custom' && !filter.trim())

  async function load() {
    error = null
    try {
      if (kind === 'favorites') {
        items = await api.favorites()
        covers = []
      } else if (kind === 'local') {
        items = await api.localTracks()
        covers = collage(items)
      } else if (kind === 'own') {
        const p = await api.playlist(id)
        title = p.name
        hidden = p.hidden
        covers = p.covers
        items = p.tracks ?? []
      } else {
        const page = await api.servicePlaylist(id)
        title = page.playlist.title
        owner = page.playlist.owner
        image = page.playlist.cover_url
        items = page.tracks
      }
    } catch (e) {
      error = errorText(e)
    } finally {
      loading = false
    }
  }

  // своё — перечитываем после любой правки медиатеки (лайк, «Убрать из плейлиста» в меню)
  $effect(() => {
    if (kind === 'service') return
    library.version
    void load()
  })
  if (kind === 'service') void load()
  // локальные — заново после скана папок (новый файл, правка тегов, удаление)
  if (kind === 'local') onDestroy(onLocalFilesChanged(() => void load()))

  const play = (i: number) => player.playList(visible, i, context, heading)

  async function rename() {
    const name = newName.trim()
    editing = false
    if (!name || name === title) return
    try {
      await api.updatePlaylist(id, { name })
      title = name
      await library.refreshPlaylists()
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  async function toggleHidden() {
    try {
      await api.updatePlaylist(id, { hidden: !hidden })
      hidden = !hidden
      toast.show(hidden ? t('Плейлист скрыт из «Все»') : t('Плейлист снова виден'))
      await library.refreshPlaylists()
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  async function remove() {
    if (!confirmDelete) {
      confirmDelete = true
      return
    }
    try {
      await api.deletePlaylist(id)
      await library.refreshPlaylists()
      toast.show(t('Плейлист «{title}» удалён', { title }))
      router.back()
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  async function importToSonar() {
    importing = true
    try {
      const p = await api.importPlaylist(id)
      await library.refreshPlaylists()
      toast.show(t('«{name}» теперь в Sonar — {tracks}', { name: p.name, tracks: tracksText(p.track_count) }))
      router.go('playlist', p.id)
    } catch (e) {
      toast.show(errorText(e))
    } finally {
      importing = false
    }
  }

  // ——— перетаскивание (только свой плейлист, порядок «По порядку», без поиска) ———
  let dragFrom = $state<number | null>(null)
  let dragOver = $state<number | null>(null)

  async function drop(to: number) {
    const from = dragFrom
    dragFrom = dragOver = null
    if (from === null || from === to) return
    const next = items.slice()
    const [moved] = next.splice(from, 1)
    next.splice(to, 0, moved)
    items = next
    try {
      await api.reorderPlaylist(id, next.map((t) => t.item_id!))
    } catch (e) {
      toast.show(errorText(e))
      void load()
    }
  }
  let tracksEl: HTMLDivElement | undefined = $state()
</script>

<CollectionHeader
  title={heading}
  {image}
  {covers}
  icon={kind === 'favorites' ? 'heart' : kind === 'local' ? 'monitor' : 'music'}
  meta={loading ? '' : `${tracksText(items.length)}${items.length ? `, ${durationText(total)}` : ''}`}
  {context}
  disabled={!visible.length}
  onplay={() => play(0)}
  onshuffle={() => player.playShuffled(visible, context, heading)}
  onqueue={() => player.addToQueue(visible, false)}
>
  {#snippet subtitle()}
    {#if kind === 'favorites'}{t('Лайкнутые треки')}
    {:else if kind === 'local'}{t('Папки с музыкой')}
    {:else if kind === 'own'}{t('Плейлист Sonar')}{#if hidden} · {t('скрыт')}{/if}
    {:else}{owner ? `${owner} · ` : ''}{t(byId(serviceOf(id))?.name ?? 'Яндекс Музыка')}{/if}
  {/snippet}
  {#snippet actions()}
    {#if kind === 'service'}
      <button class="tool" disabled={importing || !items.length} onclick={importToSonar}>
        <Icon name="download" size={16} /> {importing ? t('Переношу…') : t('Перенести в Sonar')}
      </button>
      <!-- сервис без своего потока (Spotify): можно сразу подобрать пары в играющих сервисах (этап 5) -->
      {#if !byId(serviceOf(id))?.caps.stream}
        <button class="tool" disabled={!items.length} onclick={() => openImport(id)}>
          <Icon name="link" size={16} /> {t('Перенести с подбором')}
        </button>
      {/if}
    {:else if kind === 'local'}
      <button class="tool" onclick={() => settingsPanel.show('system', 'storage')}>
        <Icon name="library" size={16} /> {t('Папки')}
      </button>
    {/if}
  {/snippet}
  {#snippet tools()}
    {#if kind === 'own'}
      {#if editing}
        <form class="rename" onsubmit={(e) => (e.preventDefault(), rename())}>
          <!-- svelte-ignore a11y_autofocus -->
          <input bind:value={newName} autofocus spellcheck="false" onkeydown={(e) => e.key === 'Escape' && (editing = false)} />
          <button class="tool" type="submit">{t('Сохранить')}</button>
        </form>
      {:else}
        <button class="tool plain" aria-label={t('Переименовать')} title={t('Переименовать')} onclick={() => ((newName = title), (editing = true))}><Icon name="pencil" size={16} /></button>
      {/if}
      <button class="tool plain" aria-label={hidden ? t('Показать') : t('Скрыть')} title={hidden ? t('Показать в «Все»') : t('Скрыть из «Все»')} onclick={toggleHidden}>
        <Icon name={hidden ? 'eye' : 'eyeOff'} size={16} />
      </button>
      <button class="tool plain" class:danger={confirmDelete} title={t('Удалить плейлист')} onclick={remove} onblur={() => (confirmDelete = false)}>
        <Icon name="trash" size={16} />{#if confirmDelete} {t('Удалить?')}{/if}
      </button>
    {/if}
    {#if kind === 'favorites' || kind === 'own'}
      <button class="tool plain" aria-label={t('Найти дубли')} title={t('Найти дубли')} onclick={() => router.go('dupes', id)}>
        <Icon name="stack" size={16} />
      </button>
    {/if}
    <button class="tool plain" class:on={sortIdx > 0} title={t('Сортировка: {sort}', { sort: t(sort.label) })} onclick={() => (sortIdx = (sortIdx + 1) % sorts.length)}>
      <Icon name="sort" size={16} />{#if sortIdx > 0} {t(sort.label)}{/if}
    </button>
    <label class="find">
      <Icon name="search" size={15} />
      <input placeholder={t('Найти')} bind:value={filter} spellcheck="false" />
    </label>
  {/snippet}
</CollectionHeader>

<!-- прокручиваются только треки, шапка и кнопки стоят на месте; где ты в списке — показывает
     горизонтальная «палочка» под кнопками (вертикальной полосы справа нет) -->
<ScrollStick target={tracksEl} />
<div class="tracks" id="tracks" bind:this={tracksEl}>
  {#if error}
    <EmptyState icon="key" title={t('Не получилось открыть')} text={error} />
  {:else if loading}
    <div class="skeleton">{#each { length: 8 } as _, i (i)}<div class="sk"></div>{/each}</div>
  {:else if !items.length}
    <EmptyState
      icon={kind === 'favorites' ? 'heart' : kind === 'local' ? 'monitor' : 'music'}
      title={t('Пока пусто')}
      text={kind === 'favorites'
        ? t('Нажми на сердце у трека — он появится здесь.')
        : kind === 'local'
          ? t('Добавь папку с музыкой в Настройках → Хранилище — mp3, flac, m4a, ogg, opus и wav появятся здесь.')
          : t('Добавляй треки через меню трека: «Добавить в плейлист».')}
    />
  {:else if !visible.length}
    <EmptyState icon="search" title={t('Ничего не нашлось')} text={t('В «{title}» нет «{query}».', { title: heading, query: filter.trim() })} />
  {:else}
    <div class="list" use:cascade>
      {#each visible as t, i (t.item_id ?? t.ref + i)}
        <div
          class="drag"
          class:over={dragOver === i && dragFrom !== i}
          draggable={canReorder}
          role="listitem"
          ondragstart={(e) => {
            dragFrom = i
            e.dataTransfer?.setData('text/plain', String(i))
          }}
          ondragover={(e) => {
            if (dragFrom === null) return
            e.preventDefault()
            dragOver = i
          }}
          ondragend={() => (dragFrom = dragOver = null)}
          ondrop={(e) => (e.preventDefault(), drop(i))}
        >
          <TrackRow
            track={t}
            addedAt={t.added_at}
            playlistId={kind === 'own' ? id : undefined}
            itemId={kind === 'own' ? t.item_id : undefined}
            onplay={() => play(i)}
          />
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .find {
    display: flex;
    align-items: center;
    gap: 8px;
    width: 200px;
    height: 34px;
    padding: 0 12px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    color: var(--text-3);
  }
  .find:focus-within {
    border-color: var(--border-strong);
  }
  .find input,
  .rename input {
    flex: 1;
    min-width: 0;
    background: none;
    border: 0;
    outline: none;
    user-select: text;
  }
  .rename {
    display: flex;
    gap: 6px;
  }
  .rename input {
    width: 200px;
    height: 34px;
    padding: 0 12px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--border-strong);
  }
  :global(.tool.danger) {
    color: var(--danger) !important;
  }
  .tracks {
    flex: 1;
    min-height: 0;
    margin: 4px 0 0;
    padding: 0 0 24px;
    overflow-y: auto;
    scrollbar-width: none;
  }
  .tracks::-webkit-scrollbar {
    display: none;
  }
  .list {
    display: flex;
    flex-direction: column;
  }
  .drag {
    border-radius: var(--radius-m);
    border-top: 2px solid transparent;
  }
  .drag.over {
    border-top-color: var(--accent);
  }
  .skeleton {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .sk {
    height: 56px;
    border-radius: var(--radius-m);
    background: linear-gradient(90deg, var(--plate), var(--hover), var(--plate));
    background-size: 200% 100%;
    animation: shimmer 1.2s linear infinite;
  }
  @keyframes shimmer {
    to {
      background-position: -200% 0;
    }
  }
</style>
