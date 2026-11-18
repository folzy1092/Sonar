<script lang="ts">
  // Содержимое мини-окна и оверлея (mini.rs): обложка, название, артист, лайк, назад / пауза / вперёд.
  // Тянется мышью за любое место, кроме кнопок; перемотки нет. Двойной клик по обложке — открыть
  // Sonar, крестик при наведении — закрыть. Оверлей (Интерфейс → Оверлей) рисуется по виду из главного
  // окна (`overlay:look`): Карточка — та же плашка, Остров — капсула, Полноэкранный — затемнение и большая
  // карточка по центру (клик мимо или Esc — закрыть).
  import { onMount } from 'svelte'
  import { emit, listen } from '@tauri-apps/api/event'
  import { invoke } from '@tauri-apps/api/core'
  import { getCurrentWindow } from '@tauri-apps/api/window'
  import Icon from '../components/Icon.svelte'
  import PlayPause from '../components/PlayPause.svelte'
  import type { MiniCmd, MiniState } from '../lib/mini.svelte'
  import type { OverlayLook } from '../lib/overlay'
  import { settings } from '../lib/settings.svelte'
  import { t } from '../lib/i18n.svelte'

  let { kind = 'mini' }: { kind?: 'mini' | 'overlay' } = $props()

  /** Мини-окно — всегда карточка, непрозрачность как раньше. */
  const MINI_LOOK: OverlayLook = { mode: 'card', shape: 'rounded', opacity: 94, scale: 100 }

  let s = $state<MiniState>({ title: null, artist: null, cover_url: null, playing: false, liked: false, has: false })
  let look = $state<OverlayLook | null>(null)
  const shown = $derived(kind === 'mini' ? MINI_LOOK : (look ?? MINI_LOOK))
  const zoom = $derived(shown.scale / 100)

  const cmd = (c: MiniCmd) => void emit('mini:cmd', c)

  onMount(() => {
    // язык интерфейса — из настроек (t() читает general.language); вид оверлея — пока не пришёл свой
    void settings.load().then(() => {
      if (kind === 'overlay' && !look) {
        const g = settings.get.bind(settings)
        look = { mode: g('overlay.mode'), shape: g('overlay.shape'), opacity: g('overlay.opacity'), scale: g('overlay.scale') }
      }
    })
    let got = false
    const off = listen<MiniState>('mini:state', (e) => {
      got = true
      s = e.payload
    })
    const offLook = kind === 'overlay' ? listen<OverlayLook>('overlay:look', (e) => (look = e.payload)) : null
    void emit(`${kind}:hello`)
    // главное окно могло не успеть ответить — спрашиваем, пока не придёт состояние
    const retry = setInterval(() => (got ? clearInterval(retry) : void emit(`${kind}:hello`)), 1000)
    const bye = () => void emit(`${kind}:bye`)
    const esc = (e: KeyboardEvent) => e.key === 'Escape' && shown.mode === 'fullscreen' && close()
    window.addEventListener('beforeunload', bye)
    window.addEventListener('keydown', esc)
    return () => {
      void off.then((f) => f())
      void offLook?.then((f) => f())
      clearInterval(retry)
      window.removeEventListener('beforeunload', bye)
      window.removeEventListener('keydown', esc)
    }
  })

  /** Закрыть плашку. Мини-окно возвращает Sonar на экран, оверлей — просто уходит. */
  function close() {
    void emit(`${kind}:bye`)
    // закрывает Rust (destroy); не вышло — закрываемся сами
    const command = kind === 'mini' ? 'mini_window' : 'overlay_window'
    void invoke(command, { show: false }).catch(() => getCurrentWindow().destroy())
  }
</script>

{#snippet art(size: number)}
  <button class="art" style:--size="{size}px" title={t('Открыть Sonar (двойной клик)')} ondblclick={() => invoke('show_main')}>
    {#key s.cover_url}
      {#if s.cover_url}<img src={s.cover_url} alt="" draggable="false" />{:else}<span class="ph"><Icon name="music" size={size * 0.4} /></span>{/if}
    {/key}
  </button>
{/snippet}

{#snippet controls(big: boolean, like: boolean)}
  {@const k = big ? 1.5 : 1}
  <div class="ctl" class:big>
    {#if like}
      <button class="ic like" class:on={s.liked} disabled={!s.has} aria-label={s.liked ? t('Убрать из Любимых') : t('В Любимые')} onclick={() => cmd('like')}>
        <Icon name="heart" size={16 * k} filled={s.liked} />
      </button>
      <button class="ic" disabled={!s.has} aria-label={t('Назад')} onclick={() => cmd('prev')}><Icon name="prev" size={17 * k} filled /></button>
    {/if}
    <button class="play" disabled={!s.has} aria-label={s.playing ? t('Пауза') : t('Играть')} onclick={() => cmd('toggle')}>
      <PlayPause playing={s.playing} size={17 * k} />
    </button>
    <button class="ic" disabled={!s.has} aria-label={t('Вперёд')} onclick={() => cmd('next')}><Icon name="next" size={17 * k} filled /></button>
  </div>
{/snippet}

{#if shown.mode === 'fullscreen'}
  <!-- клик мимо карточки закрывает; с клавиатуры — Esc -->
  <div class="full" role="presentation" style:--a={shown.opacity} onclick={(e) => e.target === e.currentTarget && close()}>
    <div class="stage" class:square={shown.shape === 'square'} style:zoom>
      {@render art(220)}
      {#key s.title}
        <div class="big-meta">
          <b>{s.title ?? t('Ничего не играет')}</b>
          <small>{s.artist ?? 'Sonar'}</small>
        </div>
      {/key}
      {@render controls(true, true)}
    </div>
    <small class="esc">{t('Esc или клик мимо — закрыть')}</small>
  </div>
{:else}
  {@const island = shown.mode === 'island'}
  <div
    class="mini"
    class:island
    class:square={shown.shape === 'square'}
    style:--a={shown.opacity}
    style:--k={zoom}
    style:zoom
    data-tauri-drag-region
  >
    {@render art(island ? 26 : 44)}
    <div class="meta" data-tauri-drag-region>
      {#key s.title}
        <b data-tauri-drag-region>{s.title ?? t('Ничего не играет')}</b>
        {#if !island}<small data-tauri-drag-region>{s.artist ?? 'Sonar'}</small>{/if}
      {/key}
    </div>
    {@render controls(false, !island)}
    <button class="x" aria-label={kind === 'mini' ? t('Закрыть мини-плеер') : t('Закрыть оверлей')} title={t('Закрыть')} onclick={close}><Icon name="x" size={11} /></button>
  </div>
{/if}

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
    /* zoom растягивает и vh — делим, чтобы плашка ровно заняла окно */
    height: calc(100vh / var(--k, 1));
    padding: 0 10px 0 8px;
    border-radius: 14px;
    background: color-mix(in srgb, var(--surface-1) calc(var(--a, 94) * 1%), transparent);
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
  .mini.square {
    border-radius: 4px;
  }
  /* Остров — капсула: обложка-кружок, название и две кнопки */
  .mini.island {
    gap: 8px;
    padding: 0 6px 0 5px;
    border-radius: 999px;
    background: color-mix(in srgb, #000 calc(var(--a, 94) * 1%), transparent);
    color: #fff;
    --text: #fff;
    --text-2: rgb(255 255 255 / 0.75);
    --text-3: rgb(255 255 255 / 0.55);
    --on-text: #000;
  }
  .mini.island.square {
    border-radius: 8px;
  }
  .mini.island .art {
    border-radius: 50%;
  }
  .mini.island .meta b {
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
  }
  .mini.island .play {
    width: 26px;
    height: 26px;
  }
  .art {
    flex: none;
    width: var(--size, 44px);
    height: var(--size, 44px);
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
  .mini.island .x {
    top: 50%;
    right: auto;
    left: 2px;
    translate: 0 -50%;
  }
  /* Полноэкранный: затемнение на весь экран и большая карточка по центру */
  .full {
    position: fixed;
    inset: 0;
    display: grid;
    place-items: center;
    background: color-mix(in srgb, #000 calc(var(--a, 90) * 0.6%), transparent);
    animation: fade 0.3s var(--ease);
  }
  @keyframes fade {
    from {
      opacity: 0;
    }
  }
  .stage {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 18px;
    width: 300px;
    padding: 28px 26px 24px;
    border-radius: 24px;
    background: color-mix(in srgb, var(--surface-1) calc(var(--a, 90) * 1%), transparent);
    border: 1px solid var(--border-strong);
    box-shadow: 0 30px 80px rgb(0 0 0 / 0.45);
    animation: rise 0.42s var(--ease);
  }
  .stage.square {
    border-radius: 6px;
  }
  .stage.square .art {
    border-radius: 3px;
  }
  .stage .art {
    border-radius: 16px;
    box-shadow: 0 12px 40px rgb(0 0 0 / 0.35);
  }
  @keyframes rise {
    from {
      opacity: 0;
      translate: 0 16px;
      scale: 0.94;
    }
  }
  .big-meta {
    display: grid;
    gap: 3px;
    width: 100%;
    text-align: center;
    animation: in 0.3s var(--ease);
  }
  .big-meta b,
  .big-meta small {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .big-meta b {
    font-size: calc(19px * var(--fs, 1));
    font-weight: 700;
  }
  .big-meta small {
    font-size: calc(14px * var(--fs, 1));
    color: var(--text-3);
  }
  .ctl.big {
    gap: 10px;
  }
  .ctl.big .ic {
    width: 42px;
    height: 42px;
    border-radius: 12px;
  }
  .ctl.big .play {
    width: 56px;
    height: 56px;
  }
  .esc {
    position: fixed;
    bottom: 28px;
    left: 0;
    right: 0;
    text-align: center;
    font-size: calc(12px * var(--fs, 1));
    color: rgb(255 255 255 / 0.6);
    pointer-events: none;
  }
  @media (prefers-reduced-motion: reduce) {
    .stage {
      animation: fade 0.3s var(--ease);
    }
  }
</style>
