// Текущий импорт по ссылке (экран pages/ImportPage). Живёт вне страницы: «Искать вручную» уводит в
// поиск, а «назад» возвращает к тому же импорту — с найденным, без нового чтения источника.
// Новый импорт останавливает прежний (оставшиеся треки прежнего не ищутся).
import { api, errorText, onImportProgress, type Playlist } from './api'
import { EMPTY_IMPORT, applyProgress, fromResult, importTracks, newJobId, type ImportState } from './import'

class ImportJob {
  /** Ссылка (или ref) текущего импорта. */
  link = $state<string | null>(null)
  state = $state<ImportState>(EMPTY_IMPORT)
  error = $state<string | null>(null)
  running = $state(false)
  /** Сохранённый плейлист — кнопка становится «Открыть плейлист». */
  saved = $state<Playlist | null>(null)
  private job: string | null = null
  private off: (() => void) | null = null

  /** Начать импорт `link`; тот же, что уже открыт, — ничего не делать. */
  async start(link: string, force = false) {
    if (!force && link === this.link && !this.error) return
    this.stop()
    const job = newJobId()
    this.job = job
    this.link = link
    this.state = EMPTY_IMPORT
    this.error = null
    this.saved = null
    this.running = true
    const sub = onImportProgress((ev) => {
      if (ev.job === this.job) this.state = applyProgress(this.state, ev)
    })
    this.off = sub.off
    try {
      await sub.ready
      const result = await api.importLink(link, job)
      if (this.job === job) this.state = fromResult(result)
    } catch (e) {
      if (this.job === job) this.error = errorText(e)
    } finally {
      if (this.job === job) this.finish()
    }
  }

  /** Остановить подбор пар (новый импорт или «Остановить»). */
  stop() {
    if (this.job && this.running) void api.importCancel(this.job).catch(() => {})
    this.finish()
  }

  /** Сохранить найденное смешанным плейлистом. */
  async create(name: string): Promise<Playlist> {
    const head = this.state.head
    if (!head) throw new Error('Переносить нечего: ни один трек не нашёлся')
    const p = await api.importCreate(name, head.source, importTracks(this.state))
    this.saved = p
    return p
  }

  private finish() {
    this.running = false
    this.off?.()
    this.off = null
  }
}

export const importJob = new ImportJob()
