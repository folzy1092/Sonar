// Умные плейлисты в памяти интерфейса: список для медиатеки и открытый конструктор правил.
// Источник правды — локальная база (`store/smart.rs`), правила — lib/smart.ts.
import { api, errorText, type SmartPlaylist } from './api'
import { library } from './library.svelte'
import { toast } from './toast.svelte'
import { t } from './i18n.svelte'
import { tracksText } from './format'
import { cloneRules, normalizeRules, parseRules, type SmartRules } from './smart'

/** Что правится в конструкторе: новый плейлист (без id) или существующий. */
export interface SmartDraft {
  id: string | null
  name: string
  rules: SmartRules
}

class SmartLists {
  list = $state<SmartPlaylist[]>([])
  /** Открытый конструктор правил (одно окно на приложение) или null. */
  draft = $state<SmartDraft | null>(null)

  async load() {
    try {
      this.list = await api.smartPlaylists()
    } catch {
      this.list = [] // вне приложения — пусто
    }
  }

  /** Открыть конструктор: из шаблона/с нуля (`id` null) или правка существующего. */
  edit(draft: SmartDraft) {
    this.draft = { id: draft.id, name: draft.name, rules: cloneRules(draft.rules) }
  }

  editExisting(p: SmartPlaylist) {
    const rules = parseRules(p.rules)
    if (!rules) {
      toast.show(t('Правила этого плейлиста не читаются'))
      return
    }
    this.edit({ id: p.id, name: p.name, rules })
  }

  close() {
    this.draft = null
  }

  /** Сохранить черновик: создать или обновить. Вернёт id плейлиста или null при ошибке. */
  async save(draft: SmartDraft): Promise<string | null> {
    const rules = normalizeRules(draft.rules)
    const name = draft.name.trim()
    try {
      let id = draft.id
      if (id) await api.updateSmartPlaylist(id, { name, rules })
      else id = (await api.createSmartPlaylist(name, rules)).id
      await this.changed()
      toast.show(draft.id ? t('Правила сохранены') : t('Умный плейлист «{name}» создан', { name }))
      return id
    } catch (e) {
      toast.show(errorText(e))
      return null
    }
  }

  async remove(p: SmartPlaylist): Promise<boolean> {
    try {
      await api.deleteSmartPlaylist(p.id)
      await this.changed()
      toast.show(t('Плейлист «{title}» удалён', { title: p.name }))
      return true
    } catch (e) {
      toast.show(errorText(e))
      return false
    }
  }

  /** «Сохранить как обычный плейлист»: снимок текущих треков — дальше живёт сам по себе. */
  async snapshot(p: SmartPlaylist) {
    const tracks = p.tracks ?? (await api.smartPlaylist(p.id).catch(() => null))?.tracks ?? []
    if (!tracks.length) {
      toast.show(t('В плейлисте нет треков — сохранять нечего'))
      return null
    }
    const copy = await library.createPlaylist(p.name, tracks)
    if (copy) toast.show(t('«{name}» сохранён как обычный плейлист — {tracks}', { name: copy.name, tracks: tracksText(copy.track_count) }))
    return copy
  }

  private async changed() {
    await this.load()
    library.version++
  }
}

export const smartLists = new SmartLists()
