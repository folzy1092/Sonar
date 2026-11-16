<script lang="ts">
  // Содержимое мини-окна (mini.rs): обложка, название, артист, лайк, назад / пауза / вперёд.
  // Тянется мышью за любое место, кроме кнопок; перемотки нет. Двойной клик по обложке — открыть
  // Sonar, крестик при наведении — закрыть мини-окно.
  import { onMount } from 'svelte'
  import { emit, listen } from '@tauri-apps/api/event'
  import { invoke } from '@tauri-apps/api/core'
  import { getCurrentWindow } from '@tauri-apps/api/window'
  import Icon from '../components/Icon.svelte'
  import PlayPause from '../components/PlayPause.svelte'
  import type { MiniCmd, MiniState } from '../lib/mini.svelte'
  import { settings } from '../lib/settings.svelte'
  import { t } from '../lib/i18n.svelte'

  let s = $state<MiniState>({ title: null, artist: null, cover_url: null, playing: false, liked: false, has: false })

  const cmd = (c: MiniCmd) => void emit('mini:cmd', c)

  onMount(() => {
    // язык интерфейса — из настроек (t() читает general.language)
    void settings.load()
    let got = false
    const off = listen<MiniState>('mini:state', (e) => {
      got = true
      s = e.payload
    })
    void emit('mini:hello')
    // главное окно могло не успеть ответить — спрашиваем, пока не придёт состояние
    const retry = setInterval(() => (got ? clearInterval(retry) : void emit('mini:hello')), 1000)
    const bye = () => void emit('mini:bye')
    window.addEventListener('beforeunload', bye)
    return () => {
      void off.then((f) => f())
      clearInterval(retry)
      window.removeEventListener('beforeunload', bye)
    }
  })

  /** Закрыть плашку — Sonar возвращается на экран. */
  function close() {
    void emit('mini:bye')
    // закрывает Rust (destroy) и возвращает Sonar; не вышло — закрываемся сами
    void invoke('mini_window', { show: false }).catch(() => getCurrentWindow().destroy())
  }
</script>

<div class="mini" data-tauri-drag-region>
  <button class="art" title={t('Открыть Sonar (двойной клик)')} ondblclick={() => invoke('show_main')}>
    {#key s.cover_url}
      {#if s.cover_url}<img src={s.cover_url} alt="" draggable="false" />{:else}<span class="ph"><Icon name="music" size={18} /></span>{/if}
    {/key}
  </button>
  <div class="meta" data-tauri-drag-region>
    {#key s.title}
      <b data-tauri-drag-region>{s.title ?? t('Ничего не играет')}</b>
      <small data-tauri-drag-region>{s.artist ?? 'Sonar'}</small>
    {/key}
  </div>
  <div class="ctl">
    <button class="ic like" class:on={s.liked} disabled={!s.has} aria-label={s.liked ? t('Убрать из Любимых') : t('В Любимые')} onclick={() => cmd('like')}>
      <Icon name="heart" size={16} filled={s.liked} />
    </button>
    <button class="ic" disabled={!s.has} aria-label={t('Назад')} onclick={() => cmd('prev')}><Icon name="prev" size={17} filled /></button>
    <button class="play" disabled={!s.has} aria-label={s.playing ? t('Пауза') : t('Играть')} onclick={() => cmd('toggle')}>
      <PlayPause playing={s.playing} size={17} />
    </button>
    <button class="ic" disabled={!s.has} aria-label={t('Вперёд')} onclick={() => cmd('next')}><Icon name="next" size={17} filled /></button>
  </div>
  <button class="x" aria-label={t('Закрыть мини-плеер')} title={t('Закрыть')} onclick={close}><Icon name="x" size={11} /></button>
</div>

<style>
  :global(html.mini-window),
  :global(html.mini-window body) {
    background: transparent;
  }
  .mini {
    position: relative;
    display: flex;
    align-items: center;
    gap: 10px;
    height: 100vh;
    padding: 0 10px 0 8px;
    border-radius: 14px;
    background: color-mix(in srgb, var(--surface-1) 94%, transparent);
    border: 1px solid var(--border-strong);
    overflow: hidden;
    cursor: grab;
    animation: in 0.28s var(--ease);
  }
  @keyframes in {
    from {
      opacity: 0;
      scale: 0.96;
    }
  }
  .art {
    flex: none;
    width: 44px;
    height: 44px;
    border-radius: 9px;
    overflow: hidden;
    cursor: pointer;
  }
  .art img,
  .ph {
    display: grid;
    place-items: center;
    width: 100%;
    height: 100%;
    object-fit: cover;
    background: var(--surface-3);
    color: var(--text-3);
    animation: in 0.3s var(--ease);
  }
  .meta {
    flex: 1;
    min-width: 0;
    display: grid;
  }
  .meta b,
  .meta small {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
    animation: in 0.3s var(--ease);
  }
  .meta b {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 700;
  }
  .meta small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .ctl {
    display: flex;
    align-items: center;
    gap: 2px;
  }
  .ic {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    border-radius: 8px;
    color: var(--text-2);
    transition:
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .ic:hover:not(:disabled) {
    color: var(--text);
  }
  .ic:active:not(:disabled),
  .play:active:not(:disabled) {
    transform: scale(0.9);
  }
  .like.on {
    color: var(--accent);
  }
  .play {
    display: grid;
    place-items: center;
    width: 34px;
    height: 34px;
    margin: 0 2px;
    border-radius: 50%;
    background: var(--text);
    color: var(--on-text);
    transition: transform var(--fast) var(--ease);
  }
  button:disabled {
    opacity: 0.4;
    cursor: default;
  }
  .x {
    position: absolute;
    top: 3px;
    right: 3px;
    display: grid;
    place-items: center;
    width: 16px;
    height: 16px;
    border-radius: 50%;
    background: var(--surface-3);
    color: var(--text-2);
    opacity: 0;
    transition: opacity var(--fast) var(--ease);
  }
  .mini:hover .x {
    opacity: 1;
  }
</style>
