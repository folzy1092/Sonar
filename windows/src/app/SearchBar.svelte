<script lang="ts">
  import SourceIcon from '../components/SourceIcon.svelte'
  import Icon from '../components/Icon.svelte'
  import { router } from './router.svelte'
  import { search, type Source } from './search.svelte'
  import { IMPLEMENTED } from '../lib/services'
  import Cover from '../components/Cover.svelte'
  import { onMount } from 'svelte'
  import { fly } from 'svelte/transition'
  import { searchHistory, type SearchEntry } from '../lib/search-history.svelte'
  import { openRef } from './router.svelte'
  import { playStation } from '../player/autoplay.svelte'
  import { api, type Track } from '../lib/api'
  import { t } from '../lib/i18n.svelte'

  // недавнее под пустым полем: открывается кликом по полю, закрывается кликом мимо (или выбором)
  let open = $state(false)
  let root: HTMLDivElement | undefined = $state()
  const showRecent = $derived(open && !search.query.trim() && searchHistory.items.length > 0)

  onMount(() => {
    const outside = (e: MouseEvent) => {
      if (open && root && !root.contains(e.target as Node)) open = false
    }
    window.addEventListener('mousedown', outside, true)
    return () => window.removeEventListener('mousedown', outside, true)
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
    if (search.query.trim() && router.page !== 'search') router.go('search')
  }
</script>

<div class="bar" bind:this={root}>
  <label class="field">
    <Icon name="search" size={18} />
    <input
      type="text"
      placeholder={t('Что включить?')}
      spellcheck="false"
      bind:value={search.query}
      oninput={onInput}
      onclick={() => {
        open = true
        void searchHistory.load()
      }}
    />
  </label>
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

  <div class="sources" role="radiogroup" aria-label={t('Источник поиска')}>
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
  input {
    flex: 1;
    min-width: 0;
    background: none;
    border: 0;
    outline: none;
    color: var(--text);
    user-select: text;
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
</style>
