<script lang="ts">
  // Меню трека по pc/Screenshot_29. Открывается и закрывается только кликом (правило владельца):
  // клик мимо, Esc или выбор пункта. «Добавить в плейлист ›» — тоже по клику, список внутри меню.
  import Cover from '../components/Cover.svelte'
  import Icon from '../components/Icon.svelte'
  import SourceIcon from '../components/SourceIcon.svelte'
  import { ICONS } from '../lib/service-icons'
  import type { IconName } from '../components/icons'
  import { trackMenu } from '../lib/menu.svelte'
  import { library } from '../lib/library.svelte'
  import { toast } from '../lib/toast.svelte'
  import { player } from '../player/player.svelte'
  import { openRef, router } from './router.svelte'
  import { search } from './search.svelte'
  import { byId, serviceOf } from '../lib/services'
  import { isMissingLocal, servicesQuery } from '../lib/local'
  import { pop } from '../lib/motion'
  import { wave } from '../player/my-wave.svelte'
  import { waveWhyText } from '../lib/wave-why'
  import { t, lang } from '../lib/i18n.svelte'
  import { downloads } from '../lib/downloads.svelte'
  import { isLocalRef } from '../lib/services'
  import ArtistTasteSeg from '../components/ArtistTasteSeg.svelte'
  import { mainArtist } from '../lib/artist-prefs-core'
  import { api, type Track } from '../lib/api'
  import { offline } from '../lib/offline.svelte'
  import { canShare, shareLink } from '../lib/share'
  import { isChosen, sourceChoices, sourceName, sourceValue, type SourceChoice } from '../lib/track-source'
  import type { TrackSources } from '../lib/api'

  const W = 280
  let el: HTMLElement | undefined = $state()
  let view = $state<'main' | 'playlists' | 'share' | 'source'>('main')
  /** «Играть из»: где трек есть (null — ещё ищем) и для какого трека. */
  let sources = $state<TrackSources | null>(null)
  let sourcesFor = $state<string | null>(null)
  let newName = $state('')
  let pos = $state({ left: 0, top: 0 })

  const LOCALES = { ru: 'ru-RU', en: 'en-GB', uk: 'uk-UA', es: 'es-ES', de: 'de-DE', pl: 'pl-PL' } as const
  const target = $derived(trackMenu.target)
  const liked = $derived(target ? library.isLiked(target.track.ref) : false)
  const added = $derived(
    target?.addedAt ? new Date(target.addedAt).toLocaleDateString(LOCALES[lang()], { day: 'numeric', month: 'long', year: 'numeric' }) : null,
  )
  /** «Волна по треку» — только у сервисов с похожими (у файла с компьютера похожих нет). */
  const canWave = $derived(target ? !!byId(serviceOf(target.track.ref))?.caps.similar : false)
  /** «Почему этот трек» — у треков Sonar Mix: откуда он пришёл (не зависит от тумблера строки в плеере). */
  const why = $derived(target ? waveWhyText(target.track.why) : '')
  /** Сервис трека — знак в шапке (у файла с компьютера знака нет). */
  const svc = $derived(target ? serviceOf(target.track.ref) : null)
  /** Главный артист — для «Чаще · Реже · Никогда». */
  const main = $derived(target ? mainArtist(target.track) : { key: '', name: '' })
  const playlists = $derived(library.playlists.filter((p) => p.id !== target?.playlistId))
  /** «Играть из» — у треков сервисов (не файлов с компьютера) и не в офлайне: там ничего не найти. */
  const canPickSource = $derived(!!target && !isLocalRef(target.track.ref) && !offline.on)
  const choices = $derived(target && sourcesFor === target.track.ref ? sourceChoices(target.track.ref, sources) : [])
  /** Скачивание (`docs/OFFLINE.md` §8): файлу с компьютера не нужно — он и так на диске. */
  const dl = $derived(target && !isLocalRef(target.track.ref) ? downloads.stateOf(target.track.ref) : undefined)

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
      if (view !== 'main') view = 'main'
      else trackMenu.close()
    }
  }

  function run(fn: () => unknown) {
    fn()
    trackMenu.close()
  }

  /** «Поделиться» — ссылка на страницу трека на сайте: сначала ищем трек в других сервисах (≤ 4 с),
   *  не нашли или нет сети — делимся тем, что знаем. */
  async function shareTrack(track: Track) {
    toast.show(t('Готовим ссылку…'), 5000)
    const twins = offline.on ? null : await api.shareTwins(track.ref, track).catch(() => null)
    const link = shareLink(track, twins, lang())
    if (link) await copy(link, t('Ссылка на трек скопирована'))
  }

  async function copy(text: string, done: string) {
    try {
      await navigator.clipboard.writeText(text)
      toast.show(done)
    } catch {
      toast.show(t('Не получилось скопировать'))
    }
  }

  /** «Играть из ›»: варианты ищутся при открытии подменю (двойники в других сервисах — как у резерва). */
  async function openSources(track: Track) {
    view = 'source'
    if (sourcesFor === track.ref && sources) return
    sources = null
    sourcesFor = track.ref
    const found = await api.trackSources(track.ref, track).catch(() => ({ services: [], pinned: null }))
    if (sourcesFor === track.ref) sources = found
  }

  async function pickSource(track: Track, choice: SourceChoice) {
    trackMenu.close()
    if (sources && isChosen(choice, sources.pinned)) return
    try {
      await api.setTrackSource(track.ref, sourceValue(choice))
      if (sources) sources = { ...sources, pinned: sourceValue(choice) }
      toast.show(choice === 'auto' ? t('Трек снова играет как решит Sonar') : t('Играть из: {service}', { service: sourceName(choice) }))
      await player.sourceChanged(track.ref)
    } catch {
      toast.show(t('Не получилось сохранить выбор'))
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
      <Cover url={target.track.cover_url} size={52} />
      <div class="meta">
        <b>{target.track.title}</b>
        <span>{target.track.artist}</span>
        {#if added}<small>{t('Добавлен')} <b>{added}</b></small>{/if}
      </div>
      {#if svc && ICONS[svc]}<span class="svc"><SourceIcon service={svc} size={20} plain /></span>{/if}
    </div>
    {#if why && view === 'main'}
      <div class="why" role="note" aria-label={t('Почему этот трек')}>
        <Icon name="info" size={15} />
        <span><small>{t('Почему этот трек')}</small>{why}</span>
      </div>
    {/if}

    {#if view === 'main'}
      {@render item('playNext', t('Следующим'), () => player.addToQueue([target.track], true))}
      {#if target.queueAt !== undefined}
        <!-- трек уже в «Далее» — его можно убрать, а не добавить ещё раз -->
        {@const at = target.queueAt}
        {@render item('trash', t('Убрать из очереди'), () => player.removeUpcoming(at))}
      {:else}
        {@render item('queue', t('В очередь'), () => player.addToQueue([target.track], false))}
      {/if}
      {#if canWave}
        {@render item('bolt', t('Sonar Mix по треку'), () => wave.start(target.track))}
      {/if}
      {#if isMissingLocal(target.track)}
        {@const query = servicesQuery(target.track)}
        {@render item('search', t('Найти в сервисах'), () => ((search.query = query), router.go('search')))}
      {/if}
      <hr />
      {@render item('heart', liked ? t('Удалить из Любимых') : t('В Любимые'), () => library.toggleLike(target.track), liked)}
      {@render item('dislike', wave.isDisliked(target.track.ref) ? t('Убрать из «Не нравится»') : t('Не нравится'), () => wave.dislike(target.track), wave.isDisliked(target.track.ref))}
      {#if main.key}
        <!-- вкус по артисту (у совместного трека — по главному): Чаще · Реже · Никогда -->
        <div class="taste">
          <small>{t('{name} в Sonar Mix', { name: main.name })}</small>
          <ArtistTasteSeg name={main.name} compact onpick={() => trackMenu.close()} />
        </div>
      {/if}
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
      {#if canPickSource}
        {@const tr = target.track}
        <button class="item" role="menuitem" onclick={() => openSources(tr)}>
          <Icon name="headphones" size={17} />
          <span>{t('Играть из')}</span>
          <Icon name="chevronRight" size={15} />
        </button>
      {/if}
      {#if dl === 'done'}
        {@render item('trash', t('Удалить из скачанного'), () => downloads.remove([target.track.ref]))}
      {:else if dl === 'queued' || dl === 'active'}
        {@render item('x', t('Отменить скачивание'), () => downloads.cancel([target.track.ref]))}
      {:else if dl === 'unsupported'}
        <div class="item off" role="menuitem" aria-disabled="true">
          <Icon name="cloudDown" size={17} />
          <span>{t('Этот трек нельзя скачать')}</span>
        </div>
      {:else if dl !== undefined}
        {@render item('cloudDown', t('Скачать'), () => downloads.download([target.track]))}
      {/if}
      <hr />
      {#each target.track.artists.slice(0, 3) as a (a.ref)}
        {@render item('user', target.track.artists.length > 1 ? a.name : t('Перейти к исполнителю'), () => openRef(a.ref))}
      {/each}
      {#if target.track.album?.ref}
        <!-- у файла с компьютера альбом без ref — страницы нет -->
        {@const album = target.track.album}
        {@render item('disc', t('Перейти к альбому'), () => openRef(album.ref))}
      {/if}
      <hr />
      {@render item('copy', t('Копировать название'), () => copy(`${target.track.artist} — ${target.track.title}`, t('Название скопировано')))}
      {#if canShare(target.track)}
        {@const tr = target.track}
        <button class="item" role="menuitem" onclick={() => (view = 'share')}>
          <Icon name="share" size={17} />
          <span>{t('Поделиться')}</span>
          <Icon name="chevronRight" size={15} />
        </button>
      {/if}
      {#if target.track.url}
        {@const url = target.track.url}
        {@const name = byId(serviceOf(target.track.ref))?.name ?? ''}
        {@render item('link', t('Ссылка на {service}', { service: t(name) }), () => copy(url, t('Ссылка скопирована')))}
      {/if}
    {:else if view === 'source'}
      {@const tr = target.track}
      <button class="item back" onclick={() => (view = 'main')}>
        <Icon name="chevronLeft" size={17} />
        <span>{t('Играть из')}</span>
      </button>
      {#if sourcesFor !== tr.ref || !sources}
        <p class="none">{t('Ищем трек в других сервисах…')}</p>
      {:else if choices.length === 0}
        <p class="none">{t('В других сервисах этот трек не нашёлся')}</p>
      {:else}
        {#each choices as c (c)}
          {@const on = isChosen(c, sources.pinned)}
          <button class="item" role="menuitemradio" aria-checked={on} onclick={() => pickSource(tr, c)}>
            {#if c === 'auto'}
              <Icon name="waveform" size={17} />
            {:else}
              <span class="src"><SourceIcon service={c} size={17} plain /></span>
            {/if}
            <span>{sourceName(c)}{#if c === 'auto'}<small class="hint">{t('как решит Sonar')}</small>{/if}</span>
            {#if on}<Icon name="check" size={15} />{/if}
          </button>
        {/each}
      {/if}
    {:else if view === 'share'}
      {@const tr = target.track}
      <button class="item back" onclick={() => (view = 'main')}>
        <Icon name="chevronLeft" size={17} />
        <span>{t('Поделиться')}</span>
      </button>
      {@render item('link', t('Ссылкой'), () => shareTrack(tr))}
      <!-- личные сообщения — через сервер (docs/DM.md): до него пункт неактивен, как «Пригласить друга» -->
      <button class="item" role="menuitem" disabled title={t('Появится вместе с сервером Sonar')}>
        <Icon name="user" size={17} />
        <span>{t('Отправить другу')}</span>
      </button>
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
    padding: 8px 8px 12px;
  }
  .svc {
    display: grid;
    flex: none;
    align-self: flex-start;
    margin-left: auto;
    padding-left: 4px;
  }
  .why {
    display: flex;
    gap: 10px;
    align-items: flex-start;
    margin: 2px 4px 6px;
    padding: 8px 10px;
    border-radius: var(--radius-s);
    background: color-mix(in srgb, var(--accent) 10%, transparent);
    color: var(--text-2);
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.4;
  }
  .why :global(svg) {
    flex: none;
    margin-top: 1px;
    color: var(--accent);
  }
  .why span {
    display: grid;
    gap: 1px;
    min-width: 0;
  }
  .why small {
    color: var(--text-3);
    font-size: calc(11px * var(--fs, 1));
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
  .taste {
    display: grid;
    gap: 6px;
    padding: 6px 10px 8px;
  }
  .taste small {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .taste :global(.seg) {
    display: flex;
  }
  .taste :global(.seg button) {
    flex: 1;
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
  .item:hover:not(:disabled) {
    background: var(--hover);
    color: var(--text);
  }
  .item:disabled {
    opacity: 0.45;
    cursor: default;
  }
  .item span.src {
    flex: none;
    display: grid;
    place-items: center;
    width: 17px;
  }
  .item .hint {
    margin-left: 8px;
    color: var(--text-3);
    font-size: var(--fs-meta);
  }
  .item[aria-checked='true'] {
    color: var(--text);
  }
  .item.off {
    opacity: 0.5;
    cursor: default;
  }
  .item.off:hover {
    background: none;
    color: var(--text-2);
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
