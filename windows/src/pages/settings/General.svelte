<script lang="ts">
  import { t } from '../../lib/i18n.svelte'
  // Приложение → Общее (SETTINGS_NEXT «Общее»): три карточки — язык и платформа, медиатека, запуск.
  // «О приложении» — отдельный пункт меню (About.svelte). «Продолжить с прошлого раза» и «Авто похожие» —
  // в Плеере, в блоке очереди.
  import { onMount } from 'svelte'
  import Icon from '../../components/Icon.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Card from '../../components/settings/Card.svelte'
  import Soon from '../../components/settings/Soon.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { api } from '../../lib/api'
  import { ACCOUNT_SERVICES, byId, type ServiceId, type ServiceKey } from '../../lib/services'
  import { ICONS, uniquifyIds } from '../../lib/service-icons'
  import { searchableServices } from '../../lib/unified-search'
  import { wave } from '../../player/my-wave.svelte'

  const LANGUAGES = [
    { id: 'ru' as const, label: 'Русский', flag: 'ru' },
    { id: 'en' as const, label: 'English', flag: 'en' },
    { id: 'uk' as const, label: 'Українська', flag: 'uk' },
  ]

  const serviceName = (id: ServiceId) => (id === 'ym' ? t('Яндекс') : t(byId(id)?.name ?? id))
  /** Цветной знак сервиса для капсулы; id внутри svg — свои у каждой строки (две строки со знаками). */
  const serviceSvg = (id: ServiceId, row: string) => {
    const svg = ICONS[id]?.plain
    return svg ? uniquifyIds(svg, `general-${row}`) : undefined
  }

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

<Card>
  <Choice
    title={t('Язык')}
    hint={t('Язык интерфейса')}
    value={settings.get('general.language')}
    options={LANGUAGES}
    onchange={(v) => settings.set('general.language', v)}
  />
  <Choice
    title={t('Платформа')}
    hint={t('Откуда главная берёт Sonar Mix и рекомендации')}
    value={settings.get('general.platform')}
    options={ACCOUNT_SERVICES.filter((s) => s.caps.similar).map((s) => ({
      id: s.key,
      label: serviceName(s.id),
      svg: serviceSvg(s.id, 'platform'),
    }))}
    onchange={setPlatform}
  />
  <Choice
    title={t('Поиск сначала в')}
    hint={t('Чьи результаты единого поиска стоят сверху')}
    value={settings.get('search.preferred')}
    options={searchableServices().map((id) => ({ id, label: serviceName(id), svg: serviceSvg(id, 'search') }))}
    onchange={(v) => settings.set('search.preferred', v)}
  />
</Card>

<Card title={t('Медиатека')}>
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
  <div class="row">
    <span class="txt">
      <b>{t('Синхронизировать')} <Soon /></b>
      <small>{t('Лайки и плейлисты между устройствами — когда появится сервер Sonar')}</small>
    </span>
    <button class="sync" disabled aria-label={t('Синхронизировать')}><Icon name="refresh" size={16} /></button>
  </div>
</Card>

<Card title={t('Запуск')}>
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
</Card>

<style>
  .row {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 11px 0;
  }
  .txt {
    display: flex;
    flex: 1;
    flex-direction: column;
    gap: 3px;
    min-width: 0;
  }
  .txt b {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  .txt small {
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.45;
    color: var(--text-3);
  }
  .sync {
    display: grid;
    place-items: center;
    width: 34px;
    height: 34px;
    border-radius: 50%;
    background: var(--surface-3);
    color: var(--text-3);
  }
  .sync:disabled {
    cursor: default;
  }
</style>
