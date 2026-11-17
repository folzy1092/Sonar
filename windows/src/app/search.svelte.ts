// Состояние строки поиска: запрос и выбранный источник.
import type { Source } from '../lib/api'

export type { Source }

class SearchState {
  query = $state('')
  source = $state<Source>('sc')
}

export const search = new SearchState()
