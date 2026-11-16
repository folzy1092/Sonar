// Полоска-индикатор вкладок: переезжает к выбранной вкладке (PLATFORMS.md «Анимации»).
// `use:indicator={{ key: tab, kind: 'line' }}` на контейнере кнопок; выбранная кнопка — класс `on`.
// line — полоска снизу (настройки, медиатека), pill — капсула за кнопкой (чипы поиска, подразделы).

interface Opts {
  key: unknown
  kind?: 'line' | 'pill'
}

export function indicator(node: HTMLElement, opts: Opts) {
  const ind = document.createElement('span')
  ind.className = `tab-ind ${opts.kind ?? 'line'}`
  ind.setAttribute('aria-hidden', 'true')
  node.classList.add('has-ind')
  node.prepend(ind)
  let first = true
  let raf = 0

  function place() {
    const on = node.querySelector<HTMLElement>(':scope > .on')
    if (!on) {
      ind.style.opacity = '0'
      return
    }
    if (first) ind.style.transition = 'none'
    ind.style.opacity = '1'
    ind.style.width = `${on.offsetWidth}px`
    ind.style.transform = `translateX(${on.offsetLeft}px)`
    if ((opts.kind ?? 'line') === 'pill') {
      ind.style.top = `${on.offsetTop}px`
      ind.style.height = `${on.offsetHeight}px`
    }
    if (first) {
      void ind.offsetWidth
      ind.style.transition = ''
      first = false
    }
  }
  const schedule = () => {
    cancelAnimationFrame(raf)
    raf = requestAnimationFrame(place)
  }
  schedule()
  // кнопки меняют ширину сами (размер шрифта, догрузка шрифта) — следим и за ними
  const ro = new ResizeObserver(schedule)
  const watch = () => {
    ro.disconnect()
    ro.observe(node)
    for (const c of Array.from(node.children)) if (c !== ind) ro.observe(c)
  }
  watch()
  const mo = new MutationObserver(() => {
    watch()
    schedule()
  })
  mo.observe(node, { childList: true })

  return {
    update(o: Opts) {
      opts = o
      schedule()
    },
    destroy() {
      cancelAnimationFrame(raf)
      ro.disconnect()
      mo.disconnect()
      ind.remove()
    },
  }
}
