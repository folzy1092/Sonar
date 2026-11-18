<script lang="ts">
  import { t } from '../../lib/i18n.svelte'
  // Система → Общее по pc/Screenshot_16: язык, платформа волны, медиатека (добавление, облако), запуск
  // (автозапуск, трей, экономия ресурсов), внизу — о приложении (AboutBlock). «Продолжить с прошлого
// раза» и «Авто похожие» — в Очереди.
  import { onMount } from 'svelte'
  import Icon from '../../components/Icon.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Select from '../../components/settings/Select.svelte'
  import Group from '../../components/settings/Group.svelte'
  import Soon from '../../components/settings/Soon.svelte'
  import AboutBlock from './AboutBlock.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { api } from '../../lib/api'
  import { ACCOUNT_SERVICES, type ServiceKey } from '../../lib/services'
  import { wave } from '../../player/my-wave.svelte'

  // автозапуск — реальное состояние из реестра Windows, а не только настройка
  let autostart = $state(false)
  onMount(() => {
    api
      .autostartEnabled()
      .then((v) => (autostart = v))
      .catch(() => {})
  })

  function setPlatform(v: ServiceKey) {
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

<Select
  title={t('Язык')}
  hint={t('Язык интерфейса')}
  value={settings.get('general.language')}
  options={[
    { id: 'ru' as const, label: 'Русский', flag: 'ru' },
    { id: 'en' as const, label: 'English', flag: 'en' },
    { id: 'uk' as const, label: 'Українська', flag: 'uk' },
  ]}
  onchange={(v) => settings.set('general.language', v)}
/>
<Choice
  title={t('Платформа')}
  hint={t('Откуда главная берёт волну и рекомендации')}
  value={settings.get('general.platform')}
  options={ACCOUNT_SERVICES.map((s) => ({ id: s.key, label: s.id === 'ym' ? t('Яндекс') : t(s.name) }))}
  onchange={setPlatform}
/>

<Group title={t('Медиатека')}>
  <Choice
    title={t('Добавление')}
    hint={t('Куда добавлять новые треки в плейлистах')}
    value={settings.get('general.add_position')}
    options={[
      { id: 'start', label: t('В начало') },
      { id: 'end', label: t('В конец') },
    ]}
    onchange={(v) => settings.set('general.add_position', v)}
  />
  <button class="cloud" disabled>
    <Icon name="cloudUp" size={18} />
    <span><b>{t('Сохранить в облако')} <Soon /></b><small>{t('Лайки и плейлисты с этого устройства')}</small></span>
  </button>
  <button class="cloud" disabled>
    <Icon name="cloudDown" size={18} />
    <span><b>{t('Загрузить из облака')} <Soon /></b><small>{t('Заменит лайки и плейлисты здесь')}</small></span>
  </button>
</Group>

<Group title={t('Запуск')}>
  <Switch title={t('Автозапуск')} hint={t('Открывать Sonar при входе в систему')} on={autostart} onchange={setAutostart} />
  <Switch title={t('Сворачивать в трей')} hint={t('Крестик прячет окно, музыка играет дальше')} on={settings.get('system.tray')} onchange={setTray} />
  <Choice
    title={t('Экономия ресурсов')}
    hint={t('Когда упрощать эффекты, чтобы не нагружать компьютер')}
    wide
    value={settings.get('system.power_saving')}
    options={[
      { id: 'off', label: t('Выключено') },
      { id: 'minimized', label: t('При сворачивании') },
      { id: 'background', label: t('В фоне') },
    ]}
    onchange={(v) => settings.set('system.power_saving', v)}
  />
</Group>

<AboutBlock />

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
    font-size: calc(13px * var(--fs, 1));
    color: var(--text);
  }
  .cloud small {
    font-size: calc(11px * var(--fs, 1));
    color: var(--text-3);
  }
</style>
