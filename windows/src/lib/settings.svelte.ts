// Настройки (docs/SETTINGS.md) одним хранилищем: читаются один раз при запуске (`all_settings`),
// меняются сразу в интерфейсе и пишутся в локальную базу. Значения по умолчанию — из каталога.
import { api } from './api'

export type MiniStyle = 'off' | 'full' | 'rounded' | 'hybrid' | 'deck'

/** Пресеты стиля мини-плеера (как у Dotify, заметка владельца в reference/pc/ПРОЧИТАЙ МЕНЯ.txt). */
export const MINI_PRESETS: Record<Exclude<MiniStyle, 'off'>, { bg: 'theme' | 'cover' | 'cover_color'; progress: 'line' | 'background' | 'cover'; cover: 'default' | 'circle'; shape: 'default' | 'capsule' }> = {
  full: { bg: 'theme', progress: 'line', cover: 'default', shape: 'default' },
  rounded: { bg: 'theme', progress: 'cover', cover: 'circle', shape: 'capsule' },
  hybrid: { bg: 'theme', progress: 'background', cover: 'default', shape: 'default' },
  deck: { bg: 'cover', progress: 'background', cover: 'default', shape: 'default' },
}

export const DEFAULTS = {
  'general.platform': 'soundcloud' as 'soundcloud' | 'yandex',
  'general.restore': 'queue' as 'none' | 'track' | 'queue',
  'general.similar_autoplay': true,
  'general.add_position': 'start' as 'start' | 'end',
  'appearance.cover_theme': true,
  'appearance.preset': 'neutral' as string,
  'appearance.animations': true,
  'appearance.scale_window': 100,
  'appearance.scale_fullscreen': 100,
  'appearance.font': 'default' as string,
  'appearance.corner_radius': 'rounded' as 'none' | 'soft' | 'rounded' | 'pill',
  'audio.output_device': '' as string,
  'player.cover_position': 'left' as 'left' | 'right',
  'queue.show': true,
  'queue.add_following': true,
  'mini.style': 'hybrid' as MiniStyle,
  'mini.background': 'theme' as 'theme' | 'cover' | 'cover_color',
  'mini.progress': 'background' as 'line' | 'background' | 'cover',
  'mini.cover_shape': 'default' as 'default' | 'circle',
  'mini.shape': 'default' as 'default' | 'capsule',
  'player.title_align': 'center' as 'left' | 'center' | 'right',
  'player.artist_avatars': true,
  'player.visualizer': 'bar' as 'off' | 'bar',
  'integrations.discord.enabled': true,
  'integrations.discord.cover': true,
  'integrations.discord.progress': true,
  'system.autostart': true,
  'system.tray': true,
  'system.power_saving': 'background' as 'off' | 'minimized' | 'background',
  'wave.mode': 'own' as 'own' | 'hard' | 'calm' | 'sad' | 'fun' | 'new',
  'obs.size': 'standard' as 'standard' | 'compact',
  'obs.hide_paused': true,
  'update.auto_check': true,
  'update.auto_download': true,
  'update.channel': 'stable' as 'stable' | 'beta',
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

  /** Стиль мини-плеера: пресет выставляет фон, прогресс, обложку и форму. */
  setMiniStyle(style: MiniStyle) {
    this.set('mini.style', style)
    if (style === 'off') return
    const p = MINI_PRESETS[style]
    this.set('mini.background', p.bg)
    this.set('mini.progress', p.progress)
    this.set('mini.cover_shape', p.cover)
    this.set('mini.shape', p.shape)
  }

  /** После «Сбросить настройки». */
  async reload() {
    this.loading = null
    await this.load()
  }
}

export const settings = new Settings()
