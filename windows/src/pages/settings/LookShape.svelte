<script lang="ts">
  // Интерфейс → Вид → «Форма» (SETTINGS_NEXT «Вид»): скругление углов и кнопки окна — с живым примером
  // над выбором, «Показывать площадки», масштаб в окне и на весь экран («Авто» — как в окне), анимации.
  import Icon from '../../components/Icon.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { api } from '../../lib/api'
  import { RADII } from '../../theme/look'
  import { windowButtonsLook } from '../../lib/window-buttons'
  import { t } from '../../lib/i18n.svelte'

  const radius = $derived(RADII[settings.get('appearance.corner_radius')] ?? RADII.rounded)
  const mac = $derived(windowButtonsLook(settings.get('appearance.window_buttons'), navigator.platform) === 'macos')

  const PERCENTS = [75, 90, 100, 110, 125]
  const scales = PERCENTS.map((n) => ({ id: n, label: `${n}%` }))
  const fullScales = $derived([{ id: 0, label: t('Авто') }, ...scales])

  function setScale(key: 'appearance.scale_window' | 'appearance.scale_fullscreen', v: number) {
    settings.set(key, v)
    void api.setZoom(key === 'appearance.scale_window' ? 'window' : 'fullscreen', v).catch(() => {})
  }
</script>

<Choice
  title={t('Скругление углов')}
  hint={t('Радиус скругления элементов интерфейса и карточек')}
  wide
  fill
  value={settings.get('appearance.corner_radius')}
  options={[
    { id: 'none' as const, label: t('Нет') },
    { id: 'soft' as const, label: t('Маленькое') },
    { id: 'rounded' as const, label: t('Среднее') },
    { id: 'pill' as const, label: t('Большое') },
  ]}
  onchange={(v) => settings.set('appearance.corner_radius', v)}
>
  {#snippet preview()}
  <!-- живой пример: карточка, две строки трека и кнопка — радиусы как будут в интерфейсе -->
    <div class="demo radius" style:--r-s="{radius[0]}px" style:--r-m="{radius[1]}px" style:--r-l="{radius[2]}px">
      <div class="d-card">
        <span class="d-cover"></span>
        <span class="d-lines"><i></i><i class="short"></i></span>
      </div>
      <div class="d-rows">
        {#each [0, 1] as i (i)}
          <div class="d-row" class:on={i === 0}>
            <span class="d-thumb"></span>
            <span class="d-lines"><i></i><i class="short"></i></span>
            <span class="d-time">3:2{i + 4}</span>
          </div>
        {/each}
        <span class="d-btn">{t('Слушать')}</span>
      </div>
    </div>
  {/snippet}
</Choice>

<Switch
  title={t('Показывать площадки')}
  hint={t('Значок сервиса рядом с длительностью трека')}
  on={settings.get('appearance.show_sources')}
  onchange={(v) => settings.set('appearance.show_sources', v)}
/>

<Choice
  title={t('Кнопки окна')}
  hint={t('Свернуть, развернуть и закрыть — в духе Windows или macOS')}
  wide
  fill
  value={settings.get('appearance.window_buttons')}
  options={[
    { id: 'auto' as const, label: t('Авто') },
    { id: 'windows' as const, label: 'Windows' },
    { id: 'macos' as const, label: 'macOS' },
  ]}
  onchange={(v) => settings.set('appearance.window_buttons', v)}
>
  {#snippet preview()}
  <div class="demo win">
      <div class="w-bar">
        <span class="w-title"><i></i></span>
        {#key mac}
          <span class="w-btns tab-in" class:mac>
            {#if mac}
              <i class="l red"></i><i class="l yellow"></i><i class="l green"></i>
            {:else}
              <Icon name="minus" size={13} stroke={1.8} />
              <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" aria-hidden="true"><rect x="5" y="5" width="14" height="14" rx="2" /></svg>
              <Icon name="x" size={13} stroke={1.8} />
            {/if}
          </span>
        {/key}
      </div>
      <div class="w-body"><span></span><span></span><span></span></div>
    </div>
  {/snippet}
</Choice>

<Choice title={t('Масштаб в окне')} hint={t('Размер интерфейса в обычном окне')} wide fill value={settings.get('appearance.scale_window')} options={scales} onchange={(v) => setScale('appearance.scale_window', v)} />
<Choice
  title={t('Масштаб на весь экран')}
  hint={t('Когда окно развёрнуто; «Авто» — как в окне')}
  wide
  fill
  value={settings.get('appearance.scale_fullscreen')}
  options={fullScales}
  onchange={(v) => setScale('appearance.scale_fullscreen', v)}
/>

<Switch
  title={t('Анимации')}
  hint={t('Плавные переходы, появление списков, всплывашки. Выключено (или «Меньше движения» в Windows) — только прозрачность.')}
  on={settings.get('appearance.animations')}
  onchange={(v) => settings.set('appearance.animations', v)}
/>

<style>
  .demo {
    padding: 14px;
    border-radius: var(--radius-l);
    background: var(--surface-2);
  }
  /* --- скругление --- */
  .radius {
    display: grid;
    grid-template-columns: 120px 1fr;
    gap: 12px;
  }
  .radius * {
    transition: border-radius 0.35s var(--ease);
  }
  .d-card {
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 8px;
    border-radius: var(--r-l);
    background: var(--surface-3);
  }
  .d-cover {
    aspect-ratio: 1;
    border-radius: var(--r-m);
    background: linear-gradient(135deg, var(--accent), color-mix(in srgb, var(--accent) 35%, var(--surface-2)));
  }
  .d-lines {
    display: flex;
    flex: 1;
    flex-direction: column;
    gap: 5px;
    min-width: 0;
  }
  .d-lines i {
    height: 6px;
    border-radius: 3px;
    background: var(--text-3);
    opacity: 0.55;
  }
  .d-lines i.short {
    width: 55%;
    opacity: 0.3;
  }
  .d-rows {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .d-row {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 7px 10px 7px 7px;
    border-radius: var(--r-m);
  }
  .d-row.on {
    background: var(--surface-3);
  }
  .d-thumb {
    flex: none;
    width: 30px;
    height: 30px;
    border-radius: var(--r-s);
    background: color-mix(in srgb, var(--accent) 45%, var(--surface-3));
  }
  .d-time {
    font-size: calc(11px * var(--fs, 1));
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  .d-btn {
    align-self: flex-start;
    margin-top: auto;
    padding: 7px 16px;
    border-radius: var(--r-m);
    background: var(--accent);
    color: var(--accent-ink);
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
  }
  /* --- кнопки окна --- */
  .win {
    padding: 12px 14px 14px;
  }
  .w-bar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    height: 26px;
  }
  .w-title i {
    display: block;
    width: 90px;
    height: 7px;
    border-radius: 4px;
    background: var(--text-3);
    opacity: 0.35;
  }
  .w-btns {
    display: flex;
    align-items: center;
    gap: 12px;
    color: var(--text-2);
  }
  .w-btns.mac {
    gap: 7px;
  }
  .l {
    width: 11px;
    height: 11px;
    border-radius: 50%;
  }
  .red {
    background: #ff5f57;
  }
  .yellow {
    background: #febc2e;
  }
  .green {
    background: #28c840;
  }
  .w-body {
    display: grid;
    grid-template-columns: 0.6fr 2fr 1fr;
    gap: 8px;
    height: 56px;
    margin-top: 8px;
  }
  .w-body span {
    border-radius: var(--radius-m);
    background: var(--surface-3);
  }
</style>
