<script lang="ts">
  // Интерфейс → Вид (pc/Screenshot_1): «Под трек» и готовые темы, анимации, масштаб окна.
  import Icon from '../../components/Icon.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Slider from '../../components/settings/Slider.svelte'
  import Group from '../../components/settings/Group.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { api } from '../../lib/api'
  import { PRESETS, theme } from '../../theme/theme.svelte'
  import { css, themeFrom, type RGB } from '../../theme/palette'

  const cover = $derived(settings.get('appearance.cover_theme'))
  const preset = $derived(settings.get('appearance.preset'))

  /** Образец темы: два кружка — фон и акцент (как в Dotify). */
  function swatch(c: RGB | null, black = false): [string, string] {
    if (!c) return ['#f5f5f6', black ? '#000' : '#26262b']
    const t = themeFrom(c)
    return [css(t.accent), css(t.bg)]
  }

  function setScale(v: number) {
    settings.set('appearance.scale_window', v)
    void api.setZoom(v / 100).catch(() => {})
  }
</script>

{#snippet tile(title: string, colors: [string, string], on: boolean, pick: () => void)}
  <button class="theme" class:on onclick={pick}>
    <span class="dots"><i style:background={colors[1]}></i><i style:background={colors[0]}></i></span>
    <span>{title}</span>
    {#if on}<span class="tick"><Icon name="check" size={13} /></span>{/if}
  </button>
{/snippet}

<Group title="Готовые темы">
  <div class="themes">
    {@render tile('Под трек', swatch(theme.accent ?? [196, 164, 132]), cover, () => theme.setEnabled(true))}
    {#each PRESETS as p (p.id)}
      {@render tile(p.title, swatch(p.accent, p.black), !cover && preset === p.id, () => theme.setPreset(p.id))}
    {/each}
  </div>
</Group>

<Group title="Движение">
  <Switch
    title="Анимации"
    hint="Плавные переходы, появление списков, всплывашки. Выключено (или «Меньше движения» в Windows) — только прозрачность."
    on={settings.get('appearance.animations')}
    onchange={(v) => settings.set('appearance.animations', v)}
  />
</Group>

<Group title="Масштаб">
  <Slider
    title="Масштаб окна"
    hint="Размер всего интерфейса"
    value={settings.get('appearance.scale_window')}
    min={75}
    max={125}
    step={5}
    unit="%"
    onchange={setScale}
  />
</Group>

<style>
  .themes {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 8px;
  }
  .theme {
    position: relative;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    padding: 14px 4px 10px;
    border-radius: 12px;
    background: var(--plate);
    border: 1px solid var(--border);
    font-size: 11px;
    font-weight: 600;
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      border-color var(--fast) var(--ease),
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
    border-color: var(--border-strong);
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
  .tick {
    position: absolute;
    top: 5px;
    right: 6px;
    color: var(--accent);
    animation: tick-in var(--normal) var(--ease);
  }
  @keyframes tick-in {
    from {
      opacity: 0;
      transform: scale(0.4);
    }
  }
</style>
