<script lang="ts">
  // Панель режима выбора треков (кнопка «Выбрать треки» в плейлисте / Любимых): стоит на месте строки
  // «Слушать · В очередь», пока выбираешь. Слева — выйти и «Выбрано: N», справа — действия над отмеченным.
  // Меню «в плейлист» открывается и закрывается только кликом (правило владельца).
  import Icon from './Icon.svelte'
  import type { Track } from '../lib/api'
  import { downloads } from '../lib/downloads.svelte'
  import { tracksText } from '../lib/format'
  import { t } from '../lib/i18n.svelte'
  import { library } from '../lib/library.svelte'
  import { trackMenu } from '../lib/menu.svelte'
  import { pop } from '../lib/motion'
  import { toast } from '../lib/toast.svelte'
  import { router } from '../app/router.svelte'
  import { player } from '../player/player.svelte'

  interface Props {
    /** Отмеченные треки в порядке списка на экране. */
    tracks: Track[]
    /** Сколько треков в списке сейчас (с учётом поиска): «Выбрать все» / «Снять выбор». */
    total: number
    title: string
    /** `favorites` — «Удалить из Любимых», `playlist` — «Убрать из плейлиста», `null` — убирать нечего (альбом, сервис, файлы). */
    removable: 'favorites' | 'playlist' | null
    /** Плейлист, в который «нельзя добавить сюда же» — тот, из которого выбирают. */
    fromPlaylist?: string
    /** «Найти дубли» — по Любимым и своим плейлистам: параметр экрана дублей. */
    dupesId?: string
    canLike?: boolean
    canDownload?: boolean
    onall: () => void
    onnone: () => void
    onclose: () => void
    onremove: () => void | Promise<void>
  }

  let { tracks, total, title, removable, fromPlaylist, dupesId, canLike = true, canDownload = true, onall, onnone, onclose, onremove }: Props = $props()

  const n = $derived(tracks.length)
  const all = $derived(n > 0 && n >= total)
  const playlists = $derived(library.playlists.filter((p) => p.id !== fromPlaylist))
  let picker = $state(false)
  let newName = $state('')
  let sure = $state(false)
  let wrap: HTMLElement | undefined = $state()

  $effect(() => {
    void library.load()
  })
  // выбор опустел — подтверждение и список плейлистов закрываются
  $effect(() => {
    if (!n) sure = picker = false
  })

  function onPointerDown(e: PointerEvent) {
    if (picker && wrap && !wrap.contains(e.target as Node)) picker = false
  }

  function onKey(e: KeyboardEvent) {
    if (trackMenu.target) return
    const field = (e.target as HTMLElement | null)?.closest('input, textarea')
    if (e.key === 'Escape') {
      if (picker) picker = false
      else if (!field) onclose()
    } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'a' && !field) {
      e.preventDefault()
      onall()
    }
  }

  const play = () => void player.playList(tracks, 0, null, title)

  function queue(next: boolean) {
    void player.addToQueue(tracks, next)
    toast.show(next ? t('Треки будут играть следующими') : t('Треки добавлены в очередь'))
  }

  async function like() {
    const k = await library.likeAll(tracks)
    toast.show(k ? t('{tracks} — в Любимых', { tracks: tracksText(k) }) : t('Все треки уже в Любимых'))
  }

  async function addTo(p: (typeof playlists)[number]) {
    picker = false
    await library.addToPlaylist(p, tracks)
  }

  async function createWith() {
    const name = newName.trim()
    if (!name) return
    picker = false
    newName = ''
    await library.createPlaylist(name, tracks)
  }

  async function remove() {
    if (!sure) {
      sure = true
      return
    }
    sure = false
    await onremove()
  }
</script>

<svelte:window onpointerdown={onPointerDown} onkeydown={onKey} />

<div class="sel" in:pop={{ y: -4 }}>
  <button class="round" aria-label={t('Выйти из выбора')} title={t('Выйти из выбора')} onclick={onclose}><Icon name="x" size={16} /></button>
  <span class="count" aria-live="polite">{t('Выбрано: {tracks}', { tracks: tracksText(n) })}</span>
  <button class="text" onclick={all ? onnone : onall}>{all ? t('Снять выбор') : t('Выбрать все')}</button>

  <span class="spacer"></span>

  <button class="tool plain" aria-label={t('Слушать')} title={t('Слушать')} disabled={!n} onclick={play}><Icon name="play" size={16} filled /></button>
  <button class="tool plain" aria-label={t('Следующими')} title={t('Следующими')} disabled={!n} onclick={() => queue(true)}><Icon name="playNext" size={16} /></button>
  <button class="tool plain" aria-label={t('В очередь')} title={t('В очередь')} disabled={!n} onclick={() => queue(false)}><Icon name="queue" size={16} /></button>

  <span class="sep" aria-hidden="true"></span>

  <span class="wrap" bind:this={wrap}>
    <button class="tool plain" class:on={picker} aria-label={t('Добавить в плейлист')} title={t('Добавить в плейлист')} aria-expanded={picker} disabled={!n} onclick={() => (picker = !picker)}>
      <Icon name="playlistAdd" size={16} />
    </button>
    {#if picker}
      <div class="menu" role="menu" in:pop={{ y: -6 }} out:pop={{ y: -6 }}>
        <form class="new" onsubmit={(e) => (e.preventDefault(), createWith())}>
          <!-- svelte-ignore a11y_autofocus -->
          <input placeholder={t('Новый плейлист…')} bind:value={newName} autofocus spellcheck="false" />
          <button type="submit" aria-label={t('Создать')} title={t('Создать')} disabled={!newName.trim()}><Icon name="plus" size={16} /></button>
        </form>
        <div class="lists">
          {#each playlists as p (p.id)}
            <button class="item" role="menuitem" onclick={() => addTo(p)}><Icon name="music" size={17} /><span>{p.name}</span></button>
          {:else}
            <p class="none">{t('Своих плейлистов пока нет')}</p>
          {/each}
        </div>
      </div>
    {/if}
  </span>
  {#if canLike}
    <button class="tool plain" aria-label={t('В Любимые')} title={t('В Любимые')} disabled={!n} onclick={like}><Icon name="heart" size={16} /></button>
  {/if}
  {#if canDownload}
    <button class="tool plain" aria-label={t('Скачать')} title={t('Скачать')} disabled={!n} onclick={() => downloads.download(tracks)}><Icon name="cloudDown" size={16} /></button>
  {/if}
  {#if dupesId}
    <!-- «Найти дубли» ищет по всему списку, а не по отмеченному — отдельная кнопка, не пункт над выбором -->
    <button class="tool plain" aria-label={t('Найти дубли')} title={t('Найти дубли')} onclick={() => router.go('dupes', dupesId)}><Icon name="stack" size={16} /></button>
  {/if}
  {#if removable}
    <button class="tool plain danger" class:sure aria-label={removable === 'favorites' ? t('Удалить из Любимых') : t('Убрать из плейлиста')} title={removable === 'favorites' ? t('Удалить из Любимых') : t('Убрать из плейлиста')} disabled={!n} onclick={remove} onblur={() => (sure = false)}>
      <Icon name="trash" size={16} />{#if sure} {t('Удалить?')}{/if}
    </button>
  {/if}
</div>

<style>
  .sel {
    display: flex;
    flex: 1;
    align-items: center;
    gap: var(--sp-2);
    min-width: 0;
  }
  .round {
    display: grid;
    place-items: center;
    flex: none;
    width: var(--ctl-s);
    height: var(--ctl-s);
    border-radius: 50%;
    border: 1px solid var(--border-strong);
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .round:hover {
    background: var(--hover);
    color: var(--text);
  }
  .round:active {
    transform: scale(0.92);
  }
  .count {
    padding: 0 var(--sp-3);
    height: var(--ctl-s);
    display: inline-flex;
    align-items: center;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    font-size: var(--fs-2);
    font-weight: 600;
    white-space: nowrap;
    font-variant-numeric: tabular-nums;
  }
  .text {
    padding: 0 var(--sp-2);
    height: var(--ctl-s);
    border-radius: 999px;
    color: var(--text-2);
    font-size: var(--fs-2);
    font-weight: 600;
    white-space: nowrap;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .text:hover {
    background: var(--hover);
    color: var(--text);
  }
  .spacer {
    flex: 1;
  }
  .sep {
    width: 1px;
    height: var(--ic-m);
    margin: 0 var(--sp-1);
    background: var(--border-strong);
  }
  .sel :global(.tool:disabled) {
    opacity: 0.4;
    cursor: default;
  }
  .sel :global(.tool.on) {
    color: var(--text);
    background: var(--hover);
  }
  .sel :global(.tool.danger) {
    color: var(--danger);
  }
  .sel :global(.tool.sure) {
    background: color-mix(in srgb, var(--danger) 14%, transparent);
  }
  .wrap {
    position: relative;
  }
  .menu {
    position: absolute;
    z-index: 58; /* как у меню трека: выше всплывашки обновления, ниже тостов */
    top: calc(100% + var(--sp-2));
    right: 0;
    width: 280px;
    padding: 6px;
    border-radius: var(--radius-l);
    background: var(--surface-1);
    border: 1px solid var(--border-strong);
    box-shadow: 0 16px 40px rgba(0, 0, 0, 0.55);
    transform-origin: top right;
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
  .none {
    margin: 6px 10px 8px;
    font-size: var(--fs-meta);
    color: var(--text-3);
  }
</style>
