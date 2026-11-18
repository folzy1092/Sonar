<script lang="ts">
  // Выбор трека для «Похоже на трек» (MixPage): Любимые и недавнее, поиск по названию и исполнителю.
  // Открывается и закрывается только кликом (кнопкой или мимо всплывашки).
  import Cover from './Cover.svelte'
  import Icon from './Icon.svelte'
  import { api, type Track } from '../lib/api'
  import { matchTracks } from '../lib/home-mixes'
  import { isLocalRef } from '../lib/services'
  import { pop } from '../lib/motion'
  import { t } from '../lib/i18n.svelte'

  interface Props {
    current: string | null
    onpick: (track: Track) => void
    onclose: () => void
  }
  let { current, onpick, onclose }: Props = $props()

  /** Сколько истории показываем в выборе. */
  const HISTORY = 200

  let pool = $state<Track[]>([])
  let loading = $state(true)
  let query = $state('')
  let input: HTMLInputElement | undefined = $state()

  // недавнее первым (его вспоминают чаще), за ним Любимые; файлы с компьютера — нельзя, у них нет похожего
  $effect(() => {
    let alive = true
    void Promise.all([api.recentTracks(HISTORY).catch(() => [] as Track[]), api.favorites().catch(() => [] as Track[])]).then(([recent, favs]) => {
      if (!alive) return
      pool = [...recent, ...favs].filter((x) => !isLocalRef(x.ref) && x.available !== false)
      loading = false
    })
    queueMicrotask(() => input?.focus())
    return () => (alive = false)
  })

  const visible = $derived(matchTracks(pool, query))

  /** Клик мимо — закрыть (кнопка-открывашка сама переключает). */
  function outside(node: HTMLElement) {
    const onDown = (e: MouseEvent) => {
      const target = e.target as Node
      if (!node.contains(target) && !(target instanceof Element && target.closest('[data-picker-toggle]'))) onclose()
    }
    window.addEventListener('mousedown', onDown, true)
    return { destroy: () => window.removeEventListener('mousedown', onDown, true) }
  }
</script>

<div class="picker" role="dialog" aria-label={t('Выбрать трек')} use:outside in:pop out:pop>
  <label class="find">
    <Icon name="search" size={15} />
    <input bind:this={input} placeholder={t('Найти в Любимых и недавнем')} bind:value={query} spellcheck="false" />
  </label>
  <div class="list">
    {#if loading}
      {#each { length: 5 } as _, i (i)}<div class="sk skel"></div>{/each}
    {:else if !visible.length}
      <p class="empty">{query.trim() ? t('Ничего не нашлось') : t('Послушай или лайкни что-нибудь — и выбери отсюда.')}</p>
    {:else}
      {#each visible as x (x.ref)}
        <button class="item" class:on={x.ref === current} onclick={() => onpick(x)}>
          <Cover url={x.cover_url} size={38} />
          <span class="text"><b>{x.title}</b><small>{x.artist}</small></span>
          {#if x.ref === current}<Icon name="check" size={16} />{/if}
        </button>
      {/each}
    {/if}
  </div>
</div>

<style>
  .picker {
    position: absolute;
    top: calc(100% + 8px);
    left: 0;
    z-index: 20;
    display: flex;
    flex-direction: column;
    gap: 8px;
    width: min(380px, 80vw);
    padding: 10px;
    border-radius: 18px;
    background: var(--surface-1, var(--surface-0));
    border: 1px solid var(--card-line);
    box-shadow: 0 18px 50px rgba(0, 0, 0, 0.45);
  }
  .find {
    display: flex;
    align-items: center;
    gap: 8px;
    height: 36px;
    padding: 0 12px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--card-line);
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
  .list {
    display: flex;
    flex-direction: column;
    max-height: 340px;
    overflow-y: auto;
    scrollbar-width: thin;
  }
  .item {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 6px 8px;
    border-radius: var(--radius-m);
    text-align: left;
    color: var(--text-2);
    transition: background var(--fast) var(--ease);
  }
  .item:hover,
  .item.on {
    background: var(--hover);
    color: var(--text);
  }
  .text {
    display: flex;
    flex-direction: column;
    flex: 1;
    min-width: 0;
  }
  .text b,
  .text small {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .text b {
    font-weight: 600;
    color: var(--text);
  }
  .text small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .sk {
    height: 46px;
    margin-bottom: 4px;
    border-radius: var(--radius-m);
  }
  .empty {
    margin: 8px;
    color: var(--text-3);
  }
</style>
