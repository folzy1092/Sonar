<script lang="ts">
  import ScrollStick from '../components/ScrollStick.svelte'
  import { cascade } from '../lib/cascade'
  import { growLimit, LIST_WINDOW } from '../lib/list-window'
  import { nearEnd } from '../lib/near-end'
  // Плейлист / Любимые (pc/Screenshot_28). Параметр роутера:
  //   favorites — свои лайки; pl_… — плейлист Sonar (правка, скрыть, удалить, порядок перетаскиванием);
  //   scpl:… / ympl:… — плейлист сервиса «фантомом», с кнопкой «Перенести в Sonar»;
  //   local — файлы из «Папок с музыкой» (Система → Хранилище), обновляется сам после скана.
  import CollectionHeader from '../components/CollectionHeader.svelte'
  import EmptyState from '../components/EmptyState.svelte'
  import Icon from '../components/Icon.svelte'
  import SelectBar from '../components/SelectBar.svelte'
  import TrackRow from '../components/TrackRow.svelte'
  import { api, errorText, onLocalFilesChanged, type ListTrack, type Playlist, type Track } from '../lib/api'
  import { adderOf, isCollab } from '../lib/collab'
  import { durationText, tracksText } from '../lib/format'
  import { library } from '../lib/library.svelte'
  import { openImport } from '../lib/import.svelte'
  import { toast } from '../lib/toast.svelte'
  import { router } from '../app/router.svelte'
  import { player } from '../player/player.svelte'
  import { t } from '../lib/i18n.svelte'
  import { byId, playlistWebUrl, serviceOf } from '../lib/services'
  import { pickSelected, rangeKeys, selKey, shareText, toggleKey } from '../lib/track-select'
  import { settingsPanel } from './settings-section.svelte'
  import { onDestroy, untrack } from 'svelte'
  import { PixelCollage } from '../lib/pixel-collage.svelte'
  import { offline } from '../lib/offline.svelte'
  import { findGroup, parseGroupId } from '../lib/offline-groups'
  import { trackBackfill } from '../lib/track-backfill-run'
  import { mergeMissing } from '../lib/track-backfill'

  const id = router.param ?? 'favorites'
  /** `offline` — альбом или исполнитель из доступного без сети (lib/offline-groups.ts): локальный список, без сети. */
  const group = parseGroupId(id)
  const kind: 'favorites' | 'own' | 'service' | 'local' | 'offline' = group
    ? 'offline'
    : id === 'favorites'
      ? 'favorites'
      : id === 'local'
        ? 'local'
        : id.startsWith('pl_')
          ? 'own'
          : 'service'

  let title = $state('')
  /** Заголовок на экране: «Любимые» и «На этом компьютере» переводятся на лету, остальное — как есть. */
  const heading = $derived(kind === 'favorites' ? t('Любимые') : kind === 'local' ? t('На этом компьютере') : title)
  let owner = $state('')
  const pc = new PixelCollage()
  const covers = $derived(pc.covers)
  let image = $state<string | null>(null)
  let hidden = $state(false)
  /** Участники совместного плейлиста (с сервером); обычный — пусто. */
  let members = $state<Pick<Playlist, 'owner' | 'collaborators'>>({ owner: null, collaborators: [] })
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
  /** В офлайне — только то, что играет без сети (OFFLINE.md §6: недоступное скрыто, не серое). */
  const avail = $derived(offline.only(items))
  const visible = $derived.by(() => {
    const q = filter.trim().toLowerCase()
    let list = q ? avail.filter((t) => `${t.title} ${t.artist}`.toLowerCase().includes(q)) : avail.slice()
    if (sort.id === 'title') list.sort((a, b) => a.title.localeCompare(b.title, 'ru'))
    else if (sort.id === 'artist') list.sort((a, b) => a.artist.localeCompare(b.artist, 'ru'))
    else if (sort.id === 'duration') list.sort((a, b) => a.duration_ms - b.duration_ms)
    return list
  })
  // окно списка: «Любимые» на тысячи треков не рисуются целиком; новый фильтр или порядок — окно снова маленькое
  let limit = $state(LIST_WINDOW)
  $effect.pre(() => {
    void filter
    void sortIdx
    limit = LIST_WINDOW
  })
  const shown = $derived(visible.length > limit ? visible.slice(0, limit) : visible)
  const total = $derived(avail.reduce((s, t) => s + t.duration_ms, 0))
  const countMeta = $derived(offline.on ? offline.countText(avail.length, items.length) : tracksText(items.length))
  const context = kind === 'favorites' ? 'favorites' : kind === 'local' ? 'local' : kind === 'offline' ? 'offline' : `playlist:${id}`
  const headIcon = kind === 'favorites' ? 'heart' : kind === 'local' ? 'monitor' : kind === 'offline' ? (group?.kind === 'artist' ? 'user' : 'disc') : 'music'
  // в офлайне часть треков скрыта — индексы на экране не совпадают с плейлистом, порядок не трогаем
  const canReorder = $derived(kind === 'own' && sort.id === 'custom' && !filter.trim() && !offline.on)

  async function load() {
    error = null
    // плейлист сервиса — только из сети (OFFLINE.md §5.1)
    if (kind === 'service' && offline.on) {
      loading = false
      return
    }
    try {
      if (kind === 'favorites') {
        items = await api.favorites()
        pc.set([], [])
        // у перенесённых из Dotify нет обложки и длительности — добиваем лениво (NOW_ACCURACY_PROMPT §2)
        trackBackfill.enqueue(items)
      } else if (kind === 'local') {
        items = await api.localTracks()
        pc.set(items)
      } else if (kind === 'offline') {
        const found = findGroup(await offline.pool(), id)
        title = found?.title ?? ''
        owner = found?.subtitle ?? ''
        items = found?.tracks ?? []
        pc.set(items)
      } else if (kind === 'own') {
        const p = await api.playlist(id)
        title = p.name
        hidden = p.hidden
        members = { owner: p.owner, collaborators: p.collaborators }
        items = p.tracks ?? []
        // обложки с сервера — сразу, потом сверка по картинкам, если треки пришли
        pc.set(items, p.covers)
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
    // офлайн-группа — заново, когда кэш докачал или вытеснил трек
    if (kind === 'offline') void offline.refs
    void load()
  })
  $effect(() => {
    if (kind === 'service' && !offline.on) void load()
  })
  // свежие обложки и длительности — в список на экране, без перечитывания (`library.version` не трогаем)
  onDestroy(
    trackBackfill.subscribe((fresh) => {
      const byRef = new Map(fresh.map((f) => [f.ref, f]))
      const next = items.map((it) => {
        const f = byRef.get(it.ref)
        return f ? mergeMissing(it, f) : it
      })
      if (next.some((it, i) => it !== items[i])) items = next
    }),
  )
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

  // ——— режим выбора треков (кнопка «Выбрать треки»; панель — components/SelectBar.svelte) ———
  let selecting = $state(false)
  let picked = $state(new Set<string>())
  /** Строка прошлой отметки в `visible` — от неё считается диапазон по Shift. */
  let anchor: number | null = null
  /** Отмечено и видно на экране: отметки, которые скрыл поиск, в действия не попадают. */
  const selected = $derived(pickSelected(visible, picked))

  // перечитали список (убрали, лайк снят) — отметки пропавших строк сбрасываем
  $effect(() => {
    const alive = new Set(items.map(selKey))
    untrack(() => {
      if ([...picked].some((k) => !alive.has(k))) picked = new Set([...picked].filter((k) => alive.has(k)))
    })
  })

  function closeSelect() {
    selecting = false
    picked = new Set()
    anchor = null
  }

  function selectAll() {
    picked = new Set(visible.map(selKey))
  }

  function pickRow(i: number, shift: boolean) {
    const keys = visible.map(selKey)
    if (shift && anchor !== null) picked = new Set([...picked, ...rangeKeys(keys, anchor, i)])
    else picked = toggleKey(picked, keys[i])
    anchor = i
  }

  async function removeSelected() {
    const list = selected
    if (!list.length) return
    if (kind === 'favorites') {
      const n = await library.unlikeAll(list)
      toast.show(t('Убрано {tracks}', { tracks: tracksText(n) }))
    } else if (kind === 'own') {
      await library.removeFromPlaylist(id, list.map((x) => x.item_id!))
      toast.show(t('Убрано {tracks}', { tracks: tracksText(list.length) }))
    }
    closeSelect()
  }

  /** «Поделиться»: у плейлиста сервиса — его ссылка; у своего списка и Любимых публичной ссылки до сервера нет — копируем текст «Артист — Название». */
  async function share() {
    const url = kind === 'service' ? playlistWebUrl(id) : null
    try {
      await navigator.clipboard.writeText(url ?? shareText(heading, avail))
      toast.show(url ? t('Ссылка скопирована') : t('Список треков скопирован'))
    } catch {
      toast.show(t('Не получилось скопировать'))
    }
  }
</script>

{#snippet selectionBar()}
  <SelectBar
    tracks={selected}
    total={visible.length}
    title={heading}
    removable={kind === 'favorites' ? 'favorites' : kind === 'own' ? 'playlist' : null}
    fromPlaylist={kind === 'own' ? id : undefined}
    dupesId={kind === 'favorites' || kind === 'own' ? id : undefined}
    canLike={kind !== 'favorites'}
    canDownload={kind !== 'local'}
    onall={selectAll}
    onnone={() => (picked = new Set())}
    onclose={closeSelect}
    onremove={removeSelected}
  />
{/snippet}

<CollectionHeader
  title={heading}
  {image}
  {covers}
  icon={headIcon}
  meta={loading ? '' : `${countMeta}${avail.length ? `, ${durationText(total)}` : ''}`}
  {context}
  disabled={!visible.length}
  onplay={() => play(0)}
  onshuffle={() => player.playShuffled(visible, context, heading)}
  onqueue={() => player.addToQueue(visible, false)}
  selection={selecting ? selectionBar : undefined}
>
  {#snippet subtitle()}
    {#if kind === 'favorites'}{t('Лайкнутые треки')}
    {:else if kind === 'local'}{t('Папки с музыкой')}
    {:else if kind === 'offline'}{owner ? `${owner} · ` : ''}{group?.kind === 'artist' ? t('Исполнитель · офлайн') : t('Альбом · офлайн')}
    {:else if kind === 'own'}{t('Плейлист Sonar')}{#if isCollab(members)} · <span class="collab" title={[members.owner, ...members.collaborators].map((m) => m?.display_name || m?.username).filter(Boolean).join(', ')}>{t('Совместный')}</span>{/if}{#if hidden} · {t('скрыт')}{/if}
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
    <button class="tool plain" aria-label={t('Выбрать треки')} title={t('Выбрать треки')} disabled={!items.length} onclick={() => (selecting = true)}>
      <Icon name="listCheck" size={16} />
    </button>
    <button class="tool plain" aria-label={t('Поделиться')} title={t('Поделиться')} disabled={!avail.length} onclick={share}>
      <Icon name="share" size={16} />
    </button>
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
  {#if kind === 'service' && offline.on && !items.length}
    <EmptyState icon="wifiOff" title={t('Недоступно в офлайне')} text={t('Плейлисты сервисов открываются только с сетью.')} />
  {:else if error}
    <EmptyState icon="key" title={t('Не получилось открыть')} text={error} />
  {:else if loading}
    <div class="skeleton">{#each { length: 8 } as _, i (i)}<div class="sk"></div>{/each}</div>
  {:else if kind === 'offline' && !items.length}
    <EmptyState icon="wifiOff" title={t('Офлайн: здесь ничего нет')} text={t('Треков отсюда на этом компьютере больше нет.')} />
  {:else if !items.length}
    <EmptyState
      icon={headIcon}
      title={t('Пока пусто')}
      text={kind === 'favorites'
        ? t('Нажми на сердце у трека — он появится здесь.')
        : kind === 'local'
          ? t('Добавь папку с музыкой в Настройках → Хранилище — mp3, flac, m4a, ogg, opus и wav появятся здесь.')
          : t('Добавляй треки через меню трека: «Добавить в плейлист».')}
    />
  {:else if !avail.length}
    <EmptyState icon="wifiOff" title={t('Офлайн: здесь ничего нет')} text={t('Ни одного трека из «{title}» нет на этом компьютере.', { title: heading })} />
  {:else if !visible.length}
    <EmptyState icon="search" title={t('Ничего не нашлось')} text={t('В «{title}» нет «{query}».', { title: heading, query: filter.trim() })} />
  {:else}
    <div class="list" use:cascade>
      {#each shown as t, i (t.item_id ?? t.ref + i)}
        <div
          class="drag"
          class:over={dragOver === i && dragFrom !== i}
          draggable={canReorder && !selecting}
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
            addedBy={adderOf(members, t.added_by)}
            {selecting}
            selected={picked.has(selKey(t))}
            onselect={(shift) => pickRow(i, shift)}
            onplay={() => play(i)}
          />
        </div>
      {/each}
      {#if shown.length < visible.length}
        <div class="more" use:nearEnd={{ key: limit, onreach: () => (limit = growLimit(limit, visible.length)) }}></div>
      {/if}
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
    /* строки вне экрана не раскладываются и не рисуются */
    content-visibility: auto;
    contain-intrinsic-size: auto 56px;
  }
  /* сторож окна списка — невидимая строка в самом низу */
  .more {
    height: 1px;
  }
  .collab {
    padding: 1px 8px;
    border-radius: 999px;
    background: var(--accent-soft);
    color: var(--accent);
    font-weight: 600;
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
