// Блокировка аккаунта (API.md §1 «Блокировка», `403 account_banned`). Rust отдаёт её во фронт строкой
// `banned:{"until":мс|null,"reason":"…"|null}` (account.rs `ApiError::to_front`); здесь — разбор и текст срока.

export interface Ban {
  /** До какого момента (мс); null — навсегда. */
  until: number | null
  reason: string | null
}

export const BANNED_PREFIX = 'banned:'

/** Ошибка из `invoke` → блокировка, если это она. Кривой JSON — всё равно блокировка, но без срока и причины. */
export function parseBan(e: unknown): Ban | null {
  const s = e instanceof Error ? e.message : String(e)
  if (!s.startsWith(BANNED_PREFIX)) return null
  try {
    const v = JSON.parse(s.slice(BANNED_PREFIX.length)) as { until?: unknown; reason?: unknown }
    return {
      until: typeof v.until === 'number' && Number.isFinite(v.until) ? v.until : null,
      reason: typeof v.reason === 'string' && v.reason.trim() ? v.reason.trim().slice(0, 200) : null,
    }
  } catch {
    return { until: null, reason: null }
  }
}

/** Сессия кончилась по воле сервера: отозвана (`signed_out`) или аккаунт заблокирован. */
export const sessionEnded = (e: unknown): boolean => String(e instanceof Error ? e.message : e) === 'signed_out' || parseBan(e) !== null

/** Срок блокировки для людей: «до 27.11.2026, 14:05» — на языке интерфейса; null — навсегда. */
export function untilText(ban: Ban, locale?: string): string | null {
  if (ban.until === null) return null
  return new Date(ban.until).toLocaleString(locale, { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
}
