// Простой роутер страниц: текущая страница с параметром + история для кнопки «назад».
// playlist: 'favorites' | 'pl_…' (свой) | 'scpl:…' / 'ympl:…' (плейлист сервиса);
// artist: 'sca:…' / 'yma:…'; album: 'scalb:…' / 'ymalb:…'.
export type Page = 'home' | 'player' | 'search' | 'library' | 'playlist' | 'artist' | 'album'

interface Route {
  page: Page
  param: string | null
}

class Router {
  private route = $state<Route>({ page: 'home', param: null })
  private stack = $state<Route[]>([])
  /** Куда вернуться кнопкой «вперёд» (боковая кнопка мыши) после «назад». */
  private ahead = $state<Route[]>([])

  get page() {
    return this.route.page
  }

  get param() {
    return this.route.param
  }

  /** Ключ для перерисовки страницы: другой плейлист — новая страница. */
  get key() {
    return `${this.route.page}:${this.route.param ?? ''}`
  }

  get canGoBack() {
    return this.stack.length > 0
  }

  get canGoForward() {
    return this.ahead.length > 0
  }

  go(page: Page, param: string | null = null) {
    if (page === this.route.page && param === this.route.param) return
    this.stack.push(this.route)
    if (this.stack.length > 50) this.stack.shift()
    this.ahead = []
    this.route = { page, param }
  }

  back() {
    const prev = this.stack.pop()
    if (!prev) return
    this.ahead.push(this.route)
    this.route = prev
  }

  forward() {
    const next = this.ahead.pop()
    if (!next) return
    this.stack.push(this.route)
    this.route = next
  }
}

export const router = new Router()

/** Куда ведёт ref: исполнитель, альбом или плейлист. */
export function openRef(ref: string) {
  const kind = ref.split(':')[0]
  if (kind === 'sca' || kind === 'yma') router.go('artist', ref)
  else if (kind === 'scalb' || kind === 'ymalb') router.go('album', ref)
  else router.go('playlist', ref)
}
