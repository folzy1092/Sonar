<script lang="ts">
  import Icon from '../components/Icon.svelte'
  import type { IconName } from '../components/icons'
  import Services from './settings/Services.svelte'
  import { settingsSection, type SettingsSection } from './settings-section.svelte'

  // Пока список разделов. Панель с 3D-анимацией открытия — W5 (PLATFORMS.md).
  const sections: { icon: IconName; title: string; text: string; id?: SettingsSection }[] = [
    { icon: 'user', title: 'Аккаунт', text: 'Профиль, статистика, вход — с сервером' },
    { icon: 'key', title: 'Сервисы', text: 'Токены SoundCloud и Яндекс Музыки', id: 'services' },
    { icon: 'palette', title: 'Интерфейс', text: 'Тема, фон, вкладки, мини-плеер' },
    { icon: 'player', title: 'Плеер', text: 'Кроссфейд, нормализация, устройство вывода' },
    { icon: 'lyrics', title: 'Тексты', text: 'lrclib, Genius, синхронизация' },
    { icon: 'database', title: 'Хранилище', text: 'Кеш треков и обложек' },
    { icon: 'info', title: 'О приложении', text: 'Версия, обновления, Telegram' },
  ]
</script>

{#if settingsSection.value === 'services'}
  <button class="back" onclick={() => (settingsSection.value = null)}>
    <Icon name="chevronLeft" size={18} /> Настройки
  </button>
  <h1>Сервисы</h1>
  <Services />
{:else}
<h1>Настройки</h1>

<div class="grid">
  {#each sections as s (s.title)}
    <button class="card" class:soon={!s.id} disabled={!s.id} onclick={() => s.id && (settingsSection.value = s.id)}>
      <span class="ico"><Icon name={s.icon} size={20} /></span>
      <span class="txt">
        <span class="t">{s.title}</span>
        <span class="d">{s.text}</span>
      </span>
      <Icon name="chevronRight" size={18} />
    </button>
  {/each}
</div>

<p class="ver">Sonar 0.1.0 · автономный режим</p>
{/if}

<style>
  h1 {
    font-size: 32px;
    font-weight: 800;
    margin-bottom: 20px;
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
    gap: 10px;
  }
  .card {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 14px 16px;
    border-radius: var(--radius-l);
    background: var(--plate);
    border: 1px solid var(--border);
    color: var(--text-3);
    text-align: left;
    transition:
      background var(--fast) var(--ease),
      border-color var(--fast) var(--ease);
  }
  .card.soon {
    opacity: 0.55;
    cursor: default;
  }
  .back {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    margin: 0 0 8px -6px;
    padding: 4px 10px 4px 4px;
    border-radius: 999px;
    color: var(--text-3);
  }
  .back:hover {
    color: var(--text);
    background: var(--hover);
  }
  .card:hover:not(:disabled) {
    background: var(--hover);
    border-color: var(--border-strong);
  }
  .ico {
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    flex-shrink: 0;
    border-radius: var(--radius-m);
    background: var(--surface-2);
    color: var(--text);
  }
  .txt {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .t {
    color: var(--text);
    font-weight: 600;
  }
  .d {
    font-size: 12px;
  }
  .ver {
    margin-top: 28px;
    color: var(--text-3);
    font-size: 12px;
  }
</style>
