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
  import { FONT_CATEGORIES, FONTS, fontCategory, fontLabel, fontStack, type FontCategory } from '../../theme/look'

  const cover = $derived(settings.get('appearance.cover_theme'))
  const preset = $derived(settings.get('appearance.preset'))
  const font = $derived(settings.get('appearance.font'))
  let category = $state<FontCategory>(fontCategory(settings.get('appearance.font')))

  /** Образец темы: два кружка — фон и акцент (как в Dotify). */
  function swatch(c: RGB | null, black = false): [string, string] {
    if (!c) return ['#f5f5f6', black ? '#000' : '#26262b']
    const t = themeFrom(c)
    return [css(t.accent), css(t.bg)]
  }

  function setScale(key: 'appearance.scale_window' | 'appearance.scale_fullscreen', v: number) {
    settings.set(key, v)
    void api.setZoom(key === 'appearance.scale_window' ? 'window' : 'fullscreen', v).catch(() => {})
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
  title="Тема"
  hint="Выберите цветовую схему интерфейса"
  icons
  value="dark"
  options={[
    { id: 'dark', label: 'Тёмная', icon: 'moon' },
    { id: 'light', label: 'Светлая', icon: 'sun', soon: true },
    { id: 'system', label: 'Как в системе', icon: 'monitor', soon: true },
  ]}
/>

<p class="caption">Готовые темы</p>
<div class="themes">
  {@render tile('Под трек', swatch(theme.accent ?? [196, 164, 132]), cover, () => theme.setEnabled(true))}
  {#each PRESETS as p (p.id)}
    {@render tile(p.title, swatch(p.accent, p.black), !cover && preset === p.id, () => theme.setPreset(p.id))}
  {/each}
</div>

<Divider />

<Switch title="Прозрачность" hint="Эффекты прозрачности и размытия окна" on={false} soon />
<Slider title="Непрозрачность" value={100} min={0} max={100} unit="%" onchange={() => {}} soon />
<Slider title="Размытие стекла" hint="Радиус размытия заднего плана под окном" value={0} min={0} max={40} unit="px" onchange={() => {}} soon />

<Divider />

<div class="block">
  <b>Шрифт</b>
  <small>Семейство шрифта</small>
  <div class="cats" use:indicator={{ key: category, kind: 'pill' }}>
    {#each FONT_CATEGORIES as c (c.id)}
      <button class:on={category === c.id} onclick={() => (category = c.id)}>{c.label}</button>
    {/each}
  </div>
  {#key category}
    <div class="chips tab-in">
      {#each FONTS[category] as f (f)}
        <button class="chip" class:on={font === f} style:font-family={fontStack(f) ?? 'var(--font)'} onclick={() => settings.set('appearance.font', f)}>
          {fontLabel(f)}
        </button>
      {/each}
      <button class="chip" disabled title="Свой шрифт — скоро"><Icon name="download" size={13} /> Свой</button>
    </div>
  {/key}
  <div class="sample" style:font-family={fontStack(font) ?? 'var(--font)'}>Sonar — Съешь ещё этих мягких французских булок да выпей же чаю</div>
</div>

<Choice
  title="Размер шрифта"
  hint="Базовый размер шрифта интерфейса"
  wide
  fill
  soon
  value={16}
  options={[12, 14, 16, 18, 20].map((n) => ({ id: n, label: String(n), sub: n === 16 ? 'Авто' : undefined }))}
/>
<Choice
  title="Жирность шрифта"
  hint="Плотность начертания текста"
  wide
  fill
  soon
  value="auto"
  options={[{ id: 'auto', label: 'Авто' }, ...['400', '500', '600', '700'].map((n) => ({ id: n, label: n }))]}
/>

<Divider />

<Cards
  title="Скругление углов"
  hint="Радиус скругления элементов интерфейса и карточек"
  scroll
  value={settings.get('appearance.corner_radius')}
  options={[
    { id: 'none', label: 'Нет' },
    { id: 'soft', label: 'Маленькое' },
    { id: 'rounded', label: 'Среднее' },
    { id: 'pill', label: 'Большое' },
  ]}
  onchange={(v) => settings.set('appearance.corner_radius', v)}
/>

<Divider />

<Choice title="Масштаб в окне" hint="Размер интерфейса в обычном окне" wide value={settings.get('appearance.scale_window')} options={scales} onchange={(v) => setScale('appearance.scale_window', v)} />
<Choice
  title="Масштаб на весь экран"
  hint="Размер интерфейса, когда окно развёрнуто"
  wide
  value={settings.get('appearance.scale_fullscreen')}
  options={scales}
  onchange={(v) => setScale('appearance.scale_fullscreen', v)}
/>

<Divider />

<Switch
  title="Анимации"
  hint="Плавные переходы, появление списков, всплывашки. Выключено (или «Меньше движения» в Windows) — только прозрачность."
  on={settings.get('appearance.animations')}
  onchange={(v) => settings.set('appearance.animations', v)}
/>

<style>
  .caption {
    margin: 14px 0 8px;
    font-size: 12px;
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
    font-size: 11px;
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
    font-size: 14px;
    font-weight: 600;
  }
  .block small {
    font-size: 12px;
    color: var(--text-3);
  }
  .cats {
    display: flex;
    margin-top: 10px;
    padding: 3px;
    border-radius: 10px;
    border: 1px solid var(--border);
  }
  .cats :global(.tab-ind.pill) {
    border-radius: 7px;
    background: var(--surface-3);
  }
  .cats button {
    flex: 1;
    height: 30px;
    border-radius: 7px;
    font-size: 12px;
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
    font-size: 13px;
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
    font-size: 15px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
