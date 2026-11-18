<script lang="ts">
  // Интерфейс → Стиль (STYLE_PROMPT §5): сверху готовые стили и свои сохранённые — карточки с живой
  // миниатюрой (при наведении играет смена трека стиля), ниже «Свой стиль» — по строке на ось.
  // Любая правка оси сразу применяется и делает стиль «Своим»; его можно сохранить под своим именем,
  // переименовать и удалить, или сбросить к ближайшему готовому стилю.
  import Choice from '../../components/settings/Choice.svelte'
  import Select from '../../components/settings/Select.svelte'
  import Divider from '../../components/settings/Divider.svelte'
  import Icon from '../../components/Icon.svelte'
  import Cover from '../../components/Cover.svelte'
  import LoadFx from '../../components/LoadFx.svelte'
  import StylePreview from '../../components/StylePreview.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { theme, PRESETS } from '../../theme/theme.svelte'
  import { FONTS, fontLabel, type FontCategory } from '../../theme/look'
  import { CUSTOM_STYLE_PREFIX, nearestPreset, STYLES, SURFACE_LABELS, UNSAVED, axisKey, type AxisName, type StyleAxes } from '../../theme/style'
  import { trackChange } from '../../lib/track-fx.svelte'
  import { likeFx } from '../../lib/like-fx'
  import { toast } from '../../lib/toast.svelte'
  import { t } from '../../lib/i18n.svelte'
  import type { RGB } from '../../theme/palette'

  const current = $derived(settings.get('appearance.style'))
  const customs = $derived(settings.get('appearance.custom_styles'))
  const axes = $derived(theme.axes)
  // цвет миниатюр — текущей темы (под трек или готовой)
  const accent = $derived<RGB | null>(
    settings.get('appearance.cover_theme') ? theme.accent : (PRESETS.find((p) => p.id === settings.get('appearance.preset'))?.accent ?? null),
  )

  /** Перезапуск миниатюры при наведении: id карточки → счётчик. */
  let plays = $state<Record<string, number>>({})
  const replay = (id: string) => (plays = { ...plays, [id]: (plays[id] ?? 0) + 1 })

  function setAxis<A extends AxisName>(a: A, v: StyleAxes[A]) {
    settings.set(axisKey(a), v as never)
  }

  const allFonts = (['modern', 'bright', 'serif', 'mono', 'system'] as FontCategory[]).flatMap((c) => FONTS[c]).filter((f) => f !== 'default')
  const fontOptions = allFonts.map((f) => ({ id: f, label: fontLabel(f) }))

  const ANIMS = $derived([
    { id: 'echo' as const, label: t('Эхо') },
    { id: 'signal' as const, label: t('Сигнал') },
    { id: 'edge' as const, label: t('Грань') },
    { id: 'tactile' as const, label: t('Тактиль') },
    { id: 'monolith' as const, label: t('Монолит') },
  ])

  // ---- сохранить / переименовать ----
  let naming = $state<string | null>(null) // null — не вводим; '' — новый; 'custom:<id>' — переименование
  let name = $state('')
  function startSave() {
    naming = ''
    name = ''
  }
  function startRename(id: string, old: string) {
    naming = id
    name = old
  }
  function commitName() {
    if (naming === null) return
    if (naming === '') {
      theme.saveStyle(name)
      toast.show(t('Стиль сохранён'))
    } else theme.renameStyle(naming, name)
    naming = null
  }
  const base = $derived(nearestPreset(axes))

  // ---- «Показать» ----
  let heart: HTMLSpanElement | undefined = $state()
  let liked = $state(false)
  function showLike() {
    liked = false
    requestAnimationFrame(() => {
      liked = true
      if (heart && !likeFx(heart)) {
        heart.classList.remove('like-pop')
        void heart.offsetWidth
        heart.classList.add('like-pop')
      }
    })
  }
  let demo = $state<number | null>(null)
  function showLoading() {
    const steps = [0, 0.35, 0.6, 0.9, 1]
    steps.forEach((s, i) => setTimeout(() => (demo = s), i * 360))
    setTimeout(() => (demo = null), steps.length * 360 + 250)
  }
  // демо смены трека — на своей обложке в кнопке, а не на окне, которое отъехало за настройками
  let trackDemo = $state<HTMLElement>()
  function showTrack() {
    replay('now')
    if (trackDemo) trackChange(trackDemo)
  }
</script>

{#snippet card(id: string, title: string, a: StyleAxes, own: boolean)}
  <div class="card" class:on={current === id} role="group" onmouseenter={() => replay(id)}>
    <button class="pick" onclick={() => theme.applyStyle(id)} aria-pressed={current === id}>
      <StylePreview axes={a} {accent} light={theme.light} play={plays[id] ?? 0} />
      <span class="name">{title}</span>
    </button>
    {#if own}
      <span class="tools">
        <button title={t('Переименовать')} aria-label={t('Переименовать')} onclick={() => startRename(id, title)}><Icon name="pencil" size={13} /></button>
        <button title={t('Удалить')} aria-label={t('Удалить')} onclick={() => theme.deleteStyle(id)}><Icon name="trash" size={13} /></button>
      </span>
    {/if}
  </div>
{/snippet}

<p class="caption">{t('Готовые стили')}</p>
<div class="cards">
  {#each STYLES as s (s.id)}
    {@render card(s.id, t(s.title), s.axes, false)}
  {/each}
  {#each customs as c (c.id)}
    {@render card(CUSTOM_STYLE_PREFIX + c.id, c.name, c.axes, true)}
  {/each}
  {#if current === UNSAVED}
    <div class="card on" role="group" onmouseenter={() => replay('now')}>
      <div class="pick">
        <StylePreview {axes} {accent} light={theme.light} play={plays.now ?? 0} />
        <span class="name">{t('Свой — не сохранён')}</span>
      </div>
    </div>
  {/if}
</div>

<div class="actions">
  {#if naming !== null}
    <!-- svelte-ignore a11y_autofocus -->
    <input
      class="name-in"
      placeholder={naming === '' ? t('Название стиля') : t('Новое название')}
      maxlength="40"
      bind:value={name}
      autofocus
      onkeydown={(e) => {
        if (e.key === 'Enter') commitName()
        if (e.key === 'Escape') naming = null
      }}
    />
    <button class="btn primary" onclick={commitName}>{naming === '' ? t('Сохранить') : t('Переименовать')}</button>
    <button class="btn" onclick={() => (naming = null)}>{t('Отмена')}</button>
  {:else}
    <button class="btn primary" onclick={startSave}><Icon name="bookmark" size={14} /> {t('Сохранить как свой стиль')}</button>
    {#if current === UNSAVED}
      <button class="btn" onclick={() => theme.applyStyle(base.id)}><Icon name="refresh" size={14} /> {t('Сбросить к стилю «{name}»', { name: t(base.title) })}</button>
    {/if}
  {/if}
</div>

<Divider />

<p class="caption">{t('Свой стиль — из частей разных стилей')}</p>

<Choice
  title={t('Поверхности')}
  hint={t('Фон, карточки, рамки, тени и блики')}
  wide
  fill
  value={axes.surface}
  options={(Object.keys(SURFACE_LABELS) as StyleAxes['surface'][]).map((s) => ({ id: s, label: t(SURFACE_LABELS[s]) }))}
  onchange={(v) => setAxis('surface', v)}
/>
<Select title={t('Шрифт интерфейса')} hint={t('Обычный текст, кнопки, списки')} value={axes.font} options={fontOptions} onchange={(v) => setAxis('font', v)} />
<Select title={t('Шрифт заголовков')} hint={t('Sonar Mix, названия страниц и разделов')} value={axes.font_display} options={fontOptions} onchange={(v) => setAxis('font_display', v)} />
<Choice
  title={t('Оформление заголовков')}
  hint={t('«Журнал» — капсом, крупно, с номерами разделов')}
  value={axes.title_style}
  options={[
    { id: 'plain' as const, label: t('Обычное') },
    { id: 'editorial' as const, label: t('Журнал') },
  ]}
  onchange={(v) => setAxis('title_style', v)}
/>
<Choice
  title={t('Толщина линий')}
  hint={t('Иконки левой панели и кнопок плеера')}
  value={axes.icon_stroke}
  options={[
    { id: 1.5 as const, label: '1.5' },
    { id: 1.75 as const, label: '1.75' },
    { id: 2 as const, label: '2' },
  ]}
  onchange={(v) => setAxis('icon_stroke', v)}
/>
<Choice
  title={t('Скругления')}
  hint={t('Углы карточек, кнопок и обложек')}
  value={settings.get('appearance.corner_radius')}
  options={[
    { id: 'none' as const, label: t('Нет') },
    { id: 'soft' as const, label: t('Малые') },
    { id: 'rounded' as const, label: t('Средние') },
    { id: 'pill' as const, label: t('Большие') },
  ]}
  onchange={(v) => settings.set('appearance.corner_radius', v)}
/>

<div class="axis">
  <Choice title={t('Смена трека')} hint={t('Как обложка и заголовок встречают новый трек')} wide fill value={axes.anim_track} options={[...ANIMS, { id: 'fade' as const, label: t('Плавно') }]} onchange={(v) => setAxis('anim_track', v)} />
  <button class="show" onclick={showTrack}>
    <span class="demo-cover" bind:this={trackDemo}><span class="demo-frame" data-fx-cover data-fx-frame><Cover url={null} size={22} radius="6px" /></span></span> {t('Показать')}
  </button>
</div>
<div class="axis">
  <Choice title={t('Лайк')} hint={t('Что происходит с сердцем, когда ставишь лайк')} wide fill value={axes.anim_like} options={[...ANIMS, { id: 'pop' as const, label: t('Прыжок') }]} onchange={(v) => setAxis('anim_like', v)} />
  <!-- сердце стоит отдельно, справа от него — место под эффект лайка, чтобы он не ложился на подпись -->
  <span class="show-row">
    <span class="demo-heart" bind:this={heart}><Icon name="heart" size={15} filled={liked} /></span>
    <button class="show" onclick={showLike}><Icon name="play" size={12} filled /> {t('Показать')}</button>
  </span>
</div>
<Choice
  title={t('Выбранный раздел')}
  hint={t('Как отмечен раздел в левой панели')}
  wide
  fill
  value={axes.anim_nav}
  options={[
    { id: 'dot' as const, label: t('Заливка') },
    { id: 'capsule' as const, label: t('Капсула') },
    { id: 'plate' as const, label: t('Плашка') },
    { id: 'inset' as const, label: t('Утопленная') },
  ]}
  onchange={(v) => setAxis('anim_nav', v)}
/>
<Choice
  title={t('Прогресс')}
  hint={t('Как нарисован ползунок времени')}
  wide
  fill
  value={axes.progress_look}
  options={[
    { id: 'line' as const, label: t('Линия') },
    { id: 'wave' as const, label: t('Волна') },
    { id: 'groove' as const, label: t('Желобок') },
  ]}
  onchange={(v) => setAxis('progress_look', v)}
/>
<div class="axis">
  <Choice
    title={t('Загрузка трека')}
    hint={t('Пока трек грузится — по настоящему прогрессу')}
    wide
    fill
    value={axes.loading}
    options={[
      { id: 'color' as const, label: t('Цвет возвращается') },
      { id: 'ring' as const, label: t('Круг') },
    ]}
    onchange={(v) => setAxis('loading', v)}
  />
  <button class="show" onclick={showLoading}>
    <span class="demo-cover"><Cover url={null} size={22} radius="6px" /><LoadFx demo={demo} /></span> {t('Показать')}
  </button>
</div>

<style>
  .caption {
    margin: 4px 0 10px;
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
  }
  .cards {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(196px, 1fr));
    gap: 10px;
  }
  .card {
    position: relative;
    border-radius: var(--radius-l);
    border: 1.5px solid transparent;
    transition: border-color var(--fast) var(--ease);
  }
  .card.on {
    border-color: var(--accent);
  }
  .pick {
    display: flex;
    flex-direction: column;
    gap: 6px;
    width: 100%;
    padding: 5px;
    text-align: left;
    border-radius: inherit;
    transition: background var(--fast) var(--ease);
  }
  button.pick:hover {
    background: var(--hover);
  }
  .name {
    padding: 0 4px 2px;
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
  }
  .tools {
    position: absolute;
    right: 8px;
    bottom: 6px;
    display: flex;
    gap: 2px;
    opacity: 0;
    transition: opacity var(--fast) var(--ease);
  }
  .card:hover .tools {
    opacity: 1;
  }
  .tools button {
    display: grid;
    place-items: center;
    width: 24px;
    height: 24px;
    border-radius: 7px;
    color: var(--text-2);
  }
  .tools button:hover {
    background: var(--hover);
    color: var(--text);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px;
    margin: 12px 0 2px;
  }
  .btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 32px;
    padding: 0 12px;
    border-radius: var(--radius-m);
    background: var(--surface-2);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    box-shadow: var(--key);
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .btn:hover {
    background: var(--surface-3);
  }
  .btn:active {
    transform: scale(0.97) translateY(var(--key-shift));
  }
  .btn.primary {
    background: var(--accent);
    color: var(--accent-ink);
  }
  .name-in {
    flex: 1;
    min-width: 160px;
    height: 32px;
    padding: 0 12px;
    border-radius: var(--radius-m);
    border: 1px solid var(--border);
    background: var(--surface-1);
    color: var(--text);
    font: inherit;
  }
  .name-in:focus {
    outline: none;
    border-color: var(--accent);
  }
  .axis {
    position: relative;
  }
  .show {
    position: absolute;
    top: 9px;
    right: 0;
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 26px;
    padding: 0 10px;
    border-radius: 999px;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
    background: var(--surface-2);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .show:hover {
    color: var(--text);
    background: var(--surface-3);
  }
  .show-row {
    position: absolute;
    top: 9px;
    right: 0;
    display: inline-flex;
    align-items: center;
    gap: 40px;
  }
  .show-row .show {
    position: static;
  }
  .demo-heart {
    display: grid;
    color: var(--accent);
  }
  .demo-frame {
    display: grid;
    border-radius: 6px;
  }
  .demo-cover {
    position: relative;
    display: grid;
    overflow: hidden;
    border-radius: 6px;
  }
</style>
