<script lang="ts">
  // Плеер → Мини плеер по pc/Screenshot_8, 9, 30: стиль-пресет (меняет фон, прогресс, обложку и форму,
  // как у Dotify), позиция, фон, прогресс, обложка, форма. Сверху — живой пример (настоящий мини
  // плеер), позиция — плитки со схемой окна, редкое — в «Ещё настройки» (NEXT_PROMPT «Этап 0» п. 4–5).
  import Cards from '../../components/settings/Cards.svelte'
  import Tiles from '../../components/settings/Tiles.svelte'
  import Slider from '../../components/settings/Slider.svelte'
  import More from '../../components/settings/More.svelte'
  import MiniPreview from '../../components/settings/MiniPreview.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { t } from '../../lib/i18n.svelte'

  // живой пример: пока тянут ползунок — показываем значение под пальцем, отпустили — сохраняем
  let capLive = $state<number | null>(null)
  let coverLive = $state<number | null>(null)
  const tabs = $derived(settings.get('tabs.position'))
  const tabStyle = $derived(settings.get('tabs.style'))
</script>

<MiniPreview shape={capLive ?? settings.get('mini.shape_round')} cover={coverLive ?? settings.get('mini.cover_round')} />

<Cards
  title={t('Стиль')}
  hint={t('Готовый набор: фон, прогресс, обложка и форма')}
  scroll
  value={settings.get('mini.style')}
  options={[
    { id: 'off', label: t('Отключено'), icon: 'x' },
    { id: 'full', label: t('Полный'), icon: 'grid' },
    { id: 'rounded', label: t('Закругленный'), icon: 'circle' },
    { id: 'hybrid', label: t('Гибрид'), icon: 'vinyl' },
    { id: 'deck', label: t('Дек'), icon: 'photo' },
  ]}
  onchange={(v) => settings.setMiniStyle(v)}
/>

<Tiles
  title={t('Позиция')}
  hint={t('Где мини плеер в окне')}
  value={settings.get('mini.position')}
  options={[
    { id: 'top' as const, label: t('Сверху') },
    { id: 'bottom' as const, label: t('Снизу') },
    { id: 'bottom_inset' as const, label: t('Снизу внутри') },
    { id: 'floating' as const, label: t('Плавающий'), sub: t('Можно перетащить') },
  ].map((o) => ({ ...o, diagram: { tabs, style: tabStyle, mini: o.id } }))}
  onchange={(v) => settings.set('mini.position', v)}
/>
<Cards
  title={t('Фон')}
  hint={t('Чем залит мини плеер')}
  value={settings.get('mini.background')}
  options={[
    { id: 'theme', label: t('Тема'), icon: 'grid' },
    { id: 'cover', label: t('Обложка'), icon: 'photo' },
    { id: 'cover_color', label: t('Цвет обложки'), icon: 'vinyl' },
  ]}
  onchange={(v) => settings.set('mini.background', v)}
/>
<Cards
  title={t('Прогресс')}
  hint={t('Как видно, сколько прошло')}
  value={settings.get('mini.progress')}
  options={[
    { id: 'line', label: t('Линия'), icon: 'line' },
    { id: 'background', label: t('Фоном'), icon: 'layoutTop' },
    { id: 'cover', label: t('Вокруг обложки'), icon: 'circle' },
  ]}
  onchange={(v) => settings.set('mini.progress', v)}
/>

<More>
  <Slider
    title={t('Форма')}
    hint={t('Скругление концов мини плеера и левой панели: 100% — капсула')}
    value={settings.get('mini.shape_round')}
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
    title={t('Обложка')}
    hint={t('Скругление обложки в мини плеере: 100% — круг')}
    value={settings.get('mini.cover_round')}
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
