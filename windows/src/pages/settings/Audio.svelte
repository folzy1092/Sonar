<script lang="ts">
  // Плеер → Аудио по pc/Screenshot_4, 5: устройство вывода, качество (ряд карточек листается),
  // «Громкость и переходы»; плюс своё — «SoundCloud в качестве Яндекса».
  import { onMount } from 'svelte'
  import { settingsPanel } from '../settings-section.svelte'
  import Cards from '../../components/settings/Cards.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Slider from '../../components/settings/Slider.svelte'
  import { slide } from 'svelte/transition'
  import Group from '../../components/settings/Group.svelte'
  import { api } from '../../lib/api'
  import { settings } from '../../lib/settings.svelte'
  import { player } from '../../player/player.svelte'

  type Quality = 'low' | 'medium' | 'high' | 'max'
  let quality = $state<Quality>('max')
  let scViaYandex = $state(true)
  let devices = $state<{ id: string; label: string; sub: string }[]>([{ id: '', label: 'По умолчанию', sub: 'Системное устройство' }])

  /** Устройства вывода. WebView2 отдаёт их id и названия только с разрешением на звук: флаг
   *  `--use-fake-ui-for-media-stream` (как у Dotify) выдаёт его без окна; если список всё равно
   *  пустой — один раз открываем и сразу закрываем доступ к звуку, чтобы Chromium показал устройства. */
  async function outputDevices() {
    const read = async () => {
      const seen = new Set([''])
      return (await navigator.mediaDevices.enumerateDevices()).filter(
        (d) => d.kind === 'audiooutput' && d.deviceId !== 'default' && d.deviceId !== 'communications' && !seen.has(d.deviceId) && !!seen.add(d.deviceId),
      )
    }
    let outs = await read()
    if (!outs.length || outs.every((d) => !d.label)) {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
        stream.getTracks().forEach((t) => t.stop())
        outs = await read()
      } catch {
        // доступа нет — остаётся системное устройство
      }
    }
    return outs.map((d, i) => ({ id: d.deviceId, label: d.label || `Устройство ${i + 1}`, sub: 'Устройство вывода' }))
  }

  onMount(() => {
    void load()
    // устройства подключили или отключили — список обновляется сам
    const onChange = () => settingsPanel.open && void outputDevices().then((outs) => (devices = [devices[0], ...outs])).catch(() => {})
    navigator.mediaDevices?.addEventListener?.('devicechange', onChange)
    return () => navigator.mediaDevices?.removeEventListener?.('devicechange', onChange)
  })

  async function load() {
    try {
      const [q, via] = await Promise.all([api.getSetting<Quality>('audio.quality'), api.getSetting<boolean>('audio.sc_via_yandex')])
      if (q) quality = q
      if (typeof via === 'boolean') scViaYandex = via
    } catch {
      // вне приложения — по умолчанию
    }
  }

  // список устройств — только когда настройки открыты (а не при запуске Sonar)
  $effect(() => {
    if (!settingsPanel.open) return
    void outputDevices()
      .then((outs) => (devices = [devices[0], ...outs]))
      .catch(() => {})
  })

  function setQuality(q: Quality) {
    quality = q
    void api.setSetting('audio.quality', q).catch(() => {})
  }

  function setVia(on: boolean) {
    scViaYandex = on
    void api.setSetting('audio.sc_via_yandex', on).catch(() => {})
  }

  function setDevice(id: string) {
    settings.set('audio.output_device', id)
    void player.setOutput(id)
  }
</script>

<Cards
  title="Устройство вывода"
  hint="Выберите аудиоустройство для воспроизведения музыки на этом компьютере"
  scroll
  value={settings.get('audio.output_device')}
  options={devices.map((d) => ({ id: d.id, label: d.label, sub: d.sub, icon: 'speaker' as const }))}
  onchange={setDevice}
/>

<Cards
  title="Качество аудио"
  hint="Выберите предпочтительное качество воспроизведения"
  scroll
  value={quality}
  options={[
    { id: 'low', label: 'Низкое', sub: '192 кбит/с', icon: 'music' },
    { id: 'medium', label: 'Среднее', sub: '256 кбит/с', icon: 'headphones' },
    { id: 'high', label: 'Высокое', sub: '320 кбит/с', icon: 'equalizer' },
    { id: 'max', label: 'Максимальное', sub: 'от 1411 кбит/с', icon: 'disc' },
  ]}
  onchange={setQuality}
/>

<Group title="Громкость и переходы">
  <Switch
    title="Нормализация громкости"
    hint="Тихие и громкие треки звучат ровно — без докручивания громкости"
    on={settings.get('audio.normalize')}
    onchange={(v) => settings.set('audio.normalize', v)}
  />
  <Switch
    title="Бесшовное воспроизведение"
    hint="Следующий трек начинается без паузы — заранее подгружается"
    on={settings.get('audio.gapless')}
    onchange={(v) => settings.set('audio.gapless', v)}
  />
  <Switch
    title="Кроссфейд"
    hint="Плавное затухание в конце трека и нарастание в начале следующего"
    on={settings.get('audio.crossfade') > 0}
    onchange={(v) => settings.set('audio.crossfade', v ? 6 : 0)}
  />
  {#if settings.get('audio.crossfade') > 0}
    <div transition:slide={{ duration: 220 }}>
      <Slider title="Длительность кроссфейда" value={settings.get('audio.crossfade')} min={1} max={12} unit=" с" onchange={(v) => settings.set('audio.crossfade', v)} />
    </div>
  {/if}
  <Switch
    title="Тише во время звонков"
    hint="Музыка стихает до 20 %, пока другое приложение занимает микрофон: звонок, голосовой чат Discord или Telegram"
    on={settings.get('audio.duck_calls')}
    onchange={(v) => {
      settings.set('audio.duck_calls', v)
      player.setCall(player.inCall)
    }}
  />
</Group>

<Group title="SoundCloud">
  <Switch
    title="SoundCloud в качестве Яндекса"
    hint="Если тот же трек есть на Яндексе (исполнитель, название и длительность совпадают), играть его оттуда — в качестве выше. Иначе SoundCloud: AAC 160 кбит/с, с Go+ — 256."
    on={scViaYandex}
    onchange={setVia}
  />
</Group>
