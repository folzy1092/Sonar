<script lang="ts">
  import SourceIcon from '../components/SourceIcon.svelte'
  import Icon from '../components/Icon.svelte'
  import { router } from './router.svelte'
  import { search, type Source } from './search.svelte'
  import { IMPLEMENTED } from '../lib/services'
  import Cover from '../components/Cover.svelte'
  import { onMount } from 'svelte'
  import { searchHistory, type SearchEntry } from '../lib/search-history.svelte'
  import { openRef } from './router.svelte'
  import { playStation } from '../player/autoplay.svelte'
  import { api, type Track } from '../lib/api'
  import { t } from '../lib/i18n.svelte'
  import { tick } from 'svelte'
  import { fade } from 'svelte/transition'
  import { autocompleteSource } from './autocomplete-source.svelte'
  import { canSuggest, decideKey, suggest, type FieldState } from '../lib/autocomplete'
  import { reducedMotion, fly } from '../lib/motion'
  import { offline } from '../lib/offline.svelte'

  // недавнее под пустым полем: открывается кликом по полю, закрывается кликом мимо (или выбором)
  let open = $state(false)
  let root: HTMLDivElement | undefined = $state()
  const showRecent = $derived(open && !search.query.trim() && searchHistory.items.length > 0)

  // Серая подсказка-дописывание (lib/autocomplete.ts): слой под полем, Tab / → — принять.
  let input: HTMLInputElement | undefined = $state()
  let focused = $state(false)
  let composing = $state(false)
  let caret = $state({ start: 0, end: 0 })
  /** Сдвиг прокрутки поля — слой подсказки едет вместе с текстом. */
  let scrollX = $state(0)
  /** Esc убрал подсказку к этому тексту; набрал дальше — подсказка вернётся. */
  let dismissedFor = $state<string | null>(null)

  autocompleteSource.watchLikes()

  const fieldState = $derived<FieldState>({ value: search.query, selectionStart: caret.start, selectionEnd: caret.end, composing })
  const hint = $derived(!offline.on && focused && dismissedFor !== search.query && canSuggest(fieldState) ? suggest(autocompleteSource.candidates, search.query) : null)
  const fadeMs = $derived(reducedMotion() ? 0 : 120)

  function syncCaret() {
    if (!input) return
    caret = { start: input.selectionStart ?? 0, end: input.selectionEnd ?? 0 }
    scrollX = input.scrollLeft
  }

  async function accept(value: string) {
    search.query = value
    dismissedFor = null
    open = false
    if (router.page !== 'search') router.go('search')
    await tick()
    if (!input) return
    input.setSelectionRange(value.length, value.length)
    input.scrollLeft = input.scrollWidth
    syncCaret()
  }

  /** Второй Esc (подсказки уже нет): закрыть недавнее, потом очистить, потом уйти из поля. */
  function escape() {
    if (open) open = false
    else if (search.query) search.query = ''
    else input?.blur()
  }

  function onKeydown(e: KeyboardEvent) {
    if (e.isComposing) return
    const d = decideKey(e.key, fieldState, hint, { shift: e.shiftKey, ctrl: e.ctrlKey || e.metaKey, alt: e.altKey })
    if (d.kind === 'accept') {
      e.preventDefault()
      void accept(d.value)
    } else if (d.kind === 'search') {
      open = false
      if (d.value.trim() && router.page !== 'search') router.go('search')
    } else if (d.kind === 'dismiss') {
      e.preventDefault()
      dismissedFor = search.query
    } else if (e.key === 'Escape') escape()
  }

  onMount(() => {
    const outside = (e: MouseEvent) => {
      if (open && root && !root.contains(e.target as Node)) open = false
    }
    // выделение мышью и перенос курсора — подсказка прячется, пока курсор не в конце
    const selection = () => document.activeElement === input && syncCaret()
    window.addEventListener('mousedown', outside, true)
    document.addEventListener('selectionchange', selection)
    return () => {
      window.removeEventListener('mousedown', outside, true)
      document.removeEventListener('selectionchange', selection)
    }
  })

  async function pick(e: SearchEntry) {
    open = false
    if (e.kind === 'query') {
      search.query = e.query
      if (router.page !== 'search') router.go('search')
      return
    }
    if (!e.ref) return
    if (e.kind === 'track') {
      // трек из истории: сначала из кэша треков (полные данные), иначе — по сохранённому
      const stub = { ref: e.ref, title: e.title ?? '', artist: e.subtitle ?? '', artists: [], album: null, duration_ms: 0, cover_url: e.cover_url ?? null, url: null, explicit: false, available: true } as unknown as Track
      const [full] = await api.cachedTracks([e.ref]).catch(() => [] as Track[])
      void playStation(full ?? stub)
    } else openRef(e.ref)
  }

  // label / title — ключи перевода, t() — при выводе; источники — реализованные сервисы с поиском
  const sources: { id: Source; label: string; title: string }[] = IMPLEMENTED.filter((s) => s.caps.search).map((s) => ({
    id: s.id,
    label: s.short,
    title: s.name,
  }))

  function onInput() {
    syncCaret()
    // Esc убрал подсказку только к тому тексту; любая правка (и Backspace) — снова считаем
    dismissedFor = null
    if (search.query.trim() && router.page !== 'search') router.go('search')
  }
</script>

<div class="bar" bind:this={root}>
  <label class="field">
    <Icon name="search" size={18} />
    <span class="inwrap">
      {#if hint}
        <span class="ghost" aria-hidden="true">
          <span class="ghost-line" style:transform="translateX({-scrollX}px)">
            <span class="typed">{search.query}</span>{#key hint.full}<span class="tail" in:fade|global={{ duration: fadeMs }}
                >{#if hint.relayout}<span class="arrow">&nbsp;→&nbsp;</span>{hint.full}{:else}{hint.tail}{/if}<span class="tab">Tab</span></span
              >{/key}
          </span>
        </span>
      {/if}
      <input
        bind:this={input}
        type="text"
        placeholder={t('Что включить?')}
        spellcheck="false"
        autocomplete="off"
        aria-autocomplete="inline"
        bind:value={search.query}
        oninput={onInput}
        onkeydown={onKeydown}
        onkeyup={syncCaret}
        onscroll={syncCaret}
        onfocus={() => {
          focused = true
          autocompleteSource.ensure()
          syncCaret()
        }}
        onblur={() => (focused = false)}
        oncompositionstart={() => (composing = true)}
        oncompositionend={() => {
          composing = false
          syncCaret()
        }}
        onclick={() => {
          open = true
          void searchHistory.load()
        }}
      />
    </span>
  </label>
  <span class="sr" aria-live="polite">{hint ? t('Подсказка: {text}. Tab — дописать', { text: hint.full }) : ''}</span>
  {#if showRecent}
    <div class="recent" transition:fly={{ y: -6, duration: 200 }}>
      <div class="r-head">
        <b>{t('Недавнее')}</b>
        <button class="r-clear" onclick={() => void searchHistory.clear()}>{t('Очистить')}</button>
      </div>
      {#each searchHistory.items.slice(0, 8) as e (e.kind + (e.ref ?? e.query))}
        <button class="r-item" onclick={() => pick(e)}>
          {#if e.kind === 'query'}
            <span class="r-ic"><Icon name="history" size={16} /></span>
            <span class="r-text"><span class="r-title">{e.query}</span></span>
          {:else}
            <span class="r-cover" class:round={e.kind === 'artist'}><Cover url={e.cover_url ?? null} size={32} radius={e.kind === 'artist' ? '50%' : '7px'} /></span>
            <span class="r-text">
              <span class="r-title">{e.title}</span>
              <span class="r-sub">{e.kind === 'track' ? t('Трек') : e.kind === 'artist' ? t('Исполнитель') : e.kind === 'album' ? t('Альбом') : t('Плейлист')}{#if e.subtitle}&nbsp;· {e.subtitle}{/if}</span>
            </span>
          {/if}
        </button>
      {/each}
    </div>
  {/if}

  {#if offline.on}
    <!-- офлайн: вместо сервисов — плашка; клик выключает режим (docs/OFFLINE.md §8) -->
    <button
      class="offline"
      title={t('Выключить офлайн-режим')}
      onclick={() => offline.set(false)}
      in:fly={{ y: -4, duration: 200 }}
    >
      <Icon name="wifiOff" size={15} />
      {t('Офлайн')}
    </button>
  {:else}
    <div class="sources" role="radiogroup" aria-label={t('Источник поиска')}>
      <button
        class="src all"
        class:on={search.source === 'all'}
        role="radio"
        aria-checked={search.source === 'all'}
        title={t('Все сервисы сразу')}
        onclick={() => (search.source = 'all')}
      >
        {t('поиск::Все')}
      </button>
      {#each sources as s (s.id)}
        <button
          class="src"
          class:on={search.source === s.id}
          role="radio"
          aria-checked={search.source === s.id}
          title={t(s.title)}
          onclick={() => (search.source = s.id)}
        >
          <SourceIcon service={s.id} size={16} plain />
        </button>
      {/each}
    </div>
  {/if}

</div>

<style>
  .bar {
    position: relative;
    display: flex;
    align-items: center;
    gap: 8px;
    width: min(560px, 100%);
  }
  .recent {
    position: absolute;
    top: calc(100% + 8px);
    left: 0;
    z-index: 30;
    width: min(460px, 100%);
    padding: 8px;
    border-radius: var(--radius-l);
    background: var(--surface-2);
    border: 1px solid var(--card-line);
    box-shadow:
      0 18px 40px oklch(0 0 0 / 0.45),
      var(--sheen);
  }
  .r-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 4px 8px 8px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .r-clear {
    color: var(--text-2);
    font-size: calc(12px * var(--fs, 1));
  }
  .r-clear:hover {
    color: var(--text);
  }
  .r-item {
    display: flex;
    align-items: center;
    gap: 10px;
    width: 100%;
    padding: 6px 8px;
    border-radius: var(--radius-m);
    text-align: left;
    transition: background var(--fast) var(--ease);
  }
  .r-item:hover {
    background: var(--hover);
  }
  .r-ic {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
    color: var(--text-3);
  }
  .r-text {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .r-title,
  .r-sub {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .r-sub {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .field {
    flex: 1;
    display: flex;
    align-items: center;
    gap: 10px;
    height: 40px;
    padding: 0 14px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--border);
    color: var(--text-3);
    transition:
      border-color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .field:focus-within {
    border-color: var(--border-strong);
    background: var(--surface-2);
    color: var(--text-2);
  }
  /* поле и слой подсказки — один шрифт, интервал и отступы: буквы совпадают пиксель в пиксель */
  .inwrap {
    position: relative;
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: center;
  }
  input {
    position: relative;
    flex: 1;
    min-width: 0;
    padding: 0;
    background: none;
    border: 0;
    outline: none;
    font: inherit;
    letter-spacing: inherit;
    color: var(--text);
    user-select: text;
  }
  .ghost {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    overflow: hidden;
    pointer-events: none;
    font: inherit;
    letter-spacing: inherit;
    white-space: pre;
  }
  .ghost-line {
    display: flex;
    align-items: center;
  }
  .typed {
    color: transparent;
  }
  .tail {
    display: inline-flex;
    align-items: center;
    color: var(--text-3);
  }
  .arrow {
    opacity: 0.7;
  }
  .tab {
    margin-left: 8px;
    padding: 1px 5px;
    border-radius: 5px;
    border: 1px solid var(--border);
    font-size: calc(10px * var(--fs, 1));
    font-weight: 600;
    line-height: 1.3;
    letter-spacing: 0.02em;
    color: var(--text-3);
    opacity: 0.7;
  }
  .sr {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }
  input::placeholder {
    color: var(--text-3);
  }
  .sources {
    display: flex;
    padding: 3px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--border);
  }
  .src {
    min-width: 38px;
    height: 32px;
    padding: 0 10px;
    border-radius: 999px;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 700;
    color: var(--text-3);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .src:hover {
    color: var(--text);
  }
  .src.on {
    background: var(--accent);
    color: var(--accent-ink);
  }
  .offline {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 38px;
    padding: 0 14px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--border);
    font-size: calc(12px * var(--fs, 1));
    font-weight: 700;
    color: var(--text-2);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .offline:hover {
    color: var(--text);
    background: var(--surface-3);
  }
  .offline:active {
    transform: scale(0.96);
  }
</style>
