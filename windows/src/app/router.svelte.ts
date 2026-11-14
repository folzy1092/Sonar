// Простой роутер страниц: текущая страница + история для кнопки «назад».
export type Page = 'home' | 'player' | 'search' | 'library' | 'settings'

class Router {
  page = $state<Page>('home')
  private stack = $state<Page[]>([])

  get canGoBack() {
    return this.stack.length > 0
  }

  go(page: Page) {
    if (page === this.page) return
    this.stack.push(this.page)
    if (this.stack.length > 50) this.stack.shift()
    this.page = page
  }

  back() {
    const prev = this.stack.pop()
    if (prev) this.page = prev
  }
}

export const router = new Router()
