// Появление блоков при прокрутке: `data-reveal` у элемента, `data-reveal-group` у родителя — дети идут
// каскадом (номер в группе → `--i`, задержка в CSS). Без IntersectionObserver всё видно сразу.
const THRESHOLD = 0.12
const ROOT_MARGIN = '0px 0px -8% 0px'

export function initReveal(): void {
  for (const group of document.querySelectorAll<HTMLElement>('[data-reveal-group]')) {
    group.querySelectorAll<HTMLElement>(':scope > [data-reveal]').forEach((el, i) => {
      el.style.setProperty('--i', String(i))
    })
  }
  const items = document.querySelectorAll<HTMLElement>('[data-reveal]')
  if (!('IntersectionObserver' in window)) {
    items.forEach((el) => el.classList.add('is-in'))
    return
  }
  const io = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue
        entry.target.classList.add('is-in')
        io.unobserve(entry.target)
      }
    },
    { threshold: THRESHOLD, rootMargin: ROOT_MARGIN },
  )
  items.forEach((el) => io.observe(el))
}
