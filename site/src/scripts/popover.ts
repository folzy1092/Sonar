// Всплывашки сайта открываются и закрываются только кликом (CLAUDE.md): по кнопке, кликом мимо или Esc.
// Наведение их не трогает.
export function bindPopover(root: HTMLElement, btn: HTMLButtonElement, onToggle?: (open: boolean) => void): void {
  const toggle = (open: boolean) => {
    root.classList.toggle('is-open', open)
    btn.setAttribute('aria-expanded', String(open))
    onToggle?.(open)
  }
  btn.addEventListener('click', (e) => {
    e.stopPropagation()
    toggle(!root.classList.contains('is-open'))
  })
  document.addEventListener('click', (e) => {
    if (root.classList.contains('is-open') && !root.contains(e.target as Node)) toggle(false)
  })
  root.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || !root.classList.contains('is-open')) return
    toggle(false)
    btn.focus()
  })
}
