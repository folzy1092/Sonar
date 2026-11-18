// Версии для блока «Скачать»: iOS — `updates/ios-update.json`, «Что нового» — `updates/changelog.json`.
// Версия Windows выпускается на каждый пуш (авто-патч), поэтому на странице она уточняется у GitHub
// (`releases/latest`), а при сборке подставляется последняя из changelog.
import changelog from '../../../updates/changelog.json'
import iosUpdate from '../../../updates/ios-update.json'

export type Platform = 'windows' | 'ios'

export interface ChangelogEntry {
  readonly version: string
  readonly date: string
  readonly platform: Platform
  readonly title: string
  readonly changes: readonly string[]
}

export const CHANGELOG = changelog as readonly ChangelogEntry[]

export const IOS = {
  version: iosUpdate.version,
  build: iosUpdate.build,
  notes: iosUpdate.notes,
  minOs: '18',
} as const

const WINDOWS_TAG_RE = /^windows-v(\d+\.\d+\.\d+)$/

/** `windows-v0.1.23` → `0.1.23`; чужой тег (iOS и т. п.) → null. */
export function windowsVersionFromTag(tag: unknown): string | null {
  if (typeof tag !== 'string') return null
  return WINDOWS_TAG_RE.exec(tag)?.[1] ?? null
}

/** Сравнение версий `a.b.c` по числам. */
export function compareVersions(a: string, b: string): number {
  const pa = a.split('.').map(Number)
  const pb = b.split('.').map(Number)
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0)
    if (d !== 0) return d
  }
  return 0
}

/** Последняя запись changelog для платформы (по версии, не по порядку в файле). */
export function latestEntry(platform: Platform, entries: readonly ChangelogEntry[] = CHANGELOG): ChangelogEntry | null {
  return entries
    .filter((e) => e.platform === platform)
    .reduce<ChangelogEntry | null>((best, e) => (!best || compareVersions(e.version, best.version) > 0 ? e : best), null)
}

const MB = 1024 * 1024

/** Размер файла в мегабайтах с одной цифрой после запятой: `12.4`. */
export function megabytes(bytes: number): string {
  return (Math.round((bytes / MB) * 10) / 10).toFixed(1)
}

/** Что нужно странице из ответа GitHub `releases/latest`; неверный ответ → null. */
export interface WindowsRelease {
  readonly version: string
  readonly sizeBytes: number | null
}

export function parseLatestRelease(json: unknown, assetName: string): WindowsRelease | null {
  if (!json || typeof json !== 'object') return null
  const rel = json as { tag_name?: unknown; assets?: unknown }
  const version = windowsVersionFromTag(rel.tag_name)
  if (!version) return null
  const assets = Array.isArray(rel.assets) ? (rel.assets as { name?: unknown; size?: unknown }[]) : []
  const asset = assets.find((a) => a.name === assetName)
  return { version, sizeBytes: typeof asset?.size === 'number' ? asset.size : null }
}
