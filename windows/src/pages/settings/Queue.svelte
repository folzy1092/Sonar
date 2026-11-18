<script lang="ts">
  // Карточка «Очередь» на странице «Плеер» (SETTINGS_NEXT «Плеер» п. 6, с 2026-11-18 — не отдельный
  // раздел): что вернуть при запуске, показ очереди, её положение (плитки со схемой окна) и вид,
  // «Продолжать очередь» похожими, «Добавлять следующие».
  import PreviewTiles from '../../components/settings/PreviewTiles.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Tiles from '../../components/settings/Tiles.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { t } from '../../lib/i18n.svelte'

  const frame = $derived({
    tabs: settings.get('tabs.position'),
    style: settings.get('tabs.style'),
    mini: settings.get('mini.style') === 'off' ? ('none' as const) : settings.get('mini.position'),
  })
</script>

<Choice
  title={t('При запуске')}
  hint={t('Что вернуть при открытии приложения')}
  wide
  value={settings.get('general.restore')}
  options={[
    { id: 'none', label: t('Ничего'), icon: 'x' },
    { id: 'track', label: t('Трек'), icon: 'music' },
    { id: 'queue', label: t('Очередь'), icon: 'queue' },
  ]}
  onchange={(v) => settings.set('general.restore', v)}
/>
<Switch title={t('Показывать очередь')} hint={t('Отображать панель очереди')} on={settings.get('queue.show')} onchange={(v) => settings.set('queue.show', v)} />
<Switch
  title={t('Предпросмотр следующего трека')}
  hint={t('За 10 секунд до конца — карточка «Дальше» с названием следующего')}
  on={settings.get('queue.preview')}
  onchange={(v) => settings.set('queue.preview', v)}
/>
<Tiles
  title={t('Положение очереди')}
  hint={t('Где открывается панель очереди')}
  value={settings.get('queue.position')}
  options={[
    { id: 'bottom' as const, label: t('Снизу') },
    { id: 'left' as const, label: t('Слева') },
    { id: 'right' as const, label: t('Справа') },
  ].map((o) => ({ ...o, diagram: { ...frame, queue: o.id } }))}
  onchange={(v) => settings.set('queue.position', v)}
/>
{#snippet viewTile(id: 'normal' | 'extended', on: boolean)}
  <span class="rows" class:ext={id === 'extended'} class:on>
    {#each [0, 1, 2] as i (i)}
      <span class="r">{#if id === 'extended'}<i class="c"></i>{/if}<i class="t" style:width="{70 - i * 12}%"></i></span>
    {/each}
  </span>
{/snippet}
<PreviewTiles
  title={t('Вид очереди')}
  hint={t('Выберите режим отображения треков в списке очереди')}
  cols={2}
  value={settings.get('queue.view')}
  options={[
    { id: 'normal' as const, label: t('Обычный') },
    { id: 'extended' as const, label: t('Развернутый') },
  ]}
  tile={viewTile}
  onchange={(v) => settings.set('queue.view', v)}
/>
<Switch
  title={t('Продолжать очередь')}
  hint={t('Как в SoundCloud: после любой очереди — поиска, Любимых, плейлиста — играют похожие треки')}
  on={settings.get('general.similar_autoplay')}
  onchange={(v) => settings.set('general.similar_autoplay', v)}
/>
<Switch
  title={t('Добавлять следующие')}
  hint={t('Нажатый трек ставит в очередь и треки после него')}
  on={settings.get('queue.add_following')}
  onchange={(v) => settings.set('queue.add_following', v)}
/>

<style>
  .rows {
    display: flex;
    flex-direction: column;
    gap: 5px;
    width: 70%;
  }
  .r {
    display: flex;
    align-items: center;
    gap: 6px;
    height: 7px;
    transition: height var(--normal) var(--ease);
  }
  .ext .r {
    height: 12px;
  }
  .c {
    width: 12px;
    height: 12px;
    flex-shrink: 0;
    border-radius: 3px;
    background: var(--surface-3);
  }
  .t {
    height: 3px;
    border-radius: 2px;
    background: var(--text-3);
    transition: background var(--fast) var(--ease);
  }
  .on .t {
    background: var(--text-2);
  }
</style>
