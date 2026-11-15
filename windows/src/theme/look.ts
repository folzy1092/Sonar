// Шрифты и скругления для Интерфейс → Вид (pc/Screenshot_2, 3). Шрифты — системные Windows и
// встроенные (Inter, Roboto Flex из fontsource), сгруппированы как у Dotify: Система / Модерн /
// Засечки / Моно. «Стандартный» — Inter, как у Dotify.

export type FontCategory = 'system' | 'modern' | 'serif' | 'mono'

export const FONT_CATEGORIES: { id: FontCategory; label: string }[] = [
  { id: 'system', label: 'Система' },
  { id: 'modern', label: 'Модерн' },
  { id: 'serif', label: 'Засечки' },
  { id: 'mono', label: 'Моно' },
]

export const FONTS: Record<FontCategory, string[]> = {
  system: ['default', 'Segoe UI', 'Arial', 'Tahoma', 'Verdana', 'Calibri', 'Trebuchet MS', 'Lucida Sans Unicode', 'Arial Black', 'Segoe UI Light', 'Segoe UI Semibold'],
  modern: ['Inter Variable', 'Roboto Flex Variable', 'Bahnschrift', 'Segoe UI Variable Display', 'Candara', 'Corbel', 'Gadugi', 'Ebrima'],
  serif: ['Georgia', 'Times New Roman', 'Cambria', 'Constantia', 'Palatino Linotype', 'Sitka Text', 'Book Antiqua'],
  mono: ['Consolas', 'Cascadia Code', 'Cascadia Mono', 'Courier New', 'Lucida Console'],
}

export function fontLabel(f: string): string {
  if (f === 'default') return 'Стандартный'
  return f.replace(' Variable', '')
}

export function fontCategory(f: string): FontCategory {
  return (Object.keys(FONTS) as FontCategory[]).find((c) => FONTS[c].includes(f)) ?? 'system'
}

/** Значение для CSS `font-family` с запасными шрифтами. */
export function fontStack(f: string): string | null {
  if (!f || f === 'default') return null
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
