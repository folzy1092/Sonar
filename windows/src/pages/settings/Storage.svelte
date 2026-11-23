<script lang="ts">
  // Приложение → Хранилище (SETTINGS_NEXT «Хранилище»): сверху карточка — кольцо с общим размером и
  // «Что очистить?» (галочки, размер, полоска доли), внизу кнопка «Очистить N MB» на сумму отмеченного.
  // Ниже — кеширование треков отдельной карточкой, папки с музыкой и «Данные» (история поиска,
  // настройки треков). Размеры — storage_usage, очистка — clear_storage (track_cache.rs, commands.rs).
  import { onDestroy, onMount } from 'svelte'
  import Group from '../../components/settings/Group.svelte'
  import Icon from '../../components/Icon.svelte'
  import CountUp from '../../components/CountUp.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import MusicFolders from '../../components/settings/MusicFolders.svelte'
  import { searchHistory } from '../../lib/search-history.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { api, onOfflineIndexChanged, type StorageUsage } from '../../lib/api'
  import { blendAnalysis } from '../../player/blend/analyze.svelte'
  import { downloads } from '../../lib/downloads.svelte'
  import { offline } from '../../lib/offline.svelte'
  import { slide } from '../../lib/motion'
  import { t, tn } from '../../lib/i18n.svelte'
  import { toast } from '../../lib/toast.svelte'

  type Kind = 'tracks' | 'covers' | 'lyrics'
  const KINDS: Kind[] = ['tracks', 'covers', 'lyrics']
  /** Длина окружности кольца (r = 52) — от неё считаются дуги долей. */
  const RING = 2 * Math.PI * 52
  const RING_GAP = 4
  /** Лимиты автоскачивания Любимых, ГБ. */
  const LIKED_LIMITS_GB = [2, 5, 10, 20, 50]

  let usage = $state<StorageUsage | null>(null)
  let confirmPrefs = $state(false)
  let confirmBlend = $state(false)
  let busy = $state(false)
  // Кэш треков — то, что играет без сети, поэтому по умолчанию не отмечен.
  let picked = $state<Record<Kind, boolean>>({ tracks: false, covers: true, lyrics: true })
  let historyCount = $state(0)

  const mb = (b: number) => b / 1_048_576
  const mbText = (b: number) =>
    b < 1_048_576 ? t('{n} КБ', { n: Math.max(1, Math.round(b / 1024)) }) : t('{n} МБ', { n: mb(b) < 10 ? mb(b).toFixed(1) : Math.round(mb(b)) })
  const bytes = (u: StorageUsage, k: Kind) => (k === 'tracks' ? u.tracks_bytes : k === 'covers' ? u.covers_bytes : u.lyrics_bytes)
  const count = (u: StorageUsage, k: Kind) => (k === 'tracks' ? u.tracks : k === 'covers' ? u.covers : u.lyrics)
  const total = $derived(usage ? usage.tracks_bytes + usage.covers_bytes + usage.lyrics_bytes + usage.downloaded_bytes + usage.db_bytes : 0)
  const share = (b: number) => (total ? b / total : 0)
  const selected = $derived(usage ? KINDS.filter((k) => picked[k]).reduce((sum, k) => sum + bytes(usage!, k), 0) : 0)

  const label = (k: Kind) => (k === 'tracks' ? t('Треки') : k === 'covers' ? t('Обложки') : t('Тексты'))
  const units = (k: Kind, n: number) =>
    k === 'tracks' ? tn(n, ['трек', 'трека', 'треков']) : k === 'covers' ? tn(n, ['обложка', 'обложки', 'обложек']) : tn(n, ['текст', 'текста', 'текстов'])

  /** Дуги кольца: доли по порядку, между ними зазор; самая малая доля всё равно видна. */
  const arcs = $derived.by(() => {
    if (!usage || !total) return []
    const parts = [
      ...KINDS.map((k) => ({ id: k as string, b: bytes(usage!, k) })),
      { id: 'downloaded', b: usage.downloaded_bytes },
      { id: 'db', b: usage.db_bytes },
    ].filter((p) => p.b > 0)
    let offset = 0
    return parts.map((p) => {
      const len = Math.max(2, share(p.b) * RING - RING_GAP)
      const arc = { id: p.id, len, offset }
      offset += len + RING_GAP
      return arc
    })
  })

  async function refresh() {
    try {
      usage = await api.storageUsage()
    } catch {
      usage = null
    }
    historyCount = await api.searchHistoryCount().catch(() => 0)
  }
  onMount(refresh)
  // скачалось или удалилось — размер «Скачанного» и кольцо обновляются сами
  onDestroy(onOfflineIndexChanged(() => void refresh()))

  /** Очередь скачивания видна, пока есть что качать или что не скачалось. */
  const queueShown = $derived(downloads.queue.left > 0 || downloads.failed > 0)
  const queueText = $derived.by(() => {
    const left = downloads.queue.left
    if (!left) return t('Не скачалось: {n}', { n: downloads.failed })
    const rest = t('осталось {n}', { n: left })
    if (offline.on) return `${t('Офлайн-режим — продолжится, когда он выключится')} · ${rest}`
    if (downloads.queue.paused) return `${t('Пауза')} · ${rest}`
    return `${t('Скачивается')} · ${rest}`
  })

  async function toggleAutoLiked(on: boolean) {
    if (!on) settings.set('storage.auto_download_liked', false)
    else if (await downloads.enableLiked()) await refresh()
  }

  function setLikedLimit(gb: number) {
    settings.set('storage.auto_download_limit_gb', gb)
    void downloads.fillLiked()
  }

  async function clearDownloads() {
    if (!usage || !(await downloads.clear(usage.downloaded, usage.downloaded_bytes))) return
    await refresh()
  }

  async function clearPicked() {
    if (busy || !selected) return
    busy = true
    const freed = mbText(selected)
    try {
      for (const k of KINDS.filter((k) => picked[k])) await api.clearStorage(k)
      toast.show(t('Освобождено {n}', { n: freed }))
    } catch (e) {
      toast.show(String(e))
    }
    busy = false
    await refresh()
  }

  async function clearPrefs() {
    try {
      await api.clearStorage('track_prefs')
      toast.show(t('Настройки треков сброшены'))
    } catch (e) {
      toast.show(String(e))
    }
    confirmPrefs = false
    await refresh()
  }

  async function clearBlend() {
    try {
      await api.clearStorage('blend')
      blendAnalysis.reset()
      toast.show(t('Анализ для сведения очищен'))
    } catch (e) {
      toast.show(String(e))
    }
    confirmBlend = false
    await refresh()
  }

  async function clearHistory() {
    await searchHistory.clear()
    toast.show(t('История поиска очищена'))
    await refresh()
  }
</script>

{#if usage}
  <section class="card summary">
    <div class="ring">
      <svg viewBox="0 0 120 120" aria-hidden="true">
        <circle class="track" cx="60" cy="60" r="52" />
        {#each arcs as a (a.id)}
          <circle
            class="arc {a.id}"
            cx="60"
            cy="60"
            r="52"
            stroke-dasharray="{a.len} {RING}"
            stroke-dashoffset={-a.offset}
          />
        {/each}
      </svg>
      <div class="sum">
        <b><CountUp value={mb(total)} format={(n) => n.toFixed(1)} /></b>
        <span>MB · {t('Занято')}</span>
      </div>
    </div>

    <div class="pick">
      <b class="ask">{t('Что очистить?')}</b>
      {#each KINDS as k (k)}
        {@const b = bytes(usage, k)}
        <label class="item" class:on={picked[k]}>
          <input type="checkbox" checked={picked[k]} disabled={!b} onchange={(e) => (picked = { ...picked, [k]: e.currentTarget.checked })} />
          <span class="box" aria-hidden="true"></span>
          <span class="name">
            <span class="line"><span class="dot {k}"></span>{label(k)}<small>{count(usage, k)} {units(k, count(usage, k))}</small></span>
            <span class="share"><i class={k} style:width="{Math.max(b ? 3 : 0, share(b) * 100)}%"></i></span>
          </span>
          <span class="size">{mbText(b)}</span>
        </label>
      {/each}
    </div>

    <button class="clear" disabled={!selected || busy} onclick={clearPicked}>
      {selected ? t('Очистить {n}', { n: mbText(selected) }) : t('Нечего очищать')}
    </button>
  </section>

  <section class="card">
    <Switch
      title={t('Кеширование треков')}
      hint={t('Прослушанные треки сохраняются на диск и в следующий раз играют без сети')}
      on={settings.get('storage.cache_tracks')}
      onchange={(v) => settings.set('storage.cache_tracks', v)}
    />
    {#if settings.get('storage.cache_tracks')}
      <Choice
        title={t('Размер кэша треков')}
        hint={t('Сверх лимита удаляются давно не игравшие')}
        value={settings.get('storage.cache_limit_mb')}
        options={[512, 1024, 2048, 5120, 10240].map((n) => ({ id: n, label: n < 1024 ? t('{n} МБ', { n }) : t('{n} ГБ', { n: n / 1024 }) }))}
        onchange={(v) => settings.set('storage.cache_limit_mb', v)}
      />
      <Switch
        title={t('Sonar Mix офлайн')}
        hint={t('Следующие 15 треков Sonar Mix заранее скачиваются в кэш — микс доиграет и без сети')}
        on={settings.get('storage.wave_offline')}
        onchange={(v) => settings.set('storage.wave_offline', v)}
      />
    {/if}
  </section>

  <section class="card dl">
    <div class="row">
      <span class="text">
        <b>{t('Скачанное')}</b>
        <small>
          {usage.downloaded} {tn(usage.downloaded, ['трек', 'трека', 'треков'])} · {mbText(usage.downloaded_bytes)} — {t('играет без сети, кэш его не вытесняет')}
        </small>
      </span>
      <button class="pill" disabled={!usage.downloaded} onclick={downloads.reveal}>{t('Показать в папке')}</button>
      <button class="pill" disabled={!usage.downloaded} onclick={clearDownloads}>{t('Удалить все')}</button>
    </div>
    {#if queueShown}
      <div class="queue" transition:slide>
        <div class="qline">
          <small>{queueText}</small>
          {#if downloads.failed}
            <button class="pill" onclick={downloads.retry}>{t('Повторить')}</button>
          {/if}
          {#if downloads.queue.left}
            <button
              class="pill icon"
              aria-label={downloads.queue.paused ? t('Продолжить') : t('Пауза')}
              title={downloads.queue.paused ? t('Продолжить') : t('Пауза')}
              onclick={() => downloads.pause(!downloads.queue.paused)}
            >
              <Icon name={downloads.queue.paused ? 'play' : 'pause'} size={14} />
            </button>
            <button class="pill icon" aria-label={t('Отменить скачивание')} title={t('Отменить скачивание')} onclick={downloads.cancelAll}>
              <Icon name="x" size={14} />
            </button>
          {/if}
        </div>
        <div class="bar" class:idle={downloads.queue.paused || offline.on}><i style:width="{downloads.share * 100}%"></i></div>
      </div>
    {/if}
  </section>

  <section class="card">
    <Switch
      title={t('Скачивать Любимые')}
      hint={t('Лайкнутые треки сами скачиваются на этот компьютер, пока не упрутся в лимит')}
      on={settings.get('storage.auto_download_liked')}
      onchange={toggleAutoLiked}
    />
    {#if settings.get('storage.auto_download_liked')}
      <div transition:slide>
        <Choice
          title={t('Лимит для Любимых')}
          hint={t('Сколько места на диске могут занять скачанные треки')}
          value={settings.get('storage.auto_download_limit_gb')}
          options={LIKED_LIMITS_GB.map((n) => ({ id: n, label: t('{n} ГБ', { n }) }))}
          onchange={setLikedLimit}
        />
        <small class="note">{t('Лимитную сеть Sonar на ПК не различает — качает по любой, в том числе через точку доступа телефона')}</small>
      </div>
    {/if}
  </section>

  <MusicFolders />

  <Group title={t('Данные')}>
    <div class="row">
      <span class="text"><b>{t('История поиска')}</b><small>{historyCount} {tn(historyCount, ['запись', 'записи', 'записей'])} — {t('запросы и открытые из поиска результаты')}</small></span>
      <button class="pill" disabled={!historyCount} onclick={clearHistory}>{t('Очистить')}</button>
    </div>
    <div class="row">
      <span class="text">
        <b>{t('Настройки треков')}</b>
        <small>{t('Скорость, эквалайзер и сдвиг текста, сохранённые для отдельных треков ({n})', { n: usage.track_prefs })}</small>
      </span>
      {#if confirmPrefs}
        <button class="pill danger" onclick={clearPrefs}>{t('Точно сбросить?')}</button>
      {:else}
        <button class="pill" disabled={!usage.track_prefs} onclick={() => (confirmPrefs = true)}>{t('Сбросить')}</button>
      {/if}
    </div>
    <div class="row">
      <span class="text">
        <b>{t('Анализ для сведения')}</b>
        <small>{usage.blend} {tn(usage.blend, ['трек', 'трека', 'треков'])} · {mbText(usage.blend_bytes)} — {t('доли, тональность и фразы; посчитается заново, когда понадобится')}</small>
      </span>
      {#if confirmBlend}
        <button class="pill danger" onclick={clearBlend}>{t('Точно очистить?')}</button>
      {:else}
        <button class="pill" disabled={!usage.blend} onclick={() => (confirmBlend = true)}>{t('Очистить')}</button>
      {/if}
    </div>
  </Group>
{:else}
  <div class="skel ph"></div>
{/if}

<style>
  .card {
    padding: 14px 16px;
    border-radius: var(--radius-xl, 18px);
    background: var(--plate);
    margin-bottom: 12px;
  }
  .summary {
    display: grid;
    grid-template-columns: 132px 1fr;
    gap: 14px 22px;
    align-items: center;
  }
  .ring {
    position: relative;
    width: 132px;
    height: 132px;
  }
  .ring svg {
    width: 100%;
    height: 100%;
    transform: rotate(-90deg);
  }
  circle {
    fill: none;
    stroke-width: 11;
  }
  .track {
    stroke: var(--hover);
  }
  .arc {
    stroke-linecap: round;
    transition:
      stroke-dasharray 0.7s var(--ease),
      stroke-dashoffset 0.7s var(--ease);
    animation: ring-in 0.8s var(--ease) both;
  }
  @keyframes ring-in {
    from {
      stroke-dasharray: 0 999;
    }
  }
  .sum {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 1px;
  }
  .sum b {
    font-family: var(--font-display);
    font-size: calc(24px * var(--fs, 1));
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    letter-spacing: -0.02em;
  }
  .sum span {
    font-size: calc(11px * var(--fs, 1));
    color: var(--text-3);
  }
  .pick {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }
  .ask {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
    margin-bottom: 4px;
  }
  .item {
    position: relative;
    display: grid;
    grid-template-columns: 18px 1fr auto;
    gap: 12px;
    align-items: center;
    padding: 7px 8px;
    margin: 0 -8px;
    border-radius: 10px;
    cursor: pointer;
    color: var(--text-3);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .item:hover {
    background: var(--hover);
  }
  .item.on {
    color: var(--text);
  }
  .item input {
    position: absolute;
    opacity: 0;
    pointer-events: none;
  }
  .box {
    width: 18px;
    height: 18px;
    border-radius: 6px;
    border: 1.5px solid var(--text-3);
    display: grid;
    place-items: center;
    transition:
      background var(--fast) var(--ease),
      border-color var(--fast) var(--ease);
  }
  .box::after {
    content: '';
    width: 8px;
    height: 4px;
    border: 2px solid var(--accent-ink);
    border-top: 0;
    border-right: 0;
    transform: translateY(-1px) rotate(-45deg) scale(0);
    transition: transform var(--fast) var(--ease);
  }
  .on .box {
    background: var(--accent);
    border-color: var(--accent);
  }
  .on .box::after {
    transform: translateY(-1px) rotate(-45deg) scale(1);
  }
  .item input:focus-visible + .box {
    outline: 2px solid var(--accent);
    outline-offset: 2px;
  }
  .item:has(input:disabled) {
    opacity: 0.45;
    cursor: default;
  }
  .name {
    display: flex;
    flex-direction: column;
    gap: 5px;
    min-width: 0;
  }
  .line {
    display: flex;
    align-items: baseline;
    gap: 8px;
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
  }
  .line small {
    font-size: calc(11px * var(--fs, 1));
    font-weight: 400;
    color: var(--text-3);
  }
  .share {
    height: 4px;
    border-radius: 2px;
    background: var(--hover);
    overflow: hidden;
  }
  .share i {
    display: block;
    height: 100%;
    border-radius: 2px;
    transition: width 0.6s var(--ease);
  }
  .size {
    font-size: calc(13px * var(--fs, 1));
    font-variant-numeric: tabular-nums;
  }
  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    align-self: center;
  }
  /* Доли — оттенки текста, кольцо и полоски одного цвета на тип. */
  .tracks {
    background: var(--accent);
    stroke: var(--accent);
  }
  .covers {
    background: var(--text);
    stroke: var(--text);
  }
  .lyrics {
    background: var(--text-2);
    stroke: var(--text-2);
  }
  .db {
    stroke: var(--text-3);
  }
  .downloaded {
    stroke: var(--accent);
    opacity: 0.45;
  }
  .dl .row {
    padding: 0;
  }
  .note {
    display: block;
    padding: 2px 0 4px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .queue {
    padding-top: 12px;
  }
  .qline {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-bottom: 8px;
  }
  .qline small {
    flex: 1;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  .pill.icon {
    display: grid;
    place-items: center;
    padding: 6px;
  }
  .bar {
    height: 4px;
    border-radius: 2px;
    background: var(--hover);
    overflow: hidden;
  }
  .bar i {
    display: block;
    height: 100%;
    border-radius: inherit;
    background: var(--accent);
    transition:
      width 0.5s var(--ease),
      opacity 0.3s var(--ease);
  }
  .bar.idle i {
    opacity: 0.4;
  }
  .clear {
    grid-column: 1 / -1;
    height: 42px;
    border-radius: 12px;
    background: var(--text);
    color: var(--bg, #000);
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    transition:
      opacity var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .clear:hover:not(:disabled) {
    opacity: 0.88;
  }
  .clear:active:not(:disabled) {
    transform: scale(0.985);
  }
  .clear:disabled {
    opacity: 0.35;
    cursor: default;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 0;
  }
  .text {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .text b {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  .text small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .pill {
    padding: 7px 14px;
    border-radius: 999px;
    background: var(--hover);
    font-size: calc(13px * var(--fs, 1));
    color: var(--text);
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .pill:hover:not(:disabled) {
    background: var(--surface-3);
  }
  .pill:active:not(:disabled) {
    transform: scale(0.96);
  }
  .pill:disabled {
    opacity: 0.4;
    cursor: default;
  }
  .pill.danger {
    color: var(--danger);
    animation: tab-in var(--normal) var(--ease);
  }
  .ph {
    height: 160px;
    border-radius: 18px;
  }
  /* ширина панели настроек, не окна (окно не уже 960) */
  @container (max-width: 440px) {
    .summary {
      grid-template-columns: 1fr;
      justify-items: center;
    }
    .pick {
      width: 100%;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .arc {
      animation: none;
    }
    .clear:active,
    .pill:active {
      transform: none;
    }
  }
</style>
