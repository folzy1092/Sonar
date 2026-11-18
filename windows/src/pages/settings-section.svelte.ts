// Панель настроек (PLATFORMS.md, reference/pc/Screenshot_30..32): слева плоская панель, а окно
// плеера уезжает вправо и поворачивается вглубь на ~15°. Другие экраны могут открыть нужный раздел.
import type { IconName } from '../components/icons'

export type SettingsTab = 'account' | 'interface' | 'player' | 'services' | 'integrations' | 'system'

// Названия вкладок и подразделов — по-русски: это ключи перевода, `t()` при показе (SettingsPanel),
// чтобы смена языка подхватывалась сразу.

export const TABS: { id: SettingsTab; title: string }[] = [
  { id: 'account', title: 'Аккаунт' },
  { id: 'interface', title: 'Интерфейс' },
  { id: 'player', title: 'Плеер' },
  { id: 'services', title: 'Сервисы' },
  { id: 'integrations', title: 'Интеграции' },
  { id: 'system', title: 'Система' },
]

/** Подразделы — капсулы под вкладками, по reference/pc. `soon` — с сервером / ещё не сделано,
 *  `lock` — «В разработке» (приватность). Не делаем: подписку, Кастом/Мастерскую, оверлей, прокси
 *  (CLAUDE.md). Горячие клавиши — делаем (решение владельца 2026-11-17). */
export interface SettingsSub {
  id: string
  title: string
  icon: IconName
  soon?: boolean
  lock?: boolean
}

export const SUBS: Record<SettingsTab, SettingsSub[]> = {
  account: [
    { id: 'profile', title: 'Профиль', icon: 'user2' },
    { id: 'login', title: 'Вход', icon: 'shield', soon: true },
    { id: 'privacy', title: 'Приватность', icon: 'lock', lock: true },
    { id: 'stats', title: 'Статистика', icon: 'bars' },
  ],
  interface: [
    { id: 'style', title: 'Стиль', icon: 'sparkles' },
    { id: 'look', title: 'Вид', icon: 'palette' },
    { id: 'tabs', title: 'Вкладки', icon: 'grid' },
  ],
  player: [
    { id: 'audio', title: 'Аудио', icon: 'volume' },
    { id: 'view', title: 'Вид', icon: 'player' },
    { id: 'queue', title: 'Очередь', icon: 'queue' },
    { id: 'mini', title: 'Мини плеер', icon: 'music' },
  ],
  services: [{ id: 'services', title: 'Сервисы', icon: 'key' }],
  integrations: [{ id: 'apps', title: 'Приложения', icon: 'stack' }],
  system: [
    { id: 'general', title: 'Общее', icon: 'adjustments' },
    { id: 'hotkeys', title: 'Горячие клавиши', icon: 'keyboard' },
    { id: 'remote', title: 'Пульт', icon: 'phone' },
    { id: 'update', title: 'Обновления', icon: 'download' },
    { id: 'storage', title: 'Хранилище', icon: 'database' },
  ],
}

/** Подраздел по умолчанию — первый рабочий. */
export const firstSub = (tab: SettingsTab) => (SUBS[tab].find((s) => !s.soon && !s.lock) ?? SUBS[tab][0]).id

class SettingsPanel {
  open = $state(false)
  tab = $state<SettingsTab>('player')
  sub = $state('audio')

  show(tab?: SettingsTab, sub?: string) {
    if (tab && tab !== this.tab) {
      this.tab = tab
      this.sub = firstSub(tab)
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
