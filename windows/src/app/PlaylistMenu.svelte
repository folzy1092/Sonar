<script lang="ts">
  // Меню плейлиста (правый клик по плитке в медиатеке): открыть, слушать, перемешать, следующими, в
  // очередь, скопировать название. У плейлиста сервиса ещё «Перенести в Sonar» и сайт сервиса, у своего
  // плейлиста Sonar — «Лайкнуть все треки» и внизу «Скрыть плейлист» / «Показать плейлист»
  // (решение владельца 2026-11-17). Любимые — те же действия и «Очистить Любимые» с двойным подтверждением
  // окном по центру (второй раз — «Да» через 3 с). Треки сервиса грузятся один раз и запоминаются.
  // «Экспорт ›» у всех трёх — подменю M3U8 / CSV / JSON (ExportItems, export.ts), файл — в окне «Сохранить как».
  import Cover from '../components/Cover.svelte'
  import Icon from '../components/Icon.svelte'
  import SourceIcon from '../components/SourceIcon.svelte'
  import type { IconName } from '../components/icons'
  import { playlistMenu } from '../lib/playlist-menu.svelte'
  import { api, errorText, type Playlist, type ServicePlaylist, type Track } from '../lib/api'
  import { library } from '../lib/library.svelte'
  import { toast } from '../lib/toast.svelte'
  import { tracksText } from '../lib/format'
  import { player } from '../player/player.svelte'
  import { openRef, router } from './router.svelte'
  import { pop, rise } from '../lib/motion'
  import { t } from '../lib/i18n.svelte'
  import { byId, isTrackRef, playlistWebUrl, serviceOf } from '../lib/services'
  import { confirm } from '../lib/confirm.svelte'
  import NavIcon from '../components/NavIcon.svelte'
  import ExportItems from './ExportItems.svelte'
  import type { ExportFormat } from '../lib/export'
  import { saveExport } from '../lib/export-save'

  const W = 260
  let el: HTMLElement | undefined = $state()
  let pos = $state({ left: 0, top: 0 })
  const p = $derived(playlistMenu.target)
  const own = $derived(playlistMenu.own)
  const fav = $derived(playlistMenu.fav)
  /** Сервис плейлиста (lib/services); не распознан — Яндекс, как раньше. */
  const svc = $derived(byId(serviceOf(p?.ref)) ?? byId('ym')!)

  const cache = new Map<string, Promise<Track[]>>()
  function tracksOf(pl: ServicePlaylist): Promise<Track[]> {
    let list = cache.get(pl.ref)
    if (!list) {
      list = api.servicePlaylist(pl.ref).then((r) => r.tracks)
      list.catch(() => cache.delete(pl.ref))
      cache.set(pl.ref, list)
    }
    return list
  }

  /** Что показывает меню: действия или подменю «Экспорт». Новый плейлист — снова действия. */
  let view = $state<'main' | 'export'>('main')
  $effect(() => {
    p
    own
    fav
    view = 'main'
  })

  // не вылезать за окно
  $effect(() => {
    if ((!p && !own && !fav) || !el) return
    view // подменю «Экспорт» короче — после смены пересчитать
    const h = el.offsetHeight
    const left = Math.min(Math.max(8, playlistMenu.x), innerWidth - W - 8)
    const top = Math.min(playlistMenu.y, innerHeight - h - 8)
    pos = { left, top: Math.max(8, top) }
  })

  function onPointerDown(e: PointerEvent) {
    if ((p || own || fav) && el && !el.contains(e.target as Node)) playlistMenu.close()
  }

  /** Действие с треками плейлиста: меню закрывается сразу, треки догружаются в фоне. */
  function withTracks(fn: (tracks: Track[], pl: ServicePlaylist) => unknown, done?: string) {
    const pl = p
    if (!pl) return
    playlistMenu.close()
    tracksOf(pl)
      .then((tracks) => {
        if (!tracks.length) return toast.show(t('В плейлисте нет треков'))
        fn(tracks, pl)
        if (done) toast.show(done)
      })
      .catch((e) => toast.show(errorText(e)))
  }

  /** То же для своего плейлиста: треки берутся из базы при каждом действии (список мог поменяться). */
  function withOwn(fn: (tracks: Track[], pl: Playlist) => unknown, done?: string) {
    const pl = own
    if (!pl) return
    playlistMenu.close()
    api
      .playlist(pl.id)
      .then((full) => {
        const tracks = full.tracks ?? []
        if (!tracks.length) return toast.show(t('В плейлисте нет треков'))
        return Promise.resolve(fn(tracks, full)).then((r) => {
          if (typeof r === 'string') toast.show(r)
          else if (done) toast.show(done)
        })
      })
      .catch((e) => toast.show(errorText(e)))
  }

  /** Действие с Любимыми: треки берутся из базы при каждом действии. */
  function withFav(fn: (tracks: Track[]) => unknown, done?: string) {
    playlistMenu.close()
    api
      .favorites()
      .then((tracks) => {
        if (!tracks.length) return toast.show(t('В Любимых пока пусто'))
        fn(tracks)
        if (done) toast.show(done)
      })
      .catch((e) => toast.show(errorText(e)))
  }

  /** Очистить Любимые — два вопроса подряд, во втором «Да» доступна через 3 секунды. */
  async function clearFav() {
    playlistMenu.close()
    const first = await confirm.ask({
      title: t('Очистить Любимые?'),
      text: t('Из Любимых уберутся все треки. Альбомы и исполнители останутся.'),
      yes: t('Да'),
      no: t('Нет'),
      danger: true,
    })
    if (!first) return
    const sure = await confirm.ask({
      title: t('Точно очистить Любимые?'),
      text: t('Это действие невозможно отменить.'),
      yes: t('Да, очистить'),
      no: t('Нет'),
      danger: true,
      delay: 3,
    })
    if (sure) await library.clearFavorites()
  }

  async function toggleHidden() {
    const pl = own
    if (!pl) return
    playlistMenu.close()
    try {
      await api.updatePlaylist(pl.id, { hidden: !pl.hidden })
      toast.show(pl.hidden ? t('Плейлист снова виден') : t('Плейлист скрыт из «Все»'))
      await library.refreshPlaylists()
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  // удаление — в два клика: первый превращает пункт в красное «Точно удалить?», второй удаляет
  let confirmDelete = $state(false)
  $effect(() => {
    own
    confirmDelete = false
  })
  async function removeOwn() {
    const pl = own
    if (!pl) return
    if (!confirmDelete) {
      confirmDelete = true
      return
    }
    playlistMenu.close()
    try {
      await api.deletePlaylist(pl.id)
      await library.refreshPlaylists()
      toast.show(t('Плейлист «{title}» удалён', { title: pl.name }))
      if (router.page === 'playlist' && router.param === pl.id) router.back()
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  async function copyOwnTitle() {
    const pl = own
    playlistMenu.close()
    if (!pl) return
    try {
      await navigator.clipboard.writeText(pl.name)
      toast.show(t('Название скопировано'))
    } catch {
      toast.show(t('Не получилось скопировать'))
    }
  }

  async function importIt() {
    const pl = p
    if (!pl) return
    playlistMenu.close()
    try {
      const r = await api.importPlaylist(pl.ref)
      await library.refreshPlaylists()
      toast.show(t('Плейлист «{name}» теперь в Sonar', { name: r.name }))
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  async function copyTitle() {
    const pl = p
    playlistMenu.close()
    if (!pl) return
    try {
      await navigator.clipboard.writeText(pl.owner ? `${pl.title} — ${pl.owner}` : pl.title)
      toast.show(t('Название скопировано'))
    } catch {
      toast.show(t('Не получилось скопировать'))
    }
  }

  /** Экспорт в файл: треки берутся так же, как для остальных действий (Любимые и свой — из базы). */
  function exportAs(format: ExportFormat) {
    if (fav) return withFav((list) => saveExport(format, t('Любимые'), list))
    if (own) return withOwn((list, pl) => saveExport(format, pl.name, list))
    withTracks((list, pl) => saveExport(format, pl.title, list))
  }

  function onKey(e: KeyboardEvent) {
    if (e.key !== 'Escape') return
    if (view === 'export') view = 'main'
    else playlistMenu.close()
  }

  /** Адрес на сайте сервиса: у Яндекса он собирается из ref, у SoundCloud без адреса — пункта нет. */
  const webUrl = $derived(p ? playlistWebUrl(p.ref) : null)
</script>

<svelte:window onpointerdown={onPointerDown} onkeydown={onKey} onblur={() => playlistMenu.close()} />

{#snippet exportEntry()}
  <button class="item" role="menuitem" onclick={() => (view = 'export')}>
    <Icon name="download" size={17} />
    <span>{t('Экспорт')}</span>
    <Icon name="chevronRight" size={15} />
  </button>
{/snippet}

{#snippet item(icon: IconName, label: string, fn: () => unknown)}
  <button class="item" role="menuitem" onclick={fn}>
    <Icon name={icon} size={17} />
    <span>{label}</span>
  </button>
{/snippet}

{#if fav}
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
      <span class="fav-art"><NavIcon name="heart" active size={24} /></span>
      <div class="meta">
        <b>{t('Любимые')}</b>
        <span>{t('Лайкнутые треки')}</span>
        {#if library.liked.size}<small>{tracksText([...library.liked].filter(isTrackRef).length)}</small>{/if}
      </div>
    </div>

    {#if view === 'export'}
      <ExportItems onback={() => (view = 'main')} onpick={exportAs} />
    {:else}
      <!-- переход локальный: при открытии меню строки не «въезжают», только при возврате из «Экспорт» -->
      <div in:rise={{ y: 6, duration: 220 }}>
        {@render item('chevronRight', t('Открыть'), () => {
          playlistMenu.close()
          router.go('playlist', 'favorites')
        })}
        {@render item('play', t('Слушать'), () => withFav((list) => player.playList(list, 0, 'favorites', t('Любимые'))))}
        {@render item('shuffle', t('Слушать вперемешку'), () => withFav((list) => player.playShuffled(list, 'favorites', t('Любимые'))))}
        <hr />
        {@render item('playNext', t('Следующими'), () => withFav((list) => player.addToQueue(list, true), t('Треки будут играть следующими')))}
        {@render item('queue', t('В очередь'), () => withFav((list) => player.addToQueue(list, false), t('Треки добавлены в очередь')))}
        <hr />
        {@render exportEntry()}
        <hr />
        <button class="item danger" role="menuitem" onclick={clearFav}>
          <Icon name="trash" size={17} />
          <span>{t('Очистить Любимые')}</span>
        </button>
      </div>
    {/if}
  </div>
{:else if own}
  {@const ctx = `playlist:${own.id}`}
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
      <Cover url={own.covers[0]} size={44} />
      <div class="meta">
        <b>{own.name}</b>
        <span>{own.hidden ? t('Скрыт') : 'Sonar'}</span>
        {#if own.track_count}<small>{tracksText(own.track_count)}</small>{/if}
      </div>
    </div>

    {#if view === 'export'}
      <ExportItems onback={() => (view = 'main')} onpick={exportAs} />
    {:else}
      <div in:rise={{ y: 6, duration: 220 }}>
        {@render item('chevronRight', t('Открыть'), () => {
          playlistMenu.close()
          router.go('playlist', own.id)
        })}
        {@render item('play', t('Слушать'), () => withOwn((list, pl) => player.playList(list, 0, ctx, pl.name)))}
        {@render item('shuffle', t('Слушать вперемешку'), () => withOwn((list, pl) => player.playShuffled(list, ctx, pl.name)))}
        <hr />
        {@render item('playNext', t('Следующими'), () => withOwn((list) => player.addToQueue(list, true), t('Треки будут играть следующими')))}
        {@render item('queue', t('В очередь'), () => withOwn((list) => player.addToQueue(list, false), t('Треки добавлены в очередь')))}
        <hr />
        {@render item('heart', t('Лайкнуть все треки'), () =>
          withOwn(async (list) => {
            const n = await library.likeAll(list)
            return n ? t('{tracks} — в Любимых', { tracks: tracksText(n) }) : t('Все треки уже в Любимых')
          }),
        )}
        {@render item('copy', t('Копировать название'), copyOwnTitle)}
        {@render exportEntry()}
        <hr />
        {@render item(own.hidden ? 'eye' : 'eyeOff', own.hidden ? t('Показать плейлист') : t('Скрыть плейлист'), toggleHidden)}
        <button class="item danger" class:sure={confirmDelete} role="menuitem" onclick={removeOwn}>
          <Icon name="trash" size={17} />
          <span>{confirmDelete ? t('Точно удалить?') : t('Удалить плейлист')}</span>
        </button>
      </div>
    {/if}
  </div>
{:else if p}
  {@const ctx = `playlist:${p.ref}`}
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
      <Cover url={p.cover_url} size={44} source={p.ref} />
      <div class="meta">
        <b>{p.title}</b>
        <span><SourceIcon service={svc.id} size={12} plain /> {p.owner || t(svc.name)}</span>
        {#if p.track_count}<small>{tracksText(p.track_count)}</small>{/if}
      </div>
    </div>

    {#if view === 'export'}
      <ExportItems onback={() => (view = 'main')} onpick={exportAs} />
    {:else}
      <div in:rise={{ y: 6, duration: 220 }}>
        {@render item('chevronRight', t('Открыть'), () => {
          playlistMenu.close()
          openRef(p.ref)
        })}
        {@render item('play', t('Слушать'), () => withTracks((list, pl) => player.playList(list, 0, ctx, pl.title)))}
        {@render item('shuffle', t('Слушать вперемешку'), () => withTracks((list, pl) => player.playShuffled(list, ctx, pl.title)))}
        <hr />
        {@render item('playNext', t('Следующими'), () => withTracks((list) => player.addToQueue(list, true), t('Треки будут играть следующими')))}
        {@render item('queue', t('В очередь'), () => withTracks((list) => player.addToQueue(list, false), t('Треки добавлены в очередь')))}
        <hr />
        {@render item('playlistAdd', t('Перенести в Sonar'), importIt)}
        {@render item('copy', t('Копировать название'), copyTitle)}
        {@render exportEntry()}
        {#if webUrl}
          {@const url = webUrl}
          {@render item('link', t(svc.openIn ?? 'Открыть в Яндекс Музыке'), () => {
            playlistMenu.close()
            void api.openUrl(url).catch(() => {})
          })}
        {/if}
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
  .meta > span {
    display: flex;
    align-items: center;
    gap: 5px;
  }
  .meta > span,
  small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .fav-art {
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    border-radius: var(--radius-s);
    background: var(--hover);
    flex: none;
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
  .item.danger:hover,
  .item.danger.sure {
    color: var(--danger, #ff5b5b);
  }
  .item.danger.sure {
    background: color-mix(in oklch, var(--danger, #ff5b5b) 14%, transparent);
  }
</style>
