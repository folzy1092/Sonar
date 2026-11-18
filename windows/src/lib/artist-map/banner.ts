// Когда предложить карту баннером «Вот твоя музыкальная карта»: один раз — после первого переноса
// из сервиса или когда в медиатеке набралось 20 исполнителей. Клик или крестик — больше не показываем.

/** Столько исполнителей — и карта уже интересна без переноса. */
export const BANNER_MIN_ARTISTS = 20
/** После переноса хватит и нескольких — иначе карта из одной точки. */
export const BANNER_MIN_AFTER_IMPORT = 3

export interface BannerInput {
  /** Баннер уже открывали или закрыли (`library.map_banner_done`). */
  done: boolean
  /** Исполнителей из медиатеки на карте. */
  artists: number
  /** Есть хоть один плейлист, перенесённый из сервиса. */
  imported: boolean
}

export function shouldOfferMap({ done, artists, imported }: BannerInput): boolean {
  if (done) return false
  return artists >= BANNER_MIN_ARTISTS || (imported && artists >= BANNER_MIN_AFTER_IMPORT)
}
