// Плейлисты в панели Sonar (app/Rail.svelte): свои, не скрытые, свежие правки сверху. Чистая функция — тест рядом.
import type { Playlist } from '../lib/api'

/** Больше не влезает в колонку и на ноутбуке — дальше путь через Медиатеку. */
export const RAIL_PINS_MAX = 12

export function railPins(playlists: readonly Playlist[], max = RAIL_PINS_MAX): Playlist[] {
  return playlists
    .filter((p) => !p.hidden)
    .slice()
    .sort((a, b) => b.updated_at - a.updated_at)
    .slice(0, max)
}
