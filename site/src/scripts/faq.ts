// /faq в браузере: аккордеон, поиск, открытие по якорю и копирование ссылки на вопрос.
import { matches } from '../lib/faq'

const COPIED_MS = 1600

interface Strings {
  copied: string
}

function setOpen(qa: HTMLElement, open: boolean): void {
  qa.classList.toggle('is-open', open)
  qa.querySelector('[data-qa-toggle]')?.setAttribute('aria-expanded', String(open))
}

function openFromHash(root: HTMLElement, behavior: ScrollBehavior): void {
  const id = decodeURIComponent(location.hash.slice(1))
  if (!id) return
  const qa = root.querySelector<HTMLElement>(`[data-qa]#${CSS.escape(id)}`)
  if (!qa) return
  setOpen(qa, true)
  qa.classList.add('is-in')
  // Ответы выше только что свернулись — прокручиваем после пересчёта раскладки.
  requestAnimationFrame(() => qa.scrollIntoView({ block: 'start', behavior }))
}

function initSearch(root: HTMLElement): void {
  const input = root.querySelector<HTMLInputElement>('[data-faq-input]')
  const empty = root.querySelector<HTMLElement>('[data-faq-empty]')
  const live = root.querySelector<HTMLElement>('[data-faq-live]')
  const groups = [...root.querySelectorAll<HTMLElement>('[data-faq-group]')]
  if (!input) return

  input.addEventListener('input', () => {
    let total = 0
    for (const group of groups) {
      let shown = 0
      for (const qa of group.querySelectorAll<HTMLElement>('[data-qa]')) {
        const ok = matches(qa.dataset.search ?? '', input.value)
        if (ok && qa.hidden) qa.classList.add('is-shown')
        qa.hidden = !ok
        qa.classList.add('is-in')
        if (ok) shown += 1
      }
      group.hidden = shown === 0
      total += shown
    }
    if (empty) empty.hidden = total > 0
    if (live) live.textContent = String(total)
  })

  root.addEventListener('animationend', (e) => (e.target as HTMLElement).classList.remove('is-shown'))
}

export function initFaq(root: HTMLElement): void {
  const strings = JSON.parse(root.querySelector('[data-faq-strings]')?.textContent ?? '{}') as Strings

  for (const qa of root.querySelectorAll<HTMLElement>('[data-qa]')) {
    setOpen(qa, false)
    qa.querySelector('[data-qa-toggle]')?.addEventListener('click', () => {
      const open = !qa.classList.contains('is-open')
      setOpen(qa, open)
      if (open) history.replaceState(null, '', `#${qa.id}`)
    })

    const copy = qa.querySelector<HTMLButtonElement>('[data-qa-copy]')
    const label = copy?.querySelector<HTMLElement>('[data-qa-copy-label]')
    copy?.addEventListener('click', async () => {
      const url = `${location.origin}${location.pathname}#${qa.id}`
      try {
        await navigator.clipboard.writeText(url)
      } catch {
        history.replaceState(null, '', `#${qa.id}`)
        return
      }
      if (!label) return
      const before = label.textContent
      label.textContent = strings.copied
      setTimeout(() => (label.textContent = before), COPIED_MS)
    })
  }

  initSearch(root)
  openFromHash(root, 'instant')
  window.addEventListener('hashchange', () => openFromHash(root, 'smooth'))
}
