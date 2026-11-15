// Панель настроек (PLATFORMS.md, reference/pc/Screenshot_30..32): слева плоская панель, а окно
// плеера уезжает вправо и поворачивается вглубь на ~15°. Другие экраны могут открыть нужный раздел.
import type { IconName } from '../components/icons'

export type SettingsTab = 'account' | 'interface' | 'player' | 'services' | 'integrations' | 'system'

export const TABS: { id: SettingsTab; title: string }[] = [
  { id: 'account', title: 'Аккаунт' },
  { id: 'interface', title: 'Интерфейс' },
  { id: 'player', title: 'Плеер' },
  { id: 'services', title: 'Сервисы' },
  { id: 'integrations', title: 'Интеграции' },
  { id: 'system', title: 'Система' },
]

/** Подразделы — капсулы под вкладками. Профиль, вход, Last.fm, ключ API — вместе с сервером. */
export const SUBS: Record<SettingsTab, { id: string; title: string; icon: IconName }[]> = {
  account: [{ id: 'stats', title: 'Статистика', icon: 'history' }],
  interface: [{ id: 'look', title: 'Вид', icon: 'palette' }],
  player: [
    { id: 'audio', title: 'Аудио', icon: 'volume' },
    { id: 'view', title: 'Вид', icon: 'eye' },
  ],
  services: [{ id: 'services', title: 'Сервисы', icon: 'key' }],
  integrations: [{ id: 'apps', title: 'Приложения', icon: 'link' }],
  system: [
    { id: 'general', title: 'Общее', icon: 'adjustments' },
    { id: 'storage', title: 'Хранилище', icon: 'database' },
    { id: 'about', title: 'О приложении', icon: 'info' },
  ],
}

class SettingsPanel {
  open = $state(false)
  tab = $state<SettingsTab>('player')
  sub = $state('audio')

  show(tab?: SettingsTab, sub?: string) {
    if (tab && tab !== this.tab) {
      this.tab = tab
      this.sub = SUBS[tab][0].id
    }
    if (sub) this.sub = sub
    this.open = true
  }

  close() {
    this.open = false
  }

  toggle() {
    this.open = !this.open
  }
}

export const settingsPanel = new SettingsPanel()
