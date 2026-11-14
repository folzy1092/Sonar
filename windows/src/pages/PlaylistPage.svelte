<script lang="ts">
  // Плейлист / Любимые (pc/Screenshot_28). Параметр роутера:
  //   favorites — свои лайки; pl_… — плейлист Sonar (правка, скрыть, удалить, порядок перетаскиванием);
  //   scpl:… / ympl:… — плейлист сервиса «фантомом», с кнопкой «Перенести в Sonar».
  import CollectionHeader from '../components/CollectionHeader.svelte'
  import EmptyState from '../components/EmptyState.svelte'
  import Icon from '../components/Icon.svelte'
  import TrackRow from '../components/TrackRow.svelte'
  import { api, errorText, type ListTrack, type Track } from '../lib/api'
  import { durationText, tracksText } from '../lib/format'
  import { library } from '../lib/library.svelte'
  import { toast } from '../lib/toast.svelte'
  import { router } from '../app/router.svelte'
  import { player } from '../player/player.svelte'

  const id = router.param ?? 'favorites'
  const kind: 'favorites' | 'own' | 'service' = id === 'favorites' ? 'favorites' : id.startsWith('pl_') ? 'own' : 'service'

  let title = $state(kind === 'favorites' ? 'Любимые' : '')
  let owner = $state('')
  let covers = $state<string[]>([])
  let image = $state<string | null>(null)
  let hidden = $state(false)
  let items = $state<(Track & Partial<ListTrack>)[]>([])
  let loading = $state(true)
  let error = $state<string | null>(null)

  const sorts = [
    { id: 'custom', label: kind === 'favorites' ? 'Сначала новые' : 'По порядку' },
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
  const context = kind === 'favorites' ? 'favorites' : `playlist:${id}`
  const canReorder = $derived(kind === 'own' && sort.id === 'custom' && !filter.trim())

  async function load() {
    error = null
    try {
      if (kind === 'favorites') {
        items = await api.favorites()
        covers = []
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

  const play = (i: number) => player.playList(visible, i, context, title)

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
      toast.show(hidden ? 'Плейлист скрыт из «Все»' : 'Плейлист снова виден')
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
      toast.show(`Плейлист «${title}» удалён`)
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
      toast.show(`«${p.name}» теперь в Sonar — ${tracksText(p.track_count)}`)
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
</script>

<CollectionHeader
  {title}
  {image}
  {covers}
  icon={kind === 'favorites' ? 'heart' : 'music'}
  meta={loading ? '' : `${tracksText(items.length)}${items.length ? `, ${durationText(total)}` : ''}`}
  disabled={!visible.length}
  onplay={() => play(0)}
  onshuffle={() => player.playShuffled(visible, context, title)}
  onqueue={() => player.addToQueue(visible, false)}
>
  {#snippet subtitle()}
    {#if kind === 'favorites'}Лайкнутые треки
    {:else if kind === 'own'}Плейлист Sonar{#if hidden} · скрыт{/if}
    {:else}{owner ? `${owner} · ` : ''}{id.startsWith('sc') ? 'SoundCloud' : 'Яндекс Музыка'}{/if}
  {/snippet}
  {#snippet actions()}
    {#if kind === 'service'}
      <button class="tool" disabled={importing || !items.length} onclick={importToSonar}>
        <Icon name="download" size={16} /> {importing ? 'Переношу…' : 'Перенести в Sonar'}
      </button>
    {/if}
  {/snippet}
  {#snippet tools()}
    {#if kind === 'own'}
      {#if editing}
        <form class="rename" onsubmit={(e) => (e.preventDefault(), rename())}>
          <!-- svelte-ignore a11y_autofocus -->
          <input bind:value={newName} autofocus spellcheck="false" onkeydown={(e) => e.key === 'Escape' && (editing = false)} />
          <button class="tool" type="submit">Сохранить</button>
        </form>
      {:else}
        <button class="tool plain" aria-label="Переименовать" title="Переименовать" onclick={() => ((newName = title), (editing = true))}><Icon name="pencil" size={16} /></button>
      {/if}
      <button class="tool plain" aria-label={hidden ? 'Показать' : 'Скрыть'} title={hidden ? 'Показать в «Все»' : 'Скрыть из «Все»'} onclick={toggleHidden}>
        <Icon name={hidden ? 'eye' : 'eyeOff'} size={16} />
      </button>
      <button class="tool plain" class:danger={confirmDelete} title="Удалить плейлист" onclick={remove} onblur={() => (confirmDelete = false)}>
        <Icon name="trash" size={16} />{#if confirmDelete} Удалить?{/if}
      </button>
    {/if}
    <button class="tool plain" class:on={sortIdx > 0} title="Сортировка: {sort.label}" onclick={() => (sortIdx = (sortIdx + 1) % sorts.length)}>
      <Icon name="sort" size={16} />{#if sortIdx > 0} {sort.label}{/if}
    </button>
    <label class="find">
      <Icon name="search" size={15} />
      <input placeholder="Найти" bind:value={filter} spellcheck="false" />
    </label>
  {/snippet}
</CollectionHeader>

{#if error}
  <EmptyState icon="key" title="Не получилось открыть" text={error} />
{:else if loading}
  <div class="skeleton">{#each { length: 8 } as _, i (i)}<div class="sk"></div>{/each}</div>
{:else if !items.length}
  <EmptyState
    icon={kind === 'favorites' ? 'heart' : 'music'}
    title="Пока пусто"
    text={kind === 'favorites' ? 'Жми ❤ у трека — он появится здесь.' : 'Добавляй треки через меню ⋮ → «Добавить в плейлист».'}
  />
{:else if !visible.length}
  <EmptyState icon="search" title="Ничего не нашлось" text={`В «${title}» нет «${filter.trim()}».`} />
{:else}
  <div class="list">
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
    border: 1px solid var(--border);
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
