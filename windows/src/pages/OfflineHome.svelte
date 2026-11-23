<script lang="ts">
  // Главная в офлайне (docs/OFFLINE.md §8.2): без Sonar Mix, «Для тебя», релизов и всего сетевого.
  // Только то, что играет без сети: недавнее, любимые и всё скачанное / локальное.
  import Icon from '../components/Icon.svelte'
  import Tile from '../components/Tile.svelte'
  import Shelf from '../components/Shelf.svelte'
  import { api, type Track } from '../lib/api'
  import { offline } from '../lib/offline.svelte'
  import { autoplayFromPool } from '../lib/offline-core'
  import { player } from '../player/player.svelte'
  import { t, tn } from '../lib/i18n.svelte'
  import { cascade } from '../lib/cascade'

  /** Сколько треков в каждой полке. */
  const SHELF = 30

  let recent = $state<Track[]>([])
  let favorites = $state<Track[]>([])
  let pool = $state<Track[]>([])

  async function load() {
    const [r, f, p] = await Promise.allSettled([api.recentTracks(SHELF * 2), api.favorites(), offline.pool()])
    if (r.status === 'fulfilled') recent = r.value
    if (f.status === 'fulfilled') favorites = f.value
    if (p.status === 'fulfilled') pool = p.value
  }

  // кэш докачал или вытеснил файл (`offline.refs` сменился) — полки пересобираются
  $effect(() => {
    void offline.refs
    void load()
  })

  const shelves = $derived(
    [
      { id: 'recent', title: t('Недавно играло'), tracks: offline.only(recent).slice(0, SHELF) },
      { id: 'liked', title: t('Любимые офлайн'), tracks: offline.only(favorites).slice(0, SHELF) },
      { id: 'saved', title: t('На этом компьютере'), tracks: pool.slice(0, SHELF) },
    ].filter((s) => s.tracks.length),
  )

  function play(tracks: Track[], i: number, title: string) {
    void player.playList(tracks, i, 'offline', title)
  }

  function shuffleAll() {
    const all = autoplayFromPool(pool, new Set(), () => false, pool.length)
    if (all.length) void player.playList(all, 0, 'offline', t('Всё доступное'))
  }
</script>

<section class="head" use:cascade>
  <span class="badge"><Icon name="wifiOff" size={18} /></span>
  <h1>{t('Офлайн-режим')}</h1>
  <p>
    {t('Играет только то, что есть на этом компьютере')} · {offline.refs.size}
    {tn(offline.refs.size, ['трек', 'трека', 'треков'])}
  </p>
  <div class="actions">
    <button class="listen press" disabled={!pool.length} onclick={shuffleAll}>
      <Icon name="shuffle" size={18} />{t('Перемешать всё')}
    </button>
    <button class="ghost press" onclick={() => offline.set(false)}>{t('Выключить офлайн-режим')}</button>
  </div>
</section>

{#each shelves as s (s.id)}
  <section class="block">
    <h2>{s.title}</h2>
    <Shelf key={s.tracks.length}>
      {#each s.tracks as tr, i (tr.ref)}
        <Tile title={tr.title} subtitle={tr.artist} image={tr.cover_url} source={tr.ref} onclick={() => play(s.tracks, i, s.title)} />
      {/each}
    </Shelf>
  </section>
{:else}
  <p class="empty">{t('Пока ничего нет: послушай треки, пока есть сеть, — они останутся в кэше.')}</p>
{/each}

<style>
  .head {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 10px;
    padding: 24px 0 8px;
  }
  .badge {
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    border-radius: 50%;
    background: var(--plate);
    color: var(--text-2);
  }
  h1 {
    margin: 0;
    font-size: calc(40px * var(--fs, 1));
    font-weight: 800;
  }
  p {
    margin: 0;
    color: var(--text-3);
  }
  .actions {
    display: flex;
    gap: 10px;
    margin-top: 8px;
  }
  .listen,
  .ghost {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 42px;
    padding: 0 20px;
    border-radius: 999px;
    font-weight: 700;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      opacity var(--fast) var(--ease);
  }
  .listen {
    background: var(--accent);
    color: var(--accent-ink);
  }
  .listen:disabled {
    opacity: 0.5;
  }
  .ghost {
    background: var(--plate);
    color: var(--text-2);
  }
  .ghost:hover {
    color: var(--text);
  }
  .block {
    margin-top: 32px;
  }
  h2 {
    font-size: calc(24px * var(--fs, 1));
    font-weight: 800;
    margin: 0 0 14px;
  }
  .empty {
    margin-top: 32px;
    color: var(--text-3);
  }
</style>
