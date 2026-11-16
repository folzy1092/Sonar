// История поиска (локально, store/search.rs): запросы и открытые из поиска результаты. Показывается
// под строкой поиска, когда поле пустое; чистится там же и в «Хранилище».
import { api } from './api'

export interface SearchEntry {
  kind: 'query' | 'track' | 'artist' | 'album' | 'playlist'
  query: string
  ref?: string | null
  title?: string | null
  subtitle?: string | null
  cover_url?: string | null
  at?: number
}

class SearchHistory {
  items = $state<SearchEntry[]>([])
  private loaded = false

  async load(force = false) {
    if (this.loaded && !force) return
    this.loaded = true
    try {
      this.items = await api.searchHistory(20)
    } catch {
      this.items = []
    }
  }

  /** Записать и сразу показать наверху (повтор — без дубля, как в базе). */
  add(e: SearchEntry) {
    if (e.kind === 'query' && !e.query.trim()) return
    const same = (x: SearchEntry) => (e.kind === 'query' ? x.kind === 'query' && x.query.toLowerCase() === e.query.trim().toLowerCase() : x.kind === e.kind && x.ref === e.ref)
    this.items = [{ ...e, query: e.query.trim() }, ...this.items.filter((x) => !same(x))].slice(0, 20)
    void api.addSearchHistory(e).catch(() => {})
  }

  async clear() {
    this.items = []
    await api.clearSearchHistory().catch(() => {})
  }
}

export const searchHistory = new SearchHistory()
