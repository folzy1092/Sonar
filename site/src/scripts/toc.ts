// Оглавление юр-страниц: подсветка раздела, который сейчас читают, и плавный бегунок под ним.
const ACTIVE_BAND = '-30% 0px -60% 0px'

export function initToc(nav: HTMLElement): void {
  const links = new Map<string, HTMLAnchorElement>()
  nav.querySelectorAll<HTMLAnchorElement>('[data-toc-link]').forEach((a) => links.set(a.dataset.tocLink ?? '', a))
  const marker = nav.querySelector<HTMLElement>('[data-toc-marker]')
  const sections = [...document.querySelectorAll<HTMLElement>('[data-toc-section]')]
  if (!sections.length || !('IntersectionObserver' in window)) return

  const setActive = (id: string): void => {
    for (const [key, a] of links) a.setAttribute('aria-current', String(key === id))
    const link = links.get(id)
    if (!marker || !link) return
    marker.style.setProperty('--y', `${link.offsetTop}px`)
    marker.style.setProperty('--h', `${link.offsetHeight}px`)
    marker.classList.add('is-on')
  }

  const io = new IntersectionObserver(
    (entries) => {
      const hit = entries.find((e) => e.isIntersecting)
      if (hit) setActive(hit.target.id)
    },
    { rootMargin: ACTIVE_BAND },
  )
  sections.forEach((s) => io.observe(s))
  setActive(location.hash.slice(1) && links.has(location.hash.slice(1)) ? location.hash.slice(1) : sections[0].id)
}
