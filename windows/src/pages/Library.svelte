<script lang="ts">
  import { cascade } from '../lib/cascade'
  import { pop } from '../lib/motion'
  import { hscroll } from '../lib/hscroll'
  import { edges } from '../lib/edges'
  // Медиатека один в один по Dotify (pc/Screenshot_21): вкладки Все / Плейлисты / Альбомы /
  // Исполнители без подчёркивания, «Вы вошли как», в одном ряду Любимые, свои плейлисты и плейлисты
  // сервисов («фантомом» — открыть или перенести в Sonar), сохранённые альбомы и исполнители;
  // внизу слева — создать · перенос · обновить. Создание — всплывашка над «+» (только кликом).
  import Icon from '../components/Icon.svelte'
  import NavIcon from '../components/NavIcon.svelte'
  import { playlistMenu } from '../lib/playlist-menu.svelte'
  import Tile from '../components/Tile.svelte'
  import { api, onLocalFilesChanged, type Album, type Artist, type ServicePlaylist, type ServiceStatus, type ServicesStatus } from '../lib/api'
  import { tracksText } from '../lib/format'
  import { library } from '../lib/library.svelte'
  import { smartLists } from '../lib/smart-lists.svelte'
  import { blankRules } from '../lib/smart'
  import { openRef, router } from '../app/router.svelte'
  import { settingsPanel } from './settings-section.svelte'
  import SourceIcon from '../components/SourceIcon.svelte'
  import { ACCOUNT_SERVICES, byId, isTrackRef, serviceOf, statusOf, type ServiceId } from '../lib/services'
  import { ICONS } from '../lib/service-icons'
  import { reducedMotion } from '../lib/motion'
  import { cubicOut } from 'svelte/easing'
  import { t } from '../lib/i18n.svelte'
  import { settings } from '../lib/settings.svelte'
  import { onDestroy } from 'svelte'

  const tabs = ['Все', 'Плейлисты', 'Альбомы', 'Исполнители'] as const
  let tab = $state<(typeof tabs)[number]>('Все')

  let status = $state<ServicesStatus | null>(null)
  let albums = $state<Album[]>([])
  let artists = $state<Artist[]>([])
  let phantom = $state<Partial<Record<ServiceId, ServicePlaylist[]>>>({})
  let phantomError = $state<string | null>(null)
  /** Статус сервисов уже запрошен (успешно или нет) — дальше не скелет, а ответ. */
  let servicesTried = $state(false)
  let creating = $state(false)
  /** Файлы из «Папок с музыкой» (Система → Хранилище): сколько и первые обложки для плитки. */
  let localCount = $state(0)
  let localCovers = $state<string[]>([])
  const hasFolders = $derived(settings.get('storage.music_folders').length > 0)
  let newName = $state('')

  const favCount = $derived([...library.liked].filter(isTrackRef).length)
  const own = $derived(tab === 'Все' ? library.playlists.filter((p) => !p.hidden) : library.playlists)
  const imported = $derived(new Set(library.playlists.map((p) => p.source_ref).filter(Boolean)))
  /** Сервисы блока «плейлисты сервисов» по кругу (решение владельца 2026-11-16): клик по названию —
   *  следующий, ряд уезжает свайпом. Сервисы — реализованные из реестра (lib/services): Spotify и
   *  VK Музыка встанут сюда сами, когда их включат. */
  let svc = $state<ServiceId>(ACCOUNT_SERVICES[0].id)
  /** Куда едет свайп: 1 — следующий справа налево. */
  let dir = $state(1)
  const svcInfo = $derived(byId(svc) ?? ACCOUNT_SERVICES[0])
  const svcName = $derived(t(svcInfo.name))
  const svcConnected = $derived(!!statusOf(status, svcInfo)?.connected)
  /** Плейлисты выбранного сервиса, ещё не перенесённые в Sonar (перенесённые уже есть среди своих). */
  const services = $derived((phantom[svc] ?? []).filter((p) => !imported.has(p.ref)))

  // ширина текущего названия сервиса: последнее появившееся название задаёт ширину кнопки
  let faceW = $state(0)
  let faceNode: HTMLElement | null = null
  function measureFace(node: HTMLElement) {
    faceNode = node
    const ro = new ResizeObserver(() => {
      if (faceNode === node) faceW = node.offsetWidth
    })
    ro.observe(node)
    return { destroy: () => ro.disconnect() }
  }

  function nextService() {
    const i = ACCOUNT_SERVICES.findIndex((x) => x.id === svc)
    dir = 1
    svc = ACCOUNT_SERVICES[(i + 1) % ACCOUNT_SERVICES.length].id
  }

  /** Смена сервиса снизу вверх (решение владельца 2026-11-16): прежний уходит вверх, следующий
   *  поднимается снизу; «меньше движения» — только прозрачность. */
  function swipe(_n: Element, { out = false } = {}) {
    if (reducedMotion()) return { duration: 160, css: (t: number) => `opacity:${t}` }
    const sign = out ? -dir : dir
    return {
      duration: 420,
      easing: cubicOut,
      css: (t: number, u: number) => `opacity:${t};transform:translateY(${sign * u * 26}px)`,
    }
  }
  const accounts = $derived(
    status ? ACCOUNT_SERVICES.map((s) => statusOf(status, s)).filter((s): s is ServiceStatus => !!s?.connected) : [],
  )

  async function loadSaved() {
    try {
      ;[albums, artists] = await Promise.all([api.likedCatalog<Album>('album'), api.likedCatalog<Artist>('artist')])
    } catch {
      // вне приложения
    }
  }

  async function loadServices() {
    phantomError = null
    try {
      const st = await api.servicesStatus()
      status = st
      const lists = await Promise.all(
        ACCOUNT_SERVICES.map((s): Promise<ServicePlaylist[]> | ServicePlaylist[] =>
          statusOf(st, s)?.connected ? api.servicePlaylists(s.key).catch((e) => ((phantomError = String(e)), [])) : [],
        ),
      )
      phantom = Object.fromEntries(ACCOUNT_SERVICES.map((s, i) => [s.id, lists[i]]))
    } catch {
      status = null
    } finally {
      servicesTried = true
    }
  }

  $effect(() => {
    library.version
    void loadSaved()
    void smartLists.load()
  })
  void library.load()
  void loadServices()

  async function loadLocal() {
    try {
      const list = await api.localTracks()
      localCount = list.length
      localCovers = list.flatMap((x) => (x.cover_url ? [x.cover_url] : [])).filter((c, i, a) => a.indexOf(c) === i).slice(0, 4)
    } catch {
      // вне приложения
    }
  }
  void loadLocal()
  onDestroy(onLocalFilesChanged(() => void loadLocal()))

  function refresh() {
    void library.load(true)
    void loadSaved()
    void loadServices()
    void loadLocal()
  }

  async function create() {
    const name = newName.trim()
    if (!name) return
    const p = await library.createPlaylist(name)
    creating = false
    newName = ''
    if (p) router.go('playlist', p.id)
  }

  /** «Умный плейлист» из окна создания: конструктор правил с уже введённым названием. */
  function createSmart() {
    creating = false
    smartLists.edit({ id: null, name: newName.trim(), rules: blankRules() })
    newName = ''
  }

  function openServices() {
    settingsPanel.show('services')
  }
</script>

<div class="tabs" role="tablist" data-tauri-drag-region>
  {#each tabs as tb (tb)}
    <button class="tab" class:on={tab === tb} role="tab" aria-selected={tab === tb} onclick={() => (tab = tb)}>{t(tb)}</button>
  {/each}
</div>

{#if accounts.length}
  <p class="who">
    {t('Вы вошли как')}
    <span class="avatars">
      {#each accounts as a, i (i)}
        <span class="av">{#if a.avatar_url}<img src={a.avatar_url} alt="" />{:else}{(a.name ?? '?').slice(0, 1).toUpperCase()}{/if}</span>
      {/each}
    </span>
    <b>{accounts.map((a) => a.name ?? t('аккаунт')).join(', ')}</b>
  </p>
{:else}
  <p class="who">{t('Свои плейлисты сервисов появятся здесь после входа:')} <button class="link" onclick={openServices}>{t('Настройки → Сервисы')}</button></p>
{/if}

{#snippet phantomTile(p: ServicePlaylist)}
  {@const ps = byId(serviceOf(p.ref)) ?? byId('ym')!}
  {#snippet likeArt()}<span class="svc-like"><SourceIcon service={ps.id} size={ICONS[ps.id]?.likeArtSize ?? 54} mono /></span>{/snippet}
  <Tile
    title={p.title}
    subtitle={p.owner || t(ps.name)}
    meta={p.track_count ? tracksText(p.track_count) : undefined}
    image={p.cover_url}
    icon={p.ref.endsWith('likes') ? 'heart' : 'music'}
    art={p.ref.endsWith('likes') && !p.cover_url ? likeArt : undefined}
    onclick={() => openRef(p.ref)}
    oncontextmenu={(e) => {
      e.preventDefault()
      playlistMenu.open(p, e.clientX, e.clientY)
    }}
  />
{/snippet}

{#snippet smartBadge()}<Icon name="sparkles" size={15} />{/snippet}

{#snippet favArt()}<NavIcon name="heart" active size={44} />{/snippet}

{#if tab === 'Все' || tab === 'Плейлисты'}
  <section class="block">
    {#if tab === 'Все'}
      <h2>{t('Плейлисты')} <button class="more" aria-label={t('Все плейлисты')} onclick={() => (tab = 'Плейлисты')}><Icon name="chevronRight" size={18} /></button></h2>
    {/if}
    <div class:row={tab === 'Все'} class:grid={tab !== 'Все'} use:cascade={tab} use:hscroll use:edges>
      <Tile
        title={t('Любимые')}
        subtitle={t('Лайкнутые треки')}
        meta={tracksText(favCount)}
        art={favArt}
        onclick={() => router.go('playlist', 'favorites')}
        oncontextmenu={(e) => {
          e.preventDefault()
          playlistMenu.openFav(e.clientX, e.clientY)
        }}
      />
      {#each own as p (p.id)}
        <Tile
          title={p.name}
          subtitle={p.hidden ? t('Скрыт') : 'Sonar'}
          meta={tracksText(p.track_count)}
          covers={p.covers}
          dim={p.hidden}
          onclick={() => router.go('playlist', p.id)}
          oncontextmenu={(e) => {
            e.preventDefault()
            playlistMenu.openOwn(p, e.clientX, e.clientY)
          }}
        />
      {/each}
      {#each smartLists.list as p (p.id)}
        <Tile
          title={p.name}
          subtitle={t('Умный плейлист')}
          meta={p.error ? t('Правила не читаются') : tracksText(p.track_count)}
          covers={p.covers}
          icon="sparkles"
          badge={smartBadge}
          onclick={() => router.go('playlist', p.id)}
        />
      {/each}
    </div>
  </section>

  <!-- файлы из «Папок с музыкой» (NEXT_PROMPT этап 10): только если папки выбраны или что-то найдено -->
  {#if hasFolders || localCount}
    <section class="block">
      <h2>{t('На этом компьютере')} <button class="more" aria-label={t('Все файлы')} onclick={() => router.go('playlist', 'local')}><Icon name="chevronRight" size={18} /></button></h2>
      <div class="row" use:cascade={tab}>
        <Tile
          title={t('Файлы')}
          subtitle={t('Папки с музыкой')}
          meta={tracksText(localCount)}
          icon="monitor"
          covers={localCovers}
          onclick={() => router.go('playlist', 'local')}
        />
        <Tile title={t('Папки')} subtitle={t('Настройки → Хранилище')} icon="library" ghost onclick={() => settingsPanel.show('system', 'storage')} />
      </div>
    </section>
  {/if}

  <!-- плейлисты сервисов — свой ряд, сервис переключается по кругу кликом по названию -->
  <section class="block">
    <h2 class="svc-head">
      <button class="svc press" title={t('Следующий сервис')} onclick={nextService}>
        <!-- ширина названия плавно тянется к новому сервису, а не прыгает (решение владельца 2026-11-17) -->
        <span class="svc-faces" style:width={faceW ? `${faceW}px` : undefined}>
          {#key svc}
            <span class="svc-face" in:swipe out:swipe={{ out: true }} use:measureFace>
              <SourceIcon service={svc} size={20} />
              {svcName}
            </span>
          {/key}
        </span>
        <span class="svc-next"><Icon name="chevronRight" size={18} /></span>
      </button>
    </h2>
    <div class="svc-stage">
      {#key svc}
        <div class="svc-slide" in:swipe out:swipe={{ out: true }}>
          {#if !status && !servicesTried}
            <div class="row"><div class="sk-tile skel"></div><div class="sk-tile skel"></div><div class="sk-tile skel"></div></div>
          {:else if !svcConnected}
            <p class="hint">{svcInfo.gender === 'f' ? t('{service} не подключена', { service: svcName }) : t('{service} не подключён', { service: svcName })} — <button class="link" onclick={openServices}>{t('Настройки → Сервисы')}</button></p>
          {:else if services.length}
            <div class:row={tab === 'Все'} class:grid={tab !== 'Все'} use:cascade={svc} use:hscroll use:edges>
              {#each services as p (p.ref)}{@render phantomTile(p)}{/each}
            </div>
          {:else}
            <p class="hint">{t('Все плейлисты {service} уже перенесены в Sonar.', { service: svcName })}</p>
          {/if}
        </div>
      {/key}
    </div>
    {#if phantomError && tab === 'Плейлисты'}<p class="hint err">{phantomError}</p>{/if}
  </section>
{/if}

{#if tab === 'Все' || tab === 'Альбомы'}
  {#if albums.length || tab === 'Альбомы'}
    <section class="block">
      <h2>{t('Альбомы')} {#if tab === 'Все'}<button class="more" aria-label={t('Все альбомы')} onclick={() => (tab = 'Альбомы')}><Icon name="chevronRight" size={18} /></button>{/if}</h2>
      {#if albums.length}
        <div class:row={tab === 'Все'} class:grid={tab !== 'Все'} use:cascade={tab} use:hscroll use:edges>
          {#each albums as a (a.ref)}
            <Tile title={a.title} subtitle={a.artist} meta={a.year ? String(a.year) : undefined} image={a.cover_url} icon="disc" source={a.ref} onclick={() => openRef(a.ref)} />
          {/each}
        </div>
      {:else}
        <p class="hint">{t('Нажми на сердце на странице альбома — он появится здесь.')}</p>
      {/if}
    </section>
  {/if}
{/if}

{#if tab === 'Все' || tab === 'Исполнители'}
  <section class="block">
    <h2>{t('Исполнители')} {#if tab === 'Все'}<button class="more" aria-label={t('Все исполнители')} onclick={() => (tab = 'Исполнители')}><Icon name="chevronRight" size={18} /></button>{/if}</h2>
    {#if artists.length}
      <div class:row={tab === 'Все'} class:grid={tab !== 'Все'} use:cascade={tab} use:hscroll use:edges>
        {#each artists as a (a.ref)}
          <Tile title={a.name} image={a.avatar_url} icon="user" round onclick={() => openRef(a.ref)} />
        {/each}
      </div>
    {:else}
      <p class="hint">{t('Нажми «Подписаться» на странице исполнителя — он появится здесь.')}</p>
    {/if}
  </section>
{/if}

<div class="dock">
  {#if creating}
    <form class="create" onsubmit={(e) => (e.preventDefault(), create())} in:pop={{ y: 8 }} out:pop={{ y: 8 }}>
      <b>{t('Новый плейлист')}</b>
      <!-- svelte-ignore a11y_autofocus -->
      <input placeholder={t('Название')} bind:value={newName} autofocus spellcheck="false" onkeydown={(e) => e.key === 'Escape' && (creating = false)} />
      <div class="btns">
        <button type="button" class="ghost" onclick={() => (creating = false)}>{t('Отмена')}</button>
        <button type="submit" class="primary" disabled={!newName.trim()}>{t('Создать')}</button>
      </div>
      <button type="button" class="smart" onclick={createSmart}><Icon name="sparkles" size={15} /> {t('Умный плейлист — по правилам')}</button>
    </form>
  {/if}
  <div class="actions">
    <button class:on={creating} aria-label={t('Создать плейлист')} title={t('Создать плейлист')} onclick={() => (creating = !creating)}><NavIcon name="add" size={18} /></button>
    <button aria-label={t('Перенос плейлистов сервисов')} title={t('Перенос плейлистов сервисов')} onclick={() => (tab = 'Плейлисты')}><NavIcon name="transfer" size={18} /></button>
    <button aria-label={t('список::Обновить')} title={t('список::Обновить')} onclick={refresh}><NavIcon name="refresh" size={18} /></button>
  </div>
</div>

<style>
  .tabs {
    display: flex;
    align-items: center;
    gap: 18px;
    min-height: 40px;
    padding-right: 150px;
  }
  .tab {
    font-family: var(--font-display);
    font-size: calc(26px * var(--fs, 1));
    font-weight: 800;
    letter-spacing: -0.02em;
    color: var(--text-3);
    transition: color var(--fast) var(--ease);
  }
  .tab:hover {
    color: var(--text-2);
  }
  .tab.on {
    color: var(--text);
  }
  .who {
    display: flex;
    align-items: center;
    gap: 10px;
    margin: 12px 0 0;
    color: var(--text-2);
    font-size: calc(16px * var(--fs, 1));
  }
  .avatars {
    display: flex;
  }
  .av {
    display: grid;
    place-items: center;
    width: 30px;
    height: 30px;
    margin-left: -8px;
    overflow: hidden;
    border-radius: 50%;
    border: 2px solid var(--surface-0);
    background: var(--surface-3);
    color: var(--text);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 700;
  }
  .av:first-child {
    margin-left: 0;
  }
  .av img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .who b {
    color: var(--text);
  }
  .link {
    color: var(--text);
    text-decoration: underline;
    text-underline-offset: 2px;
  }
  .block {
    margin-top: 28px;
  }
  .svc {
    position: relative;
    overflow: hidden;
    display: inline-grid;
    grid-template-columns: auto auto;
    align-items: center;
    gap: 6px;
    margin-left: -10px;
    padding: 4px 10px;
    border-radius: 14px;
    font: inherit;
    overflow: hidden;
    transition: background var(--fast) var(--ease);
  }
  .svc:hover {
    background: var(--hover);
  }
  .svc-faces {
    display: grid;
    justify-items: start;
    transition: width 0.36s cubic-bezier(0.22, 1, 0.36, 1);
  }
  .svc-face {
    grid-area: 1 / 1;
    display: inline-flex;
    align-items: center;
    gap: 10px;
    white-space: nowrap;
  }
  .svc-next {
    grid-column: 2;
    display: grid;
    color: var(--text-3);
    transition:
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .svc:hover .svc-next {
    color: var(--text);
    transform: translateX(2px);
  }
  /* старый и новый ряд стоят в одной клетке, пока один уезжает, а другой въезжает */
  .svc-stage {
    display: grid;
  }
  .svc-slide {
    grid-area: 1 / 1;
    min-width: 0;
  }
  .sk-tile {
    width: 160px;
    height: 200px;
    flex: none;
    border-radius: var(--radius-l);
  }
  h2 {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: calc(24px * var(--fs, 1));
    font-weight: 800;
    margin-bottom: 14px;
  }
  .more {
    display: grid;
    color: var(--text-3);
  }
  .more:hover {
    color: var(--text);
  }
  .row {
    --fade: 64px;
    display: flex;
    gap: 18px;
    overflow-x: auto;
    padding-bottom: 4px;
    scrollbar-width: none;
  }
  .row::-webkit-scrollbar {
    display: none;
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
    gap: 18px;
  }
  .grid :global(.tile) {
    width: auto;
  }
  .dock {
    position: relative;
    display: inline-block;
    margin-top: 32px;
  }
  .create {
    position: absolute;
    left: 0;
    bottom: calc(100% + 8px);
    z-index: 5;
    display: flex;
    flex-direction: column;
    gap: 10px;
    width: 260px;
    padding: 14px;
    border-radius: var(--radius-l);
    background: var(--surface-2);
    border: 1px solid var(--border-strong);
    box-shadow: 0 16px 40px rgba(0, 0, 0, 0.45);
    transform-origin: bottom left;
  }
  .create b {
    font-size: calc(14px * var(--fs, 1));
  }
  .create input {
    height: 36px;
    padding: 0 12px;
    border-radius: var(--radius-s);
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    outline: none;
    user-select: text;
    transition: border-color var(--fast) var(--ease);
  }
  .create input:focus {
    border-color: var(--border-strong);
  }
  .btns {
    display: flex;
    justify-content: flex-end;
    gap: 6px;
  }
  .btns button {
    height: 32px;
    padding: 0 14px;
    border-radius: 10px;
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    transition:
      background var(--fast) var(--ease),
      opacity var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .btns button:active:not(:disabled) {
    transform: scale(0.96);
  }
  .ghost {
    color: var(--text-2);
  }
  .ghost:hover {
    background: var(--hover);
    color: var(--text);
  }
  .primary {
    background: var(--accent);
    color: var(--accent-ink);
  }
  .primary:disabled {
    opacity: 0.4;
  }
  .smart {
    display: flex;
    align-items: center;
    gap: 8px;
    height: 34px;
    padding: 0 12px;
    border-radius: 10px;
    border: 1px dashed var(--border-strong);
    color: var(--text-2);
    font-weight: 600;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .smart:hover {
    background: var(--hover);
    color: var(--text);
  }
  .smart :global(svg) {
    color: var(--accent);
  }
  .hint {
    margin: -6px 0 12px;
    color: var(--text-3);
  }
  .err {
    color: var(--danger);
  }
  .actions {
    display: inline-flex;
    gap: 2px;
    padding: 4px;
    border-radius: var(--radius-m);
    background: var(--plate);
  }
  .actions button {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
    border-radius: 9px;
    color: var(--text-3);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .actions button:hover,
  .actions button.on {
    color: var(--text);
    background: var(--hover);
  }
  .actions button:active {
    transform: scale(0.9);
  }
  /* «Лайки SoundCloud» / «Мне нравится» — знак сервиса цветом темы, как сердце «Любимых» */
  .svc-like {
    display: grid;
    color: var(--accent);
    transition: color 0.6s var(--ease);
  }
</style>
