<script lang="ts">
  // Ссылка в строке поиска (решение владельца 2026-11-16): вставил ссылку на трек, альбом, артиста
  // или плейлист SoundCloud / Яндекс Музыки — вместо поиска карточка того, что за ней, и одна
  // кнопка «В медиатеку»: трек и альбом — в лайки, артист — подписка, плейлист — перенос в Sonar.
  // Плейлист и альбом ещё можно «Перенести с подбором» (этап 5, pages/ImportPage): каждому треку —
  // пара в подключённых сервисах. Apple Music (своего сервиса нет) — только так.
  import Cover from '../components/Cover.svelte'
  import Icon from '../components/Icon.svelte'
  import SourceIcon from '../components/SourceIcon.svelte'
  import EmptyState from '../components/EmptyState.svelte'
  import { api, errorText, type LinkItem } from '../lib/api'
  import { library } from '../lib/library.svelte'
  import { toast } from '../lib/toast.svelte'
  import { openRef } from '../app/router.svelte'
  import { player } from '../player/player.svelte'
  import { tracksText } from '../lib/format'
  import { trackMenu } from '../lib/menu.svelte'
  import { pulse } from '../lib/pulse'
  import { t } from '../lib/i18n.svelte'
  import { serviceOf } from '../lib/services'
  import type { ImportService } from '../lib/import'
  import { openImport } from '../lib/import.svelte'

  let { url }: { url: string } = $props()

  let item = $state<LinkItem | null>(null)
  let error = $state<string | null>(null)
  let busy = $state(false)
  let imported = $state(false)

  $effect(() => {
    const u = url.trim()
    item = null
    error = null
    imported = false
    let alive = true
    api
      .resolveLink(u)
      .then((r) => alive && (item = r))
      .catch((e) => alive && (error = errorText(e)))
    return () => (alive = false)
  })

  const view = $derived.by(() => {
    if (!item) return null
    switch (item.kind) {
      case 'track':
        return { ref: item.track.ref, title: item.track.title, sub: item.track.artist, cover: item.track.cover_url, label: t('Трек'), round: false }
      case 'album':
        return {
          ref: item.album.ref,
          title: item.album.title,
          sub: `${item.album.artist}${item.album.year ? ` · ${item.album.year}` : ''}`,
          cover: item.album.cover_url,
          label: t('Альбом'),
          round: false,
        }
      case 'artist':
        return { ref: item.artist.ref, title: item.artist.name, sub: t('Исполнитель'), cover: item.artist.avatar_url, label: t('Артист'), round: true }
      case 'playlist':
        return {
          ref: item.playlist.ref,
          title: item.playlist.title,
          sub: `${item.playlist.owner}${item.playlist.track_count ? ` · ${tracksText(item.playlist.track_count)}` : ''}`,
          cover: item.playlist.cover_url,
          label: t('Плейлист'),
          round: false,
        }
      case 'import':
        return {
          ref: item.head.source,
          title: item.head.title,
          sub: `${item.head.owner ? `${item.head.owner} · ` : ''}${tracksText(item.head.total)}`,
          cover: item.head.cover_url,
          label: item.head.album ? t('Альбом') : t('Плейлист'),
          round: false,
        }
    }
  })
  /** Значок источника: сервис по ref, у Apple Music — из шапки импорта. */
  const service = $derived<ImportService>(item?.kind === 'import' ? item.head.service : (serviceOf(view?.ref) ?? 'ym'))
  /** Плейлист и альбом можно перенести с подбором пар (экран импорта). */
  const canMatch = $derived(item?.kind === 'playlist' || item?.kind === 'album' || item?.kind === 'import')

  function importWithMatch() {
    if (!view) return
    openImport(item?.kind === 'import' ? url.trim() : view.ref)
  }

  const added = $derived(item?.kind === 'playlist' ? imported : !!view && library.isLiked(view.ref))
  const addLabel = $derived(item?.kind === 'artist' ? (added ? t('Вы подписаны') : t('Подписаться')) : added ? t('В медиатеке') : t('В медиатеку'))

  async function add() {
    if (!item || busy || item.kind === 'import') return
    busy = true
    try {
      if (item.kind === 'playlist') {
        const p = await api.importPlaylist(item.playlist.ref)
        imported = true
        await library.refreshPlaylists()
        toast.show(t('Плейлист «{name}» теперь в медиатеке', { name: p.name }))
      } else {
        const it = item.kind === 'track' ? item.track : item.kind === 'album' ? item.album : item.artist
        await library.toggleLike(it)
        if (library.isLiked(it.ref)) toast.show(item.kind === 'artist' ? t('Подписка оформлена') : t('Добавлено в медиатеку'))
      }
    } catch (e) {
      toast.show(errorText(e))
    } finally {
      busy = false
    }
  }

  function open() {
    if (!item) return
    if (item.kind === 'import') return importWithMatch()
    if (item.kind === 'track') void player.playList([item.track], 0, 'search', item.track.title)
    else openRef(view!.ref)
  }
</script>

{#if error}
  <EmptyState icon="link" title={t('Не открылось')} text={error} />
{:else if !view}
  <div class="card skel-card" aria-label={t('Открываю ссылку…')}>
    <div class="skel cov"></div>
    <div class="lines"><div class="skel l1"></div><div class="skel l2"></div></div>
  </div>
{:else}
  <div class="card">
    <button class="cov-btn" onclick={open} aria-label={item?.kind === 'track' ? t('Играть') : t('Открыть')}>
      <Cover url={view.cover} size={120} radius={view.round ? '50%' : 'var(--radius-l)'} source={view.ref} />
      <span class="hover"><Icon name={item?.kind === 'track' ? 'play' : 'chevronRight'} size={28} filled={item?.kind === 'track'} /></span>
    </button>
    <div class="info">
      <span class="kind"><SourceIcon {service} size={14} /> {view.label}</span>
      <b class="selectable">{view.title}</b>
      <small>{view.sub}</small>
      <div class="btns">
        {#if item?.kind === 'track'}
          {@const tr = item.track}
          <!-- трек: «Слушать», ❤ и «В плейлист» (решение владельца 2026-11-16) -->
          <button class="btn primary press" onclick={open}><Icon name="play" size={15} filled /> {t('Слушать')}</button>
          <button
            class="btn icon press"
            class:liked={added}
            aria-label={added ? t('Удалить из Любимых') : t('В Любимые')}
            title={added ? t('Удалить из Любимых') : t('В Любимые')}
            onclick={() => library.toggleLike(tr)}
          >
            <span class="ic" use:pulse={added}><Icon name="heart" size={17} filled={added} /></span>
          </button>
          <button class="btn press" onclick={(e) => trackMenu.openAt({ track: tr }, e.currentTarget, 'playlists')}>
            <Icon name="plus" size={16} /> {t('В плейлист')}
          </button>
        {:else if item?.kind === 'import'}
          <button class="btn primary press" onclick={importWithMatch}><Icon name="download" size={16} /> {t('Перенести с подбором')}</button>
        {:else}
        <button class="btn primary press" class:done={added} disabled={busy || (added && item?.kind === 'playlist')} onclick={add}>
          {#key added}
            <span class="lbl"><Icon name={added ? 'check' : item?.kind === 'artist' ? 'heart' : 'plus'} size={16} /> {addLabel}</span>
          {/key}
        </button>
        <button class="btn press" onclick={open}>{t('Открыть')}</button>
        {#if canMatch}
          <button class="btn press" title={t('Каждому треку — пара в подключённых сервисах')} onclick={importWithMatch}>{t('Перенести с подбором')}</button>
        {/if}
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .card {
    display: flex;
    align-items: center;
    gap: 22px;
    /* чипов «Все / Треки…» над ссылкой нет — карточка стоит под строкой поиска со своим воздухом */
    margin-top: 22px;
    padding: 18px;
    border-radius: var(--radius-xl);
    background: linear-gradient(135deg, var(--plate), transparent);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    animation: card-in var(--normal) var(--ease);
  }
  @keyframes card-in {
    from {
      opacity: 0;
      transform: translateY(8px) scale(0.98);
    }
  }
  .cov-btn {
    position: relative;
    flex: none;
    border-radius: var(--radius-l);
    box-shadow: 0 14px 34px rgba(0, 0, 0, 0.45);
    transition: transform var(--normal) var(--ease);
  }
  .cov-btn:hover {
    transform: scale(1.03);
  }
  .hover {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
    border-radius: inherit;
    background: rgba(0, 0, 0, 0.35);
    opacity: 0;
    transition: opacity var(--fast) var(--ease);
  }
  .cov-btn:hover .hover {
    opacity: 1;
  }
  .info {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }
  .kind {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }
  b {
    font-family: var(--font-display);
    font-size: calc(24px * var(--fs, 1));
    font-weight: 800;
    letter-spacing: -0.01em;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  small {
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-2);
  }
  .btns {
    display: flex;
    gap: 8px;
    margin-top: 10px;
  }
  .btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    height: 38px;
    padding: 0 16px;
    border-radius: 12px;
    background: var(--surface-3);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    transition:
      background var(--normal) var(--ease),
      color var(--normal) var(--ease);
  }
  .btn.primary {
    background: var(--text);
    color: var(--on-text);
  }
  .btn.primary.done {
    background: color-mix(in srgb, var(--online) 22%, var(--surface-2));
    color: var(--text);
  }
  /* ❤ — круглая кнопка; наведение — само сердечко чуть толще и больше (app.css) */
  .btn.icon {
    width: 38px;
    padding: 0;
    border-radius: 50%;
    color: var(--text-2);
  }
  .btn.icon:hover,
  .btn.icon.liked {
    color: var(--accent);
  }
  .ic {
    display: grid;
    place-items: center;
  }
  .btn:disabled {
    cursor: default;
  }
  .lbl {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    animation: card-in var(--normal) var(--ease);
  }
  .skel-card .cov {
    width: 120px;
    height: 120px;
    border-radius: var(--radius-l);
  }
  .lines {
    flex: 1;
    display: grid;
    gap: 10px;
  }
  .l1 {
    width: 60%;
    height: 20px;
    border-radius: 8px;
  }
  .l2 {
    width: 35%;
    height: 14px;
    border-radius: 8px;
  }
</style>
