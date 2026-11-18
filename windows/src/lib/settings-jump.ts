// Переход из поиска по настройкам к самому пункту (NEXT_PROMPT «Этап 0» п. 4): найти заголовок на
// открытой странице, раскрыть «Ещё настройки», если пункт там, докрутить и коротко подсветить.
import { normalize, titleMatches } from './settings-catalog'
import { reducedMotion } from './motion'

/** Где на страницах настроек стоят заголовки пунктов (Switch, Cards, Choice, Group, Tiles…). */
const TITLE_SELECTOR = 'b, h4, .title, .caption, strong'
/** Что подсвечивать — строку или блок пункта целиком. */
const ROW_SELECTOR = '.row, .block, section'
/** «Ещё настройки» раскрывается за --normal; ждём чуть дольше, чтобы высота была настоящей. */
const REVEAL_WAIT_MS = 320
/** Подсветка держится FLASH_MS и гаснет за FADE_MS (переход цвета фона — работает и с «Меньше движения»). */
const FLASH_MS = 1600
const FADE_MS = 600

const wait = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms))

/** Сначала точное совпадение («Стиль» ≠ «Стиль плеера»), потом — с начала (у заголовка бывает значок «Скоро»). */
function findTitle(root: HTMLElement, title: string): HTMLElement | null {
  const all = [...root.querySelectorAll<HTMLElement>(TITLE_SELECTOR)]
  const want = normalize(title)
  return all.find((el) => normalize(el.textContent ?? '') === want) ?? all.find((el) => titleMatches(el.textContent ?? '', title)) ?? null
}

function flash(row: HTMLElement) {
  row.classList.add('flash')
  requestAnimationFrame(() => row.classList.add('found'))
  setTimeout(() => row.classList.remove('found'), FLASH_MS)
  setTimeout(() => row.classList.remove('flash'), FLASH_MS + FADE_MS)
}

/** Раскрывает свёрнутый блок «Ещё настройки» вокруг элемента; true — пришлось раскрывать. */
function reveal(el: HTMLElement): boolean {
  const more = el.closest<HTMLElement>('[data-more]')
  if (!more || more.classList.contains('open')) return false
  more.dispatchEvent(new Event('reveal'))
  return true
}

/** Прокрутить к пункту и подсветить его. Пункт не нашёлся (страница ещё грузится) — тихо остаёмся наверху. */
export async function jumpToSetting(root: HTMLElement, title: string): Promise<boolean> {
  const el = findTitle(root, title)
  if (!el) return false
  if (reveal(el)) await wait(REVEAL_WAIT_MS)
  el.scrollIntoView({ block: 'center', behavior: reducedMotion() ? 'auto' : 'smooth' })
  flash(el.closest<HTMLElement>(ROW_SELECTOR) ?? el)
  return true
}
