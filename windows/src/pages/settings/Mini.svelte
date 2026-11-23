<script lang="ts">
  import { offline } from '../../lib/offline.svelte'
  // Интерфейс → Мини плеер (SETTINGS_NEXT «Мини плеер»): сверху — живой пример (настоящий мини плеер),
  // ниже карточки. Стиль и фон — превью с обложкой играющего трека, позиция — значки окна, прогресс —
  // можно несколько сразу, обложка и форма — две кнопки. Тонкое скругление — в «Ещё настройки».
  import Card from '../../components/settings/Card.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import PreviewTiles from '../../components/settings/PreviewTiles.svelte'
  import Slider from '../../components/settings/Slider.svelte'
  import More from '../../components/settings/More.svelte'
  import MiniPreview from '../../components/settings/MiniPreview.svelte'
  import { player } from '../../player/player.svelte'
  import { settings, MINI_PRESETS, type MiniProgress, type MiniStyle } from '../../lib/settings.svelte'
  import { t } from '../../lib/i18n.svelte'
  import { MINI_POSITION_GLYPHS } from './mini-glyphs'

  type Bg = 'theme' | 'cover' | 'cover_color'

  // живой пример: пока тянут ползунок — показываем значение под пальцем, отпустили — сохраняем
  let capLive = $state<number | null>(null)
  let coverLive = $state<number | null>(null)
  const cover = $derived(offline.src(player.current?.cover_url) ?? null)
  const progress = $derived(settings.get('mini.progress'))
  const coverRound = $derived(settings.get('mini.cover_round'))
  const shapeRound = $derived(settings.get('mini.shape_round'))

  /** Прогресс: нажатый вариант включается или гаснет, но хотя бы один остаётся. */
  function toggleProgress(id: MiniProgress) {
    const next = progress.includes(id) ? progress.filter((p) => p !== id) : [...progress, id]
    if (next.length) settings.set('mini.progress', next)
  }

  /** Как выглядит вариант стиля: его фон, прогресс, обложка и форма. */
  const look = (id: MiniStyle) => (id === 'off' ? null : MINI_PRESETS[id])
</script>

{#snippet bar(bg: Bg, prog: readonly MiniProgress[], round: boolean, capsule: boolean)}
  <span class="bar bg-{bg}" class:capsule style:--art={cover ? `url("${cover}")` : null}>
    {#if prog.includes('background')}<i class="fill"></i>{/if}
    {#if prog.includes('line')}<i class="fill line"></i>{/if}
    <span class="art" class:round class:ring={prog.includes('cover')}></span>
    <span class="txt"><i class="t1"></i><i class="t2"></i></span>
    <span class="dot"></span>
  </span>
{/snippet}

{#snippet styleTile(id: MiniStyle)}
  {@const p = look(id)}
  {#if p}
    {@render bar(p.bg, p.progress, p.cover === 'circle', p.shape === 'capsule')}
  {:else}
    <span class="none"></span>
  {/if}
{/snippet}

{#snippet bgTile(id: Bg)}
  {@render bar(id, progress, coverRound >= 100, shapeRound >= 100)}
{/snippet}

{#snippet progressTile(id: MiniProgress, on: boolean)}
  <span class="solo" class:live={on}>{@render bar('theme', [id], id === 'cover', id === 'cover')}</span>
{/snippet}

<MiniPreview shape={capLive ?? shapeRound} cover={coverLive ?? coverRound} />

<Card>
  <PreviewTiles
    title={t('Стиль')}
    hint={t('Готовый набор: фон, прогресс, обложка и форма')}
    cols={5}
    value={settings.get('mini.style')}
    options={[
      { id: 'off' as const, label: t('Отключено') },
      { id: 'full' as const, label: t('Полный') },
      { id: 'rounded' as const, label: t('Закругленный') },
      { id: 'hybrid' as const, label: t('Гибрид') },
      { id: 'deck' as const, label: t('Дек') },
    ]}
    tile={styleTile}
    onchange={(v) => settings.setMiniStyle(v)}
  />
  <Choice
    title={t('Позиция')}
    hint={t('Где мини плеер в окне. Плавающий можно перетащить')}
    wide
    fill
    value={settings.get('mini.position')}
    options={[
      { id: 'top' as const, label: t('Сверху'), svg: MINI_POSITION_GLYPHS.top },
      { id: 'bottom' as const, label: t('Снизу'), svg: MINI_POSITION_GLYPHS.bottom },
      { id: 'bottom_full' as const, label: t('Во всю ширину'), svg: MINI_POSITION_GLYPHS.bottom_full },
      { id: 'floating' as const, label: t('Плавающий'), svg: MINI_POSITION_GLYPHS.floating },
    ]}
    onchange={(v) => settings.set('mini.position', v)}
  />
</Card>

<Card title={t('Вид')}>
  <PreviewTiles
    title={t('Фон')}
    hint={t('Чем залит мини плеер')}
    cols={3}
    value={settings.get('mini.background')}
    options={[
      { id: 'theme' as const, label: t('Тема') },
      { id: 'cover' as const, label: t('Обложка') },
      { id: 'cover_color' as const, label: t('Цвет обложки') },
    ]}
    tile={bgTile}
    onchange={(v) => settings.set('mini.background', v)}
  />
  <PreviewTiles
    title={t('Прогресс')}
    hint={t('Как видно, сколько прошло. Можно выбрать несколько')}
    cols={3}
    value={progress}
    options={[
      { id: 'line' as const, label: t('Линия') },
      { id: 'background' as const, label: t('Фоном') },
      { id: 'cover' as const, label: t('Вокруг обложки') },
    ]}
    tile={progressTile}
    onchange={toggleProgress}
  />
  <Choice
    title={t('Обложка')}
    hint={t('Форма обложки в мини плеере')}
    value={coverRound >= 100 ? 'circle' : 'default'}
    options={[
      { id: 'default', label: t('По умолчанию') },
      { id: 'circle', label: t('Круглая') },
    ]}
    onchange={(v) => settings.setMiniCover(v)}
  />
  <Choice
    title={t('Форма')}
    hint={t('Концы мини плеера и панели вкладок')}
    value={shapeRound >= 100 ? 'capsule' : 'default'}
    options={[
      { id: 'default', label: t('По умолчанию') },
      { id: 'capsule', label: t('Капсула') },
    ]}
    onchange={(v) => settings.setMiniShape(v)}
  />
</Card>

<More>
  <Slider
    title={t('Скругление формы')}
    hint={t('Скругление концов мини плеера и панели вкладок: 100% — капсула')}
    value={shapeRound}
    min={0}
    max={100}
    step={5}
    unit="%"
    oninput={(v) => (capLive = v)}
    onchange={(v) => {
      settings.set('mini.shape_round', v)
      capLive = null
    }}
  />
  <Slider
    title={t('Скругление обложки')}
    hint={t('Скругление обложки в мини плеере: 100% — круг')}
    value={coverRound}
    min={0}
    max={100}
    step={5}
    unit="%"
    oninput={(v) => (coverLive = v)}
    onchange={(v) => {
      settings.set('mini.cover_round', v)
      coverLive = null
    }}
  />
</More>

<style>
  /* набросок мини плеера: обложка, две строки текста, кнопка; фон и прогресс — как у варианта */
  .bar {
    --art-bg: var(--art, linear-gradient(135deg, var(--accent), var(--accent-soft)));
    position: relative;
    display: flex;
    align-items: center;
    gap: 6px;
    width: 86%;
    height: 26px;
    padding: 0 7px 0 4px;
    overflow: hidden;
    border-radius: 6px;
    background: var(--surface-2);
    border: 1px solid var(--card-line);
    transition:
      border-radius var(--normal) var(--ease),
      background var(--normal) var(--ease);
  }
  .bar.capsule {
    border-radius: 999px;
    padding-left: 5px;
  }
  .bar.bg-cover_color {
    background: color-mix(in srgb, var(--tint) 75%, var(--surface-1));
  }
  .bar.bg-cover {
    background: var(--art-bg) center / cover;
  }
  .bar.bg-cover::before {
    content: '';
    position: absolute;
    inset: 0;
    background: rgb(0 0 0 / 0.45);
    backdrop-filter: blur(6px);
  }
  .fill {
    position: absolute;
    inset: 0 auto 0 0;
    width: 46%;
    background: color-mix(in srgb, var(--text) 9%, transparent);
  }
  .fill.line {
    inset: auto auto 0 0;
    height: 2px;
    background: var(--accent);
  }
  .art {
    position: relative;
    flex-shrink: 0;
    width: 18px;
    height: 18px;
    border-radius: 4px;
    background: var(--art-bg) center / cover;
    transition: border-radius var(--normal) var(--ease);
  }
  .art.round {
    border-radius: 50%;
  }
  .art.ring {
    box-shadow:
      0 0 0 1.5px var(--surface-2),
      0 0 0 3px var(--accent);
  }
  .txt {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 3px;
    flex: 1;
    min-width: 0;
  }
  .txt i {
    display: block;
    height: 3px;
    border-radius: 2px;
    background: var(--text-2);
    opacity: 0.8;
  }
  .t1 {
    width: 70%;
  }
  .t2 {
    width: 45%;
    opacity: 0.45 !important;
  }
  .bg-cover .txt i {
    background: #fff;
  }
  .dot {
    position: relative;
    flex-shrink: 0;
    width: 9px;
    height: 9px;
    border-radius: 50%;
    background: var(--text-2);
  }
  .bg-cover .dot {
    background: #fff;
  }
  .none {
    width: 70%;
    height: 22px;
    border-radius: 999px;
    border: 1.5px dashed var(--border);
  }
  /* выбранный прогресс оживает: заливка и линия идут вперёд */
  .solo {
    display: contents;
  }
  .solo.live .fill {
    animation: run 2.4s var(--ease) infinite alternate;
  }
  @keyframes run {
    from {
      width: 22%;
    }
    to {
      width: 78%;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .solo.live .fill {
      animation: none;
    }
  }
</style>
