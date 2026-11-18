// Сдвинут ли элемент эффекта со своего места (lib/fx-layer.ts `visible`): эффект слоя рисуется по
// прямоугольнику элемента в момент смены трека, и если в этот миг предок уехал (окно ушло вправо под
// панель настроек — `.shell.away`, идёт переход, предок повёрнут или сдвинут), кольца и дуга повиснут
// не там. Без DOM: на вход — снимок предков, проверяется тестами (fx-displaced.test.ts).

/** Анимация предка: CSS-переход (свойство) или анимация / WAAPI (свойства ключевых кадров). */
export interface AncestorAnimation {
  /** Свойства (`transform`, `margin-top`, `gridTemplateRows`, `all`…). */
  properties: string[]
  /** Повторяется бесконечно (пульс, свечение) — не сдвиг, а фон. */
  infinite: boolean
  /** Идёт сейчас (не на паузе и не закончилась). */
  running: boolean
}

/** Снимок одного предка элемента эффекта. */
export interface AncestorInfo {
  /** Окно уехало под панель настроек (`.shell.away`). */
  away: boolean
  /** Вычисленные `transform`, `translate`, `rotate`, `scale` (`none` — нет). */
  transform: string
  translate?: string
  rotate?: string
  scale?: string
  animations: AncestorAnimation[]
}

/** Свойства, анимация которых двигает или меняет размер того, что внутри. */
const MOVING = ['transform', 'translate', 'rotate', 'scale', 'left', 'top', 'right', 'bottom', 'inset', 'width', 'height', 'margin', 'padding', 'grid-template', 'row-gap', 'column-gap', 'gap', 'offset']

const kebab = (prop: string) => prop.replace(/[A-Z]/g, (c) => '-' + c.toLowerCase()).toLowerCase()

/** Двигает ли анимация этого свойства содержимое (`all` — да). */
export function movingProperty(prop: string): boolean {
  const p = kebab(prop.trim())
  return p === 'all' || MOVING.some((m) => p === m || p.startsWith(m + '-'))
}

const numbers = (s: string) => (s.match(/-?\d*\.?\d+(?:e-?\d+)?/gi) ?? []).map(Number)
const EPS = 1e-3

/** `transform` без сдвига, поворота и масштаба (`none` или единичная матрица). */
export function identityTransform(value: string | undefined): boolean {
  const v = (value ?? '').trim()
  if (!v || v === 'none') return true
  const m2 = /^matrix\(([^)]*)\)$/.exec(v)
  if (m2) {
    const n = numbers(m2[1])
    const id = [1, 0, 0, 1, 0, 0]
    return n.length === 6 && n.every((x, i) => Math.abs(x - id[i]) < EPS)
  }
  const m3 = /^matrix3d\(([^)]*)\)$/.exec(v)
  if (m3) {
    const n = numbers(m3[1])
    return n.length === 16 && n.every((x, i) => Math.abs(x - (i % 5 === 0 ? 1 : 0)) < EPS)
  }
  return false
}

/** Отдельные `translate` / `rotate` (нули — на месте) и `scale` (единицы — на месте). */
function identityPart(value: string | undefined, rest: number): boolean {
  const v = (value ?? '').trim()
  if (!v || v === 'none') return true
  const n = numbers(v)
  return n.length > 0 && n.every((x) => Math.abs(x - rest) < EPS)
}

/** Предок сдвинут: уехал под настройки, повёрнут / сдвинут / масштабирован или сейчас двигается. */
export function ancestorDisplaced(a: AncestorInfo): boolean {
  if (a.away) return true
  if (!identityTransform(a.transform)) return true
  if (!identityPart(a.translate, 0) || !identityPart(a.scale, 1)) return true
  if (!identityRotate(a.rotate)) return true
  return a.animations.some((x) => x.running && !x.infinite && x.properties.some(movingProperty))
}

/** `rotate`: `none`, `0deg` или ось с нулевым углом (`0 0 1 0deg`) — на месте. */
function identityRotate(value: string | undefined): boolean {
  const v = (value ?? '').trim()
  if (!v || v === 'none') return true
  const n = numbers(v)
  return n.length > 0 && Math.abs(n[n.length - 1]) < EPS
}

/** Хоть один предок сдвинут — эффект по прямоугольнику элемента рисовать нельзя. */
export function displaced(chain: AncestorInfo[]): boolean {
  return chain.some(ancestorDisplaced)
}
