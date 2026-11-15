<script lang="ts">
  // Плеер → Мини плеер по pc/Screenshot_8, 9, 30: стиль-пресет (меняет фон, прогресс, обложку и форму,
  // как у Dotify), позиция, фон, прогресс, обложка, форма.
  import Cards from '../../components/settings/Cards.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Divider from '../../components/settings/Divider.svelte'
  import { settings } from '../../lib/settings.svelte'
</script>

<Cards
  title="Стиль"
  hint="Как выглядит мини плеер"
  scroll
  value={settings.get('mini.style')}
  options={[
    { id: 'off', label: 'Отключено', icon: 'x' },
    { id: 'full', label: 'Полный', icon: 'grid' },
    { id: 'rounded', label: 'Закругленный', icon: 'circle' },
    { id: 'hybrid', label: 'Гибрид', icon: 'vinyl' },
    { id: 'deck', label: 'Дек', icon: 'photo' },
  ]}
  onchange={(v) => settings.setMiniStyle(v)}
/>

<Divider />

<Choice
  title="Позиция"
  hint="Выберите, где будет отображаться мини плеер"
  icons
  value="bottom"
  options={[
    { id: 'top', label: 'Сверху', icon: 'layoutTop', soon: true },
    { id: 'bottom', label: 'Снизу', icon: 'layoutBottom' },
    { id: 'bottom_inset', label: 'Снизу внутри', icon: 'layoutFloat', soon: true },
    { id: 'floating', label: 'Плавающий', icon: 'maximize', soon: true },
  ]}
/>
<Cards
  title="Фон"
  hint="Выберите источник фона мини плеера"
  value={settings.get('mini.background')}
  options={[
    { id: 'theme', label: 'Тема', icon: 'grid' },
    { id: 'cover', label: 'Обложка', icon: 'photo' },
    { id: 'cover_color', label: 'Цвет обложки', icon: 'vinyl' },
  ]}
  onchange={(v) => settings.set('mini.background', v)}
/>
<Cards
  title="Прогресс"
  hint="Выберите, как отображать прогресс трека"
  value={settings.get('mini.progress')}
  options={[
    { id: 'line', label: 'Линия', icon: 'line' },
    { id: 'background', label: 'Фоном', icon: 'layoutTop' },
    { id: 'cover', label: 'Вокруг обложки', icon: 'circle' },
  ]}
  onchange={(v) => settings.set('mini.progress', v)}
/>
<Choice
  title="Обложка"
  hint="Выберите форму обложки в мини плеере"
  wide
  value={settings.get('mini.cover_shape')}
  options={[
    { id: 'default', label: 'По умолчанию', icon: 'square' },
    { id: 'circle', label: 'Круглая', icon: 'circle' },
  ]}
  onchange={(v) => settings.set('mini.cover_shape', v)}
/>
<Choice
  title="Форма"
  hint="Выберите форму мини плеера"
  wide
  value={settings.get('mini.shape')}
  options={[
    { id: 'default', label: 'По умолчанию', icon: 'square' },
    { id: 'capsule', label: 'Капсула', icon: 'circle' },
  ]}
  onchange={(v) => settings.set('mini.shape', v)}
/>
