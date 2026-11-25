// Роутер 404: `/@username` → публичный профиль с сервера, остальное — обычная 404.
import { API_URL } from '../config'
import { href, splitLang, LANGS, type Lang } from '../i18n'
import { profileHandle, readProfile, type ProfileResult, type PublicProfile } from '../lib/profile'
import { parseMissingRoute, restorePath } from '../lib/route'

interface Strings {
  readonly profileTitle: string
  readonly loading: string
  readonly since: string
  readonly showcase: string
  readonly errorTitle: string
  readonly errorLead: string
}

const TIMEOUT_MS = 8_000

export function initNotFound(root: HTMLElement): void {
  const lang = document.documentElement.lang as Lang
  const back = restorePath(new URLSearchParams(location.search).get('from'), lang)
  if (back) history.replaceState(null, '', back)

  const route = parseMissingRoute(splitLang(location.pathname).rest)
  if (route.kind !== 'profile') return

  const strings = JSON.parse(root.querySelector('[data-nf-strings]')?.textContent ?? '{}') as Strings
  const missingTitle = document.title
  root.dataset.state = 'profile'
  show(root, 'profile')
  setText(root, '[data-nf-handle]', `@${route.username}`)
  setText(root, '[data-nf-initial]', route.username[0])
  if (strings.profileTitle) document.title = `${strings.profileTitle.replace('{name}', route.username)} — Sonar`

  // флаг языка ведёт на этот же профиль на другом языке
  for (const l of LANGS) {
    document.querySelectorAll<HTMLAnchorElement>(`[data-lang-link="${l}"]`).forEach((a) => {
      a.href = href(l, `/@${route.username}`)
    })
  }

  // без сервера остаётся заглушка из разметки
  if (!API_URL) return
  setText(root, '[data-nf-name]', strings.loading)
  setText(root, '[data-nf-lead]', '')
  void loadProfile(API_URL, route.username).then((result) => render(root, strings, lang, result, missingTitle))
}

async function loadProfile(api: string, username: string): Promise<ProfileResult> {
  try {
    const res = await fetch(`${api}/public/users/${encodeURIComponent(username)}`, {
      signal: AbortSignal.timeout(TIMEOUT_MS),
      headers: { Accept: 'application/json' },
    })
    const body: unknown = res.status === 200 ? await res.json() : null
    return readProfile(res.status, body, username)
  } catch {
    return { kind: 'error' }
  }
}

function render(root: HTMLElement, strings: Strings, lang: Lang, result: ProfileResult, missingTitle: string): void {
  if (result.kind === 'missing') {
    root.dataset.state = 'missing'
    show(root, 'missing')
    document.title = missingTitle
    return
  }
  if (result.kind === 'error') {
    setText(root, '[data-nf-name]', strings.errorTitle)
    setText(root, '[data-nf-lead]', strings.errorLead)
    return
  }
  const p = result.profile
  setText(root, '[data-nf-name]', p.displayName)
  setText(root, '[data-nf-handle]', profileHandle(p))
  setText(root, '[data-nf-initial]', p.displayName[0])
  setText(root, '[data-nf-lead]', sinceText(strings, lang, p))
  document.title = `${p.displayName} (@${p.username}) — Sonar`
}

function sinceText(strings: Strings, lang: Lang, p: PublicProfile): string {
  if (!p.createdAt) return strings.showcase
  const date = new Intl.DateTimeFormat(lang, { dateStyle: 'long' }).format(new Date(p.createdAt))
  const since = strings.since.replace('{date}', date)
  // «26 ноября 2026 г.» уже с точкой — вторую не ставим
  return `${/[.!?]$/.test(since) ? since : `${since}.`} ${strings.showcase}`
}

function show(root: HTMLElement, view: 'profile' | 'missing'): void {
  root.querySelectorAll<HTMLElement>('[data-nf-missing]').forEach((el) => (el.hidden = view !== 'missing'))
  root.querySelectorAll<HTMLElement>('[data-nf-profile]').forEach((el) => (el.hidden = view !== 'profile'))
}

function setText(root: HTMLElement, selector: string, text: string): void {
  root.querySelectorAll(selector).forEach((el) => (el.textContent = text))
}
