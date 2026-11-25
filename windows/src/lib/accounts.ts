// Подключённые аккаунты для списка «Вы вошли как» (медиатека): кто, в каком сервисе и куда вести по клику.
import type { ServicesStatus } from './api'
import { ACCOUNT_SERVICES, statusOf, type ServiceId } from './services'

export interface AccountRow {
  service: ServiceId
  name: string | null
  avatar: string | null
  /** Профиль на сайте сервиса; null — сервис адрес не отдал, тогда строка без ссылки. */
  url: string | null
}

/** Только https-адрес: в `open_url` не должно уходить ничего, кроме страницы в браузер. */
export function safeProfileUrl(url: string | null | undefined): string | null {
  if (!url) return null
  try {
    const u = new URL(url)
    return u.protocol === 'https:' ? u.href : null
  } catch {
    return null
  }
}

/** Строки по порядку сервисов; не подключённые пропускаем. */
export function accountRows(status: ServicesStatus | null | undefined): AccountRow[] {
  const rows: AccountRow[] = []
  for (const s of ACCOUNT_SERVICES) {
    const st = statusOf(status, s)
    if (!st?.connected) continue
    rows.push({ service: s.id, name: st.name, avatar: st.avatar_url, url: safeProfileUrl(st.profile_url) })
  }
  return rows
}

/** Ключ API на экране — спрятан: префикс и последние 4 знака (`snr_••••••••wxyz`). Короткий — целиком точками. */
export function maskKey(key: string): string {
  const prefix = key.startsWith('snr_') ? 'snr_' : ''
  const rest = key.slice(prefix.length)
  return rest.length <= 8 ? '•'.repeat(rest.length) : `${prefix}${'•'.repeat(8)}${rest.slice(-4)}`
}
