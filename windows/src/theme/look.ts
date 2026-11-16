// Шрифты и скругления для Интерфейс → Вид (pc/Screenshot_2, 3). Шрифты — живые, современные, с
// кириллицей: встроены в exe из fontsource (theme/fonts.css, только латиница+кириллица, woff2;
// качаются, только когда показаны), плюс немного системных Windows. Группы как у Dotify — Система /
// Модерн / Засечки / Моно — и «Яркие» для заголовков с характером. «Стандартный» — Inter.
// «Свой» — файл шрифта с компьютера (theme/custom-font.ts), значение `custom:<имя>`.

export type FontCategory = 'system' | 'modern' | 'serif' | 'mono' | 'bright'

export const FONT_CATEGORIES: { id: FontCategory; label: string }[] = [
  { id: 'system', label: 'Система' },
  { id: 'modern', label: 'Модерн' },
  { id: 'serif', label: 'Засечки' },
  { id: 'mono', label: 'Моно' },
  { id: 'bright', label: 'Яркие' },
]

export const FONTS: Record<FontCategory, string[]> = {
  system: ['default', 'Segoe UI Variable Display', 'Bahnschrift', 'Segoe UI', 'Arial', 'Verdana', 'Trebuchet MS'],
  modern: [
    'Inter Variable',
    'Manrope Variable',
    'Onest Variable',
    'Golos Text Variable',
    'Geologica Variable',
    'Inter Tight Variable',
    'Wix Madefor Display Variable',
    'Commissioner Variable',
    'Roboto Flex Variable',
    'Montserrat Variable',
    'Rubik Variable',
    'Nunito Variable',
    'Raleway Variable',
    'Exo 2 Variable',
    'Comfortaa Variable',
    'Jost Variable',
    'Mulish Variable',
    'Sofia Sans Variable',
    'Open Sans Variable',
    'IBM Plex Sans Variable',
    'Fira Sans',
    'Ubuntu',
    'PT Sans',
    'Oswald Variable',
    'Play',
  ],
  serif: [
    'Lora Variable',
    'Playfair Display Variable',
    'Literata Variable',
    'Source Serif 4 Variable',
    'Merriweather Variable',
    'Noto Serif Variable',
    'EB Garamond Variable',
    'Cormorant Variable',
    'Spectral',
    'PT Serif',
    'Alice',
    'Prata',
    'Yeseva One',
  ],
  mono: [
    'JetBrains Mono Variable',
    'Fira Code Variable',
    'Martian Mono Variable',
    'IBM Plex Mono',
    'Source Code Pro Variable',
    'Roboto Mono Variable',
    'Ubuntu Mono',
    'PT Mono',
    'Cascadia Code',
    'Consolas',
  ],
  bright: [
    'Unbounded Variable',
    'Tektur Variable',
    'Dela Gothic One',
    'Russo One',
    'Days One',
    'Rubik Mono One',
    'Pixelify Sans Variable',
    'Press Start 2P',
    'Pacifico',
    'Lobster',
    'Caveat Variable',
    'Amatic SC',
    'Neucha',
    'Marck Script',
  ],
}

export const CUSTOM_PREFIX = 'custom:'
/** Имя, под которым в документе зарегистрирован свой шрифт (FontFace). */
export const CUSTOM_FAMILY = 'Sonar Custom'

export function fontLabel(f: string): string {
  if (f === 'default') return 'Стандартный'
  if (f.startsWith(CUSTOM_PREFIX)) return f.slice(CUSTOM_PREFIX.length)
  if (f === 'Segoe UI Variable Display') return 'Segoe UI Variable'
  return f.replace(' Variable', '')
}

export function fontCategory(f: string): FontCategory {
  return (Object.keys(FONTS) as FontCategory[]).find((c) => FONTS[c].includes(f)) ?? 'system'
}

/** Значение для CSS `font-family` с запасными шрифтами. */
export function fontStack(f: string): string | null {
  if (!f || f === 'default') return null
  if (f.startsWith(CUSTOM_PREFIX)) return `'${CUSTOM_FAMILY}', 'Inter Variable', 'Segoe UI', sans-serif`
  const mono = FONTS.mono.includes(f)
  return `'${f}', ${mono ? 'monospace' : "'Inter Variable', 'Segoe UI', sans-serif"}`
}

/** Скругления: Нет / Маленькое / Среднее (по умолчанию) / Большое — радиусы s / m / l / xl. */
export const RADII: Record<'none' | 'soft' | 'rounded' | 'pill', [number, number, number, number]> = {
  none: [2, 3, 4, 6],
  soft: [5, 8, 11, 15],
  rounded: [8, 12, 16, 22],
  pill: [11, 16, 22, 28],
}
