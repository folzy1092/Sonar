// Горячие клавиши — чистая часть (тесты в hotkeys.test.ts): действия, сочетание из нажатия, подпись,
// что регистрировать по всей системе при выбранной области.

const MODIFIERS = ['Control', 'Alt', 'Shift', 'Meta', 'AltGraph', 'OS']

/** Где действуют сочетания (Приложение → Клавиши): только в окне Sonar · ещё и пока открыто окно поверх
 *  остальных (мини-окно, оверлей) · всегда, даже из трея. */
export type HotkeyScope = 'app' | 'top' | 'global'
export type HotkeyGroup = 'player' | 'nav' | 'window'

interface ActionDef {
  id: string
  /** Подпись по-русски — ключ перевода, `t()` при показе. */
  title: string
  group: HotkeyGroup
  /** Только внутри окна Sonar: по всей системе не регистрируется, можно голую клавишу (`/`). */
  local?: boolean
  /** Только по всей системе: внутри окна смысла нет («Показать / скрыть окно»). */
  outside?: boolean
}

/** Действия по порядку строк в настройках. Порядок и id без `local` — те же, что `ACTIONS` в hotkeys.rs. */
export const HOTKEY_ACTIONS = [
  { id: 'toggle', title: 'Играть / пауза', group: 'player' },
  { id: 'next', title: 'Следующий трек', group: 'player' },
  { id: 'prev', title: 'Предыдущий трек', group: 'player' },
  { id: 'seek_back', title: 'Назад на 5 секунд', group: 'player' },
  { id: 'seek_fwd', title: 'Вперёд на 5 секунд', group: 'player' },
  { id: 'volume_up', title: 'Громче', group: 'player' },
  { id: 'volume_down', title: 'Тише', group: 'player' },
  { id: 'mute', title: 'Без звука', group: 'player' },
  { id: 'shuffle', title: 'Перемешивание', group: 'player' },
  { id: 'repeat', title: 'Повтор', group: 'player' },
  { id: 'like', title: 'В Любимые / убрать', group: 'player' },
  { id: 'search', title: 'Поиск', group: 'nav', local: true },
  { id: 'lyrics', title: 'Текст песни', group: 'nav', local: true },
  { id: 'queue', title: 'Очередь', group: 'nav', local: true },
  { id: 'settings', title: 'Настройки', group: 'nav', local: true },
  { id: 'wave', title: 'Запустить Sonar Mix', group: 'nav' },
  { id: 'overlay', title: 'Оверлей', group: 'window' },
  { id: 'mini', title: 'Мини-окно поверх окон', group: 'window' },
  { id: 'window', title: 'Показать / скрыть окно', group: 'window', outside: true },
] as const satisfies readonly ActionDef[]

export type HotkeyAction = (typeof HOTKEY_ACTIONS)[number]['id']

const LOCAL = new Set<string>(HOTKEY_ACTIONS.filter((a) => 'local' in a && a.local).map((a) => a.id))
const OUTSIDE = new Set<string>(HOTKEY_ACTIONS.filter((a) => 'outside' in a && a.outside).map((a) => a.id))

/** Только внутри окна (можно без модификатора). */
export const isLocalAction = (id: string) => LOCAL.has(id)
/** Только по всей системе. */
export const isOutsideAction = (id: string) => OUTSIDE.has(id)

/** Сочетание из нажатия: `Ctrl+Alt+KeyL` (коды клавиш — как у `KeyboardEvent.code`, их же ждёт Rust).
 *  `null` — нажат только модификатор или нет ни одного модификатора. Голую клавишу (`Slash`) берём
 *  только с `bare` — для действий внутри окна. */
export function comboFrom(e: Pick<KeyboardEvent, 'ctrlKey' | 'altKey' | 'shiftKey' | 'metaKey' | 'key' | 'code'>, bare = false): string | null {
  if (MODIFIERS.includes(e.key) || !e.code) return null
  const mods = [e.ctrlKey && 'Ctrl', e.altKey && 'Alt', e.shiftKey && 'Shift', e.metaKey && 'Win'].filter(Boolean) as string[]
  if (!mods.length && !bare) return null
  return [...mods, e.code].join('+')
}

/** В сочетании есть Ctrl, Alt или Win — такое срабатывает и во время набора текста. */
export const hasCommandMod = (combo: string) => /(^|\+)(Ctrl|Alt|Win)\+/.test(combo)

/** Одна клавиша без Ctrl, Alt и Win (пробел, `/`, Shift+… тоже): по всей системе её не ставим — она перехватила
 *  бы набор текста во всех программах, — работает только внутри окна Sonar. */
export const windowOnly = (combo: string) => !!combo && !hasCommandMod(combo)

/** Что отдать Rust на регистрацию по всей системе: при «Везде» — всегда, при «Поверх окон» — пока открыто
 *  окно поверх остальных; действия «только внутри окна» — никогда. Новая карта, исходная не меняется. */
export function globalMap(map: Readonly<Record<string, string>>, scope: HotkeyScope, onTopOpen: boolean): Record<string, string> {
  const on = scope === 'global' || (scope === 'top' && onTopOpen)
  if (!on) return {}
  return Object.fromEntries(Object.entries(map).filter(([id, combo]) => combo && !LOCAL.has(id) && !windowOnly(combo)))
}

/** Поля, где пробел и буквы печатают, а не командуют. Галочка, ползунок и кнопка-input — нет: на них пробел
 *  не ввод, а «нажать», и именно его мы перехватываем под «Играть / пауза». */
const NON_TEXT_INPUT = ['checkbox', 'radio', 'range', 'button', 'submit', 'reset', 'color', 'file', 'image']

/** Цель нажатия принимает текст (или список, который листается буквами): голые клавиши там не команды. */
export function takesText(el: { tagName?: string; type?: string; isContentEditable?: boolean } | null): boolean {
  if (!el) return false
  if (el.isContentEditable) return true
  const tag = el.tagName?.toUpperCase()
  if (tag === 'TEXTAREA' || tag === 'SELECT') return true
  return tag === 'INPUT' && !NON_TEXT_INPUT.includes((el.type ?? 'text').toLowerCase())
}

/** Что делает голый пробел в окне: свою команду из «Клавиши», если пробел туда назначен, иначе «Играть / пауза». */
export function spaceAction(map: Readonly<Record<string, string>>): string {
  return actionFor(map, 'Space') ?? 'toggle'
}

/** Действие для нажатия внутри окна: `null` — ничего (или сочетание у действия «только по всей системе»). */
export function actionFor(map: Readonly<Record<string, string>>, combo: string | null): string | null {
  if (!combo) return null
  const hit = Object.entries(map).find(([id, c]) => c === combo && !OUTSIDE.has(id))
  return hit ? hit[0] : null
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
