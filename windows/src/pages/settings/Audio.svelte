<script lang="ts">
  // Плеер → Аудио по pc/Screenshot_4, 5: устройство вывода, качество (ряд карточек листается),
  // «Громкость и переходы»; плюс своё — «Резервный сервис» (порядок перетаскиванием), «SoundCloud
  // в качестве Яндекса» (тот же механизм резерва, services/fallback.rs) и качество YouTube Music.
  import { onMount } from 'svelte'
  import { settingsPanel } from '../settings-section.svelte'
  import Cards from '../../components/settings/Cards.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Slider from '../../components/settings/Slider.svelte'
  import { slide } from 'svelte/transition'
  import Group from '../../components/settings/Group.svelte'
  import More from '../../components/settings/More.svelte'
  import FallbackOrder from '../../components/settings/FallbackOrder.svelte'
  import { api } from '../../lib/api'
  import { settings } from '../../lib/settings.svelte'
  import { player } from '../../player/player.svelte'
  import { t } from '../../lib/i18n.svelte'

  type Quality = 'low' | 'medium' | 'high' | 'max'
  let quality = $state<Quality>('max')
  let scViaYandex = $state(false)
  let devices = $state<{ id: string; label: string; sub: string; n?: number }[]>([{ id: '', label: 'По умолчанию', sub: 'Системное устройство' }])

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
        stream.getTracks().forEach((tr) => tr.stop())
        outs = await read()
      } catch {
        // доступа нет — остаётся системное устройство
      }
    }
    // подписи по-русски — переводятся при выводе (t), чтобы смена языка подхватывалась сразу
    return outs.map((d, i) => ({ id: d.deviceId, label: d.label, n: i + 1, sub: 'Устройство вывода' }))
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
  title={t('Устройство вывода')}
  hint={t('Выберите аудиоустройство для воспроизведения музыки на этом компьютере')}
  scroll
  value={settings.get('audio.output_device')}
  options={devices.map((d) => ({ id: d.id, label: !d.id ? t(d.label) : d.label || t('Устройство {n}', { n: d.n ?? 1 }), sub: t(d.sub), icon: 'speaker' as const }))}
  onchange={setDevice}
/>

<Cards
  title={t('Качество аудио')}
  hint={t('Выберите предпочтительное качество воспроизведения')}
  scroll
  value={quality}
  options={[
    { id: 'low', label: t('Низкое'), sub: t('{n} кбит/с', { n: 192 }), icon: 'music' },
    { id: 'medium', label: t('Среднее'), sub: t('{n} кбит/с', { n: 256 }), icon: 'headphones' },
    { id: 'high', label: t('Высокое'), sub: t('{n} кбит/с', { n: 320 }), icon: 'equalizer' },
    { id: 'max', label: t('Максимальное'), sub: t('от {n} кбит/с', { n: 1411 }), icon: 'disc' },
  ]}
  onchange={setQuality}
/>

<Cards
  title="YouTube Music"
  hint={t('Качество треков YouTube Music: обычное бережёт трафик, высокое звучит лучше')}
  value={settings.get('audio.yt_quality')}
  options={[
    { id: 'normal', label: t('YouTube::Обычное'), sub: t('AAC · {n} кбит/с', { n: 128 }), icon: 'headphones' },
    { id: 'high', label: t('Высокое'), sub: t('Opus · {n} кбит/с', { n: 160 }), icon: 'equalizer' },
  ]}
  onchange={(v) => settings.set('audio.yt_quality', v as 'normal' | 'high')}
/>

<Group title={t('Громкость и переходы')} hint={t('Как звучат треки и стыки между ними')}>
  <Switch
    title={t('Нормализация громкости')}
    hint={t('Тихие и громкие треки звучат ровно — без докручивания громкости')}
    on={settings.get('audio.normalize')}
    onchange={(v) => settings.set('audio.normalize', v)}
  />
  <Switch
    title={t('Бесшовное воспроизведение')}
    hint={t('Следующий трек начинается без паузы — заранее подгружается')}
    on={settings.get('audio.gapless')}
    onchange={(v) => settings.set('audio.gapless', v)}
  />
  <Switch
    title={t('Кроссфейд')}
    hint={t('Плавное затухание в конце трека и нарастание в начале следующего')}
    on={settings.get('audio.crossfade') > 0}
    onchange={(v) => settings.set('audio.crossfade', v ? 6 : 0)}
  />
  {#if settings.get('audio.crossfade') > 0}
    <div transition:slide={{ duration: 220 }}>
      <Slider title={t('Длительность кроссфейда')} value={settings.get('audio.crossfade')} min={1} max={12} unit=" {t('с')}" onchange={(v) => settings.set('audio.crossfade', v)} />
    </div>
  {/if}
</Group>

<FallbackOrder />

<More>
  <Switch
    title={t('Тише во время звонков')}
    hint={t('Музыка стихает до 20 %, пока другое приложение занимает микрофон: звонок, голосовой чат Discord или Telegram')}
    on={settings.get('audio.duck_calls')}
    onchange={(v) => {
      settings.set('audio.duck_calls', v)
      player.setCall(player.inCall)
    }}
  />

  <Group title="SoundCloud" hint={t('Откуда брать звук для треков SoundCloud')}>
    <Switch
      title={t('SoundCloud в качестве Яндекса')}
      hint={t('Если тот же трек есть на Яндексе (исполнитель, название и длительность совпадают), играть его оттуда — в качестве выше. Иначе SoundCloud: AAC 160 кбит/с, с Go+ — 256.')}
      on={scViaYandex}
      onchange={setVia}
    />
  </Group>
</More>
