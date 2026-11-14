<script lang="ts">
  // Панель настроек слева (reference/pc/Screenshot_30..32): вкладки разделов сверху, под ними
  // капсулы подразделов. Сделанные разделы — Плеер → Аудио (качество), Сервисы, Система.
  // Остальное — в W5 (ROADMAP), пустые переключатели не рисуем.
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import type { IconName } from '../components/icons'
  import Services from './settings/Services.svelte'
  import { api } from '../lib/api'
  import { settingsPanel, type SettingsTab } from './settings-section.svelte'

  const tabs: { id: SettingsTab; title: string }[] = [
    { id: 'account', title: 'Аккаунт' },
    { id: 'interface', title: 'Интерфейс' },
    { id: 'player', title: 'Плеер' },
    { id: 'services', title: 'Сервисы' },
    { id: 'integrations', title: 'Интеграции' },
    { id: 'system', title: 'Система' },
  ]

  type Quality = 'low' | 'medium' | 'high' | 'max'
  const qualities: { id: Quality; title: string; kbps: string; icon: IconName }[] = [
    { id: 'low', title: 'Обычное', kbps: '192 кбит/с', icon: 'music' },
    { id: 'medium', title: 'Среднее', kbps: '256 кбит/с', icon: 'headphones' },
    { id: 'high', title: 'Высокое', kbps: '320 кбит/с', icon: 'equalizer' },
    { id: 'max', title: 'Максимальное', kbps: 'от 1411 кбит/с', icon: 'sparkles' },
  ]
  let quality = $state<Quality>('max')
  let scViaYandex = $state(true)

  const later: Partial<Record<SettingsTab, string>> = {
    account: 'Профиль, статистика и вход появятся вместе с сервером.',
    interface: 'Тема под обложку, фон, вкладки и стиль мини-плеера — в W5.',
    integrations: 'Discord RPC («Слушает в Sonar») и Last.fm — в W5.',
  }

  let scroller: HTMLDivElement | undefined = $state()

  onMount(async () => {
    try {
      const [q, via] = await Promise.all([
        api.getSetting<Quality>('audio.quality'),
        api.getSetting<boolean>('audio.sc_via_yandex'),
      ])
      if (q && qualities.some((x) => x.id === q)) quality = q
      if (typeof via === 'boolean') scViaYandex = via
    } catch {
      // вне приложения — по умолчанию
    }
  })

  function toggleScViaYandex() {
    scViaYandex = !scViaYandex
    void api.setSetting('audio.sc_via_yandex', scViaYandex).catch(() => {})
  }

  function setQuality(q: Quality) {
    quality = q
    void api.setSetting('audio.quality', q).catch(() => {})
  }

  $effect(() => {
    settingsPanel.tab
    scroller?.scrollTo({ top: 0 })
  })
</script>

<aside class="panel" aria-label="Настройки">
  <nav class="tabs" data-tauri-drag-region>
    {#each tabs as t (t.id)}
      <button class:on={settingsPanel.tab === t.id} onclick={() => (settingsPanel.tab = t.id)}>{t.title}</button>
    {/each}
  </nav>

  <div class="scroll" bind:this={scroller}>
    {#if settingsPanel.tab === 'player'}
      <div class="subs">
        <span class="sub on"><Icon name="volume" size={15} /> Аудио</span>
      </div>

      <section>
        <h3>Качество аудио</h3>
        <p class="hint">Выбери, в каком качестве играть треки Яндекс Музыки</p>
        <div class="cards">
          {#each qualities as q (q.id)}
            <button class="card" class:on={quality === q.id} onclick={() => setQuality(q.id)}>
              <Icon name={q.icon} size={18} />
              <b>{q.title}</b>
              <small>{q.kbps}</small>
            </button>
          {/each}
        </div>
        <p class="note">
          «Максимальное» — FLAC без потерь, если трек есть в lossless (нужен Яндекс Плюс), иначе 320.
        </p>

        <button class="switch-row" role="switch" aria-checked={scViaYandex} onclick={toggleScViaYandex}>
          <span>
            <b>SoundCloud в качестве Яндекса</b>
            <small>
              Если тот же трек есть на Яндексе (исполнитель, название и длительность совпадают), играть его
              оттуда — в качестве выше. Иначе SoundCloud: AAC 160 кбит/с, с Go+ — 256.
            </small>
          </span>
          <i class="switch" class:on={scViaYandex} aria-hidden="true"></i>
        </button>
      </section>
    {:else if settingsPanel.tab === 'services'}
      <section>
        <Services />
      </section>
    {:else if settingsPanel.tab === 'system'}
      <section>
        <h3>О приложении</h3>
        <p class="hint">Sonar 0.1.0 · автономный режим</p>
      </section>
    {:else}
      <p class="later">{later[settingsPanel.tab]}</p>
    {/if}
  </div>
</aside>

<style>
  .panel {
    position: fixed;
    inset: 0 auto 0 0;
    z-index: 30;
    display: flex;
    flex-direction: column;
    width: var(--settings-w);
    background: var(--surface-0);
    border-right: 1px solid var(--border);
  }
  .tabs {
    display: flex;
    gap: 22px;
    padding: 14px 16px 0;
    overflow-x: auto;
    scrollbar-width: none;
    border-bottom: 1px solid var(--border);
  }
  .tabs button {
    position: relative;
    padding: 4px 0 12px;
    font-size: 15px;
    color: var(--text-3);
    white-space: nowrap;
    transition: color var(--fast) var(--ease);
  }
  .tabs button:hover {
    color: var(--text-2);
  }
  .tabs button.on {
    color: var(--text);
    font-weight: 700;
  }
  .tabs button.on::after {
    content: '';
    position: absolute;
    left: 0;
    right: 0;
    bottom: -1px;
    height: 2px;
    border-radius: 2px;
    background: var(--text);
  }
  .scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    padding: 16px 16px 32px;
  }
  .subs {
    display: flex;
    gap: 8px;
    margin-bottom: 22px;
  }
  .sub {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 36px;
    padding: 0 16px;
    border-radius: 999px;
    color: var(--text-2);
  }
  .sub.on {
    background: var(--text);
    color: var(--accent-ink);
    font-weight: 600;
  }
  h3 {
    margin: 0;
    font-size: 15px;
    font-weight: 600;
  }
  .hint {
    margin: 4px 0 12px;
    font-size: 13px;
    color: var(--text-3);
  }
  .cards {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 8px;
  }
  .card {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    padding: 14px 8px 12px;
    border-radius: 14px;
    background: var(--plate);
    border: 1px solid var(--border);
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      border-color var(--fast) var(--ease);
  }
  .card:hover {
    background: var(--hover);
  }
  .card.on {
    background: var(--surface-3);
    border-color: var(--border-strong);
    color: var(--text);
  }
  .card b {
    font-size: 13px;
    font-weight: 600;
    color: var(--text);
  }
  .card small {
    font-size: 11px;
    color: var(--text-3);
  }
  .note {
    margin: 12px 0 0;
    font-size: 12px;
    line-height: 1.5;
    color: var(--text-3);
  }
  .switch-row {
    display: flex;
    align-items: center;
    gap: 16px;
    width: 100%;
    margin-top: 20px;
    text-align: left;
  }
  .switch-row span {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }
  .switch-row b {
    font-size: 14px;
    font-weight: 500;
  }
  .switch-row small {
    font-size: 12px;
    line-height: 1.45;
    color: var(--text-3);
  }
  .switch {
    position: relative;
    flex-shrink: 0;
    width: 40px;
    height: 22px;
    border-radius: 999px;
    background: var(--surface-3);
    transition: background var(--fast) var(--ease);
  }
  .switch::after {
    content: '';
    position: absolute;
    top: 3px;
    left: 3px;
    width: 16px;
    height: 16px;
    border-radius: 50%;
    background: var(--text-2);
    transition:
      transform var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .switch.on {
    background: var(--text);
  }
  .switch.on::after {
    transform: translateX(18px);
    background: var(--accent-ink);
  }
  .later {
    margin: 8px 0;
    color: var(--text-3);
  }
</style>
