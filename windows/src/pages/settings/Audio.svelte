<script lang="ts">
  // Плеер → Аудио (pc/Screenshot_4, 5): качество Яндекса и «SoundCloud в качестве Яндекса».
  import { onMount } from 'svelte'
  import Icon from '../../components/Icon.svelte'
  import type { IconName } from '../../components/icons'
  import Switch from '../../components/settings/Switch.svelte'
  import Group from '../../components/settings/Group.svelte'
  import { api } from '../../lib/api'

  type Quality = 'low' | 'medium' | 'high' | 'max'
  const qualities: { id: Quality; title: string; kbps: string; icon: IconName }[] = [
    { id: 'low', title: 'Обычное', kbps: '192 кбит/с', icon: 'music' },
    { id: 'medium', title: 'Среднее', kbps: '256 кбит/с', icon: 'headphones' },
    { id: 'high', title: 'Высокое', kbps: '320 кбит/с', icon: 'equalizer' },
    { id: 'max', title: 'Максимальное', kbps: 'от 1411 кбит/с', icon: 'sparkles' },
  ]
  let quality = $state<Quality>('max')
  let scViaYandex = $state(true)

  onMount(async () => {
    try {
      const [q, via] = await Promise.all([api.getSetting<Quality>('audio.quality'), api.getSetting<boolean>('audio.sc_via_yandex')])
      if (q && qualities.some((x) => x.id === q)) quality = q
      if (typeof via === 'boolean') scViaYandex = via
    } catch {
      // вне приложения — по умолчанию
    }
  })

  function setQuality(q: Quality) {
    quality = q
    void api.setSetting('audio.quality', q).catch(() => {})
  }

  function setVia(on: boolean) {
    scViaYandex = on
    void api.setSetting('audio.sc_via_yandex', on).catch(() => {})
  }
</script>

<Group title="Качество аудио">
  <p class="hint">В каком качестве играть треки Яндекс Музыки</p>
  <div class="cards">
    {#each qualities as q (q.id)}
      <button class="card" class:on={quality === q.id} onclick={() => setQuality(q.id)}>
        <Icon name={q.icon} size={18} />
        <b>{q.title}</b>
        <small>{q.kbps}</small>
      </button>
    {/each}
  </div>
  <p class="note">«Максимальное» — FLAC без потерь, если трек есть в lossless (нужен Яндекс Плюс), иначе 320.</p>
</Group>

<Group title="SoundCloud">
  <Switch
    title="SoundCloud в качестве Яндекса"
    hint="Если тот же трек есть на Яндексе (исполнитель, название и длительность совпадают), играть его оттуда — в качестве выше. Иначе SoundCloud: AAC 160 кбит/с, с Go+ — 256."
    on={scViaYandex}
    onchange={setVia}
  />
</Group>

<style>
  .hint {
    margin: 0 0 12px;
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
      border-color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .card:hover {
    background: var(--hover);
  }
  .card:active {
    transform: scale(0.96);
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
</style>
