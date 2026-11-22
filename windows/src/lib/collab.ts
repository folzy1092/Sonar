// Совместный плейлист (docs/API.md §4 «Совместные плейлисты»): участники и кто добавил трек.
// Состав ведёт сервер; до него плейлисты всегда обычные — `collaborators` пустой.
import type { Playlist, PlaylistMember } from './api'

type Members = Pick<Playlist, 'owner' | 'collaborators'>

/** Совместный — когда есть хотя бы один соавтор. */
export function isCollab(p: Members): boolean {
  return p.collaborators.length > 0
}

/**
 * Кто добавил трек: участник по `username` (с аватаром), вышедший из плейлиста — только ник.
 * В обычном плейлисте и без `added_by` — null: аватар в строке не нужен.
 */
export function adderOf(p: Members, username: string | undefined): PlaylistMember | null {
  if (!username || !isCollab(p)) return null
  const known = [p.owner, ...p.collaborators].find((m) => m?.username === username)
  return known ?? { username, display_name: null, avatar_url: null }
}
