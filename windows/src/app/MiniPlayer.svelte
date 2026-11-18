<script lang="ts">
  // Мини-плеер в стиле «Гибрид» (reference/pc/гибрид.png, mini.style = hybrid): прогресс — фоном,
  // по центру простые значки без кругов, справа капсула скорость · громкость · очередь · текст.
  import Icon from '../components/Icon.svelte'
  import IconButton from '../components/IconButton.svelte'
  import LoadFx from '../components/LoadFx.svelte'
  import NextUp from '../components/NextUp.svelte'
  import Cover from '../components/Cover.svelte'
  import PlayPause from '../components/PlayPause.svelte'
  import SpeedButton from '../player/SpeedButton.svelte'
  import EqButton from '../player/EqButton.svelte'
  import { scale } from 'svelte/transition'
  import Volume from '../player/Volume.svelte'
  import { player } from '../player/player.svelte'
  import { openRef, router } from './router.svelte'
  import { settingsPanel } from '../pages/settings-section.svelte'
  import { library } from '../lib/library.svelte'
  import { hasSelection } from '../lib/selection'
  import { replay } from '../lib/replay'
  import { settings } from '../lib/settings.svelte'
  import { lyrics } from '../lyrics/lyrics.svelte'
  import { t } from '../lib/i18n.svelte'

  const track = $derived(player.current)
  const duration = $derived(player.durationMs || track?.duration_ms || 0)
  const liked = $derived(library.isLiked(track?.ref))
  const openPlayer = () => !hasSelection() && router.go('player')

  // Прогресс в стиле «Гибрид» — весь фон мини-плеера: клик по пустому месту (не по кнопке, ссылке
  // или тексту) перематывает туда. Только клик (просьба владельца): зажал и повёл — ничего не
  // происходит, чтобы случайно не перемотать.
  let bar: HTMLElement | undefined = $state()
  let ring: SVGCircleElement | undefined = $state()

  // Прогресс рисуется каждый кадр мимо Svelte: `--p` (0…1) на фоне-полосе через transform, кольцу —
  // stroke-dasharray. Позицию плавно ведут часы плеера (player.onFrame), а не шаги timeupdate.
  $effect(() => {
    const el = bar
    const circle = ring
    const d = duration
    if (!el) return
    return player.onFrame((ms) => {
      const p = d ? Math.min(1, Math.max(0, ms / d)) : 0
      el.style.setProperty('--p', String(p))
      circle?.setAttribute('stroke-dasharray', `${p * 100} 100`)
    })
  })
  let press: { x: number; y: number } | null = null
  const isControl = (target: EventTarget | null) =>
    !!(target as HTMLElement | null)?.closest?.('button, a, input, [role="link"], .selectable, .capsule')

  function seekAt(clientX: number) {
    if (!bar || !duration || !track) return
    const r = bar.getBoundingClientRect()
    player.seek(Math.max(0, Math.min(1, (clientX - r.left) / r.width)) * duration)
  }

  function down(e: PointerEvent) {
    press = e.button === 0 && !isControl(e.target) && track ? { x: e.clientX, y: e.clientY } : null
  }

  /** Перемотка — только если отпустили там же, где нажали (клик, а не протяжка). */
  function up(e: PointerEvent) {
    const p = press
    press = null
    if (p && Math.hypot(e.clientX - p.x, e.clientY - p.y) < 5) seekAt(e.clientX)
  }
</script>

<footer
  data-fx-frame
  class="mini bg-{settings.get('mini.background')} progress-{settings.get('mini.progress')}"
  class:round-cover={settings.get('mini.cover_round') >= 100}
  class:seekable={!!track}
  bind:this={bar}
  onpointerdown={down}
  onpointerup={up}
  onpointercancel={() => (press = null)}
>
  <!-- фон и полоса прогресса обрезаются по скруглению отдельным слоем: сам плеер не обрезает
       содержимое, иначе всплывашки эквалайзера и скорости прятались бы под страницей -->
  <div class="clip" aria-hidden="true">
    {#if settings.get('mini.background') === 'cover' && track?.cover_url}
      <!-- фон «Обложка» как у Dotify: сама обложка, чёткая, на всю ширину, затемнена для читаемости -->
      {#key track.cover_url}
        <img class="cover-bg" src={track.cover_url} alt="" />
      {/key}
      <span class="cover-shade"></span>
    {/if}
    {#if settings.get('mini.progress') !== 'cover'}
      <div class="fill"></div>
    {/if}
  </div>

  <div class="left">
    <div class="now">
      <button
        class="art"
        data-fx-cover
        disabled={!track}
        onclick={() => lyrics.open()}
        aria-label={t('Полноэкранный плеер')}
        title={t('Полноэкранный плеер')}
      >
        <Cover url={track?.cover_url} size={46} radius="calc(50% * var(--cover-k, 1))" />
        <LoadFx url={track?.cover_url} />
        {#if settings.get('mini.progress') === 'cover'}
          <!-- прогресс «Вокруг обложки»: кольцо -->
          <svg class="ring" viewBox="0 0 52 52" aria-hidden="true"><circle bind:this={ring} cx="26" cy="26" r="24.5" pathLength="100" stroke-dasharray="0 100" /></svg>
        {/if}
        <span class="expand" aria-hidden="true"><Icon name="expand" size={18} /></span>
      </button>
      <span class="meta selectable" use:replay={track?.ref}>
        <span class="title" role="link" tabindex="-1" onclick={openPlayer} onkeydown={() => {}}>{track?.title ?? t('Ничего не играет')}</span>
        {#if player.fallbackNeeded}
          <!-- трек сервиса без своего потока (Spotify): понятное состояние, по клику — Настройки → Сервисы -->
          <button class="artist fallback" title={t('Настройки → Сервисы')} onclick={() => settingsPanel.show('services')}>{t('Нужен резервный сервис')}</button>
        {:else if player.error}
          <span class="artist err" title={player.error}>{player.error}</span>
        {:else if track}
          <span class="artist">
            <!-- мини-аватарка главного артиста перед именем (решение владельца 2026-11-16) -->
            {#if track.artists[0]?.avatar_url}
              {#key track.artists[0].avatar_url}
                <img class="ava" src={track.artists[0].avatar_url} alt="" draggable="false" />
              {/key}
            {/if}
            {#each track.artists as a, i (a.ref + i)}{#if i},&nbsp;{/if}<span
                class="link"
                role="link"
                tabindex="-1"
                onclick={() => !hasSelection() && openRef(a.ref)}
                onkeydown={() => {}}>{a.name}</span
              >{:else}{track.artist}{/each}
          </span>
        {:else}
          <span class="artist">{t('Найди трек в поиске')}</span>
        {/if}
      </span>
    </div>
    {#if track}
      <IconButton icon="heart" label={liked ? t('Удалить из Любимых') : t('В Любимые')} size={17} filled={liked} active={liked} pulse={liked} onclick={() => library.toggleLike(track)} />
    {/if}
  </div>

  <div class="center">
    <IconButton
      icon={player.repeat === 'one' ? 'repeatOnce' : player.repeat === 'all' ? 'repeat' : 'repeatOff'}
      label={player.repeat === 'off' ? t('Повтор: выкл') : player.repeat === 'all' ? t('Повтор: всё') : t('Повтор: трек')}
      size={18}
      active={player.repeat !== 'off'}
      disabled={!track}
      onclick={() => player.cycleRepeat()}
    />
    <IconButton icon="prev" label={t('Назад')} size={18} filled disabled={!track} onclick={() => player.prev()} />
    <button
      class="play"
      class:loading={player.loading}
      aria-label={player.playing ? t('Пауза') : t('Играть')}
      title={player.playing ? t('Пауза') : t('Играть')}
      disabled={!track}
      onclick={() => player.toggle()}
    >
      <PlayPause playing={player.playing} size={22} />
    </button>
    <IconButton icon="next" label={t('Вперёд')} size={18} filled disabled={!track} onclick={() => player.next()} />
    <IconButton icon="shuffle" label={t('Перемешать')} size={18} active={player.shuffle} disabled={!track} onclick={() => player.toggleShuffle()} />
  </div>

  <div class="right">
    <NextUp float />
    <!-- «Тактиль»: пять светодиодов, по ним бежит огонёк при смене трека (theme/fx.css) -->
    <span class="mini-leds" data-fx-leds aria-hidden="true"><i></i><i></i><i></i><i></i><i></i></span>
    <div class="capsule">
      <EqButton />
      <SpeedButton />
      <Volume />
      <!-- текст и полноэкранный плеер — только когда у трека есть текст -->
      {#if track && lyrics.status === 'ready'}
        <span class="t-btn" transition:scale={{ duration: 200, start: 0.6 }}>
          <IconButton icon="letterT" label={t('Текст и полноэкранный плеер')} size={17} active={lyrics.fullscreen} onclick={() => (lyrics.fullscreen ? lyrics.close() : lyrics.open())} />
        </span>
      {/if}
    </div>
  </div>
</footer>

<style>
  .mini {
    position: relative;
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr);
    align-items: center;
    gap: 16px;
    height: var(--player-h);
    padding: 0 12px 0 8px;
    /* концы капсулы: --cap-k (0 — прямые углы, 1 — полукруг), середина — прямая */
    border-radius: max(var(--radius-l), calc(var(--player-h) / 2 * var(--cap-k, 1)));
    padding-left: calc(8px + 4px * var(--cap-k, 1));
    /* «Сигнал»: мини-плеер — поверхность 2 (palette.ts SURFACE_DECOR) */
    background: var(--mini-bg);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    transition:
      background 0.4s var(--ease),
      border-radius 0.4s var(--ease);
  }
  .clip {
    position: absolute;
    inset: 0;
    border-radius: inherit;
    overflow: hidden;
    pointer-events: none;
  }
  /* mini.background (Настройки → Плеер → Мини плеер): тема / обложка / цвет обложки */
  .mini.bg-cover_color {
    background: color-mix(in srgb, var(--tint) 75%, var(--surface-1));
  }
  .mini.bg-cover {
    background: #000;
    /* второстепенный текст и значки поверх обложки — светлее, чтобы читались на любой картинке */
    --text-2: rgba(255, 255, 255, 0.88);
    --text-3: rgba(255, 255, 255, 0.74);
  }
  .cover-bg {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    object-fit: cover;
    object-position: center 40%;
    filter: brightness(0.82);
    pointer-events: none;
    animation: xfade-in 0.6s var(--ease);
  }
  .cover-shade {
    position: absolute;
    inset: 0;
    pointer-events: none;
    background:
      linear-gradient(90deg, rgba(0, 0, 0, 0.62) 0%, rgba(0, 0, 0, 0.42) 20%, rgba(0, 0, 0, 0.12) 42%, rgba(0, 0, 0, 0.12) 62%, rgba(0, 0, 0, 0.4) 100%);
  }
  /* на светлой обложке название, артист и кнопки должны читаться: белый текст с мягкой тенью */
  .mini.bg-cover .title {
    color: #fff;
  }
  .mini.bg-cover .artist {
    color: rgba(255, 255, 255, 0.8);
  }
  .mini.bg-cover .meta {
    text-shadow:
      0 1px 2px rgba(0, 0, 0, 0.6),
      0 0 14px rgba(0, 0, 0, 0.45);
  }
  .mini.bg-cover :global(button svg) {
    filter: drop-shadow(0 1px 3px rgba(0, 0, 0, 0.55));
  }
  @keyframes xfade-in {
    from {
      opacity: 0;
    }
  }
  /* прогресс «Линия» — тонкая полоска внизу */
  .mini.progress-line .fill {
    top: auto;
    height: 2px;
    background: var(--accent);
  }
  /* на фоне-обложке прогресс должен читаться на любой картинке */
  .mini.bg-cover .fill {
    background: rgba(255, 255, 255, 0.16);
    box-shadow: inset -1px 0 0 rgba(255, 255, 255, 0.35);
  }
  .mini.bg-cover.progress-line .fill {
    height: 3px;
    background: #fff;
    box-shadow: 0 0 8px rgba(0, 0, 0, 0.6);
  }
  .ring {
    position: absolute;
    inset: -3px;
    width: calc(100% + 6px);
    height: calc(100% + 6px);
    transform: rotate(-90deg);
    pointer-events: none;
  }
  .ring circle {
    fill: none;
    stroke: var(--accent);
    stroke-width: 2.5;
    stroke-linecap: round;
  }
  .mini.progress-cover .art {
    overflow: visible;
  }
  /* полоса на всю ширину, уезжает влево: transform не трогает раскладку и рисуется на GPU */
  .fill {
    position: absolute;
    inset: 0;
    transform: translateX(calc((var(--p, 0) - 1) * 100%));
    will-change: transform;
    background: color-mix(in srgb, var(--accent-soft) 60%, var(--hover));
    pointer-events: none;
  }
  .left,
  .center,
  .right {
    position: relative;
  }
  .left {
    display: flex;
    align-items: center;
    gap: 4px;
    min-width: 0;
  }
  .now {
    display: flex;
    align-items: center;
    gap: 12px;
    min-width: 0;
    padding: 4px;
    border-radius: var(--radius-m);
    text-align: left;
  }
  .meta {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .title,
  .artist {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .title {
    font-weight: 600;
  }
  .art {
    position: relative;
    display: grid;
    border-radius: calc(50% * var(--cover-k, 1));
    overflow: hidden;
    /* «Монолит»: свечение цвета обложки за обложкой */
    box-shadow: var(--mono-glow, none);
  }
  .expand {
    border-radius: calc(50% * var(--cover-k, 1));
  }
  /* при наведении на обложку — две стрелки: откроется полноэкранный плеер */
  .expand {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
    background: rgba(0, 0, 0, 0.45);
    color: #fff;
    opacity: 0;
    transition: opacity var(--fast) var(--ease);
  }
  .expand :global(svg) {
    transform: scale(0.7);
    transition: transform var(--normal) var(--ease);
  }
  .art:hover:not(:disabled) .expand {
    opacity: 1;
  }
  .art:hover:not(:disabled) .expand :global(svg) {
    transform: scale(1);
  }
  .art:active:not(:disabled) .expand :global(svg) {
    transform: scale(0.9);
  }
  .title,
  .link {
    cursor: pointer;
  }
  .title:hover,
  .link:hover {
    text-decoration: underline;
    text-underline-offset: 2px;
  }
  .artist {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .ava {
    display: inline-block;
    width: 15px;
    height: 15px;
    margin: 0 6px -3px 0;
    border-radius: 50%;
    object-fit: cover;
    box-shadow: 0 0 0 1px color-mix(in srgb, var(--text) 14%, transparent);
    animation: ava-in var(--normal) var(--ease);
  }
  @keyframes ava-in {
    from {
      opacity: 0;
      scale: 0.6;
    }
  }
  .artist.err {
    color: var(--danger);
  }
  .artist.fallback {
    padding: 0;
    border: 0;
    background: none;
    font: inherit;
    text-align: left;
    color: var(--text-2);
    cursor: pointer;
    text-decoration: underline dotted;
    text-underline-offset: 3px;
    transition: color var(--fast) var(--ease);
  }
  .artist.fallback:hover {
    color: var(--text);
  }
  .center {
    display: flex;
    align-items: center;
    gap: 6px;
  }
  .play {
    display: grid;
    place-items: center;
    width: 38px;
    height: 38px;
    color: var(--text);
    transition: transform var(--fast) var(--ease);
  }
  .play:active:not(:disabled) {
    transform: scale(0.9) translateY(var(--key-shift));
  }
  .play:disabled {
    opacity: 0.35;
    cursor: default;
  }
  .play.loading {
    animation: pulse 1s ease-in-out infinite;
  }
  @keyframes pulse {
    50% {
      opacity: 0.5;
    }
  }
  .right {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 10px;
  }
  .capsule {
    display: flex;
    align-items: center;
    gap: 2px;
    /* одинаковый отступ со всех сторон: круглые кнопки на концах повторяют скругление капсулы */
    padding: 3px;
    border-radius: 999px;
    border: 1px solid var(--border-strong);
  }
  .capsule :global(.icon-btn) {
    width: 32px;
    height: 32px;
    border-radius: 999px;
  }
  .capsule :global(.icon-btn:hover:not(:disabled)) {
    background: none;
  }
  @media (prefers-reduced-motion: reduce) {
    .play.loading {
      animation: none;
    }
    .fill {
      transition: none;
    }
  }
</style>
