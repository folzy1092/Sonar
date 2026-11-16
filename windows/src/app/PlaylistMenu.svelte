<script lang="ts">
  // Меню плейлиста сервиса (правый клик по плитке «фантомного» плейлиста SoundCloud / Яндекса в
  // медиатеке): открыть, слушать, перемешать, следующими, в очередь, перенести в Sonar, скопировать
  // название, открыть на сайте сервиса. Треки грузятся один раз и запоминаются.
  import Cover from '../components/Cover.svelte'
  import Icon from '../components/Icon.svelte'
  import SourceIcon from '../components/SourceIcon.svelte'
  import type { IconName } from '../components/icons'
  import { playlistMenu } from '../lib/playlist-menu.svelte'
  import { api, errorText, type ServicePlaylist, type Track } from '../lib/api'
  import { library } from '../lib/library.svelte'
  import { toast } from '../lib/toast.svelte'
  import { tracksText } from '../lib/format'
  import { player } from '../player/player.svelte'
  import { openRef } from './router.svelte'
  import { pop } from '../lib/motion'
  import { t } from '../lib/i18n.svelte'

  const W = 260
  let el: HTMLElement | undefined = $state()
  let pos = $state({ left: 0, top: 0 })
  const p = $derived(playlistMenu.target)
  const sc = $derived(!!p?.ref.startsWith('sc'))

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

  // не вылезать за окно
  $effect(() => {
    if (!p || !el) return
    const h = el.offsetHeight
    const left = Math.min(Math.max(8, playlistMenu.x), innerWidth - W - 8)
    const top = Math.min(playlistMenu.y, innerHeight - h - 8)
    pos = { left, top: Math.max(8, top) }
  })

  function onPointerDown(e: PointerEvent) {
    if (p && el && !el.contains(e.target as Node)) playlistMenu.close()
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

  /** Адрес на сайте сервиса: у Яндекса он собирается из ref, у SoundCloud без адреса — пункта нет. */
  const webUrl = $derived.by(() => {
    if (!p) return null
    const m = /^ympl:([^:]+):(.+)$/.exec(p.ref)
    if (m) return `https://music.yandex.ru/users/${m[1]}/playlists/${m[2]}`
    if (p.ref === 'scpl:likes') return 'https://soundcloud.com/you/likes'
    return null
  })
</script>

<svelte:window onpointerdown={onPointerDown} onkeydown={(e) => e.key === 'Escape' && playlistMenu.close()} onblur={() => playlistMenu.close()} />

{#snippet item(icon: IconName, label: string, fn: () => unknown)}
  <button class="item" role="menuitem" onclick={fn}>
    <Icon name={icon} size={17} />
    <span>{label}</span>
  </button>
{/snippet}

{#if p}
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
        <span><SourceIcon kind={sc ? 'sc' : 'ym'} size={12} plain /> {p.owner || (sc ? 'SoundCloud' : t('Яндекс Музыка'))}</span>
        {#if p.track_count}<small>{tracksText(p.track_count)}</small>{/if}
      </div>
    </div>

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
    {#if webUrl}
      {@const url = webUrl}
      {@render item('link', sc ? t('Открыть в SoundCloud') : t('Открыть в Яндекс Музыке'), () => {
        playlistMenu.close()
        void api.openUrl(url).catch(() => {})
      })}
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
</style>
