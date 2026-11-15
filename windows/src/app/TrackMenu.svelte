<script lang="ts">
  // Меню трека по pc/Screenshot_29. Открывается и закрывается только кликом (правило владельца):
  // клик мимо, Esc или выбор пункта. «Добавить в плейлист ›» — тоже по клику, список внутри меню.
  import Cover from '../components/Cover.svelte'
  import Icon from '../components/Icon.svelte'
  import type { IconName } from '../components/icons'
  import { trackMenu } from '../lib/menu.svelte'
  import { library } from '../lib/library.svelte'
  import { toast } from '../lib/toast.svelte'
  import { player } from '../player/player.svelte'
  import { openRef } from './router.svelte'
  import { pop } from '../lib/motion'
  import { wave } from '../player/my-wave.svelte'

  const W = 280
  let el: HTMLElement | undefined = $state()
  let view = $state<'main' | 'playlists'>('main')
  let newName = $state('')
  let pos = $state({ left: 0, top: 0 })

  const t = $derived(trackMenu.target)
  const liked = $derived(t ? library.isLiked(t.track.ref) : false)
  const added = $derived(
    t?.addedAt ? new Date(t.addedAt).toLocaleDateString('ru-RU', { day: 'numeric', month: 'long', year: 'numeric' }) : null,
  )
  const playlists = $derived(library.playlists.filter((p) => p.id !== t?.playlistId))

  $effect(() => {
    if (!t) return
    view = 'main'
    newName = ''
    void library.load()
  })

  // Не вылезать за окно: сначала ставим по клику, после отрисовки — сдвигаем внутрь.
  $effect(() => {
    if (!t || !el) return
    view
    const h = el.offsetHeight
    const left = Math.min(Math.max(8, trackMenu.x - (trackMenu.x + W > innerWidth - 8 ? W : 0)), innerWidth - W - 8)
    const top = Math.min(trackMenu.y, innerHeight - h - 8)
    pos = { left, top: Math.max(8, top) }
  })

  function onPointerDown(e: PointerEvent) {
    // нажатие по той же ⋮ не закрываем здесь — её клик сам закроет меню (иначе оно закрылось бы и открылось снова)
    if (trackMenu.anchor?.contains(e.target as Node)) return
    if (t && el && !el.contains(e.target as Node)) trackMenu.close()
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape' && t) {
      if (view === 'playlists') view = 'main'
      else trackMenu.close()
    }
  }

  function run(fn: () => unknown) {
    fn()
    trackMenu.close()
  }

  async function copy(text: string, done: string) {
    try {
      await navigator.clipboard.writeText(text)
      toast.show(done)
    } catch {
      toast.show('Не получилось скопировать')
    }
  }

  async function createWithTrack() {
    if (!t || !newName.trim()) return
    const tracks = [t.track]
    trackMenu.close()
    await library.createPlaylist(newName.trim(), tracks)
  }
</script>

<svelte:window onpointerdown={onPointerDown} onkeydown={onKey} onblur={() => trackMenu.close()} />

{#snippet item(icon: IconName, label: string, fn: () => unknown, filled = false)}
  <button class="item" role="menuitem" onclick={() => run(fn)}>
    <Icon name={icon} size={17} {filled} />
    <span>{label}</span>
  </button>
{/snippet}

{#if t}
  <div
    class="menu"
    role="menu"
    tabindex="-1"
    bind:this={el}
    style:left="{pos.left}px"
    style:top="{pos.top}px"
    style:width="{W}px"
    in:pop={{ y: -6 }}
    out:pop={{ y: -6 }}
    oncontextmenu={(e) => e.preventDefault()}
  >
    <div class="head">
      <Cover url={t.track.cover_url} size={44} source={t.track.ref} />
      <div class="meta">
        <b>{t.track.title}</b>
        <span>{t.track.artist}</span>
        {#if added}<small>Добавлен <b>{added}</b></small>{/if}
      </div>
    </div>

    {#if view === 'main'}
      {@render item('playNext', 'Следующим', () => player.addToQueue([t.track], true))}
      {@render item('queue', 'В очередь', () => player.addToQueue([t.track], false))}
      {@render item('bolt', 'Волна по треку', () => wave.start(t.track))}
      <hr />
      {@render item('heart', liked ? 'Удалить из Любимых' : 'В Любимые', () => library.toggleLike(t.track), liked)}
      {@render item('dislike', wave.isDisliked(t.track.ref) ? 'Убрать из «Не нравится»' : 'Не нравится', () => wave.dislike(t.track), wave.isDisliked(t.track.ref))}
      <button class="item" role="menuitem" onclick={() => (view = 'playlists')}>
        <Icon name="playlistAdd" size={17} />
        <span>Добавить в плейлист</span>
        <Icon name="chevronRight" size={15} />
      </button>
      {#if t.playlistId && t.itemId}
        {@const pid = t.playlistId}
        {@const iid = t.itemId}
        {@render item('trash', 'Убрать из плейлиста', () => library.removeFromPlaylist(pid, [iid]))}
      {/if}
      <hr />
      {#each t.track.artists.slice(0, 3) as a (a.ref)}
        {@render item('user', t.track.artists.length > 1 ? a.name : 'Перейти к исполнителю', () => openRef(a.ref))}
      {/each}
      {#if t.track.album}
        {@const album = t.track.album}
        {@render item('disc', 'Перейти к альбому', () => openRef(album.ref))}
      {/if}
      <hr />
      {@render item('copy', 'Копировать название', () => copy(`${t.track.artist} — ${t.track.title}`, 'Название скопировано'))}
      {#if t.track.url}
        {@const url = t.track.url}
        {@render item('share', 'Поделиться', () => copy(url, 'Ссылка скопирована'))}
      {/if}
    {:else}
      <button class="item back" onclick={() => (view = 'main')}>
        <Icon name="chevronLeft" size={17} />
        <span>Добавить в плейлист</span>
      </button>
      <form class="new" onsubmit={(e) => (e.preventDefault(), createWithTrack())}>
        <input placeholder="Новый плейлист…" bind:value={newName} spellcheck="false" />
        <button type="submit" aria-label="Создать" title="Создать" disabled={!newName.trim()}><Icon name="plus" size={16} /></button>
      </form>
      <div class="lists">
        {#each playlists as p (p.id)}
          {@render item('music', p.name, () => library.addToPlaylist(p, [t.track]))}
        {:else}
          <p class="none">Своих плейлистов пока нет</p>
        {/each}
      </div>
    {/if}
  </div>
{/if}

<style>
  .menu {
    position: fixed;
    z-index: 50;
    padding: 6px;
    border-radius: var(--radius-l);
    background: rgba(18, 18, 21, 0.96);
    border: 1px solid var(--border-strong);
    box-shadow: 0 16px 40px rgba(0, 0, 0, 0.55);
    backdrop-filter: blur(16px);
    transform-origin: top left;
  }
  .head {
    display: flex;
    gap: 10px;
    align-items: center;
    padding: 6px 8px 10px;
  }
  .meta {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .meta > b,
  .meta > span {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .meta > span,
  small {
    font-size: 12px;
    color: var(--text-3);
  }
  small b {
    color: var(--text-2);
  }
  hr {
    margin: 4px 8px;
    border: 0;
    border-top: 1px solid var(--border);
  }
  .item {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    height: 36px;
    padding: 0 10px;
    border-radius: var(--radius-s);
    color: var(--text-2);
    text-align: left;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .item span {
    flex: 1;
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .item:hover {
    background: var(--hover);
    color: var(--text);
  }
  .back {
    color: var(--text);
    font-weight: 600;
  }
  .new {
    display: flex;
    gap: 6px;
    margin: 4px 4px 6px;
  }
  .new input {
    flex: 1;
    min-width: 0;
    height: 34px;
    padding: 0 12px;
    border-radius: var(--radius-s);
    background: var(--plate);
    border: 1px solid var(--border);
    outline: none;
    user-select: text;
  }
  .new input:focus {
    border-color: var(--border-strong);
  }
  .new button {
    display: grid;
    place-items: center;
    width: 34px;
    border-radius: var(--radius-s);
    background: var(--accent);
    color: var(--accent-ink);
  }
  .new button:disabled {
    opacity: 0.35;
  }
  .lists {
    max-height: 260px;
    overflow-y: auto;
  }
  .none {
    margin: 6px 10px 8px;
    font-size: 13px;
    color: var(--text-3);
  }
</style>
