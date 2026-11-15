// Настройки (docs/SETTINGS.md) одним хранилищем: читаются один раз при запуске (`all_settings`),
// меняются сразу в интерфейсе и пишутся в локальную базу. Значения по умолчанию — из каталога.
import { api } from './api'

export const DEFAULTS = {
  'general.platform': 'soundcloud' as 'soundcloud' | 'yandex',
  'general.restore': 'queue' as 'none' | 'track' | 'queue',
  'general.similar_autoplay': true,
  'general.add_position': 'start' as 'start' | 'end',
  'appearance.cover_theme': true,
  'appearance.preset': 'neutral' as string,
  'appearance.animations': true,
  'appearance.scale_window': 100,
  'player.title_align': 'center' as 'left' | 'center' | 'right',
  'player.artist_avatars': true,
  'player.visualizer': 'bar' as 'off' | 'bar',
  'integrations.discord.enabled': true,
  'integrations.discord.cover': true,
  'integrations.discord.progress': true,
  'integrations.discord.app_id': '' as string,
  'system.autostart': true,
  'system.tray': true,
  'system.power_saving': 'background' as 'off' | 'minimized' | 'background',
}
export type SettingKey = keyof typeof DEFAULTS
type Value<K extends SettingKey> = (typeof DEFAULTS)[K]

class Settings {
  private values = $state<Record<string, unknown>>({})
  loaded = $state(false)
  private loading: Promise<void> | null = null

  load(): Promise<void> {
    this.loading ??= api
      .allSettings()
      .then((all) => {
        this.values = all
      })
      .catch(() => {})
      .finally(() => (this.loaded = true))
    return this.loading
  }

  get<K extends SettingKey>(key: K): Value<K> {
    const v = this.values[key]
    return (v === undefined || v === null ? DEFAULTS[key] : v) as Value<K>
  }

  set<K extends SettingKey>(key: K, value: Value<K>) {
    this.values = { ...this.values, [key]: value }
    void api.setSetting(key, value).catch(() => {})
  }

  /** После «Сбросить настройки». */
  async reload() {
    this.loading = null
    await this.load()
  }
}

export const settings = new Settings()
