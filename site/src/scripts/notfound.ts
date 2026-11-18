// Роутер 404.html: `/@username` → заглушка профиля, остальное — обычная 404.
import { href, splitLang, LANGS, type Lang } from '../i18n'
import { parseMissingRoute, restorePath } from '../lib/route'

interface Strings {
  readonly profileTitle: string
}

export function initNotFound(root: HTMLElement): void {
  const lang = document.documentElement.lang as Lang
  const back = restorePath(new URLSearchParams(location.search).get('from'), lang)
  if (back) history.replaceState(null, '', back)

  const route = parseMissingRoute(splitLang(location.pathname).rest)
  if (route.kind !== 'profile') return

  const strings = JSON.parse(root.querySelector('[data-nf-strings]')?.textContent ?? '{}') as Strings
  const handle = `@${route.username}`
  root.dataset.state = 'profile'
  root.querySelectorAll<HTMLElement>('[data-nf-missing]').forEach((el) => (el.hidden = true))
  root.querySelectorAll<HTMLElement>('[data-nf-profile]').forEach((el) => (el.hidden = false))
  root.querySelectorAll('[data-nf-handle]').forEach((el) => (el.textContent = handle))
  root.querySelectorAll('[data-nf-initial]').forEach((el) => (el.textContent = route.username[0]))
  if (strings.profileTitle) document.title = `${strings.profileTitle.replace('{name}', route.username)} — Sonar`

  // флаг языка ведёт на этот же профиль на другом языке
  for (const l of LANGS) {
    document.querySelectorAll<HTMLAnchorElement>(`[data-lang-link="${l}"]`).forEach((a) => {
      a.href = href(l, `/@${route.username}`)
    })
  }
}
