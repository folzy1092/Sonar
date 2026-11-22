<script lang="ts">
  // Умный плейлист (NEXT_PROMPT, этап 6; параметр роутера — `sm_…`): треки считаются заново при
  // каждом открытии и после любой правки медиатеки (лайк, прослушивание, правка исходного плейлиста).
  // Порядок задают правила — перетаскивания нет; «Сохранить как обычный плейлист» делает снимок.
  import ScrollStick from '../components/ScrollStick.svelte'
  import CollectionHeader from '../components/CollectionHeader.svelte'
  import EmptyState from '../components/EmptyState.svelte'
  import Icon from '../components/Icon.svelte'
  import TrackRow from '../components/TrackRow.svelte'
  import { cascade } from '../lib/cascade'
  import { growLimit, LIST_WINDOW } from '../lib/list-window'
  import { nearEnd } from '../lib/near-end'
  import { api, errorText, type SmartPlaylist } from '../lib/api'
  import { durationText, tracksText } from '../lib/format'
  import { library } from '../lib/library.svelte'
  import { router } from '../app/router.svelte'
  import { player } from '../player/player.svelte'
  import { t, tn } from '../lib/i18n.svelte'
  import { parseRules } from '../lib/smart'
  import { smartLists } from '../lib/smart-lists.svelte'

  const id = router.param ?? ''
  const context = `playlist:${id}`

  let data = $state<SmartPlaylist | null>(null)
  let loading = $state(true)
  let error = $state<string | null>(null)
  let filter = $state('')
  let confirmDelete = $state(false)
  let saving = $state(false)
  let tracksEl: HTMLDivElement | undefined = $state()

  const items = $derived(data?.tracks ?? [])
  const title = $derived(data?.name ?? '')
  const visible = $derived.by(() => {
    const q = filter.trim().toLowerCase()
    return q ? items.filter((x) => `${x.title} ${x.artist}`.toLowerCase().includes(q)) : items
  })
  const total = $derived(items.reduce((s, x) => s + x.duration_ms, 0))
  // окно списка: большой умный плейлист не рисуется целиком; новый фильтр — окно снова маленькое
  let limit = $state(LIST_WINDOW)
  $effect.pre(() => {
    void filter
    limit = LIST_WINDOW
  })
  const shown = $derived(visible.length > limit ? visible.slice(0, limit) : visible)

  /** Подпись под названием: откуда треки и сколько условий. */
  const rulesText = $derived.by(() => {
    const rules = parseRules(data?.rules)
    if (!rules) return ''
    const from =
      rules.source.kind === 'liked'
        ? t('из Любимых')
        : rules.source.kind === 'played'
          ? t('из всего прослушанного')
          : t('из «{name}»', { name: library.playlists.find((p) => rules.source.kind === 'playlist' && p.id === rules.source.id)?.name ?? t('плейлиста') })
    const n = rules.conditions.length
    return n ? `${from} · ${n} ${tn(n, ['условие', 'условия', 'условий'])}` : from
  })

  // номер загрузки: ответ старого пересчёта, пришедший после нового, не затирает свежий
  let loadSeq = 0
  async function load() {
    const seq = ++loadSeq
    error = null
    try {
      const next = await api.smartPlaylist(id)
      if (seq === loadSeq) data = next
    } catch (e) {
      if (seq === loadSeq) error = errorText(e)
    } finally {
      if (seq === loadSeq) loading = false
    }
  }

  // пересчёт при открытии и после правки медиатеки (лайк, плейлист, правила умного плейлиста)
  $effect(() => {
    library.version
    void load()
  })

  const play = (i: number) => player.playList(visible, i, context, title)

  async function remove() {
    if (!data) return
    if (!confirmDelete) {
      confirmDelete = true
      return
    }
    if (await smartLists.remove(data)) router.back()
  }

  async function snapshot() {
    if (!data) return
    saving = true
    const copy = await smartLists.snapshot(data)
    saving = false
    if (copy) router.go('playlist', copy.id)
  }
</script>

<CollectionHeader
  {title}
  titleIcon="sparkles"
  covers={data?.covers ?? []}
  icon="sparkles"
  meta={loading || !data ? '' : `${tracksText(items.length)}${items.length ? `, ${durationText(total)}` : ''}`}
  {context}
  disabled={!visible.length}
  onplay={() => play(0)}
  onshuffle={() => player.playShuffled(visible, context, title)}
  onqueue={() => player.addToQueue(visible, false)}
>
  {#snippet subtitle()}
    {t('Умный плейлист')}{#if rulesText} · {rulesText}{/if}
  {/snippet}
  {#snippet actions()}
    {#if data}
      <button class="tool" onclick={() => data && smartLists.editExisting(data)}>
        <Icon name="sparkles" size={16} /> {t('Изменить правила')}
      </button>
      <button class="tool" disabled={saving || !items.length} onclick={snapshot}>
        <Icon name="copy" size={16} /> {saving ? t('Сохраняю…') : t('Сохранить как обычный плейлист')}
      </button>
    {/if}
  {/snippet}
  {#snippet tools()}
    {#if data}
      <button class="tool plain" class:danger={confirmDelete} title={t('Удалить плейлист')} onclick={remove} onblur={() => (confirmDelete = false)}>
        <Icon name="trash" size={16} />{#if confirmDelete} {t('Удалить?')}{/if}
      </button>
    {/if}
    <label class="find">
      <Icon name="search" size={15} />
      <input placeholder={t('Найти')} bind:value={filter} spellcheck="false" />
    </label>
  {/snippet}
</CollectionHeader>

<ScrollStick target={tracksEl} />
<div class="tracks" bind:this={tracksEl}>
  {#if error}
    <EmptyState icon="key" title={t('Не получилось открыть')} text={error} />
  {:else if loading}
    <div class="skeleton">{#each { length: 8 } as _, i (i)}<div class="sk"></div>{/each}</div>
  {:else if data?.error === 'invalid'}
    <EmptyState icon="sparkles" title={t('Правила этого плейлиста не читаются')} text={t('Похоже, их сохранила более новая версия Sonar. Открой «Изменить правила» и собери их заново.')} />
  {:else if data?.error === 'source_missing'}
    <EmptyState icon="sparkles" title={t('Исходного плейлиста больше нет')} text={t('Выбери другой источник в «Изменить правила».')} />
  {:else if !items.length}
    <EmptyState icon="sparkles" title={t('Пока ни один трек не подходит')} text={t('Слушай и лайкай дальше — плейлист обновится сам. Или ослабь правила.')} />
  {:else if !visible.length}
    <EmptyState icon="search" title={t('Ничего не нашлось')} text={t('В «{title}» нет «{query}».', { title, query: filter.trim() })} />
  {:else}
    <div class="list" use:cascade>
      {#each shown as x, i (x.ref)}
        <TrackRow track={x} addedAt={x.added_at} onplay={() => play(i)} />
      {/each}
      {#if shown.length < visible.length}
        <div class="more" use:nearEnd={{ key: limit, onreach: () => (limit = growLimit(limit, visible.length)) }}></div>
      {/if}
    </div>
  {/if}
</div>

<style>
  /* сторож окна списка — невидимая строка в самом низу */
  .more {
    height: 1px;
  }
  /* строки вне экрана не раскладываются и не рисуются */
  .list > :global(*) {
    content-visibility: auto;
    contain-intrinsic-size: auto 56px;
  }
  .find {
    display: flex;
    align-items: center;
    gap: 8px;
    width: 200px;
    height: 34px;
    padding: 0 12px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    color: var(--text-3);
  }
  .find:focus-within {
    border-color: var(--border-strong);
  }
  .find input {
    flex: 1;
    min-width: 0;
    background: none;
    border: 0;
    outline: none;
    user-select: text;
  }
  :global(.tool.danger) {
    color: var(--danger) !important;
  }
  .tracks {
    flex: 1;
    min-height: 0;
    margin: 4px 0 0;
    padding: 0 0 24px;
    overflow-y: auto;
    scrollbar-width: none;
  }
  .tracks::-webkit-scrollbar {
    display: none;
  }
  .list {
    display: flex;
    flex-direction: column;
  }
  .skeleton {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .sk {
    height: 56px;
    border-radius: var(--radius-m);
    background: linear-gradient(90deg, var(--plate), var(--hover), var(--plate));
    background-size: 200% 100%;
    animation: shimmer 1.2s linear infinite;
  }
  @keyframes shimmer {
    to {
      background-position: -200% 0;
    }
  }
</style>
