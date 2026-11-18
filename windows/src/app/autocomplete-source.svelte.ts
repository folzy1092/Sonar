// Кандидаты серой подсказки в строке поиска (lib/autocomplete.ts): Любимые → история поиска → недавнее.
// Список собирается один раз и держится в памяти; база читается при первом фокусе поля, Любимые — заново
// при смене лайков, недавнее — не чаще раза в минуту. На каждую букву — только поиск по готовому списку.
import { untrack } from 'svelte'
import { api, type Track } from '../lib/api'
import { buildCandidates } from '../lib/autocomplete'
import { library } from '../lib/library.svelte'
import { searchHistory } from '../lib/search-history.svelte'

/** Сколько недавних треков смотреть. */
const RECENT_LIMIT = 50
/** Недавнее перечитывается при фокусе не чаще, чем раз в столько мс. */
const RECENT_TTL_MS = 60_000

class AutocompleteSource {
  private liked = $state.raw<Track[]>([])
  private recent = $state.raw<Track[]>([])
  private started = false
  private recentAt = 0

  readonly candidates = $derived(buildCandidates({ liked: this.liked, history: searchHistory.items, recent: this.recent }))

  /** Поле поиска получило фокус: подтянуть то, чего ещё нет. Ошибки базы — просто без подсказки. */
  ensure() {
    void searchHistory.load()
    if (!this.started) {
      this.started = true
      void this.loadLiked()
    }
    if (Date.now() - this.recentAt > RECENT_TTL_MS) {
      this.recentAt = Date.now()
      api
        .recentTracks(RECENT_LIMIT)
        .then((list) => (this.recent = list))
        .catch(() => {})
    }
  }

  /** Лайки поменялись — перечитать Любимые (только если подсказка уже включалась). Звать из компонента. */
  watchLikes() {
    $effect(() => {
      void library.liked
      untrack(() => this.started && void this.loadLiked())
    })
  }

  private async loadLiked() {
    try {
      this.liked = await api.favorites()
    } catch {
      this.liked = []
    }
  }
}

export const autocompleteSource = new AutocompleteSource()
