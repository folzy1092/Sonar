<script lang="ts">
  // Система → Общее (pc/Screenshot_16): платформа волны, медиатека, восстановление, запуск
  // (автозапуск, трей, экономия ресурсов).
  import Switch from '../../components/settings/Switch.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Group from '../../components/settings/Group.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { api } from '../../lib/api'
  import { wave } from '../../player/my-wave.svelte'
  import { onMount } from 'svelte'

  // автозапуск — реальное состояние из реестра Windows, а не только настройка
  let autostart = $state(false)
  onMount(() => {
    api
      .autostartEnabled()
      .then((v) => (autostart = v))
      .catch(() => {})
  })

  function setPlatform(v: 'soundcloud' | 'yandex') {
    settings.set('general.platform', v)
    // порция волны подбиралась под старую платформу
    void wave.prefetch(true)
  }

  async function setAutostart(on: boolean) {
    autostart = on
    settings.set('system.autostart', on)
    try {
      await api.setAutostart(on)
    } catch {
      autostart = !on
    }
  }

  function setTray(on: boolean) {
    settings.set('system.tray', on)
    void api.setTrayMode(on).catch(() => {})
  }
</script>

<Group title="Волна и рекомендации">
  <Choice
    title="Платформа"
    hint="Откуда главная берёт волну и похожее"
    value={settings.get('general.platform')}
    options={[
      { id: 'soundcloud', label: 'SoundCloud' },
      { id: 'yandex', label: 'Яндекс' },
    ]}
    onchange={setPlatform}
  />
  <Switch
    title="Похожие после очереди"
    hint="Очередь закончилась — играть дальше волну по последнему треку"
    on={settings.get('general.similar_autoplay')}
    onchange={(v) => settings.set('general.similar_autoplay', v)}
  />
</Group>

<Group title="Медиатека">
  <Choice
    title="Добавление"
    hint="Куда добавлять новые треки в плейлистах"
    value={settings.get('general.add_position')}
    options={[
      { id: 'start', label: 'В начало' },
      { id: 'end', label: 'В конец' },
    ]}
    onchange={(v) => settings.set('general.add_position', v)}
  />
  <Choice
    title="При запуске"
    hint="Что вернуть после перезапуска Sonar (на паузе)"
    value={settings.get('general.restore')}
    wide
    options={[
      { id: 'none', label: 'Ничего' },
      { id: 'track', label: 'Трек' },
      { id: 'queue', label: 'Трек и очередь' },
    ]}
    onchange={(v) => settings.set('general.restore', v)}
  />
</Group>

<Group title="Запуск">
  <Switch title="Автозапуск" hint="Открывать Sonar при входе в Windows (в трее)" on={autostart} onchange={setAutostart} />
  <Switch
    title="Сворачивать в трей"
    hint="Крестик прячет окно, музыка играет дальше. Выключено — крестик закрывает Sonar"
    on={settings.get('system.tray')}
    onchange={setTray}
  />
  <Choice
    title="Экономия ресурсов"
    hint="Когда останавливать визуализатор и фоновые анимации"
    value={settings.get('system.power_saving')}
    wide
    options={[
      { id: 'off', label: 'Выключено' },
      { id: 'minimized', label: 'При сворачивании' },
      { id: 'background', label: 'В фоне' },
    ]}
    onchange={(v) => settings.set('system.power_saving', v)}
  />
</Group>
