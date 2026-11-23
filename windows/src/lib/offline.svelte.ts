// Офлайн-режим в интерфейсе (`docs/OFFLINE.md`): зеркало флага из Rust (`offline.rs`, событие `offline-changed`)
// и набор ref'ов, которые играют без сети (`offline_refs`, обновляется по `offline-index-changed` и смене папок).
// Экраны фильтруют списки через `offline.allows` / `offline.only`; включают и выключают — через настройку.
import { api, onLocalFilesChanged, onOfflineChanged, onOfflineIndexChanged, type Track } from './api'
import { settings } from './settings.svelte'
import { availableOnly, imageSrc, isAvailable, suggestOnNetwork, uniqueByRef } from './offline-core'
import { t } from './i18n.svelte'
import { toast } from './toast.svelte'

/** Сколько висит плашка «Сеть пропала» — дольше обычного тоста: успеть дотянуться до кнопки. */
const SUGGEST_TOAST_MS = 10_000

class Offline {
  on = $state(false)
  refs = $state<ReadonlySet<string>>(new Set())
  /** Порт локального сервера — для картинок в офлайне (`src`). */
  private port = $state<number | null>(null)
  private started: Promise<void> | null = null
  private seq = 0
  private listeners: Array<(on: boolean) => void> = []
  /** За эту пропажу сети офлайн-режим уже предлагали. */
  private suggested = false

  /**
   * Читает флаг и порт из Rust. `main.ts` ждёт его до монтирования интерфейса: иначе первые `<img>` успели бы
   * взять адреса CDN, пока флаг ещё «выключен» (`docs/OFFLINE.md` §5.3 — ни байта и после перезапуска).
   */
  init(): Promise<void> {
    if (this.started) return this.started
    const flag = api
      .offlineState()
      .then((on) => this.apply(on, false))
      .catch((e) => console.warn('офлайн: флаг не прочитался', e))
    const port = api
      .streamPort()
      .then((p) => {
        this.port = p
      })
      .catch((e) => console.warn('офлайн: порт локального сервера не прочитался', e))
    void this.refresh()
    this.hideDeadImages()
    this.watchNetwork()
    onOfflineChanged((on) => this.apply(on))
    onOfflineIndexChanged(() => void this.refresh())
    onLocalFilesChanged(() => void this.refresh())
    this.started = Promise.all([flag, port]).then(() => undefined)
    return this.started
  }

  /** Включить или выключить: настройка уходит в Rust, он переключает ворота и присылает событие. */
  set(on: boolean) {
    settings.set('general.offline', on)
  }

  /** Подписка на переключение (плеер: затухание и чистка очереди). */
  onChange(cb: (on: boolean) => void): () => void {
    this.listeners = [...this.listeners, cb]
    return () => (this.listeners = this.listeners.filter((x) => x !== cb))
  }

  allows = (t: { ref: string }): boolean => isAvailable(t.ref, this.on, this.refs)

  only<T extends { ref: string }>(tracks: readonly T[]): T[] {
    return availableOnly(tracks, this.on, this.refs)
  }

  /** Адрес для `<img src>`: в офлайне чужие картинки — только из кэша на диске, без сети. */
  src = (url: string | null | undefined): string | undefined => imageSrc(url, this.on, this.port)

  /** Подпись списка в офлайне: «12 из 40 · офлайн». */
  countText(n: number, total: number): string {
    return t('{n} из {m} · офлайн', { n, m: total })
  }

  /** Всё, что играет без сети: кэш (новое сверху) и живые локальные файлы. */
  async pool(): Promise<Track[]> {
    const [cached, local] = await Promise.all([
      api.offlineTracks().catch(() => [] as Track[]),
      api.localTracks().catch(() => [] as Track[]),
    ])
    return uniqueByRef([...cached, ...local.filter((t) => t.available)])
  }

  /**
   * Пропала сеть (событие браузера `offline`), режим выключен и подсказка разрешена — одна плашка с кнопкой
   * «Включить офлайн-режим» (`docs/OFFLINE.md` §12). Включается только по клику, сам — никогда.
   */
  private watchNetwork() {
    if (typeof window === 'undefined') return
    const handle = (kind: 'offline' | 'online') => {
      const next = suggestOnNetwork(this.suggested, { kind, modeOn: this.on, enabled: settings.get('general.offline_suggest') })
      this.suggested = next.shown
      if (next.show) toast.show(t('Сеть пропала'), SUGGEST_TOAST_MS, { label: t('Включить офлайн-режим'), run: () => this.set(true) })
    }
    window.addEventListener('offline', () => handle('offline'))
    window.addEventListener('online', () => handle('online'))
  }

  /**
   * Офлайн: картинки без кэша на диске `/cover` не отдаёт — прячем их, а не показываем значок битой картинки.
   * Включили сеть — `src` меняется, картинка грузится и снова видна.
   */
  private hideDeadImages() {
    if (typeof document === 'undefined') return
    document.addEventListener(
      'error',
      (e) => {
        if (!this.on || !(e.target instanceof HTMLImageElement)) return
        e.target.dataset.offlineDead = ''
        e.target.style.visibility = 'hidden'
      },
      true,
    )
    document.addEventListener(
      'load',
      (e) => {
        const img = e.target
        if (!(img instanceof HTMLImageElement) || !('offlineDead' in img.dataset)) return
        delete img.dataset.offlineDead
        img.style.visibility = ''
      },
      true,
    )
  }

  /** `notify` — сказать подписчикам; при запуске не говорим: включённый режим — не переключение. */
  private apply(on: boolean, notify = true) {
    const was = this.on
    this.on = on
    // режим могли переключить из трея: настройка в базе уже новая, зеркало настроек догоняет
    if (notify) settings.mirror('general.offline', on)
    if (notify && was !== on) for (const cb of this.listeners) cb(on)
  }

  private async refresh() {
    const my = ++this.seq
    try {
      const refs = await api.offlineRefs()
      if (my === this.seq) this.refs = new Set(refs)
    } catch (e) {
      console.warn('офлайн: список доступного не прочитался', e)
    }
  }
}

export const offline = new Offline()
