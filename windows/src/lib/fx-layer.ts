// Слой эффектов поверх окна (Интерфейс → Стиль, STYLE_PROMPT §4): кольца, световая дуга, кардиограмма
// лайка рисуются в отдельном слое над интерфейсом — по прямоугольнику элемента, а не внутри него
// (у обложек `overflow: hidden`, кольцо обрезалось бы). Элемент слоя живёт `ms` и удаляется сам.
import { displaced, type AncestorAnimation, type AncestorInfo } from './fx-displaced'

let layer: HTMLDivElement | null = null

/** Служебные ключи кадра WAAPI — не свойства CSS. */
const FRAME_KEYS = new Set(['offset', 'computedOffset', 'easing', 'composite'])

function animationInfo(a: Animation): AncestorAnimation {
  const effect = a.effect instanceof KeyframeEffect ? a.effect : null
  const properties =
    'transitionProperty' in a
      ? [String((a as Animation & { transitionProperty: string }).transitionProperty)]
      : (effect?.getKeyframes() ?? []).flatMap((k) => Object.keys(k).filter((key) => !FRAME_KEYS.has(key)))
  return {
    properties,
    infinite: effect?.getComputedTiming().iterations === Infinity,
    running: a.playState === 'running',
  }
}

/** Снимок предков элемента (сам элемент не в счёт: на нём своя анимация смены трека). */
function ancestors(el: Element): AncestorInfo[] {
  const out: AncestorInfo[] = []
  for (let a = el.parentElement; a; a = a.parentElement) {
    const cs = getComputedStyle(a)
    out.push({
      away: a.classList.contains('shell') && a.classList.contains('away'),
      transform: cs.transform,
      translate: cs.translate,
      rotate: cs.rotate,
      scale: cs.scale,
      animations: a.getAnimations().map(animationInfo),
    })
  }
  return out
}

function host(): HTMLDivElement {
  if (layer?.isConnected) return layer
  layer = document.createElement('div')
  layer.className = 'fx-layer'
  layer.setAttribute('aria-hidden', 'true')
  document.body.appendChild(layer)
  return layer
}

export interface VisibleOptions {
  /** Ещё и стоит ли на своём месте: окно уехало под панель настроек, предок сдвинут или сейчас
   *  двигается — эффект не рисуем, иначе кольца и дуга смены трека повисли бы мимо мини-плеера
   *  (lib/fx-displaced.ts). Только для эффектов смены трека (track-fx): лайк рисуется по клику, и у
   *  кнопки-предка в этот миг ещё идёт свой press-scale (`:active` → обратный переход). */
  steady?: boolean
}

/** Виден ли элемент: есть размер, попадает в окно и не закрыт полноэкранным слоем `data-fx-overlay`
 *  (иначе дуга мини-плеера рисовалась бы поверх полноэкранного плеера). `steady` — см. VisibleOptions. */
export function visible(el: Element, { steady = false }: VisibleOptions = {}): DOMRect | null {
  const overlay = document.querySelector('[data-fx-overlay]')
  if (overlay && !overlay.contains(el)) return null
  const r = el.getBoundingClientRect()
  if (r.width < 2 || r.height < 2 || r.bottom < 0 || r.right < 0 || r.top > innerHeight || r.left > innerWidth) return null
  if (steady && displaced(ancestors(el))) return null
  return r
}

/** Положить эффект в слой над прямоугольником `rect` (`pad` — на сколько шире), убрать через `ms`. */
export function spawn(rect: DOMRect, html: string, cls: string, ms: number, pad = 0, style: Record<string, string> = {}): HTMLElement {
  const el = document.createElement('div')
  el.className = `fx ${cls}`
  el.innerHTML = html
  Object.assign(el.style, {
    left: `${rect.left - pad}px`,
    top: `${rect.top - pad}px`,
    width: `${rect.width + pad * 2}px`,
    height: `${rect.height + pad * 2}px`,
    ...style,
  })
  host().appendChild(el)
  setTimeout(() => el.remove(), ms)
  return el
}

/** Перезапустить CSS-анимацию элемента: снять класс, пересчитать вёрстку, поставить снова. */
export function restart(el: Element, cls: string, ms: number) {
  el.classList.remove(cls)
  void (el as HTMLElement).offsetWidth
  el.classList.add(cls)
  const prev = Number((el as HTMLElement).dataset.fxTimer)
  if (prev) clearTimeout(prev)
  ;(el as HTMLElement).dataset.fxTimer = String(setTimeout(() => el.classList.remove(cls), ms))
}
