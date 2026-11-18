// Горячие клавиши — чистая часть (тесты в hotkeys.test.ts): сочетание из нажатия и его подпись.

const MODIFIERS = ['Control', 'Alt', 'Shift', 'Meta', 'AltGraph', 'OS']

/** Сочетание из нажатия: `Ctrl+Alt+KeyL` (коды клавиш — как у `KeyboardEvent.code`, их же ждёт Rust).
 *  `null` — нажат только модификатор или нет ни одного модификатора (голую клавишу не берём). */
export function comboFrom(e: Pick<KeyboardEvent, 'ctrlKey' | 'altKey' | 'shiftKey' | 'metaKey' | 'key' | 'code'>): string | null {
  if (MODIFIERS.includes(e.key) || !e.code) return null
  const mods = [e.ctrlKey && 'Ctrl', e.altKey && 'Alt', e.shiftKey && 'Shift', e.metaKey && 'Win'].filter(Boolean) as string[]
  if (!mods.length) return null
  return [...mods, e.code].join('+')
}

const NAMES: Record<string, string> = {
  ArrowLeft: '←',
  ArrowRight: '→',
  ArrowUp: '↑',
  ArrowDown: '↓',
  Equal: '=',
  Minus: '−',
  Comma: ',',
  Period: '.',
  Slash: '/',
  Backslash: '\\',
  BracketLeft: '[',
  BracketRight: ']',
  Semicolon: ';',
  Quote: "'",
  Backquote: '`',
  PageUp: 'PgUp',
  PageDown: 'PgDn',
}

/** Как показать сочетание — по клавише: `Ctrl`, `Alt`, `L`, стрелки — значками. */
export function comboLabel(combo: string): string[] {
  return combo
    .split('+')
    .filter(Boolean)
    .map((p) => NAMES[p] ?? p.replace(/^Key/, '').replace(/^Digit/, '').replace(/^Numpad/, 'Num '))
}

/** Карта без `combo`: у кого оно было — остаётся без клавиши (новая карта, старая не меняется). */
export function withoutCombo(map: Readonly<Record<string, string>>, combo: string): Record<string, string> {
  return Object.fromEntries(Object.entries(map).map(([k, v]) => [k, combo && v === combo ? '' : v]))
}

/** Карта, где у `action` — `combo`, а у других действий то же сочетание снято. */
export function withCombo(map: Readonly<Record<string, string>>, action: string, combo: string): Record<string, string> {
  return { ...withoutCombo(map, combo), [action]: combo }
}
