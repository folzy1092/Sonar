// Адреса сайта. Сайт и API отдаёт один сервер на Velt (SERVER_PROMPT этап 6), поэтому API — свой путь `/api`.
// `null` вернёт честные заготовки статуса и профиля (сайт без сервера, например `npm run dev`).
export const SITE_URL = 'https://try-sonar.ru'
export const API_URL: string | null = '/api'

const REPO = 'https://github.com/folzy1092/Sonar'
export const LINKS = {
  repo: REPO,
  releases: `${REPO}/releases`,
  windowsExe: `${REPO}/releases/latest/download/Sonar-setup.exe`,
  iosIpa: `${REPO}/releases/download/ios-latest/Sonar.ipa`,
  latestReleaseApi: 'https://api.github.com/repos/folzy1092/Sonar/releases/latest',
  channel: 'https://t.me/SonarUpdates',
  bot: 'https://t.me/SonarMusicApp',
  /** «Баг / Идея» в боте открывается кнопкой; deep link ведёт прямо к ней. */
  botReport: 'https://t.me/SonarMusicApp?start=report',
} as const
