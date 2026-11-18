<script lang="ts">
  // Система → Хранилище → «Папки с музыкой» (NEXT_PROMPT этап 10): «+» — выбрать папку (системный
  // диалог, local_pick_folder), «−» — убрать; после правки — скан (local_rescan). Новые и удалённые
  // на диске файлы подхватывает слежение за папками само (local/watch.rs) — строка итога обновится.
  import { onDestroy, onMount } from 'svelte'
  import Group from './Group.svelte'
  import Icon from '../Icon.svelte'
  import { cascade } from '../../lib/cascade'
  import { pulse } from '../../lib/pulse'
  import { rise } from '../../lib/motion'
  import { settings } from '../../lib/settings.svelte'
  import { api, errorText, onLocalFilesChanged, type LocalSummary } from '../../lib/api'
  import { addFolder, removeFolder } from '../../lib/local'
  import { t, tn } from '../../lib/i18n.svelte'
  import { toast } from '../../lib/toast.svelte'
  import { router } from '../../app/router.svelte'
  import { settingsPanel } from '../../pages/settings-section.svelte'

  const KEY = 'storage.music_folders'
  const folders = $derived(settings.get(KEY))

  let summary = $state<LocalSummary | null>(null)
  let count = $state<number | null>(null)
  let busy = $state(false)
  /** Подскок строки итога, когда скан что-то нашёл (use:pulse). */
  let fresh = $state(false)

  async function loadCount() {
    try {
      count = (await api.localTracks()).length
    } catch {
      count = null
    }
  }
  onMount(loadCount)
  onDestroy(onLocalFilesChanged(() => void loadCount()))

  /** Сохранить список и пересканировать: строки убранной папки уходят, новой — появляются. */
  async function save(next: string[]) {
    settings.set(KEY, next)
    busy = true
    try {
      await api.setSetting(KEY, next)
      await rescan()
    } catch (e) {
      toast.show(errorText(e))
    } finally {
      busy = false
    }
  }

  async function rescan() {
    busy = true
    fresh = false
    try {
      const s = await api.localRescan()
      summary = s
      count = s.total
      fresh = s.added + s.updated + s.removed > 0
    } catch (e) {
      toast.show(errorText(e))
    } finally {
      busy = false
    }
  }

  async function pick() {
    try {
      const dir = await api.localPickFolder(t('Выбери папку с музыкой'))
      if (!dir) return
      const next = addFolder(folders, dir)
      if (!next) return toast.show(t('Эта папка уже в списке'))
      await save(next)
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  const changes = $derived(
    summary
      ? [
          summary.added ? t('новых {n}', { n: summary.added }) : '',
          summary.updated ? t('обновлено {n}', { n: summary.updated }) : '',
          summary.removed ? t('убрано {n}', { n: summary.removed }) : '',
          summary.missing ? t('не найдено {n}', { n: summary.missing }) : '',
        ].filter(Boolean)
      : [],
  )

  function openLocal() {
    settingsPanel.close()
    router.go('playlist', 'local')
  }
</script>

<Group title={t('Папки с музыкой')}>
  {#snippet action()}
    <button class="link" disabled={busy || !folders.length} onclick={rescan}>
      <span class="spin" class:on={busy}><Icon name="refresh" size={14} /></span>{busy ? t('Сканирую…') : t('Пересканировать')}
    </button>
  {/snippet}
  <p class="hint">{t('Музыка с этого компьютера: mp3, flac, m4a, ogg, opus и wav. Треки появятся в Медиатеке — «На этом компьютере», их можно лайкать и добавлять в плейлисты.')}</p>
  <div class="folders" use:cascade={folders.length}>
    {#each folders as dir (dir)}
      <div class="folder">
        <Icon name="library" size={16} />
        <span class="path" title={dir}>{dir}</span>
        <button class="sq" aria-label={t('Убрать папку')} title={t('Убрать папку')} disabled={busy} onclick={() => save(removeFolder(folders, dir))}>
          <Icon name="minus" size={15} />
        </button>
      </div>
    {/each}
    <button class="folder add" disabled={busy} onclick={pick}>
      <Icon name="plus" size={16} />
      <span class="path">{t('Добавить папку')}</span>
    </button>
  </div>
  {#if folders.length && count !== null}
    <p class="summary" use:pulse={fresh}>
      <button class="link" onclick={openLocal}>{count} {tn(count, ['трек', 'трека', 'треков'])}</button>
      {#if changes.length}<span>· {changes.join(', ')}</span>{/if}
    </p>
    {#if summary?.truncated}
      <p class="hint" transition:rise>{t('Файлов больше 50 000 — просканированы не все. Убери лишние папки из списка.')}</p>
    {/if}
  {/if}
</Group>

<style>
  .hint {
    margin: 0 0 10px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .folders {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .folder {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 40px;
    padding: 0 6px 0 12px;
    border-radius: var(--radius-m);
    background: var(--plate);
    border: 1px solid var(--card-line);
    color: var(--text-2);
    text-align: left;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .folder.add {
    border-style: dashed;
    background: none;
    color: var(--text-3);
  }
  .folder.add:hover:not(:disabled) {
    color: var(--text);
    background: var(--hover);
  }
  .folder.add:active:not(:disabled) {
    transform: scale(0.99);
  }
  .path {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    direction: rtl;
    text-align: left;
    user-select: text;
    font-size: calc(13px * var(--fs, 1));
    color: var(--text);
  }
  .add .path {
    direction: ltr;
    color: inherit;
  }
  .sq {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    border-radius: var(--radius-s);
    color: var(--text-3);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .sq:hover:not(:disabled) {
    color: var(--danger);
    background: var(--hover);
  }
  .summary {
    display: flex;
    align-items: center;
    gap: 6px;
    margin: 8px 0 0;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .link {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-2);
    padding: 6px 4px;
    transition: color var(--fast) var(--ease);
  }
  .summary .link {
    padding: 0;
    font-size: inherit;
  }
  .link:hover:not(:disabled) {
    color: var(--text);
  }
  .link:disabled {
    opacity: 0.4;
    cursor: default;
  }
  .spin {
    display: grid;
  }
  .spin.on {
    animation: spin 0.9s linear infinite;
  }
  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .spin.on {
      animation: none;
    }
  }
</style>
