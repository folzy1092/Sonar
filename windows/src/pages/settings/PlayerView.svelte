<script lang="ts">
  // Плеер → Вид по pc/Screenshot_6, 6.1: стиль плеера, выравнивание заголовка, аватары, визуализатор,
  // тип ползунка, обложка. Канвас (видео вместо обложек) — не делаем.
  import Cards from '../../components/settings/Cards.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Group from '../../components/settings/Group.svelte'
  import More from '../../components/settings/More.svelte'
  import Soon from '../../components/settings/Soon.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { t } from '../../lib/i18n.svelte'

  const sliders: { id: 'normal' | 'thin' | 'smooth' | 'wavy' | 'wave_bars'; label: string; soon?: boolean }[] = [
    { id: 'normal', label: 'Обычный' },
    { id: 'thin', label: 'Тонкий' },
    { id: 'smooth', label: 'Плавный' },
    { id: 'wavy', label: 'Волнистый' },
    { id: 'wave_bars', label: 'Волновой' },
  ]
  // столбики «волнового» ползунка — постоянные, чтобы пример не прыгал
  const bars = Array.from({ length: 64 }, (_, i) => 30 + Math.round(60 * Math.abs(Math.sin(i * 1.7) * Math.cos(i * 0.31))))
</script>

<Cards
  title={t('Стиль плеера')}
  hint={t('Выберите визуальный стиль плеера')}
  value={settings.get('player.style')}
  options={[
    { id: 'standard' as const, label: t('Обычный'), icon: 'grid' },
    { id: 'vinyl' as const, label: t('Пластинка'), icon: 'vinyl' },
    { id: 'large' as const, label: t('Большой'), icon: 'photo' },
  ]}
  onchange={(v) => settings.set('player.style', v)}
/>

<Choice
  title={t('Выравнивание заголовка')}
  hint={t('Выберите выравнивание названия трека')}
  icons
  value={settings.get('player.title_align')}
  options={[
    { id: 'left', label: t('Слева'), icon: 'alignLeft' },
    { id: 'center', label: t('По центру'), icon: 'alignCenter' },
    { id: 'right', label: t('Справа'), icon: 'alignRight' },
  ]}
  onchange={(v) => settings.set('player.title_align', v)}
/>
<Switch
  title={t('Аватарки артистов')}
  hint={t('Отображать аватарки исполнителей перед их именами в плеере и мини плеере')}
  on={settings.get('player.artist_avatars')}
  onchange={(v) => settings.set('player.artist_avatars', v)}
/>
<Choice
  title={t('Визуализатор')}
  hint={t('Где показывать визуализацию звука')}
  wide
  fill
  value={settings.get('player.visualizer')}
  options={[
    { id: 'off', label: t('Выкл'), icon: 'x' },
    { id: 'bar', label: t('Полоса'), icon: 'line' },
    { id: 'cover', label: t('На обложке'), icon: 'photo' },
    { id: 'slider', label: t('На ползунке'), icon: 'adjustments' },
  ]}
  onchange={(v) => settings.set('player.visualizer', v)}
/>
<Choice
  title={t('Вид визуализатора')}
  hint={t('Выберите стиль визуализации аудио')}
  value={settings.get('player.visualizer_style')}
  options={[
    { id: 'wave', label: t('Волна'), icon: 'waveform' },
    { id: 'bars', label: t('Столбцы'), icon: 'bars' },
  ]}
  onchange={(v) => settings.set('player.visualizer_style', v)}
/>

<More>
  <Switch
    title={t('Спектр в полноэкранном плеере')}
    hint={t('Тихая волна звука на дне экрана, за текстом. С «Меньше движения» не рисуется')}
    on={settings.get('player.visualizer_full')}
    onchange={(v) => settings.set('player.visualizer_full', v)}
  />
  <Switch
    title={t('Почему этот трек')}
    hint={t('Под артистом у треков Sonar Mix — откуда трек: похож на твой лайк, разведка, забытый любимый')}
    on={settings.get('player.wave_why')}
    onchange={(v) => settings.set('player.wave_why', v)}
  />

  <div class="block">
    <b>{t('Тип ползунка')}</b>
    <small>{t('Выберите стиль ползунка прогресса')}</small>
    <div class="sliders">
      {#each sliders as s (s.id)}
        <button class="sl" class:on={s.id === settings.get('player.slider')} disabled={s.soon} title={t(s.label)} onclick={() => settings.set('player.slider', s.id)}>
          <span class="name">{t(s.label)}{#if s.soon}<Soon />{/if}</span>
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

  <Group title={t('Обложка')} hint={t('Обложка на странице плеера')}>
    <Choice
      title={t('Позиция обложки')}
      hint={t('Выберите где отображается обложка')}
      value={settings.get('player.cover_position')}
      options={[
        { id: 'left', label: t('Слева'), icon: 'layoutLeft' },
        { id: 'right', label: t('Справа'), icon: 'layoutRight' },
      ]}
      onchange={(v) => settings.set('player.cover_position', v)}
    />
    <Switch title={t('Обложка в обложке')} hint={t('Отображать меньшую обложку внутри основной')} on={settings.get('player.pip_cover')} onchange={(v) => settings.set('player.pip_cover', v)} />
  </Group>
</More>

<style>
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
    font-size: calc(13px * var(--fs, 1));
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
