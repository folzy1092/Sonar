// Данные главной: недавнее (локальная история), релизы любимых исполнителей, похожее на последний
// трек, аккаунт для приветствия. Сетевое держим 15 минут, чтобы возврат на главную был мгновенным.
import { api, type Album, type ServiceStatus, type Track } from '../lib/api'

const TTL = 15 * 60_000

class Home {
  recent = $state<Track[]>([])
  releases = $state<Album[]>([])
  similar = $state<Track[]>([])
  similarTo = $state<Track | null>(null)
  account = $state<ServiceStatus | null>(null)
  loading = $state(false)
  releasesLoading = $state(false)
  similarLoading = $state(false)

  private releasesAt = 0

  async load() {
    this.loading = !this.recent.length
    try {
      this.recent = await api.recentTracks(20)
    } catch {
      // вне приложения — пусто
    } finally {
      this.loading = false
    }
    void this.loadAccount()
    void this.loadReleases()
    void this.loadSimilar()
  }

  private async loadAccount() {
    try {
      const s = await api.servicesStatus()
      const a = s.soundcloud.connected && s.soundcloud.name ? s.soundcloud : s.yandex.connected ? s.yandex : null
      this.account = a?.name ? a : null
    } catch {
      this.account = null
    }
  }

  private async loadReleases() {
    if (this.releasesLoading || (this.releases.length && Date.now() - this.releasesAt < TTL)) return
    this.releasesLoading = true
    try {
      this.releases = await api.homeReleases()
      this.releasesAt = Date.now()
    } catch {
      // нет сети или сервисов — ряд покажет подсказку
    } finally {
      this.releasesLoading = false
    }
  }

  /** «Похожее» на последний прослушанный трек; тот же трек — не перезапрашиваем. */
  private async loadSimilar() {
    const seed = this.recent[0]
    if (!seed || this.similarLoading || (this.similarTo?.ref === seed.ref && this.similar.length)) return
    this.similarLoading = true
    try {
      const recent = new Set(this.recent.map((t) => t.ref))
      this.similar = (await api.similarTracks(seed.ref, 24)).filter((t) => !recent.has(t.ref))
      this.similarTo = seed
    } catch {
      this.similar = []
    } finally {
      this.similarLoading = false
    }
  }
}

export const home = new Home()
