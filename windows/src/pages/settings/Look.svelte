<script lang="ts">
  // Интерфейс → Вид по pc/Screenshot_1–3: тема, готовые темы, прозрачность и стекло, шрифт (категории,
  // семейства, пример), размер и жирность, скругление углов, масштаб в окне и на весь экран.
  import Icon from '../../components/Icon.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Slider from '../../components/settings/Slider.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Cards from '../../components/settings/Cards.svelte'
  import Divider from '../../components/settings/Divider.svelte'
  import { indicator } from '../../lib/indicator'
  import { settings } from '../../lib/settings.svelte'
  import { api } from '../../lib/api'
  import { PRESETS, theme } from '../../theme/theme.svelte'
  import { css, themeFrom, type RGB } from '../../theme/palette'
  import { CUSTOM_PREFIX, FONT_CATEGORIES, FONTS, fontCategory, fontLabel, fontStack, type FontCategory } from '../../theme/look'
  import { saveCustomFont } from '../../theme/custom-font'
  import { toast } from '../../lib/toast.svelte'
  import { t } from '../../lib/i18n.svelte'

  const cover = $derived(settings.get('appearance.cover_theme'))
  const preset = $derived(settings.get('appearance.preset'))
  const font = $derived(settings.get('appearance.font'))
  let category = $state<FontCategory>(fontCategory(settings.get('appearance.font')))

  /** Образец темы: два кружка — фон и акцент (как в Dotify). */
  function swatch(c: RGB | null, black = false): [string, string] {
    if (!c) return ['#f5f5f6', black ? '#000' : '#26262b']
    const th = themeFrom(c, settings.get('appearance.surface'), theme.light)
    return [css(th.accent), css(th.bg)]
  }

  function setScale(key: 'appearance.scale_window' | 'appearance.scale_fullscreen', v: number) {
    settings.set(key, v)
    void api.setZoom(key === 'appearance.scale_window' ? 'window' : 'fullscreen', v).catch(() => {})
  }

  let filePick: HTMLInputElement | undefined = $state()
  const custom = $derived(font.startsWith(CUSTOM_PREFIX))

  /** «Свой» — файл шрифта с компьютера; выбирается сразу, хранится в IndexedDB. */
  async function pickFont(e: Event) {
    const input = e.currentTarget as HTMLInputElement
    const file = input.files?.[0]
    input.value = ''
    if (!file) return
    try {
      const name = await saveCustomFont(file)
      settings.set('appearance.font', CUSTOM_PREFIX + name)
      toast.show(t('Шрифт «{name}» подключён', { name }))
    } catch {
      toast.show(t('Не получилось прочитать шрифт — нужен файл .ttf, .otf, .woff или .woff2'))
    }
  }

  const scales = [75, 90, 100, 110, 125].map((n) => ({ id: n, label: `${n}%` }))
</script>

{#snippet tile(title: string, colors: [string, string], on: boolean, pick: () => void)}
  <button class="theme" class:on onclick={pick}>
    <span class="dots"><i style:background={colors[0]}></i><i style:background={colors[1]}></i></span>
    <span>{title}</span>
  </button>
{/snippet}

<Choice
  title={t('Тема')}
  hint={t('Выберите цветовую схему интерфейса')}
  icons
  value={settings.get('appearance.mode')}
  options={[
    { id: 'dark' as const, label: t('Тёмная'), icon: 'moon' },
    { id: 'light' as const, label: t('Светлая'), icon: 'sun' },
    { id: 'system' as const, label: t('Как в системе'), icon: 'monitor' },
  ]}
  onchange={(v) => settings.set('appearance.mode', v)}
/>

<p class="caption">{t('Готовые темы')}</p>
<div class="themes">
  {@render tile(t('Под трек'), swatch(theme.accent ?? [196, 164, 132]), cover, () => theme.setEnabled(true))}
  {#each PRESETS as p (p.id)}
    {@render tile(p.title, swatch(p.accent, p.black), !cover && preset === p.id, () => theme.setPreset(p.id))}
  {/each}
</div>

<Divider />

<Switch
  title={t('Прозрачность')}
  hint={t('Под окном — системное стекло (Windows 11 — Mica, Windows 10 — Acrylic)')}
  on={settings.get('appearance.glass')}
  onchange={(v) => settings.set('appearance.glass', v)}
/>
{#if settings.get('appearance.glass')}
  <Slider
    title={t('Непрозрачность')}
    hint={t('Насколько плотные фон окна и карточки')}
    value={settings.get('appearance.opacity')}
    min={15}
    max={100}
    unit="%"
    onchange={(v) => settings.set('appearance.opacity', v)}
  />
  <Slider
    title={t('Размытие стекла')}
    hint={t('Радиус размытия под панелями и меню')}
    value={settings.get('appearance.glass_blur')}
    min={0}
    max={40}
    unit="px"
    onchange={(v) => settings.set('appearance.glass_blur', v)}
  />
{/if}

<Divider />

<div class="block">
  <b>{t('Шрифт')}</b>
  <small>{t('Семейство шрифта')}</small>
  <div class="cats" use:indicator={{ key: category, kind: 'pill' }}>
    {#each FONT_CATEGORIES as c (c.id)}
      <button class:on={category === c.id} onclick={() => (category = c.id)}>{t(c.label)}</button>
    {/each}
  </div>
  {#key category}
    <div class="chips tab-in">
      {#each FONTS[category] as f (f)}
        <button class="chip" class:on={font === f} style:font-family={fontStack(f) ?? 'var(--font)'} onclick={() => settings.set('appearance.font', f)}>
          {t(fontLabel(f))}
        </button>
      {/each}
      {#if custom}
        <button class="chip on" style:font-family={fontStack(font)}>{fontLabel(font)}</button>
      {/if}
      <button class="chip" title={t('Свой шрифт с компьютера (.ttf, .otf, .woff, .woff2)')} onclick={() => filePick?.click()}>
        <Icon name="cloudUp" size={13} /> {t('Свой')}
      </button>
    </div>
  {/key}
  <input bind:this={filePick} type="file" accept=".ttf,.otf,.woff,.woff2" hidden onchange={pickFont} />
  <div class="sample" style:font-family={fontStack(font) ?? 'var(--font)'}>{t('Sonar — Съешь ещё этих мягких французских булок да выпей же чаю')}</div>
</div>

<Choice
  title={t('Размер шрифта')}
  hint={t('Базовый размер шрифта интерфейса')}
  wide
  fill
  value={settings.get('appearance.font_size')}
  options={[12, 14, 16, 18, 20].map((n) => ({ id: n, label: String(n), sub: n === 16 ? t('Авто') : undefined }))}
  onchange={(v) => settings.set('appearance.font_size', v)}
/>
<Choice
  title={t('Жирность шрифта')}
  hint={t('Плотность начертания обычного текста')}
  wide
  fill
  value={settings.get('appearance.font_weight')}
  options={[{ id: 'auto' as const, label: t('Авто') }, ...(['400', '500', '600', '700'] as const).map((n) => ({ id: n, label: n }))]}
  onchange={(v) => settings.set('appearance.font_weight', v)}
/>

<Divider />

<Cards
  title={t('Скругление углов')}
  hint={t('Радиус скругления элементов интерфейса и карточек')}
  scroll
  value={settings.get('appearance.corner_radius')}
  options={[
    { id: 'none', label: t('Нет') },
    { id: 'soft', label: t('Маленькое') },
    { id: 'rounded', label: t('Среднее') },
    { id: 'pill', label: t('Большое') },
  ]}
  onchange={(v) => settings.set('appearance.corner_radius', v)}
/>

<Divider />

<Choice title={t('Масштаб в окне')} hint={t('Размер интерфейса в обычном окне')} wide value={settings.get('appearance.scale_window')} options={scales} onchange={(v) => setScale('appearance.scale_window', v)} />
<Choice
  title={t('Масштаб на весь экран')}
  hint={t('Размер интерфейса, когда окно развёрнуто')}
  wide
  value={settings.get('appearance.scale_fullscreen')}
  options={scales}
  onchange={(v) => setScale('appearance.scale_fullscreen', v)}
/>

<Divider />

<Switch
  title={t('Анимации')}
  hint={t('Плавные переходы, появление списков, всплывашки. Выключено (или «Меньше движения» в Windows) — только прозрачность.')}
  on={settings.get('appearance.animations')}
  onchange={(v) => settings.set('appearance.animations', v)}
/>

<style>
  .caption {
    margin: 14px 0 8px;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-3);
  }
  .themes {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 8px;
  }
  .theme {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    padding: 14px 4px 10px;
    border-radius: 12px;
    background: var(--plate);
    font-size: calc(11px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .theme:hover {
    background: var(--hover);
  }
  .theme:active {
    transform: scale(0.95);
  }
  .theme.on {
    background: var(--surface-3);
    color: var(--text);
  }
  .dots {
    display: flex;
  }
  .dots i {
    width: 20px;
    height: 20px;
    border-radius: 50%;
    transition: background 0.6s ease;
  }
  .dots i + i {
    margin-left: -7px;
  }
  .block {
    display: flex;
    flex-direction: column;
    gap: 3px;
    padding: 9px 0;
  }
  .block b {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  .block small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .cats {
    display: flex;
    margin-top: 10px;
    padding: 3px;
    border-radius: 10px;
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  .cats :global(.tab-ind.pill) {
    border-radius: 7px;
    background: var(--surface-3);
  }
  .cats button {
    flex: 1;
    height: 30px;
    border-radius: 7px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    transition: color var(--fast) var(--ease);
  }
  .cats button.on {
    color: var(--text);
    font-weight: 600;
  }
  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin-top: 12px;
  }
  .chip {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 32px;
    padding: 0 12px;
    border-radius: 999px;
    background: var(--plate);
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .chip:hover:not(:disabled) {
    background: var(--hover);
    color: var(--text);
  }
  .chip:active:not(:disabled) {
    transform: scale(0.95);
  }
  .chip.on {
    background: var(--surface-3);
    color: var(--text);
  }
  .chip:disabled {
    opacity: 0.45;
    cursor: default;
  }
  .sample {
    margin-top: 12px;
    padding: 12px 14px;
    border-radius: 12px;
    background: var(--plate);
    font-size: calc(15px * var(--fs, 1));
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
