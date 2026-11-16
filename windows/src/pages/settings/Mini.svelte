<script lang="ts">
  // Плеер → Мини плеер по pc/Screenshot_8, 9, 30: стиль-пресет (меняет фон, прогресс, обложку и форму,
  // как у Dotify), позиция, фон, прогресс, обложка, форма.
  import Cards from '../../components/settings/Cards.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Divider from '../../components/settings/Divider.svelte'
  import Slider from '../../components/settings/Slider.svelte'
  import Cover from '../../components/Cover.svelte'
  import Icon from '../../components/Icon.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { player } from '../../player/player.svelte'

  // живой пример: пока тянут ползунок — показываем значение под пальцем, отпустили — сохраняем
  let capLive = $state<number | null>(null)
  let coverLive = $state<number | null>(null)
  const cap = $derived((capLive ?? settings.get('mini.shape_round')) / 100)
  const cov = $derived((coverLive ?? settings.get('mini.cover_round')) / 100)
  const t = $derived(player.current)
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
  value={settings.get('mini.position')}
  options={[
    { id: 'top' as const, label: 'Сверху', icon: 'layoutTop' },
    { id: 'bottom' as const, label: 'Снизу', icon: 'layoutBottom' },
    { id: 'bottom_inset' as const, label: 'Снизу внутри', icon: 'layoutFloat' },
    { id: 'floating' as const, label: 'Плавающий — можно перетащить', icon: 'maximize' },
  ]}
  onchange={(v) => settings.set('mini.position', v)}
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
<Divider />

<!-- пример: мини-плеер в миниатюре — видны оба конца и прямая середина между ними -->
<div class="preview" aria-hidden="true">
  <div class="cap" style:--k={cap}>
    <span class="cov" style:--c={cov}><Cover url={t?.cover_url} size={38} radius="calc(50% * var(--c))" /></span>
    <span class="txt"><b>{t?.title ?? 'Название трека'}</b><small>{t?.artist ?? 'Исполнитель'}</small></span>
    <span class="mid"><Icon name="play" size={16} filled /></span>
    <span class="end"><Icon name="volume" size={15} /></span>
  </div>
</div>
<Slider
  title="Форма"
  hint="Скругление концов мини плеера и левой панели: 100% — капсула"
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
  title="Обложка"
  hint="Скругление обложки в мини плеере: 100% — круг"
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

<style>
  .preview {
    padding: 6px 0 4px;
  }
  .cap {
    display: flex;
    align-items: center;
    gap: 10px;
    height: 54px;
    padding: 0 16px 0 calc(8px + 4px * var(--k));
    border-radius: max(var(--radius-l), calc(27px * var(--k)));
    background: var(--surface-2);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    transition: border-radius 0.25s var(--ease);
  }
  .cov {
    display: grid;
    flex: none;
  }
  .cov :global(.cover) {
    transition: border-radius 0.25s var(--ease);
  }
  .txt {
    display: grid;
    min-width: 0;
    flex: 1;
  }
  .txt b,
  .txt small {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .txt b {
    font-size: calc(13px * var(--fs, 1));
  }
  .txt small {
    font-size: calc(11px * var(--fs, 1));
    color: var(--text-3);
  }
  .mid {
    display: grid;
    place-items: center;
    width: 30px;
    height: 30px;
    border-radius: 50%;
    background: var(--text);
    color: var(--on-text);
  }
  .end {
    color: var(--text-2);
  }
</style>
