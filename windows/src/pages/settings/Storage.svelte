<script lang="ts">
  // Система → Хранилище (pc/Screenshot_18): сколько занято (полоса по типам), очистка обложек и
  // текстов, сброс настроек треков, кэш треков (вкл., лимит, сколько занято, очистка — track_cache.rs).
  import { onMount } from 'svelte'
  import Group from '../../components/settings/Group.svelte'
  import CountUp from '../../components/CountUp.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import { searchHistory } from '../../lib/search-history.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { api, type StorageUsage } from '../../lib/api'
  import { t, tn } from '../../lib/i18n.svelte'
  import { toast } from '../../lib/toast.svelte'

  let usage = $state<StorageUsage | null>(null)
  let confirmPrefs = $state(false)

  const mb = (b: number) => b / 1_048_576
  const mbText = (b: number) =>
    b < 1_048_576 ? t('{n} КБ', { n: Math.max(1, Math.round(b / 1024)) }) : t('{n} МБ', { n: mb(b) < 10 ? mb(b).toFixed(1) : Math.round(mb(b)) })
  const total = $derived(usage ? usage.tracks_bytes + usage.covers_bytes + usage.lyrics_bytes + usage.db_bytes : 0)
  const part = (b: number) => (total ? Math.max(2, (b / total) * 100) : 0)

  let historyCount = $state(0)
  async function refresh() {
    try {
      usage = await api.storageUsage()
    } catch {
      usage = null
    }
    historyCount = await api.searchHistoryCount().catch(() => 0)
  }
  async function clearHistory() {
    await searchHistory.clear()
    toast.show(t('История поиска очищена'))
    await refresh()
  }
  onMount(refresh)

  async function clear(kind: 'covers' | 'tracks' | 'lyrics' | 'track_prefs' | 'all', done: string) {
    try {
      await api.clearStorage(kind)
      toast.show(done)
    } catch (e) {
      toast.show(String(e))
    }
    confirmPrefs = false
    await refresh()
  }
</script>

{#if usage}
  <div class="total">
    <b><CountUp value={mb(total)} format={(n) => n.toFixed(1)} /> MB</b>
    <span>{t('Занято')}</span>
  </div>
  <div class="bar" aria-hidden="true">
    {#if usage.tracks_bytes}<i class="tracks" style:width="{part(usage.tracks_bytes)}%"></i>{/if}
    <i class="covers" style:width="{part(usage.covers_bytes)}%"></i>
    <i class="lyrics" style:width="{part(usage.lyrics_bytes)}%"></i>
    <i class="db" style:width="{part(usage.db_bytes)}%"></i>
  </div>

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
  {/if}

  <Group title={t('Очистка кеша')}>
    {#snippet action()}
      <button class="link" onclick={() => clear('all', t('Кэш очищен'))}>{t('Очистить всё')}</button>
    {/snippet}
    <div class="row">
      <span class="dot tracks"></span>
      <span class="text"><b>{t('Треки')}</b><small>{usage.tracks} {tn(usage.tracks, ['трек', 'трека', 'треков'])}, {mbText(usage.tracks_bytes)}</small></span>
      <button class="link" disabled={!usage.tracks} onclick={() => clear('tracks', t('Кэш треков очищен'))}>{t('Очистить')}</button>
    </div>
    <div class="row">
      <span class="dot covers"></span>
      <span class="text"><b>{t('Обложки')}</b><small>{usage.covers} {tn(usage.covers, ['обложка', 'обложки', 'обложек'])}, {mbText(usage.covers_bytes)}</small></span>
      <button class="link" onclick={() => clear('covers', t('Обложки удалены'))}>{t('Очистить')}</button>
    </div>
    <div class="row">
      <span class="dot lyrics"></span>
      <span class="text"><b>{t('Тексты')}</b><small>{usage.lyrics} {tn(usage.lyrics, ['текст', 'текста', 'текстов'])}, {mbText(usage.lyrics_bytes)}</small></span>
      <button class="link" onclick={() => clear('lyrics', t('Тексты удалены'))}>{t('Очистить')}</button>
    </div>
  </Group>

  <Group title={t('Данные')}>
    <div class="row">
      <span class="text"><b>{t('История поиска')}</b><small>{historyCount} {tn(historyCount, ['запись', 'записи', 'записей'])} — {t('запросы и открытые из поиска результаты')}</small></span>
      <button class="link" disabled={!historyCount} onclick={clearHistory}>{t('Очистить')}</button>
    </div>
    <div class="row">
      <span class="text">
        <b>{t('Настройки треков')}</b>
        <small>{t('Скорость, эквалайзер и сдвиг текста, сохранённые для отдельных треков ({n})', { n: usage.track_prefs })}</small>
      </span>
      {#if confirmPrefs}
        <button class="link danger" onclick={() => clear('track_prefs', t('Настройки треков сброшены'))}>{t('Точно сбросить?')}</button>
      {:else}
        <button class="link" disabled={!usage.track_prefs} onclick={() => (confirmPrefs = true)}>{t('Сбросить')}</button>
      {/if}
    </div>
  </Group>
{:else}
  <div class="skel ph"></div>
{/if}

<style>
  .total {
    display: flex;
    align-items: baseline;
    gap: 8px;
  }
  .total b {
    font-family: var(--font-display);
    font-size: calc(30px * var(--fs, 1));
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
  .total span {
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-3);
  }
  .bar {
    display: flex;
    gap: 3px;
    height: 6px;
    margin: 10px 0 8px;
  }
  .bar i {
    border-radius: 3px;
    transition: width 0.6s var(--ease);
  }
  .covers {
    background: var(--text);
  }
  .lyrics {
    background: var(--text-2);
  }
  .db {
    background: var(--text-3);
  }
  .tracks {
    background: var(--text);
    opacity: 0.4;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 0;
  }
  .dot {
    width: 12px;
    height: 8px;
    border-radius: 2px;
    transform: skewX(-20deg);
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
  .link {
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-2);
    padding: 6px 4px;
    transition: color var(--fast) var(--ease);
  }
  .link:hover:not(:disabled) {
    color: var(--text);
  }
  .link:disabled {
    opacity: 0.4;
    cursor: default;
  }
  .link.danger {
    color: var(--danger);
    animation: tab-in var(--normal) var(--ease);
  }
  .ph {
    height: 120px;
    border-radius: 14px;
  }
</style>
