// Автообновление (ROADMAP W6): `tauri-plugin-updater` читает `latest.json` из релиза
// `windows-latest` на GitHub (подпись проверяется ключом из tauri.conf.json), качает установщик
// NSIS и ставит его поверх. Проверка — при запуске и раз в 6 ч (`update.auto_check`), скачивание
// в фоне — `update.auto_download`. Найденное обновление показывает app/UpdatePopup.svelte.
import { getVersion } from '@tauri-apps/api/app'
import { check, type Update } from '@tauri-apps/plugin-updater'
import { relaunch } from '@tauri-apps/plugin-process'
import { isTauri } from './tauri'
import { settings } from './settings.svelte'
import { t } from './i18n.svelte'
import { offline } from './offline.svelte'
import { compareVersions, isBeta, mergeReleases, noteLines, parseChangelog, type ChangelogEntry } from './update-core'

export type UpdatePhase = 'idle' | 'checking' | 'none' | 'available' | 'downloading' | 'ready' | 'installing' | 'error'

const CHANGELOG_URL = 'https://raw.githubusercontent.com/folzy1092/Sonar/main/updates/changelog.json'
const RELEASES_URL = 'https://api.github.com/repos/folzy1092/Sonar/releases?per_page=60'
const EVERY = 6 * 3_600_000
const FIRST_DELAY = 8_000

class Updater {
  phase = $state<UpdatePhase>('idle')
  current = $state('0.1.0')
  version = $state('')
  date = $state('')
  notes = $state<string[]>([])
  got = $state(0)
  total = $state<number | null>(null)
  error = $state('')
  checkedAt = $state<number | null>(null)
  changelog = $state<ChangelogEntry[] | null>(null)
  /** Всплывашка «Доступно обновление»: показывается сама, закрывается только кликом. */
  popup = $state(false)
  /** Версия, которую пользователь отложил кнопкой «Позже» — всплывашка про неё больше не выскочит. */
  private snoozed = ''
  private failedAt: 'check' | 'download' | 'install' = 'check'
  private update: Update | null = null
  private timer: ReturnType<typeof setInterval> | null = null
  private started = false

  get progress() {
    return this.total ? Math.min(1, this.got / this.total) : 0
  }

  get busy() {
    return this.phase === 'checking' || this.phase === 'downloading' || this.phase === 'installing'
  }

  init() {
    if (this.started) return
    this.started = true
    if (isTauri) void getVersion().then((v) => (this.current = v)).catch(() => {})
    setTimeout(() => void this.auto(), FIRST_DELAY)
    this.timer = setInterval(() => void this.auto(), EVERY)
  }

  private async auto() {
    await settings.load()
    if (offline.on || !settings.get('update.auto_check') || this.busy || this.phase === 'ready') return
    await this.check(true)
  }

  /** `silent` — фоновая проверка: ошибки сети не показываем, нашли — всплывашка. */
  async check(silent = false) {
    if (this.busy) return
    // офлайн: ни запроса — плагин обновлений ходит в сеть своим клиентом, мимо ворот Rust
    if (offline.on) {
      if (!silent) {
        this.phase = 'error'
        this.failedAt = 'check'
        this.error = t('Нет доступа к сети: включён офлайн-режим')
      }
      return
    }
    this.phase = 'checking'
    this.error = ''
    try {
      const u = await find()
      this.checkedAt = Date.now()
      if (!u) {
        this.update = null
        this.phase = 'none'
        return
      }
      this.update = u.raw
      this.version = u.version
      this.date = u.date
      this.notes = u.notes
      this.phase = 'available'
      if (settings.get('update.auto_download')) await this.download()
      if (silent && this.version !== this.snoozed && (this.phase === 'available' || this.phase === 'ready')) this.popup = true
    } catch (e) {
      this.phase = silent ? 'idle' : 'error'
      this.failedAt = 'check'
      this.error = humanError(e)
    }
  }

  async download() {
    if (this.phase !== 'available' && this.phase !== 'error') return
    if (offline.on) return void this.check()
    if (!this.update && isTauri) return void this.check()
    this.phase = 'downloading'
    this.got = 0
    this.total = null
    try {
      if (this.update) {
        await this.update.download((e) => {
          if (e.event === 'Started') this.total = e.data.contentLength ?? null
          else if (e.event === 'Progress') this.got += e.data.chunkLength
        })
      } else await fakeDownload(this)
      this.phase = 'ready'
    } catch (e) {
      this.phase = 'error'
      this.failedAt = 'download'
      this.error = humanError(e)
    }
  }

  /** Ставит скачанное: установщик NSIS в тихом режиме закрывает Sonar и запускает новую версию. */
  async install() {
    if (this.phase !== 'ready') return
    this.phase = 'installing'
    try {
      if (!this.update) return
      await this.update.install()
      await relaunch()
    } catch (e) {
      // установщик не запустился — скачанный файл уже не годится, качаем заново
      this.phase = 'error'
      this.failedAt = 'download'
      this.error = humanError(e)
    }
  }

  /** После ошибки: сорвалось скачивание — качаем заново, иначе проверяем ещё раз. */
  retry() {
    return this.failedAt === 'download' ? this.download() : this.check()
  }

  later() {
    this.snoozed = this.version
    this.popup = false
  }

  async loadChangelog() {
    if (this.changelog || offline.on) return
    try {
      // changelog.json — версии с названием; релизы GitHub — все авто-патчи (0.1.42, 0.1.55 …)
      const [log, rel] = await Promise.all([
        fetch(CHANGELOG_URL, { cache: 'no-store' })
          .then((r) => (r.ok ? r.json() : []))
          .catch(() => []),
        fetch(RELEASES_URL, { cache: 'no-store', headers: { Accept: 'application/vnd.github+json' } })
          .then((r) => (r.ok ? r.json() : []))
          .catch(() => []),
      ])
      this.changelog = mergeReleases(parseChangelog(log), Array.isArray(rel) ? rel : [])
    } catch {
      this.changelog = []
    }
  }

  destroy() {
    if (this.timer) clearInterval(this.timer)
  }
}

interface Found {
  raw: Update | null
  version: string
  date: string
  notes: string[]
}

async function find(): Promise<Found | null> {
  if (isTauri) {
    const u = await check({ timeout: 20_000 })
    if (!u) return null
    // бета приходит только тем, кто выбрал канал «Бета»; стабильному — ничего не предлагаем
    if (isBeta(u.version) && settings.get('update.channel') !== 'beta') return null
    return { raw: u, version: u.version, date: u.date ?? '', notes: noteLines(u.body) }
  }
  // Превью интерфейса в браузере (npm run dev): показываем пример, чтобы видеть все состояния.
  if (!import.meta.env.DEV) return null
  await new Promise((r) => setTimeout(r, 900))
  if (compareVersions('0.1.1', updater.current) <= 0) return null
  return {
    raw: null,
    version: '0.1.1',
    date: new Date().toISOString(),
    notes: [t('Пример заметок к обновлению'), t('Видно только в превью интерфейса')],
  }
}

async function fakeDownload(u: Updater) {
  u.total = 18 * 1_048_576
  while (u.got < u.total) {
    await new Promise((r) => setTimeout(r, 60))
    u.got = Math.min(u.total, u.got + 600_000)
  }
}

function humanError(e: unknown): string {
  const s = String(e instanceof Error ? e.message : e)
  if (/signature/i.test(s)) return t('Подпись обновления не сошлась — файл не установлен')
  if (/timed? ?out|timeout/i.test(s)) return t('Сервер обновлений не ответил')
  if (/network|connect|dns|error sending request/i.test(s)) return t('Нет связи с GitHub')
  if (/404|not found|release json/i.test(s)) return t('Релиз ещё не опубликован')
  return s ? t(s) : t('Не удалось проверить обновления')
}

export const updater = new Updater()
