// Значки приложения (Интерфейс → Вид → «Значок приложения», настройка `appearance.app_icon`): основной —
// «Стекло», остальные на выбор (решение владельца 2026-11-24). Те же значки и id — в Rust `app_icon.rs`
// (окно, панель задач, трей) и на iPhone `Core/Appearance/AppIcon.swift` (альтернативные значки iOS);
// файлы делает `brand/app-icons/build.mjs`, порядок — порядок плиток. Названия — ключи перевода.

export const APP_ICONS = [
  { id: 'glass', title: 'значок::Стекло' },
  { id: 'flat', title: 'значок::Плоский' },
  { id: 'bevel', title: 'значок::Фаска' },
  { id: 'puff', title: 'значок::Подушка' },
  { id: 'block', title: 'значок::Блок' },
  { id: 'echo', title: 'значок::Эхо' },
  { id: 'well', title: 'значок::Колодец' },
  { id: 'chrome', title: 'значок::Хром' },
  { id: 'carved', title: 'значок::Вдавленный' },
  { id: 'light', title: 'значок::Светлый' },
  { id: 'black', title: 'значок::Чёрный' },
  { id: 'white', title: 'значок::Белый' },
] as const

export type AppIconId = (typeof APP_ICONS)[number]['id']

/** Основной значок: тот, что вшит в exe и в сборку iOS. */
export const DEFAULT_APP_ICON: AppIconId = 'glass'

export const isAppIcon = (id: unknown): id is AppIconId => APP_ICONS.some((i) => i.id === id)

/** Незнакомый id (настройка из другой сборки) — основной значок. */
export const appIconOr = (id: unknown): AppIconId => (isAppIcon(id) ? id : DEFAULT_APP_ICON)

/** Картинка плитки: PNG 160 px с прозрачными углами (`windows/public/app-icons`). */
export const appIconSrc = (id: AppIconId): string => `/app-icons/${id}.png`
