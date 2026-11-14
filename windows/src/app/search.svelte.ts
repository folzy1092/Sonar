// Состояние строки поиска: запрос и выбранный источник.
export type Source = 'sc' | 'ym'

class SearchState {
  query = $state('')
  source = $state<Source>('sc')
}

export const search = new SearchState()
