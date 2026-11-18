// Адреса сайта. API пока нет (сервер не куплен) — `API_URL = null`: статус и профили показывают честную
// заготовку. Когда сервер заработает — вписать `https://sonar-api.folzy.ru` и пересобрать сайт.
export const SITE_URL = 'https://sonar.folzy.ru'
export const API_URL: string | null = null

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
