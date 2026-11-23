// Скачивание треков (`docs/OFFLINE.md` §8, Rust — `downloads.rs`): зеркало очереди (`downloads-changed`) и набора
// скачанного (`downloaded_refs`, перечитывается по `offline-index-changed`). Меню треков, плейлистов и альбомов зовут
// `download`, строки треков показывают `stateOf`, карточка «Скачанное» в Хранилище — прогресс и кнопки.
// Автоскачивание Любимых (`storage.auto_download_liked`): при запуске и после лайка недостающие лайки встают в
// очередь, пока всё скачанное влезает в `storage.auto_download_limit_gb`. Лимитную сеть (мобильная точка доступа)
// ПК не различает — проверки Wi-Fi нет, качает по любой сети.
import { api, errorText, onDownloadsChanged, onOfflineIndexChanged, type DownloadJob, type DownloadsSnapshot, type ListTrack, type Track } from './api'
import { batchBytes, bytesText, likedPlan, needsConfirm, progress, toDownload, type Quality } from './downloads-core'
import { confirm } from './confirm.svelte'
import { offline } from './offline.svelte'
import { settings } from './settings.svelte'
import { toast } from './toast.svelte'
import { t, tn } from './i18n.svelte'

/** Что показать в строке трека. */
export type RowState = DownloadJob['state'] | 'done' | null

const EMPTY: DownloadsSnapshot = { paused: false, done: 0, left: 0, jobs: {} }
const GB = 1024 ** 3

class Downloads {
  queue = $state<DownloadsSnapshot>(EMPTY)
  refs = $state<ReadonlySet<string>>(new Set())
  private started = false

  /** Один раз за запуск (App.svelte): подписки и первое чтение. */
  init() {
    if (this.started) return
    this.started = true
    onDownloadsChanged((s) => this.apply(s))
    onOfflineIndexChanged(() => void this.reload())
    void this.reload().then(() => this.fillLiked())
    api
      .downloadsState()
      .then((s) => (this.queue = s))
      .catch((e) => console.warn('скачивание: очередь не прочиталась', e))
  }

  /** Докачанный трек уходит из очереди раньше, чем придёт новый `downloaded_refs`, — сразу считаем его скачанным, без мигания значка. */
  private apply(next: DownloadsSnapshot) {
    const prev = this.queue
    if (next.done > prev.done) {
      const finished = Object.keys(prev.jobs).filter((r) => prev.jobs[r].state === 'active' && !next.jobs[r])
      if (finished.length) this.refs = new Set([...this.refs, ...finished])
    }
    this.queue = next
  }

  private async reload() {
    try {
      this.refs = new Set(await api.downloadedRefs())
    } catch (e) {
      console.warn('скачивание: список скачанного не прочитался', e)
    }
  }

  stateOf = (ref: string): RowState => this.queue.jobs[ref]?.state ?? (this.refs.has(ref) ? 'done' : null)

  /** Доля готового в текущей пачке. */
  get share(): number {
    return progress(this.queue.done, this.queue.left)
  }

  get failed(): number {
    return Object.values(this.queue.jobs).filter((j) => j.state === 'failed').length
  }

  /** Поставить в очередь. Большая пачка — сперва подтверждение с размером и свободным местом (§8.2). */
  async download(tracks: readonly Track[]): Promise<void> {
    const list = toDownload(tracks, this.refs)
    if (!list.length) {
      toast.show(tracks.length ? t('Уже скачано') : t('Нечего скачивать'))
      return
    }
    const bytes = batchBytes(list, await this.quality())
    if (needsConfirm(list.length, bytes) && !(await this.confirmBatch(list.length, bytes))) return
    try {
      const n = await api.downloadTracks(list)
      toast.show(n ? t('Скачивание: {n}', { n: `${n} ${tn(n, ['трек', 'трека', 'треков'])}` }) : t('Уже в очереди'))
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  private async quality(): Promise<Quality> {
    return (await api.getSetting<Quality>('audio.quality').catch(() => null)) ?? 'max'
  }

  /** Что ждёт или качается сейчас — место под это уже занято. */
  private inQueue(): ReadonlySet<string> {
    const jobs = this.queue.jobs
    return new Set(Object.keys(jobs).filter((r) => jobs[r].state === 'queued' || jobs[r].state === 'active'))
  }

  /** Любимые, которых нет на диске, — в порядке Любимых (свежие лайки сверху). */
  private async missingLiked(): Promise<ListTrack[]> {
    return toDownload(await api.favorites(), this.refs)
  }

  /** Докачать Любимые в пределах лимита (`only` — один свежий лайк). Тихо: без тостов, ошибка — в журнал. */
  async fillLiked(only?: string): Promise<void> {
    await settings.load()
    if (!settings.get('storage.auto_download_liked') || offline.on) return
    try {
      const liked = await api.favorites()
      if (!toDownload(liked, this.refs).some((x) => !only || x.ref === only)) return
      const [usage, quality] = await Promise.all([api.storageUsage(), this.quality()])
      const limit = settings.get('storage.auto_download_limit_gb') * GB
      const fit = likedPlan(liked, this.refs, this.inQueue(), usage.downloaded_bytes, limit, quality, only)
      if (fit.length) await api.downloadTracks(fit)
    } catch (e) {
      console.warn('скачивание: Любимые не докачались', e)
    }
  }

  /** Включить автоскачивание Любимых: сперва сказать, сколько их не скачано и сколько это весит. Вернёт, включили ли. */
  async enableLiked(): Promise<boolean> {
    try {
      const [missing, quality] = await Promise.all([this.missingLiked(), this.quality()])
      if (missing.length && !(await this.confirmLiked(missing.length, batchBytes(missing, quality)))) return false
      settings.set('storage.auto_download_liked', true)
      await this.fillLiked()
      return true
    } catch (e) {
      toast.show(errorText(e))
      return false
    }
  }

  private confirmLiked(count: number, bytes: number): Promise<boolean> {
    const limit = settings.get('storage.auto_download_limit_gb') * GB
    const parts = [`${count} ${tn(count, ['трек', 'трека', 'треков'])}`, `~${bytesText(bytes)}`, t('лимит {n}', { n: bytesText(limit) })]
    return confirm.ask({ title: t('Скачивать Любимые?'), text: parts.join(' · '), yes: t('Включить'), no: t('Отмена') })
  }

  private async confirmBatch(count: number, bytes: number): Promise<boolean> {
    const free = await api.diskFree().catch(() => null)
    const parts = [`${count} ${tn(count, ['трек', 'трека', 'треков'])}`, `~${bytesText(bytes)}`]
    if (free != null) parts.push(t('свободно {n}', { n: bytesText(free) }))
    return confirm.ask({ title: t('Скачать всё?'), text: parts.join(' · '), yes: t('Скачать'), no: t('Отмена') })
  }

  pause = (paused: boolean) => this.run(() => api.downloadsPause(paused))
  retry = () => this.run(() => api.downloadsRetry())
  cancel = (refs: string[]) => this.run(() => api.downloadsCancel(refs))
  reveal = () => this.run(() => api.downloadsReveal())

  /** Отменить всё, что ждёт или качается; не скачавшиеся остаются для «Повторить». */
  cancelAll = () =>
    this.cancel(
      Object.entries(this.queue.jobs)
        .filter(([, j]) => j.state === 'queued' || j.state === 'active')
        .map(([ref]) => ref),
    )

  /** Убрать с диска (и из очереди): трек снова играет только по сети. */
  async remove(refs: string[]) {
    if (await this.run(() => api.downloadsRemove(refs))) toast.show(t('Удалено из скачанного'))
  }

  /** «Удалить все» — с подтверждением. Вернёт, удалили ли. */
  async clear(count: number, bytes: number): Promise<boolean> {
    const ok = await confirm.ask({
      title: t('Удалить всё скачанное?'),
      text: t('{n} · {size} — без сети эти треки играть перестанут', { n: `${count} ${tn(count, ['трек', 'трека', 'треков'])}`, size: bytesText(bytes) }),
      yes: t('Удалить'),
      no: t('Отмена'),
      danger: true,
    })
    if (ok) await this.run(() => api.downloadsClear())
    return ok
  }

  private async run(fn: () => Promise<void>): Promise<boolean> {
    try {
      await fn()
      return true
    } catch (e) {
      toast.show(errorText(e))
      return false
    }
  }
}

export const downloads = new Downloads()
