// Панель настроек (PLATFORMS.md, reference/pc/Screenshot_30..32): слева плоская панель, а окно
// плеера уезжает вправо и поворачивается вглубь на ~15°. Другие экраны могут открыть нужный раздел.
import type { IconName } from '../components/icons'

export type SettingsTab = 'account' | 'subscription' | 'interface' | 'player' | 'services' | 'integrations' | 'system'

// Названия вкладок и подразделов — по-русски: это ключи перевода, `t()` при показе (SettingsPanel),
// чтобы смена языка подхватывалась сразу.

export const TABS: { id: SettingsTab; title: string }[] = [
  { id: 'account', title: 'Аккаунт' },
  { id: 'subscription', title: 'Подписка' },
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
    { id: 'privacy', title: 'Приватность', icon: 'lock' },
    { id: 'notifications', title: 'Уведомления', icon: 'bell' },
    { id: 'stats', title: 'Статистика', icon: 'bars' },
  ],
  subscription: [{ id: 'plans', title: 'Sonar Deep', icon: 'sparkles' }],
  interface: [
    { id: 'style', title: 'Стиль', icon: 'sparkles' },
    { id: 'look', title: 'Вид', icon: 'palette' },
  ],
  player: [
    { id: 'audio', title: 'Аудио', icon: 'volume' },
    { id: 'view', title: 'Вид', icon: 'player' },
    { id: 'mini', title: 'Мини плеер', icon: 'music' },
  ],
  services: [{ id: 'services', title: 'Сервисы', icon: 'key' }],
  integrations: [{ id: 'apps', title: 'Приложения', icon: 'stack' }],
  system: [
    { id: 'general', title: 'Общее', icon: 'adjustments' },
    { id: 'hotkeys', title: 'Клавиши', icon: 'keyboard' },
    { id: 'remote', title: 'Пульт', icon: 'phone' },
    { id: 'update', title: 'Обновления', icon: 'download' },
    { id: 'storage', title: 'Хранилище', icon: 'database' },
    { id: 'about', title: 'О приложении', icon: 'info' },
  ],
}

/** Боковое меню настроек (решение владельца 2026-11-18, вместо вкладок и капсул): группы с пунктами.
 *  Пункт — пара (вкладка, подраздел) из SUBS: адреса разделов те же, меню только раскладывает их иначе. */
export interface NavGroup {
  title: string
  items: { tab: SettingsTab; sub: string }[]
}

export const NAV: NavGroup[] = [
  {
    title: 'Аккаунт',
    items: [
      { tab: 'account', sub: 'login' },
      { tab: 'account', sub: 'privacy' },
      { tab: 'account', sub: 'notifications' },
      { tab: 'subscription', sub: 'plans' },
      { tab: 'account', sub: 'stats' },
      { tab: 'services', sub: 'services' },
    ],
  },
  {
    title: 'Приложение',
    items: [
      { tab: 'system', sub: 'general' },
      { tab: 'player', sub: 'audio' },
      { tab: 'system', sub: 'storage' },
      { tab: 'integrations', sub: 'apps' },
      { tab: 'system', sub: 'hotkeys' },
      { tab: 'system', sub: 'remote' },
      { tab: 'system', sub: 'update' },
      { tab: 'system', sub: 'about' },
    ],
  },
  {
    title: 'Интерфейс',
    items: [
      { tab: 'interface', sub: 'style' },
      { tab: 'interface', sub: 'look' },
      { tab: 'player', sub: 'view' },
      { tab: 'player', sub: 'mini' },
    ],
  },
]

/** Пункт меню → его описание из SUBS. Названия внутри «Плеера» уточнены, чтобы в общем списке не было двух «Вид». */
export function navSub(tab: SettingsTab, sub: string): SettingsSub | undefined {
  const found = SUBS[tab].find((s) => s.id === sub)
  if (!found) return undefined
  if (tab === 'player' && sub === 'view') return { ...found, title: 'Плеер' }
  if (tab === 'integrations' && sub === 'apps') return { ...found, title: 'Интеграции' }
  return found
}

/** Бывшие подразделы → куда влились (2026-11-18). */
const MERGED_SUBS: Readonly<Record<string, string>> = { tabs: 'look', queue: 'view' }

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
    // «Вкладки» влились в «Вид», «Очередь» — в «Плеер» (2026-11-18): старые ссылки ведут туда
    if (sub) this.sub = MERGED_SUBS[sub] ?? sub
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
