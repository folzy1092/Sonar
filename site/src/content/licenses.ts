// Сторонние компоненты Sonar для /licenses (SITE.md §5). Сверять при обновлении зависимостей:
// windows/package.json, windows/src-tauri/Cargo.toml, ios/Packages, site/package.json.
// Названия не переводятся, `title` и `note` — ключи перевода.

export interface LicenseItem {
  readonly name: string
  readonly license: string
  readonly url: string
  readonly note?: string
}

export interface LicenseGroup {
  readonly id: string
  readonly title: string
  readonly items: readonly LicenseItem[]
}

const OFL = 'SIL OFL 1.1'

export const LICENSE_GROUPS: readonly LicenseGroup[] = [
  {
    id: 'windows',
    title: 'Sonar для Windows',
    items: [
      { name: 'Tauri 2', license: 'MIT / Apache-2.0', url: 'https://github.com/tauri-apps/tauri', note: 'вместе с плагинами' },
      { name: 'Svelte 5', license: 'MIT', url: 'https://github.com/sveltejs/svelte' },
      { name: 'hls.js', license: 'Apache-2.0', url: 'https://github.com/video-dev/hls.js' },
      { name: 'Tokio', license: 'MIT', url: 'https://github.com/tokio-rs/tokio' },
      { name: 'reqwest', license: 'MIT / Apache-2.0', url: 'https://github.com/seanmonstar/reqwest' },
      { name: 'rustls', license: 'Apache-2.0 / ISC / MIT', url: 'https://github.com/rustls/rustls' },
      { name: 'axum', license: 'MIT', url: 'https://github.com/tokio-rs/axum' },
      { name: 'rusqlite', license: 'MIT', url: 'https://github.com/rusqlite/rusqlite' },
      { name: 'SQLite', license: 'Public Domain', url: 'https://sqlite.org/copyright.html' },
      { name: 'serde', license: 'MIT / Apache-2.0', url: 'https://github.com/serde-rs/serde' },
      { name: 'keyring', license: 'MIT / Apache-2.0', url: 'https://github.com/hwchen/keyring-rs' },
      { name: 'souvlaki', license: 'MIT', url: 'https://github.com/Sinono3/souvlaki' },
      { name: 'lofty', license: 'MIT / Apache-2.0', url: 'https://github.com/Serial-ATA/lofty-rs' },
      { name: 'discord-rich-presence', license: 'MIT', url: 'https://github.com/vionya/discord-rich-presence' },
      { name: 'mdns-sd', license: 'MIT / Apache-2.0', url: 'https://github.com/keepsimple1/mdns-sd' },
      { name: 'tokio-tungstenite', license: 'MIT', url: 'https://github.com/snapview/tokio-tungstenite' },
      { name: 'librespot', license: 'MIT', url: 'https://github.com/librespot-org/librespot' },
    ],
  },
  {
    id: 'ios',
    title: 'Sonar для iPhone',
    items: [
      { name: 'zsign', license: 'MIT', url: 'https://github.com/zhlynn/zsign', note: 'с правками Sonar' },
      { name: 'ZipArchive', license: 'MIT', url: 'https://github.com/ZipArchive/ZipArchive' },
    ],
  },
  {
    id: 'icons',
    title: 'Значки',
    items: [
      { name: 'MingCute', license: 'Apache-2.0', url: 'https://github.com/Richard9394/MingCute' },
      { name: 'Tabler Icons', license: 'MIT', url: 'https://github.com/tabler/tabler-icons' },
      { name: 'Simple Icons', license: 'CC0-1.0', url: 'https://github.com/simple-icons/simple-icons', note: 'знаки сервисов' },
      { name: 'circle-flags', license: 'MIT', url: 'https://github.com/HatScripts/circle-flags' },
      { name: 'flag-icons', license: 'MIT', url: 'https://github.com/lipis/flag-icons' },
    ],
  },
  {
    id: 'fonts',
    title: 'Шрифты',
    items: [
      { name: 'Golos Text', license: OFL, url: 'https://github.com/googlefonts/golos-text', note: 'основной шрифт сайта и приложения' },
      { name: 'Unbounded', license: OFL, url: 'https://github.com/googlefonts/unbounded', note: 'заголовки' },
      { name: 'Inter, Manrope, Onest, Geologica, Montserrat…', license: OFL, url: 'https://fontsource.org', note: 'и другие шрифты стилей' },
      { name: 'Roboto Mono', license: 'Apache-2.0', url: 'https://github.com/googlefonts/RobotoMono' },
      { name: 'Ubuntu, Ubuntu Mono', license: 'Ubuntu Font Licence 1.0', url: 'https://ubuntu.com/legal/font-licence' },
      { name: 'Fontsource', license: 'MIT', url: 'https://github.com/fontsource/fontsource', note: 'упаковка шрифтов' },
    ],
  },
  {
    id: 'site',
    title: 'Этот сайт',
    items: [
      { name: 'Astro', license: 'MIT', url: 'https://github.com/withastro/astro' },
      { name: 'Iconify', license: 'MIT', url: 'https://github.com/iconify/icon-sets', note: 'наборы значков' },
    ],
  },
]
