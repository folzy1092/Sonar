<script lang="ts">
  // Интерфейс → Вид (SETTINGS_NEXT «Вид», 2026-11-18): карточки Тема · Прозрачность · Текст · Форма · Вкладки.
  // Всё видно сразу, сеткой, без прокрутки вбок. Текст — LookText, форма с живыми примерами — LookShape,
  // вкладки (бывший отдельный пункт) — TabsView.
  import Switch from '../../components/settings/Switch.svelte'
  import Slider from '../../components/settings/Slider.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Card from '../../components/settings/Card.svelte'
  import LookText from './LookText.svelte'
  import LookShape from './LookShape.svelte'
  import TabsView from './TabsView.svelte'
  import { rise } from '../../lib/motion'
  import { settings } from '../../lib/settings.svelte'
  import { PRESETS, theme } from '../../theme/theme.svelte'
  import { COVER_STRENGTHS, css, themeFrom, type CoverStrength, type RGB } from '../../theme/palette'
  import { t } from '../../lib/i18n.svelte'

  const cover = $derived(settings.get('appearance.cover_theme'))
  const preset = $derived(settings.get('appearance.preset'))

  /** Образец темы: два кружка — фон и акцент. */
  function swatch(c: RGB | null, black = false): [string, string] {
    if (!c) return ['#f5f5f6', black ? '#000' : '#26262b']
    const th = themeFrom(c, settings.get('appearance.surface'), theme.light)
    return [css(th.accent), css(th.bg)]
  }

  const STRENGTH_LABELS: Record<CoverStrength, string> = { weak: 'Слабо', medium: 'Средне', strong: 'Сильно' }
  const strengths = $derived(COVER_STRENGTHS.map((id) => ({ id, label: t(STRENGTH_LABELS[id]) })))
</script>

{#snippet tile(title: string, colors: [string, string], on: boolean, pick: () => void)}
  <button class="theme" class:on onclick={pick}>
    <span class="dots"><i style:background={colors[0]}></i><i style:background={colors[1]}></i></span>
    <span>{title}</span>
  </button>
{/snippet}

<Card>
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
  <p class="caption">{t('Цвет')}</p>
  <div class="themes">
    {@render tile(t('Под трек'), swatch(theme.accent ?? [196, 164, 132]), cover, () => theme.setEnabled(true))}
    {#each PRESETS as p (p.id)}
      {@render tile(p.title, swatch(p.accent, p.black), !cover && preset === p.id, () => theme.setPreset(p.id))}
    {/each}
  </div>
  {#if cover}
    <div transition:rise={{ y: 6 }}>
      <Choice
        title={t('Сила темы под обложку')}
        hint={t('Насколько фон и карточки темнеют под тёмную обложку и светлеют под светлую')}
        wide
        fill
        value={settings.get('appearance.cover_strength')}
        options={strengths}
        onchange={(v) => settings.set('appearance.cover_strength', v)}
      />
    </div>
  {/if}
</Card>

<Card title={t('Прозрачность')}>
  <Switch
    title={t('Прозрачность')}
    hint={t('Под окном — системное стекло (Windows 11 — Mica, Windows 10 — Blur)')}
    on={settings.get('appearance.glass')}
    onchange={(v) => settings.set('appearance.glass', v)}
  />
  {#if settings.get('appearance.glass')}
    <div transition:rise={{ y: 6 }}>
      <Slider
        title={t('Непрозрачность')}
        hint={t('Насколько плотные фон окна и карточки')}
        value={settings.get('appearance.opacity')}
        min={15}
        max={100}
        unit="%"
        onchange={(v) => settings.set('appearance.opacity', v)}
      />
    </div>
  {/if}
</Card>

<Card title={t('Текст')}><LookText /></Card>
<Card title={t('Форма')}><LookShape /></Card>
<Card title={t('Вкладки')}><TabsView /></Card>

<style>
  .caption {
    margin: 6px 0 8px;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-3);
  }
  .themes {
    display: grid;
    /* до четырёх в ряд, не уже 96px */
    grid-template-columns: repeat(auto-fill, minmax(min(100%, max(96px, (100% - 3 * 8px) / 4)), 1fr));
    gap: 8px;
    padding-bottom: 12px;
  }
  .theme {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    padding: 14px 4px 10px;
    border-radius: 12px;
    background: var(--surface-2);
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
</style>
