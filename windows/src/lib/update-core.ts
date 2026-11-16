// Чистая логика автообновления (ROADMAP W6): сравнение версий Г.О.Ф, разбор `updates/changelog.json`
// и заметок релиза. Без Tauri — покрыто тестами.

/** Запись `updates/changelog.json`. `platform` нет — запись общая для всех клиентов. */
export interface ChangelogEntry {
  version: string
  date: string
  platform?: 'windows' | 'ios'
  title?: string
  changes: string[]
}

/** Сравнение версий «1.2.3» (Г.О.Ф): <0 — a старше, 0 — равны, >0 — a новее. */
export function compareVersions(a: string, b: string): number {
  const parts = (v: string) => v.replace(/^v/, '').split(/[.-]/).map((p) => Number.parseInt(p, 10) || 0)
  const x = parts(a)
  const y = parts(b)
  for (let i = 0; i < Math.max(x.length, y.length, 3); i++) {
    const d = (x[i] ?? 0) - (y[i] ?? 0)
    if (d) return d
  }
  return 0
}

/** Бета-сборка: «0.2.0-beta.1», «0.2.0-rc1» и т.п. Стабильный канал такие не предлагает. */
export function isBeta(version: string): boolean {
  return /-(?:alpha|beta|rc|pre|dev)/i.test(version)
}

/** Записи истории, которые придут с обновлением: новее установленной и не новее найденной. */
export function pendingEntries(log: ChangelogEntry[], current: string, target: string): ChangelogEntry[] {
  return log.filter((e) => compareVersions(e.version, current) > 0 && compareVersions(e.version, target) <= 0)
}

/** Записи для Windows (и общие), новые сверху, без мусора. */
export function parseChangelog(raw: unknown): ChangelogEntry[] {
  if (!Array.isArray(raw)) return []
  return raw
    .filter(
      (e): e is ChangelogEntry =>
        !!e && typeof e === 'object' && typeof (e as ChangelogEntry).version === 'string' && Array.isArray((e as ChangelogEntry).changes),
    )
    .filter((e) => !e.platform || e.platform === 'windows')
    .map((e) => ({ ...e, date: typeof e.date === 'string' ? e.date : '', changes: e.changes.filter((c) => typeof c === 'string' && c.trim()) }))
    .sort((a, b) => compareVersions(b.version, a.version))
}

/** Релиз GitHub (`/repos/…/releases`), нужные поля. */
export interface GhRelease {
  tag_name: string
  published_at?: string | null
  body?: string | null
  draft?: boolean
  prerelease?: boolean
}

/** История версий: записи `changelog.json` (с названиями) + каждый выпущенный релиз `windows-v*`
 *  (авто-патчи с CI в changelog не попадают — их пункты берутся из заметок релиза). Новые сверху. */
export function mergeReleases(log: ChangelogEntry[], releases: GhRelease[]): ChangelogEntry[] {
  const have = new Set(log.map((e) => e.version))
  const extra: ChangelogEntry[] = []
  for (const r of releases) {
    const m = /^windows-v(\d+\.\d+\.\d+[\w.-]*)$/.exec(r.tag_name ?? '')
    if (!m || r.draft || have.has(m[1])) continue
    have.add(m[1])
    extra.push({
      version: m[1],
      date: (r.published_at ?? '').slice(0, 10),
      platform: 'windows',
      // авто-патч: первая строка коммита — заголовок, остальное — пункты
      changes: noteLines(r.body).slice(0, 14),
    })
  }
  return [...log, ...extra].sort((a, b) => compareVersions(b.version, a.version))
}

/** Заметки релиза (`notes` в latest.json) → пункты списка: строки «- …», «• …» или просто строки. */
export function noteLines(notes: string | undefined | null): string[] {
  if (!notes) return []
  return notes
    .split(/\r?\n/)
    .map((l) => l.replace(/^\s*(?:[-*•]|\d+[.)])\s*/, '').trim())
    .filter(Boolean)
}

/** «только что», «5 мин назад», «3 ч назад», «2 дн назад». */
export function agoText(ts: number, now = Date.now()): string {
  const min = Math.floor((now - ts) / 60_000)
  if (min < 1) return 'только что'
  if (min < 60) return `${min} мин назад`
  const h = Math.floor(min / 60)
  if (h < 24) return `${h} ч назад`
  return `${Math.floor(h / 24)} дн назад`
}

/** «12.4 из 18.0 МБ». */
export function sizeText(got: number, total: number | null): string {
  const mb = (b: number) => (b / 1_048_576).toFixed(1)
  return total ? `${mb(got)} из ${mb(total)} МБ` : `${mb(got)} МБ`
}
