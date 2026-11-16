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
  import { t, lang } from '../lib/i18n.svelte'

  const W = 280
  let el: HTMLElement | undefined = $state()
  let view = $state<'main' | 'playlists'>('main')
  let newName = $state('')
  let pos = $state({ left: 0, top: 0 })

  const LOCALES = { ru: 'ru-RU', en: 'en-GB', uk: 'uk-UA' } as const
  const target = $derived(trackMenu.target)
  const liked = $derived(target ? library.isLiked(target.track.ref) : false)
  const added = $derived(
    target?.addedAt ? new Date(target.addedAt).toLocaleDateString(LOCALES[lang()], { day: 'numeric', month: 'long', year: 'numeric' }) : null,
  )
  const playlists = $derived(library.playlists.filter((p) => p.id !== target?.playlistId))

  $effect(() => {
    if (!target) return
    view = trackMenu.startView
    newName = ''
    void library.load()
  })

  // Не вылезать за окно: сначала ставим по клику, после отрисовки — сдвигаем внутрь.
  $effect(() => {
    if (!target || !el) return
    view
    const h = el.offsetHeight
    const left = Math.min(Math.max(8, trackMenu.x - (trackMenu.x + W > innerWidth - 8 ? W : 0)), innerWidth - W - 8)
    const top = Math.min(trackMenu.y, innerHeight - h - 8)
    pos = { left, top: Math.max(8, top) }
  })

  function onPointerDown(e: PointerEvent) {
    // нажатие по той же ⋮ не закрываем здесь — её клик сам закроет меню (иначе оно закрылось бы и открылось снова)
    if (trackMenu.anchor?.contains(e.target as Node)) return
    if (target && el && !el.contains(e.target as Node)) trackMenu.close()
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape' && target) {
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
      toast.show(t('Не получилось скопировать'))
    }
  }

  async function createWithTrack() {
    if (!target || !newName.trim()) return
    const tracks = [target.track]
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

{#if target}
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
      <Cover url={target.track.cover_url} size={44} source={target.track.ref} />
      <div class="meta">
        <b>{target.track.title}</b>
        <span>{target.track.artist}</span>
        {#if added}<small>{t('Добавлен')} <b>{added}</b></small>{/if}
      </div>
    </div>

    {#if view === 'main'}
      {@render item('playNext', t('Следующим'), () => player.addToQueue([target.track], true))}
      {#if target.queueAt !== undefined}
        <!-- трек уже в «Далее» — его можно убрать, а не добавить ещё раз -->
        {@const at = target.queueAt}
        {@render item('trash', t('Убрать из очереди'), () => player.removeUpcoming(at))}
      {:else}
        {@render item('queue', t('В очередь'), () => player.addToQueue([target.track], false))}
      {/if}
      {@render item('bolt', t('Волна по треку'), () => wave.start(target.track))}
      <hr />
      {@render item('heart', liked ? t('Удалить из Любимых') : t('В Любимые'), () => library.toggleLike(target.track), liked)}
      {@render item('dislike', wave.isDisliked(target.track.ref) ? t('Убрать из «Не нравится»') : t('Не нравится'), () => wave.dislike(target.track), wave.isDisliked(target.track.ref))}
      <button class="item" role="menuitem" onclick={() => (view = 'playlists')}>
        <Icon name="playlistAdd" size={17} />
        <span>{t('Добавить в плейлист')}</span>
        <Icon name="chevronRight" size={15} />
      </button>
      {#if target.playlistId && target.itemId}
        {@const pid = target.playlistId}
        {@const iid = target.itemId}
        {@render item('trash', t('Убрать из плейлиста'), () => library.removeFromPlaylist(pid, [iid]))}
      {/if}
      <hr />
      {#each target.track.artists.slice(0, 3) as a (a.ref)}
        {@render item('user', target.track.artists.length > 1 ? a.name : t('Перейти к исполнителю'), () => openRef(a.ref))}
      {/each}
      {#if target.track.album}
        {@const album = target.track.album}
        {@render item('disc', t('Перейти к альбому'), () => openRef(album.ref))}
      {/if}
      <hr />
      {@render item('copy', t('Копировать название'), () => copy(`${target.track.artist} — ${target.track.title}`, t('Название скопировано')))}
      {#if target.track.url}
        {@const url = target.track.url}
        {@render item('share', t('Поделиться'), () => copy(url, t('Ссылка скопирована')))}
      {/if}
    {:else}
      <button class="item back" onclick={() => (view = 'main')}>
        <Icon name="chevronLeft" size={17} />
        <span>{t('Добавить в плейлист')}</span>
      </button>
      <form class="new" onsubmit={(e) => (e.preventDefault(), createWithTrack())}>
        <input placeholder={t('Новый плейлист…')} bind:value={newName} spellcheck="false" />
        <button type="submit" aria-label={t('Создать')} title={t('Создать')} disabled={!newName.trim()}><Icon name="plus" size={16} /></button>
      </form>
      <div class="lists">
        {#each playlists as p (p.id)}
          {@render item('music', p.name, () => library.addToPlaylist(p, [target.track]))}
        {:else}
          <p class="none">{t('Своих плейлистов пока нет')}</p>
        {/each}
      </div>
    {/if}
  </div>
{/if}

<style>
  .menu {
    position: fixed;
    z-index: 58; /* выше всплывашки обновления (55), ниже тостов (60) */
    padding: 6px;
    border-radius: var(--radius-l);
    background: rgba(18, 18, 21, 0.96);
    border: 1px solid var(--border-strong);
    box-shadow: 0 16px 40px rgba(0, 0, 0, 0.55);
    backdrop-filter: blur(var(--menu-blur, 16px));
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
    font-size: calc(12px * var(--fs, 1));
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
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
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
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-3);
  }
</style>
