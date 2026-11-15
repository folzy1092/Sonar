<script lang="ts">
  import { cascade } from '../lib/cascade'
  import { indicator } from '../lib/indicator'
  // Медиатека (pc/Screenshot_21): вкладки Все / Плейлисты / Альбомы / Исполнители, «Вы вошли как»,
  // Любимые и свои плейлисты, плейлисты сервисов «фантомом» (открыть или перенести в Sonar),
  // сохранённые альбомы и исполнители; внизу слева — создать · импорт · обновить.
  import IconButton from '../components/IconButton.svelte'
  import Icon from '../components/Icon.svelte'
  import Tile from '../components/Tile.svelte'
  import { api, type Album, type Artist, type ServicePlaylist, type ServicesStatus } from '../lib/api'
  import { tracksText } from '../lib/format'
  import { library } from '../lib/library.svelte'
  import { openRef, router } from '../app/router.svelte'
  import { settingsPanel } from './settings-section.svelte'

  const tabs = ['Все', 'Плейлисты', 'Альбомы', 'Исполнители'] as const
  let tab = $state<(typeof tabs)[number]>('Все')

  let status = $state<ServicesStatus | null>(null)
  let albums = $state<Album[]>([])
  let artists = $state<Artist[]>([])
  let phantom = $state<{ sc: ServicePlaylist[]; ym: ServicePlaylist[] }>({ sc: [], ym: [] })
  let phantomError = $state<string | null>(null)
  let creating = $state(false)
  let newName = $state('')

  const favCount = $derived([...library.liked].filter((r) => r.startsWith('sc:') || r.startsWith('ym:')).length)
  const own = $derived(tab === 'Все' ? library.playlists.filter((p) => !p.hidden) : library.playlists)
  const imported = $derived(new Set(library.playlists.map((p) => p.source_ref).filter(Boolean)))
  const accounts = $derived(
    status ? [status.soundcloud, status.yandex].filter((s) => s.connected) : [],
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
      status = await api.servicesStatus()
      const [sc, ym] = await Promise.all([
        status.soundcloud.connected ? api.servicePlaylists('soundcloud').catch((e) => ((phantomError = String(e)), [])) : [],
        status.yandex.connected ? api.servicePlaylists('yandex').catch((e) => ((phantomError = String(e)), [])) : [],
      ])
      phantom = { sc, ym }
    } catch {
      status = null
    }
  }

  $effect(() => {
    library.version
    void loadSaved()
  })
  void library.load()
  void loadServices()

  function refresh() {
    void library.load(true)
    void loadSaved()
    void loadServices()
  }

  async function create() {
    const name = newName.trim()
    if (!name) return
    const p = await library.createPlaylist(name)
    creating = false
    newName = ''
    if (p) router.go('playlist', p.id)
  }

  function openServices() {
    settingsPanel.show('services')
  }
</script>

<div class="tabs" role="tablist" use:indicator={{ key: tab }}>
  {#each tabs as t (t)}
    <button class="tab" class:on={tab === t} role="tab" aria-selected={tab === t} onclick={() => (tab = t)}>{t}</button>
  {/each}
</div>

{#if accounts.length}
  <p class="who">
    Вы вошли как
    <span class="avatars">
      {#each accounts as a, i (i)}
        <span class="av">{#if a.avatar_url}<img src={a.avatar_url} alt="" />{:else}{(a.name ?? '?').slice(0, 1).toUpperCase()}{/if}</span>
      {/each}
    </span>
    <b>{accounts.map((a) => a.name ?? 'аккаунт').join(', ')}</b>
  </p>
{:else}
  <p class="who">Свои плейлисты сервисов появятся здесь после входа: <button class="link" onclick={openServices}>Настройки → Сервисы</button></p>
{/if}

{#snippet phantomTile(p: ServicePlaylist)}
  <Tile
    title={p.title}
    subtitle={p.owner || (p.ref.startsWith('sc') ? 'SoundCloud' : 'Яндекс Музыка')}
    meta={p.track_count ? tracksText(p.track_count) : imported.has(p.ref) ? 'Перенесён в Sonar' : undefined}
    image={p.cover_url}
    icon={p.ref.endsWith('likes') ? 'heart' : 'music'}
    source={p.ref}
    onclick={() => openRef(p.ref)}
  />
{/snippet}

{#if tab === 'Все' || tab === 'Плейлисты'}
  <section class="block">
    <h2>Плейлисты {#if tab === 'Все'}<button class="more" aria-label="Все плейлисты" onclick={() => (tab = 'Плейлисты')}><Icon name="chevronRight" size={18} /></button>{/if}</h2>
    <div class:row={tab === 'Все'} class:grid={tab !== 'Все'} use:cascade={tab}>
      <Tile title="Любимые" subtitle="Лайкнутые треки" meta={tracksText(favCount)} icon="heart" onclick={() => router.go('playlist', 'favorites')} />
      {#each own as p (p.id)}
        <Tile title={p.name} subtitle={p.hidden ? 'Скрыт' : 'Sonar'} meta={tracksText(p.track_count)} covers={p.covers} dim={p.hidden} onclick={() => router.go('playlist', p.id)} />
      {/each}
      {#if creating}
        <form class="create" onsubmit={(e) => (e.preventDefault(), create())}>
          <!-- svelte-ignore a11y_autofocus -->
          <input placeholder="Название" bind:value={newName} autofocus spellcheck="false" onkeydown={(e) => e.key === 'Escape' && (creating = false)} />
          <button type="submit" disabled={!newName.trim()}>Создать</button>
        </form>
      {:else}
        <Tile title="Новый плейлист" subtitle="SoundCloud и Яндекс вместе" icon="plus" ghost onclick={() => (creating = true)} />
      {/if}
    </div>
  </section>

  {#if tab === 'Плейлисты'}
    {#each [{ name: 'Из SoundCloud', list: phantom.sc }, { name: 'Из Яндекс Музыки', list: phantom.ym }] as g (g.name)}
      {#if g.list.length}
        <section class="block">
          <h2>{g.name}</h2>
          <p class="hint">Открой, чтобы послушать, или перенеси в Sonar кнопкой на странице плейлиста.</p>
          <div class="grid" use:cascade>{#each g.list as p (p.ref)}{@render phantomTile(p)}{/each}</div>
        </section>
      {/if}
    {/each}
    {#if phantomError}<p class="hint err">{phantomError}</p>{/if}
  {:else if phantom.sc.length || phantom.ym.length}
    <section class="block">
      <h2>Из сервисов <button class="more" aria-label="Все плейлисты сервисов" onclick={() => (tab = 'Плейлисты')}><Icon name="chevronRight" size={18} /></button></h2>
      <div class="row" use:cascade>{#each [...phantom.sc, ...phantom.ym] as p (p.ref)}{@render phantomTile(p)}{/each}</div>
    </section>
  {/if}
{/if}

{#if tab === 'Все' || tab === 'Альбомы'}
  {#if albums.length || tab === 'Альбомы'}
    <section class="block">
      <h2>Альбомы {#if tab === 'Все'}<button class="more" aria-label="Все альбомы" onclick={() => (tab = 'Альбомы')}><Icon name="chevronRight" size={18} /></button>{/if}</h2>
      {#if albums.length}
        <div class:row={tab === 'Все'} class:grid={tab !== 'Все'} use:cascade={tab}>
          {#each albums as a (a.ref)}
            <Tile title={a.title} subtitle={a.artist} meta={a.year ? String(a.year) : undefined} image={a.cover_url} icon="disc" source={a.ref} onclick={() => openRef(a.ref)} />
          {/each}
        </div>
      {:else}
        <p class="hint">Жми ❤ на странице альбома — он появится здесь.</p>
      {/if}
    </section>
  {/if}
{/if}

{#if tab === 'Все' || tab === 'Исполнители'}
  <section class="block">
    <h2>Исполнители {#if tab === 'Все'}<button class="more" aria-label="Все исполнители" onclick={() => (tab = 'Исполнители')}><Icon name="chevronRight" size={18} /></button>{/if}</h2>
    {#if artists.length}
      <div class:row={tab === 'Все'} class:grid={tab !== 'Все'} use:cascade={tab}>
        {#each artists as a (a.ref)}
          <Tile title={a.name} image={a.avatar_url} icon="user" round onclick={() => openRef(a.ref)} />
        {/each}
      </div>
    {:else}
      <p class="hint">Нажми «Подписаться» на странице исполнителя — он появится здесь.</p>
    {/if}
  </section>
{/if}

<div class="actions">
  <IconButton icon="plus" label="Создать плейлист" size={16} onclick={() => ((tab = tab === 'Все' || tab === 'Плейлисты' ? tab : 'Плейлисты'), (creating = true))} />
  <IconButton icon="download" label="Импорт плейлистов сервисов" size={16} onclick={() => (tab = 'Плейлисты')} />
  <IconButton icon="refresh" label="Обновить" size={16} onclick={refresh} />
</div>

<style>
  .tabs {
    display: flex;
    gap: 18px;
    padding-bottom: 6px;
  }
  .tab {
    font-family: var(--font-display);
    font-size: 26px;
    font-weight: 800;
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
    font-size: 16px;
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
    font-size: 13px;
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
  h2 {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 24px;
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
  .create {
    display: flex;
    flex-direction: column;
    justify-content: center;
    gap: 8px;
    width: 160px;
    flex-shrink: 0;
    aspect-ratio: 1;
    padding: 14px;
    border-radius: var(--radius-l);
    border: 1px dashed var(--border-strong);
  }
  .create input {
    height: 34px;
    padding: 0 10px;
    border-radius: var(--radius-s);
    background: var(--plate);
    border: 1px solid var(--border);
    outline: none;
    user-select: text;
  }
  .create button {
    height: 34px;
    border-radius: 999px;
    background: var(--accent);
    color: var(--accent-ink);
    font-weight: 700;
  }
  .create button:disabled {
    opacity: 0.4;
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
    margin-top: 32px;
    padding: 4px;
    border-radius: var(--radius-m);
    background: var(--plate);
    border: 1px solid var(--border);
  }
</style>
