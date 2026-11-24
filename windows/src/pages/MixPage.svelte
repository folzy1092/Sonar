<script lang="ts">
  // Страница подборки «Для тебя» (параметр роутера — `MixId`): шапка как у плейлиста с мозаикой,
  // «Слушать», «Перемешать», «Сохранить как плейлист»; у «Похоже на трек» — ещё «Выбрать трек».
  // Треки собирает `mixes` (локально, сетевые — с кэшем на день).
  import { onMount } from 'svelte'
  import ScrollStick from '../components/ScrollStick.svelte'
  import CollectionHeader from '../components/CollectionHeader.svelte'
  import EmptyState from '../components/EmptyState.svelte'
  import Icon from '../components/Icon.svelte'
  import TrackRow from '../components/TrackRow.svelte'
  import TrackPicker from '../components/TrackPicker.svelte'
  import { cascade } from '../lib/cascade'
  import type { Track } from '../lib/api'
  import { durationText, tracksText } from '../lib/format'
  import { library } from '../lib/library.svelte'
  import { router } from '../app/router.svelte'
  import { player } from '../player/player.svelte'
  import { t } from '../lib/i18n.svelte'
  import { isMixId, type MixId } from '../lib/home-mixes'
  import { PixelCollage } from '../lib/pixel-collage.svelte'
  import { home } from './home-data.svelte'
  import { mixes } from './mixes.svelte'

  const id: MixId = isMixId(router.param) ? router.param : 'daypart'
  const context = `mix:${id}`

  let filter = $state('')
  let saving = $state(false)
  let picking = $state(false)
  let tracksEl: HTMLDivElement | undefined = $state()

  const items = $derived(mixes.tracks(id))
  const pc = new PixelCollage()
  $effect(() => pc.set(items))
  const title = $derived(mixes.title(id))
  const loading = $derived(mixes.isLoading(id) && !items.length)
  const visible = $derived.by(() => {
    const q = filter.trim().toLowerCase()
    return q ? items.filter((x) => `${x.title} ${x.artist}`.toLowerCase().includes(q)) : items
  })
  const total = $derived(items.reduce((s, x) => s + x.duration_ms, 0))

  onMount(() => {
    // прямой переход (Ctrl+K, история) — Главная могла ещё не грузиться
    const ready = !home.recent.length && !home.mix.length ? home.load() : Promise.resolve()
    void ready.then(() => {
      void mixes.load()
      // «Похоже на трек» без истории и без выбора — сразу предложить выбрать (история уже пришла)
      if (id === 'like' && !mixes.seed) picking = true
    })
  })

  const play = (i: number) => player.playList(visible, i, context, title)

  async function save() {
    if (!items.length || saving) return
    saving = true
    const copy = await library.createPlaylist(title, $state.snapshot(items) as Track[])
    saving = false
    if (copy) router.go('playlist', copy.id)
  }

  async function pick(track: Track) {
    picking = false
    filter = ''
    await mixes.choose(track)
  }
</script>

<CollectionHeader
  {title}
  titleIcon="playlist"
  covers={pc.covers}
  icon="playlist"
  meta={loading ? '' : `${tracksText(items.length)}${items.length ? `, ${durationText(total)}` : ''}`}
  {context}
  disabled={!visible.length}
  onplay={() => play(0)}
  onshuffle={() => player.playShuffled(visible, context, title)}
  onqueue={() => player.addToQueue(visible, false)}
>
  {#snippet subtitle()}
    {t('Подборка Sonar')} · {mixes.about(id)}
  {/snippet}
  {#snippet actions()}
    {#if id === 'like'}
      <span class="anchor">
        <button class="tool" class:on={picking} data-picker-toggle aria-expanded={picking} onclick={() => (picking = !picking)}>
          <Icon name="music" size={16} /> {mixes.chosenSeed ? t('Сменить трек') : t('Выбрать трек')}
        </button>
        {#if picking}
          <TrackPicker current={mixes.seed?.ref ?? null} onpick={pick} onclose={() => (picking = false)} />
        {/if}
      </span>
    {/if}
    <button class="tool" disabled={saving || !items.length} onclick={save}>
      <Icon name="playlistAdd" size={16} /> {saving ? t('Сохраняю…') : t('Сохранить как плейлист')}
    </button>
  {/snippet}
  {#snippet tools()}
    <label class="find">
      <Icon name="search" size={15} />
      <input placeholder={t('Найти')} bind:value={filter} spellcheck="false" />
    </label>
  {/snippet}
</CollectionHeader>

<ScrollStick target={tracksEl} />
<div class="tracks" bind:this={tracksEl}>
  {#if loading}
    <div class="skeleton">{#each { length: 8 } as _, i (i)}<div class="sk"></div>{/each}</div>
  {:else if !items.length}
    {#if id === 'like' && !mixes.seed}
      <EmptyState icon="music" title={t('Выбери трек')} text={t('Нажми «Выбрать трек» — соберу похожее на него.')} />
    {:else if id === 'fresh'}
      <EmptyState icon="music" title={t('Пока никого не нашлось')} text={t('Свежих артистов ищу по счётчику прослушиваний SoundCloud. Слушай и лайкай больше — подборка обновится завтра.')} />
    {:else}
      <EmptyState icon="music" title={t('Подборка пока пустая')} text={t('Слушай и лайкай дальше — здесь соберутся треки под твой вкус.')} />
    {/if}
  {:else if !visible.length}
    <EmptyState icon="search" title={t('Ничего не нашлось')} text={t('В «{title}» нет «{query}».', { title, query: filter.trim() })} />
  {:else}
    <div class="list" use:cascade={items[0]?.ref}>
      {#each visible as x, i (x.ref)}
        <TrackRow track={x} note={mixes.why(id, x.ref)} onplay={() => play(i)} />
      {/each}
    </div>
  {/if}
</div>

<style>
  .anchor {
    position: relative;
    display: inline-flex;
  }
  .tool.on {
    color: var(--text);
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
