<script lang="ts">
  // Плеер → Аудио по pc/Screenshot_4, 5: устройство вывода, качество (ряд карточек листается),
  // «Громкость и переходы»; плюс своё — «SoundCloud в качестве Яндекса».
  import { onMount } from 'svelte'
  import Cards from '../../components/settings/Cards.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Group from '../../components/settings/Group.svelte'
  import { api } from '../../lib/api'
  import { settings } from '../../lib/settings.svelte'
  import { player } from '../../player/player.svelte'

  type Quality = 'low' | 'medium' | 'high' | 'max'
  let quality = $state<Quality>('max')
  let scViaYandex = $state(true)
  let devices = $state<{ id: string; label: string; sub: string }[]>([{ id: '', label: 'По умолчанию', sub: 'Системное устройство' }])

  onMount(async () => {
    try {
      const [q, via] = await Promise.all([api.getSetting<Quality>('audio.quality'), api.getSetting<boolean>('audio.sc_via_yandex')])
      if (q) quality = q
      if (typeof via === 'boolean') scViaYandex = via
    } catch {
      // вне приложения — по умолчанию
    }
    try {
      const list = await navigator.mediaDevices.enumerateDevices()
      // без разрешения id бывают пустыми — такие и повторы пропускаем
      const seen = new Set([''])
      const outs = list.filter(
        (d) => d.kind === 'audiooutput' && d.deviceId !== 'default' && d.deviceId !== 'communications' && !seen.has(d.deviceId) && !!seen.add(d.deviceId),
      )
      devices = [devices[0], ...outs.map((d, i) => ({ id: d.deviceId, label: d.label || `Устройство ${i + 1}`, sub: 'Устройство вывода' }))]
    } catch {
      // нет доступа к списку устройств — только системное
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
  <Switch title="Нормализация громкости" hint="Автоматическое выравнивание уровня громкости для всех треков" on={false} soon />
  <Switch title="Бесшовное воспроизведение" hint="Плавный переход между треками без пауз и задержек" on={true} soon />
  <Switch title="Кроссфейд" hint="Плавное затухание в конце трека и нарастание в начале следующего" on={false} soon />
  <Switch title="Тише во время звонков" hint="Музыка стихает, пока идёт звонок или голосовой чат в другом приложении" on={true} soon />
</Group>

<Group title="SoundCloud">
  <Switch
    title="SoundCloud в качестве Яндекса"
    hint="Если тот же трек есть на Яндексе (исполнитель, название и длительность совпадают), играть его оттуда — в качестве выше. Иначе SoundCloud: AAC 160 кбит/с, с Go+ — 256."
    on={scViaYandex}
    onchange={setVia}
  />
</Group>
