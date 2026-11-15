<script lang="ts">
  // Плеер → Вид по pc/Screenshot_6, 6.1: стиль плеера, выравнивание заголовка, аватары, визуализатор,
  // тип ползунка, обложка. Канвас (видео вместо обложек) — не делаем.
  import Cards from '../../components/settings/Cards.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Group from '../../components/settings/Group.svelte'
  import Soon from '../../components/settings/Soon.svelte'
  import { settings } from '../../lib/settings.svelte'

  const sliders: { id: string; label: string; soon?: boolean }[] = [
    { id: 'normal', label: 'Обычный' },
    { id: 'thin', label: 'Тонкий', soon: true },
    { id: 'smooth', label: 'Плавный', soon: true },
    { id: 'wavy', label: 'Волнистый', soon: true },
    { id: 'wave_bars', label: 'Волновой', soon: true },
  ]
  // столбики «волнового» ползунка — постоянные, чтобы пример не прыгал
  const bars = Array.from({ length: 64 }, (_, i) => 30 + Math.round(60 * Math.abs(Math.sin(i * 1.7) * Math.cos(i * 0.31))))
</script>

<Cards
  title="Стиль плеера"
  hint="Выберите визуальный стиль плеера"
  value="standard"
  options={[
    { id: 'standard', label: 'Обычный', icon: 'grid' },
    { id: 'vinyl', label: 'Пластинка', icon: 'vinyl', soon: true },
    { id: 'large', label: 'Большой', icon: 'photo', soon: true },
  ]}
/>

<Choice
  title="Выравнивание заголовка"
  hint="Выберите выравнивание названия трека"
  icons
  value={settings.get('player.title_align')}
  options={[
    { id: 'left', label: 'Слева', icon: 'alignLeft' },
    { id: 'center', label: 'По центру', icon: 'alignCenter' },
    { id: 'right', label: 'Справа', icon: 'alignRight' },
  ]}
  onchange={(v) => settings.set('player.title_align', v)}
/>
<Switch
  title="Аватарки артистов"
  hint="Отображать аватарки исполнителей перед их именами в плеере и мини плеере"
  on={settings.get('player.artist_avatars')}
  onchange={(v) => settings.set('player.artist_avatars', v)}
/>
<Choice
  title="Визуализатор"
  hint="Где показывать визуализацию звука"
  wide
  fill
  value={settings.get('player.visualizer')}
  options={[
    { id: 'off', label: 'Выкл', icon: 'x' },
    { id: 'bar', label: 'Полоса', icon: 'line' },
    { id: 'cover', label: 'На обложке', icon: 'photo', soon: true },
    { id: 'slider', label: 'На ползунке', icon: 'adjustments', soon: true },
  ]}
  onchange={(v) => settings.set('player.visualizer', v as 'off' | 'bar')}
/>
<Choice
  title="Стиль"
  hint="Выберите стиль визуализации аудио"
  value="wave"
  options={[
    { id: 'wave', label: 'Волна', icon: 'waveform' },
    { id: 'bars', label: 'Столбцы', icon: 'bars', soon: true },
  ]}
/>

<div class="block">
  <b>Тип ползунка</b>
  <small>Выберите стиль ползунка прогресса</small>
  <div class="sliders">
    {#each sliders as s (s.id)}
      <button class="sl" class:on={s.id === 'normal'} disabled={s.soon} title={s.soon ? `${s.label} — скоро` : s.label}>
        <span class="name">{s.label}{#if s.soon}<Soon />{/if}</span>
        <span class="preview {s.id}">
          {#if s.id === 'wavy'}
            <svg viewBox="0 0 200 12" preserveAspectRatio="none"><path d="M0 6 Q 6.25 0 12.5 6 T 25 6 T 37.5 6 T 50 6 T 62.5 6 T 75 6 T 87.5 6 T 100 6" /><line x1="100" y1="6" x2="200" y2="6" /></svg>
          {:else if s.id === 'wave_bars'}
            {#each bars as h, i (i)}<i style:height="{h}%" class:past={i < 32}></i>{/each}
          {:else}
            <i class="fill"></i><i class="knob"></i>
          {/if}
        </span>
      </button>
    {/each}
  </div>
</div>

<Group title="Обложка">
  <Choice
    title="Позиция обложки"
    hint="Выберите где отображается обложка"
    value={settings.get('player.cover_position')}
    options={[
      { id: 'left', label: 'Слева', icon: 'layoutLeft' },
      { id: 'right', label: 'Справа', icon: 'layoutRight' },
    ]}
    onchange={(v) => settings.set('player.cover_position', v)}
  />
  <Switch title="Обложка в обложке" hint="Отображать меньшую обложку внутри основной" on={false} soon />
</Group>

<style>
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
  .sliders {
    display: flex;
    flex-direction: column;
    gap: 2px;
    margin-top: 10px;
  }
  .sl {
    display: flex;
    align-items: center;
    gap: 16px;
    height: 42px;
    padding: 0 10px;
    border-radius: 10px;
    text-align: left;
    color: var(--text-2);
  }
  .sl.on {
    background: var(--surface-3);
    color: var(--text);
  }
  .sl:disabled {
    cursor: default;
  }
  .sl:disabled .preview {
    opacity: 0.5;
  }
  .name {
    width: 120px;
    flex-shrink: 0;
    font-size: 13px;
    font-weight: 600;
    white-space: nowrap;
  }
  .preview {
    position: relative;
    flex: 1;
    height: 14px;
    display: flex;
    align-items: center;
  }
  .preview::before {
    content: '';
    position: absolute;
    left: 0;
    right: 0;
    height: 3px;
    border-radius: 3px;
    background: var(--surface-3);
  }
  .preview.wavy::before,
  .preview.wave_bars::before {
    display: none;
  }
  .fill {
    position: absolute;
    left: 0;
    width: 55%;
    height: 3px;
    border-radius: 3px;
    background: var(--text-2);
  }
  .normal .fill {
    height: 4px;
    background: var(--text);
  }
  .knob {
    display: none;
  }
  .thin .fill {
    height: 2px;
  }
  .thin .knob {
    display: block;
    position: absolute;
    left: calc(55% - 6px);
    width: 12px;
    height: 12px;
    border-radius: 50%;
    background: var(--text-2);
  }
  .smooth .knob {
    display: block;
    position: absolute;
    left: 55%;
    width: 3px;
    height: 14px;
    border-radius: 2px;
    background: var(--text-2);
  }
  svg {
    width: 100%;
    height: 12px;
    fill: none;
    stroke: var(--text-2);
    stroke-width: 2;
  }
  svg line {
    stroke: var(--surface-3);
  }
  .wave_bars {
    gap: 2px;
    height: 24px;
  }
  .wave_bars i {
    flex: 1;
    border-radius: 1px;
    background: var(--surface-3);
  }
  .wave_bars i.past {
    background: var(--text-2);
  }
</style>
