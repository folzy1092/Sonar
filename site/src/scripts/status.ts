// Живая часть /status: даты полосок на сегодня, подсказка при наведении на день, а когда у сайта есть
// API (`API_URL` в config.ts) — опрос `GET /status` и `GET /status/history` раз в минуту.
import { pluralIndex, type Lang } from '../i18n'
import {
  HISTORY_DAYS,
  UPTIME_OK,
  averageUptime,
  formatUptime,
  lastDays,
  minutesSince,
  parseHistory,
  parseStatus,
  uptimeState,
  type HistoryDay,
  type State,
  type StatusReport,
} from '../lib/status'

interface Strings {
  api: string | null
  words: Record<State, string>
  banner: Record<'ok' | 'degraded' | 'down' | 'error' | 'errorText', string>
  ago: string
  justNow: string
  uptime: string
  people: Record<'online' | 'day' | 'users', string>
  rowUptime: string
  barsLabel: string
  noIncidents: string
}

const REFRESH_MS = 60_000
const TIMEOUT_MS = 8_000
const LOCALES: Record<Lang, string> = { ru: 'ru-RU', en: 'en-GB', uk: 'uk-UA', es: 'es-ES', de: 'de-DE', pl: 'pl-PL' }

function fill(text: string, vars: Record<string, string | number>): string {
  return text.replace(/\{(\w+)\}/g, (m, k: string) => (k in vars ? String(vars[k]) : m))
}

function rows(root: HTMLElement): HTMLElement[] {
  return [...root.querySelectorAll<HTMLElement>('[data-row]')]
}

function rowName(row: HTMLElement): string {
  return row.querySelector('.row__name')?.textContent?.trim() ?? row.dataset.row ?? ''
}

/** Страница собрана заранее — даты полосок пересчитываются на сегодняшний день. */
function relabelDays(root: HTMLElement): void {
  const days = lastDays(Date.now(), HISTORY_DAYS)
  for (const bars of root.querySelectorAll<HTMLElement>('[data-bars]')) {
    bars.querySelectorAll<HTMLElement>('.bar').forEach((bar, i) => {
      bar.dataset.date = days[i]
    })
  }
}

function initHints(root: HTMLElement, s: Strings, locale: string): void {
  const dateFmt = new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', timeZone: 'UTC' })
  for (const row of rows(root)) {
    const hint = row.querySelector<HTMLElement>('[data-row-hint]')
    const bars = row.querySelector<HTMLElement>('[data-bars]')
    if (!hint || !bars) continue
    bars.addEventListener('pointerover', (e) => {
      const bar = (e.target as HTMLElement).closest<HTMLElement>('.bar')
      if (!bar?.dataset.date) return
      const pct = bar.dataset.pct ? Number(bar.dataset.pct) : null
      const what = pct === null ? s.words.none : formatUptime(pct, locale)
      hint.textContent = `${dateFmt.format(new Date(`${bar.dataset.date}T00:00:00Z`))} · ${what}`
    })
    bars.addEventListener('pointerleave', () => {
      hint.textContent = hint.dataset.default ?? ''
    })
  }
}

async function getJson(url: string): Promise<unknown> {
  const res = await fetch(url, { signal: AbortSignal.timeout(TIMEOUT_MS), headers: { Accept: 'application/json' } })
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`)
  return res.json()
}

function agoText(s: Strings, lang: Lang, checkedAt: number): string {
  const n = minutesSince(checkedAt, Date.now())
  if (n === 0) return s.justNow
  const forms = s.ago.split('|')
  return fill(forms[Math.min(pluralIndex(lang, n), forms.length - 1)], { n })
}

function renderBanner(root: HTMLElement, s: Strings, lang: Lang, locale: string, report: StatusReport | null): void {
  const banner = root.querySelector<HTMLElement>('[data-banner]')
  const title = root.querySelector<HTMLElement>('[data-banner-title]')
  const text = root.querySelector<HTMLElement>('[data-banner-text]')
  const meta = root.querySelector<HTMLElement>('[data-banner-meta]')
  if (!banner || !title || !text || !meta) return
  banner.dataset.state = report ? report.state : 'error'
  title.textContent = report ? s.banner[report.state] : s.banner.error
  text.textContent = s.banner.errorText
  text.hidden = report !== null
  meta.hidden = report === null
  if (report) {
    const uptime = fill(s.uptime, { pct: formatUptime(report.uptime30d, locale) })
    const num = new Intl.NumberFormat(locale)
    const people = (['online', 'day', 'users'] as const).flatMap((k) => {
      const n = report.people[k]
      return n === null ? [] : [fill(s.people[k], { n: num.format(n) })]
    })
    meta.textContent = [agoText(s, lang, report.checkedAt), uptime, ...people].join(' · ')
  }
}

function renderRow(row: HTMLElement, s: Strings, locale: string, report: StatusReport, history: readonly HistoryDay[]): void {
  const id = row.dataset.row ?? ''
  const state: State = report.items.get(id)?.state ?? 'none'
  const byDate = new Map(history.map((d) => [d.date, d.items[id]]))
  const avg = averageUptime(history, id)
  row.dataset.state = state
  const word = row.querySelector<HTMLElement>('[data-row-word]')
  if (word) word.textContent = s.words[state]
  const hint = row.querySelector<HTMLElement>('[data-row-hint]')
  if (hint) {
    hint.dataset.default = avg === null ? '' : fill(s.rowUptime, { pct: formatUptime(avg, locale) })
    if (!row.querySelector('[data-bars]:hover')) hint.textContent = hint.dataset.default
  }
  const bars = row.querySelector<HTMLElement>('[data-bars]')
  bars?.setAttribute('aria-label', fill(s.barsLabel, { name: rowName(row), pct: avg === null ? s.words.none : formatUptime(avg, locale) }))
  bars?.querySelectorAll<HTMLElement>('.bar').forEach((bar) => {
    const pct = byDate.get(bar.dataset.date ?? '')
    bar.dataset.state = uptimeState(pct)
    if (pct === undefined) delete bar.dataset.pct
    else bar.dataset.pct = String(pct)
  })
}

/** «История сбоев» — дни, где аптайм сервиса ниже нормы, от свежих к старым. */
function renderIncidents(root: HTMLElement, s: Strings, locale: string, history: readonly HistoryDay[]): void {
  const list = root.querySelector<HTMLOListElement>('[data-incidents]')
  const empty = root.querySelector<HTMLElement>('[data-incidents-empty]')
  const emptyText = root.querySelector<HTMLElement>('[data-incidents-text]')
  if (!list || !empty || !emptyText) return
  const names = new Map(rows(root).map((r) => [r.dataset.row ?? '', rowName(r)]))
  const dateFmt = new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'long', timeZone: 'UTC' })
  const incidents = [...history]
    .sort((a, b) => b.date.localeCompare(a.date))
    .flatMap((day) =>
      Object.entries(day.items)
        .filter(([id, pct]) => names.has(id) && pct < UPTIME_OK)
        .map(([id, pct]) => ({ date: day.date, name: names.get(id) ?? id, pct })),
    )
  list.replaceChildren(
    ...incidents.map((inc, i) => {
      const li = document.createElement('li')
      li.style.setProperty('--i', String(i))
      const time = document.createElement('time')
      time.dateTime = inc.date
      time.textContent = dateFmt.format(new Date(`${inc.date}T00:00:00Z`))
      const what = document.createElement('span')
      what.textContent = `${inc.name} — ${formatUptime(inc.pct, locale)}`
      li.append(time, what)
      return li
    }),
  )
  list.hidden = incidents.length === 0
  empty.hidden = incidents.length > 0
  emptyText.textContent = s.noIncidents
}

async function refresh(root: HTMLElement, s: Strings, lang: Lang, locale: string, api: string): Promise<void> {
  try {
    const [status, history] = await Promise.all([
      getJson(`${api}/status`),
      getJson(`${api}/status/history?days=${HISTORY_DAYS}`),
    ])
    const report = parseStatus(status)
    if (!report) throw new Error('status: неожиданный ответ')
    const days = parseHistory(history)
    renderBanner(root, s, lang, locale, report)
    for (const row of rows(root)) renderRow(row, s, locale, report, days)
    renderIncidents(root, s, locale, days)
  } catch (err) {
    console.warn('Sonar status:', err)
    renderBanner(root, s, lang, locale, null)
  }
}

export function initStatus(root: HTMLElement): void {
  const raw = root.querySelector('[data-status-strings]')?.textContent
  if (!raw) return
  const s = JSON.parse(raw) as Strings
  const lang = (root.dataset.lang ?? 'ru') as Lang
  const locale = LOCALES[lang] ?? LOCALES.ru
  relabelDays(root)
  initHints(root, s, locale)
  if (!s.api) return
  const api = s.api.replace(/\/+$/, '')
  const load = () => void refresh(root, s, lang, locale, api)
  // Первый раз — сразу; дальше — раз в минуту, пока вкладку видно, и при возвращении на неё.
  load()
  setInterval(() => {
    if (document.visibilityState === 'visible') load()
  }, REFRESH_MS)
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') load()
  })
}
