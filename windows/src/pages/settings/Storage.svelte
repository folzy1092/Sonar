<script lang="ts">
  // Система → Хранилище (pc/Screenshot_18): сколько занято (полоса по типам), очистка обложек и
  // текстов, сброс настроек треков. Аудио на диск не кэшируется — строки «Треки» нет.
  import { onMount } from 'svelte'
  import Group from '../../components/settings/Group.svelte'
  import CountUp from '../../components/CountUp.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Soon from '../../components/settings/Soon.svelte'
  import { api, type StorageUsage } from '../../lib/api'
  import { plural } from '../../lib/format'
  import { toast } from '../../lib/toast.svelte'

  let usage = $state<StorageUsage | null>(null)
  let confirmPrefs = $state(false)

  const mb = (b: number) => b / 1_048_576
  const mbText = (b: number) =>
    b < 1_048_576 ? `${Math.max(1, Math.round(b / 1024))} КБ` : `${mb(b) < 10 ? mb(b).toFixed(1) : Math.round(mb(b))} МБ`
  const total = $derived(usage ? usage.covers_bytes + usage.lyrics_bytes + usage.db_bytes : 0)
  const part = (b: number) => (total ? Math.max(2, (b / total) * 100) : 0)

  async function refresh() {
    try {
      usage = await api.storageUsage()
    } catch {
      usage = null
    }
  }
  onMount(refresh)

  async function clear(kind: 'covers' | 'lyrics' | 'track_prefs' | 'all', done: string) {
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
    <span>Занято</span>
  </div>
  <div class="bar" aria-hidden="true">
    <i class="covers" style:width="{part(usage.covers_bytes)}%"></i>
    <i class="lyrics" style:width="{part(usage.lyrics_bytes)}%"></i>
    <i class="db" style:width="{part(usage.db_bytes)}%"></i>
  </div>

  <Switch title="Кеширование треков" hint="Все треки будут сохранены в кеш для быстрого воспроизведения" on={false} soon />

  <Group title="Очистка кеша">
    {#snippet action()}
      <button class="link" onclick={() => clear('all', 'Кэш очищен')}>Очистить всё</button>
    {/snippet}
    <div class="row off">
      <span class="dot tracks"></span>
      <span class="text"><b>Треки <Soon /></b><small>0 треков, 0 МБ</small></span>
      <button class="link" disabled>Очистить</button>
    </div>
    <div class="row">
      <span class="dot covers"></span>
      <span class="text"><b>Обложки</b><small>{usage.covers} {plural(usage.covers, ['обложка', 'обложки', 'обложек'])}, {mbText(usage.covers_bytes)}</small></span>
      <button class="link" onclick={() => clear('covers', 'Обложки удалены')}>Очистить</button>
    </div>
    <div class="row">
      <span class="dot lyrics"></span>
      <span class="text"><b>Тексты</b><small>{usage.lyrics} {plural(usage.lyrics, ['текст', 'текста', 'текстов'])}, {mbText(usage.lyrics_bytes)}</small></span>
      <button class="link" onclick={() => clear('lyrics', 'Тексты удалены')}>Очистить</button>
    </div>
  </Group>

  <Group title="Данные">
    <div class="row off">
      <span class="text"><b>История поиска <Soon /></b><small>Запросы и открытые из поиска результаты</small></span>
      <button class="link" disabled>Очистить</button>
    </div>
    <div class="row">
      <span class="text">
        <b>Настройки треков</b>
        <small>Скорость, эквалайзер и сдвиг текста, сохранённые для отдельных треков ({usage.track_prefs})</small>
      </span>
      {#if confirmPrefs}
        <button class="link danger" onclick={() => clear('track_prefs', 'Настройки треков сброшены')}>Точно сбросить?</button>
      {:else}
        <button class="link" disabled={!usage.track_prefs} onclick={() => (confirmPrefs = true)}>Сбросить</button>
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
  .row.off .text small {
    opacity: 0.6;
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
