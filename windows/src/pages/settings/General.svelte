<script lang="ts">
  // Система → Общее по pc/Screenshot_16: язык, платформа волны, медиатека (добавление, облако), запуск
  // (автозапуск, трей, экономия ресурсов). «Продолжить с прошлого раза» и «Авто похожие» — в Очереди.
  import { onMount } from 'svelte'
  import Icon from '../../components/Icon.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Group from '../../components/settings/Group.svelte'
  import Soon from '../../components/settings/Soon.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { api } from '../../lib/api'
  import { wave } from '../../player/my-wave.svelte'

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

<Choice
  title="Язык приложения"
  value="ru"
  options={[
    { id: 'en', label: 'English', sub: 'EN', soon: true },
    { id: 'ru', label: 'Русский', sub: 'RU' },
  ]}
/>
<Choice
  title="Платформа"
  hint="Откуда главная берёт волну и рекомендации"
  value={settings.get('general.platform')}
  options={[
    { id: 'soundcloud', label: 'SoundCloud' },
    { id: 'yandex', label: 'Яндекс' },
  ]}
  onchange={setPlatform}
/>

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
  <button class="cloud" disabled>
    <Icon name="cloudUp" size={18} />
    <span><b>Сохранить в облако <Soon /></b><small>Лайки и плейлисты с этого устройства</small></span>
  </button>
  <button class="cloud" disabled>
    <Icon name="cloudDown" size={18} />
    <span><b>Загрузить из облака <Soon /></b><small>Заменит лайки и плейлисты здесь</small></span>
  </button>
</Group>

<Group title="Запуск">
  <Switch title="Автозапуск" hint="Открывать Sonar при входе в систему" on={autostart} onchange={setAutostart} />
  <Switch title="Сворачивать в трей" hint="Крестик прячет окно, музыка играет дальше" on={settings.get('system.tray')} onchange={setTray} />
  <Choice
    title="Экономия ресурсов"
    hint="Когда упрощать эффекты, чтобы не нагружать компьютер"
    wide
    value={settings.get('system.power_saving')}
    options={[
      { id: 'off', label: 'Выключено' },
      { id: 'minimized', label: 'При сворачивании' },
      { id: 'background', label: 'В фоне' },
    ]}
    onchange={(v) => settings.set('system.power_saving', v)}
  />
</Group>

<style>
  .cloud {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    margin-top: 8px;
    padding: 12px 14px;
    border-radius: 12px;
    background: var(--plate);
    color: var(--text-2);
    text-align: left;
  }
  .cloud:disabled {
    cursor: default;
  }
  .cloud span {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .cloud b {
    font-size: 13px;
    color: var(--text);
  }
  .cloud small {
    font-size: 11px;
    color: var(--text-3);
  }
</style>
