// Состояние строки поиска: запрос и выбранный источник.
import type { Source } from '../lib/api'

export type { Source }
/** 'all' — единый поиск по всем сервисам (lib/unified-search.ts). */
export type SearchSource = Source | 'all'

class SearchState {
  query = $state('')
  source = $state<SearchSource>('all')
}

export const search = new SearchState()
