// Английский словарь (services): новые строки реестра сервисов (lib/services.ts) — ключ — русская строка.
export default {
  'VK Музыка': 'VK Music',
  'Локальные файлы': 'Local files',
  'VK Музыке': 'VK Music',
  'локальных файлах': 'local files',
  'Подключён': 'Connected',
  'Не подключён': 'Not connected',
  'Войти через YouTube Music': 'Sign in with YouTube Music',
  'Войти через Spotify': 'Sign in with Spotify',
  'Премиум': 'Premium',
  'Войди в SoundCloud заново': 'Sign in to SoundCloud again',
  'SoundCloud снова подключён': 'SoundCloud is connected again',
  // короткая метка Яндекс Музыки в переключателе поиска — та же буква на всех языках
  Я: 'Я',
  // VK убран (2026-11-25)
  'VK Музыка убрана из Sonar: после лимитов VK вход больше не проходит. Треки VK, что уже в медиатеке, играют через резервный сервис.':
    'VK Music has been removed from Sonar: after VK’s limits, sign-in no longer works. VK tracks already in your library play through a backup service.',
} satisfies Record<string, string>
