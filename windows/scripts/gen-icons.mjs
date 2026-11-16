// Генератор src/components/mingcute.ts: тела SVG MingCute (Apache-2.0, тот же набор, что у Dotify)
// для общих иконок интерфейса. Контур — `-line`, заливка (`filled`) — `-fill`.
// Запуск: node scripts/gen-icons.mjs (после правки MAP).
import { readFileSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const set = JSON.parse(readFileSync(require.resolve('@iconify-json/mingcute/icons.json'), 'utf8'))

/** Наше имя → имя MingCute. Нет здесь (repeatOff, brandLastfm, obs) — остаются из Tabler (icons.ts). */
const MAP = {
  home: 'home-4', search: 'search', library: 'folder', player: 'play', settings: 'settings-3',
  play: 'play', pause: 'pause', prev: 'skip-previous', next: 'skip-forward', repeatOnce: 'repeat-one',
  repeat: 'repeat', shuffle: 'shuffle-2', heart: 'heart', clock: 'time', history: 'history',
  volume: 'volume', volumeOff: 'volume-off', dots: 'more-1', dislike: 'thumb-down-2', check: 'check',
  lyrics: 'quote-left', queue: 'playlist', music: 'music-2', bolt: 'flash', link: 'link', user: 'user-3',
  download: 'download-2', plus: 'add', refresh: 'refresh-2', chevronLeft: 'left', chevronRight: 'right',
  chevronDown: 'down', eyeClosed: 'eye-close', textLines: 'align-left', expand: 'fullscreen',
  headphones: 'headphone', equalizer: 'settings-6', sparkles: 'sparkles', letterT: 'text',
  language: 'translate', adjustments: 'settings-6', minus: 'minimize', x: 'close', key: 'key-2',
  palette: 'palette', info: 'information', database: 'storage', trending: 'trending-up', chart: 'chart-bar',
  playlist: 'playlist', playlistAdd: 'playlist-2', playNext: 'skip-forward', bookmark: 'bookmark',
  share: 'share-forward', trash: 'delete-2', disc: 'album', copy: 'copy-2', pencil: 'edit-2',
  sort: 'sort-descending', eye: 'eye-2', eyeOff: 'eye-close', moon: 'moon', sun: 'sun', monitor: 'computer',
  lock: 'lock', shield: 'shield', speaker: 'speaker', alignLeft: 'align-left', alignCenter: 'align-center',
  alignRight: 'align-right', layoutTop: 'layout-top', layoutBottom: 'layout-bottom', layoutLeft: 'layout-left',
  layoutRight: 'layout-right', layoutFloat: 'layout-6', grid: 'layout-grid', circle: 'round', square: 'square',
  photo: 'pic', vinyl: 'disc', maximize: 'fullscreen-2', line: 'minimize', bars: 'chart-bar',
  waveform: 'audio-waveform', cloudUp: 'upload-2', cloudDown: 'download-3', compress: 'fullscreen-exit',
  stack: 'layers', hash: 'hashtag', layout: 'layout', discord: 'discord', user2: 'user-2', login: 'entrance',
}

const body = (n) => {
  const icon = set.icons[n] ?? set.icons[set.aliases?.[n]?.parent]
  if (!icon) throw new Error(`нет иконки ${n}`)
  return icon.body
}

const lines = Object.entries(MAP).map(
  ([k, v]) => `  ${k}: { line: ${JSON.stringify(body(`${v}-line`))}, fill: ${JSON.stringify(body(`${v}-fill`))} },`,
)
writeFileSync(
  new URL('../src/components/mingcute.ts', import.meta.url),
  `// Сгенерировано scripts/gen-icons.mjs из @iconify-json/mingcute (Apache-2.0). Руками не править.\n` +
    `export const mingcute: Record<string, { line: string; fill: string }> = {\n${lines.join('\n')}\n}\n`,
)
console.log(`иконок: ${lines.length}`)
