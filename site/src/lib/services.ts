// Музыкальные сервисы Sonar: короткие id (как в приложении) и названия — ключи перевода.
export type ServiceId = 'sc' | 'ym' | 'yt' | 'vk' | 'sp' | 'am'

export const SERVICE_NAMES: Readonly<Record<ServiceId, string>> = {
  sc: 'SoundCloud',
  ym: 'Яндекс Музыка',
  yt: 'YouTube Music',
  vk: 'VK Музыка',
  sp: 'Spotify',
  am: 'Apple Music',
}
