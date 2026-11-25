// Публичный профиль `/@username` с сервера (`GET /public/users/{username}`, API.md §1).

export interface PublicProfile {
  readonly username: string
  readonly displayName: string
  readonly number: number | null
  readonly createdAt: number | null
}

export type ProfileResult =
  | { readonly kind: 'found'; readonly profile: PublicProfile }
  | { readonly kind: 'missing' }
  | { readonly kind: 'error' }

/** Ответ сервера → что показать. 404 — такого профиля нет; кривой ответ — ошибка, а не пустая страница. */
export function readProfile(status: number, body: unknown, username: string): ProfileResult {
  if (status === 404) return { kind: 'missing' }
  if (status !== 200 || !body || typeof body !== 'object') return { kind: 'error' }
  const b = body as Record<string, unknown>
  const name = typeof b.username === 'string' && b.username ? b.username : username
  const display = typeof b.display_name === 'string' && b.display_name.trim() ? b.display_name.trim() : name
  const number = Number.isInteger(b.number) && (b.number as number) > 0 ? (b.number as number) : null
  const created = typeof b.created_at === 'number' && b.created_at > 0 ? b.created_at : null
  return { kind: 'found', profile: { username: name, displayName: display, number, createdAt: created } }
}

/** `@mira · #7` */
export function profileHandle(p: PublicProfile): string {
  return p.number ? `@${p.username} · #${p.number}` : `@${p.username}`
}
