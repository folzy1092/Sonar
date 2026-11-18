<script lang="ts">
  // «Найти дубли» (меню Любимых и своего плейлиста, этап 7 NEXT_PROMPT). Группы дублей ищет Rust по
  // сохранённым метаданным, без сети (dupes/mod.rs); в каждой группе первым — кого оставить по умолчанию
  // (лучший звук, при равенстве — добавлен раньше), остальные отмечены. Клик по строке переключает
  // отметку (последнего в группе отметить нельзя), «Оставить» — только этот трек. «Убрать отмеченные» —
  // одна правка, во всплывашке «Отменить».
  import Cover from '../components/Cover.svelte'
  import EmptyState from '../components/EmptyState.svelte'
  import Icon from '../components/Icon.svelte'
  import SourceIcon from '../components/SourceIcon.svelte'
  import { api, errorText, type DupeGroup, type ListTrack } from '../lib/api'
  import { cascade } from '../lib/cascade'
  import { dupeListOf, extraCount, initialMarks, keepOnly, keeperReason, keptIn, reasonOf, removalIds, toggleMark, type Marks } from '../lib/dupes'
  import { tracksText } from '../lib/format'
  import { t } from '../lib/i18n.svelte'
  import { library } from '../lib/library.svelte'
  import { pop, rise } from '../lib/motion'
  import { byId, serviceOf } from '../lib/services'
  import { formatTime } from '../player/player.svelte'
  import { router } from '../app/router.svelte'

  const list = dupeListOf(router.param)
  const playlistName = $derived(list && list !== 'favorites' ? (library.playlists.find((p) => p.id === list)?.name ?? '') : '')
  const where = $derived(list === 'favorites' ? t('Любимые') : playlistName)

  let groups = $state<DupeGroup[]>([])
  let marks = $state<Marks>(new Set())
  let loading = $state(true)
  let busy = $state(false)
  let error = $state<string | null>(null)

  const toRemove = $derived(removalIds(groups, marks))
  /** Номер последней сверки: ответ устаревшей (медиатека успела поменяться ещё раз) не применяется. */
  let scanSeq = 0

  async function scan() {
    if (!list) {
      error = t('Дубли ищутся только в Любимых и своих плейлистах')
      loading = false
      return
    }
    const seq = ++scanSeq
    try {
      const found = await api.findDuplicates(list)
      if (seq !== scanSeq) return
      error = null
      groups = found
      marks = initialMarks(found)
    } catch (e) {
      if (seq === scanSeq) error = errorText(e)
    } finally {
      if (seq === scanSeq) loading = false
    }
  }

  // заново после любой правки медиатеки: «Убрать отмеченные», «Отменить», лайк в другом месте
  $effect(() => {
    library.version
    void scan()
  })

  async function removeMarked() {
    if (!list || !toRemove.length || busy) return
    busy = true
    await library.removeDuplicates(list, toRemove)
    busy = false
  }

  /** Подпись «почему дубль» у трека относительно того, кого оставляем. */
  function reasonText(item: ListTrack, keeper: ListTrack): string {
    const reason = reasonOf(item, keeper)
    if (reason === 'same') return t('Тот же трек ещё раз')
    if (reason === 'similar') return t('Почти то же название')
    return t('Из сервиса «{service}»', { service: t(byId(serviceOf(item.ref))?.name ?? '') })
  }

  /** Подпись у того, кто остаётся по умолчанию. */
  function keeperText(group: DupeGroup): string {
    const reason = keeperReason(group)
    if (reason === 'available') return t('Доступен, остальные — нет')
    return reason === 'quality' ? t('Лучший звук') : t('Добавлен раньше')
  }

  const serviceName = (ref: string) => t(byId(serviceOf(ref))?.name ?? '')
</script>

<header class="head" in:rise={{ y: 8 }}>
  <button class="back" aria-label={t('Назад')} title={t('Назад')} onclick={() => router.back()}>
    <Icon name="chevronLeft" size={18} />
  </button>
  <div class="titles">
    <h1>{t('Дубли')}</h1>
    <p>
      {#if where}{t('В «{title}»', { title: where })} · {/if}{t('Без сети, по названию, исполнителю и длительности')}
    </p>
  </div>
  {#if groups.length}
    <button class="remove" disabled={!toRemove.length || busy} onclick={removeMarked} in:pop>
      <Icon name="trash" size={16} />
      {busy ? t('Убираю…') : t('Убрать отмеченные ({count})', { count: toRemove.length })}
    </button>
  {/if}
</header>

{#if error}
  <EmptyState icon="key" title={t('Не получилось найти дубли')} text={error} />
{:else if loading}
  <div class="skeleton">{#each { length: 4 } as _, i (i)}<div class="sk"></div>{/each}</div>
{:else if !groups.length}
  <EmptyState icon="check" title={t('Дублей нет')} text={t('Каждый трек здесь — один раз.')} />
{:else}
  <p class="found" in:rise={{ y: 6 }}>
    {t('Групп: {groups} · лишних: {tracks}', { groups: groups.length, tracks: tracksText(extraCount(groups)) })}
  </p>
  <div class="groups" use:cascade={groups}>
    {#each groups as group (group.keep)}
      {@const keeper = group.items[0]}
      <section class="group">
        {#each group.items as item (item.item_id)}
          {@const marked = marks.has(item.item_id)}
          {@const last = !marked && keptIn(group, marks) <= 1}
          {@const service = serviceOf(item.ref)}
          <div class="row" class:marked>
            <button
              class="pick"
              role="checkbox"
              aria-checked={!marked}
              disabled={last}
              title={last ? t('Хотя бы один трек группы остаётся') : marked ? t('Оставить') : t('Убрать')}
              onclick={() => (marks = toggleMark(marks, group, item.item_id))}
            >
              <span class="box" class:on={!marked}>{#if !marked}<span in:pop={{ scale: 0.6, y: 0 }}><Icon name="check" size={13} /></span>{/if}</span>
              <Cover url={item.cover_url} size={40} source={item.ref} />
              <span class="meta">
                <b>{item.title}</b>
                <small>{item.artist}</small>
              </span>
            </button>
            <span class="src">{#if service}<SourceIcon {service} size={13} plain /> {serviceName(item.ref)}{/if}</span>
            <span class="why">
              {#if item === keeper}{keeperText(group)}{:else}{reasonText(item, keeper)}{/if}
              {#if !item.available} · {t('недоступен')}{/if}
            </span>
            <span class="dur">{item.duration_ms ? formatTime(item.duration_ms) : '—'}</span>
            <span class="state" class:keep={!marked}>{marked ? t('Уберётся') : t('Остаётся')}</span>
            <button class="only" title={t('Оставить только этот')} onclick={() => (marks = keepOnly(marks, group, item.item_id))}>
              {t('Только этот')}
            </button>
          </div>
        {/each}
      </section>
    {/each}
  </div>
{/if}

<style>
  .head {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 8px 0 18px;
  }
  .back {
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    border-radius: 999px;
    color: var(--text-2);
    transition: background var(--fast) var(--ease);
  }
  .back:hover {
    background: var(--hover);
    color: var(--text);
  }
  .titles {
    flex: 1;
    min-width: 0;
  }
  h1 {
    margin: 0;
    font-size: calc(26px * var(--fs, 1));
  }
  .titles p,
  .found {
    margin: 2px 0 0;
    color: var(--text-3);
  }
  .found {
    margin: 0 0 12px;
  }
  .remove {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 36px;
    padding: 0 16px;
    border-radius: 999px;
    background: var(--text);
    color: var(--on-text);
    font-weight: 700;
    transition:
      opacity var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .remove:active:not(:disabled) {
    transform: scale(0.97);
  }
  .remove:disabled {
    opacity: 0.45;
  }
  .groups {
    display: flex;
    flex-direction: column;
    gap: 12px;
    padding-bottom: 24px;
  }
  .group {
    display: flex;
    flex-direction: column;
    padding: 6px;
    border-radius: var(--radius-l);
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  .row {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 150px 190px 52px 86px auto;
    align-items: center;
    gap: 12px;
    padding: 4px 8px 4px 4px;
    border-radius: var(--radius-m);
    transition:
      background var(--fast) var(--ease),
      opacity var(--normal) var(--ease);
  }
  .row:hover {
    background: var(--hover);
  }
  .row.marked .meta,
  .row.marked :global(.cover) {
    opacity: 0.5;
  }
  .row.marked b {
    text-decoration: line-through;
    text-decoration-color: color-mix(in srgb, var(--text) 40%, transparent);
  }
  .pick {
    display: flex;
    align-items: center;
    gap: 12px;
    min-width: 0;
    padding: 2px;
    text-align: left;
  }
  .pick:disabled {
    cursor: default;
  }
  .box {
    flex: none;
    display: grid;
    place-items: center;
    width: 20px;
    height: 20px;
    border-radius: 6px;
    border: 1.5px solid var(--border-strong);
    color: var(--on-text);
    transition:
      background var(--fast) var(--ease),
      border-color var(--fast) var(--ease);
  }
  .box.on {
    background: var(--text);
    border-color: var(--text);
  }
  .meta {
    display: flex;
    flex-direction: column;
    min-width: 0;
    transition: opacity var(--normal) var(--ease);
  }
  .meta b,
  .meta small {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .meta small,
  .src,
  .why,
  .dur {
    color: var(--text-3);
  }
  .src {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    white-space: nowrap;
    overflow: hidden;
  }
  .why {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .dur {
    text-align: right;
    font-variant-numeric: tabular-nums;
  }
  .state {
    justify-self: start;
    padding: 2px 10px;
    border-radius: 999px;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--danger);
    background: color-mix(in srgb, var(--danger) 12%, transparent);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .state.keep {
    color: var(--text);
    background: var(--accent-soft);
  }
  .only {
    height: 28px;
    padding: 0 10px;
    border-radius: 999px;
    color: var(--text-2);
    font-weight: 600;
    opacity: 0;
    transition:
      opacity var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .row:hover .only,
  .only:focus-visible {
    opacity: 1;
  }
  .only:hover {
    background: var(--hover);
    color: var(--text);
  }
  @media (max-width: 980px) {
    .row {
      grid-template-columns: minmax(0, 1fr) 52px 86px auto;
    }
    .src,
    .why {
      display: none;
    }
  }
  .skeleton {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }
  .sk {
    height: 110px;
    border-radius: var(--radius-l);
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
