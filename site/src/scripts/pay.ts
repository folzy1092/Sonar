// Живая часть /pay: выбор из `?plan=&period=&u=`, пересчёт цен с анимацией, адрес страницы в такт выбору
// (ссылкой можно поделиться), шторка сводки на телефоне. Логика цен — `lib/plans.ts` (покрыта тестами).
import {
  PERIODS,
  findPeriod,
  findPlan,
  normalizeUsername,
  parsePayQuery,
  payQuery,
  price,
  rub,
  savedPercent,
  type PaySelection,
  type PeriodId,
  type PlanId,
} from '../lib/plans'
import { tweenNumber } from './count'

interface PayStrings {
  plans: Record<PlanId, { name: string; seats: string }>
  periods: Record<PeriodId, { short: string; title: string }>
  payTo: string
  noUser: string
  perMonth: string
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`)
}

function setText(root: HTMLElement, selector: string, text: string): void {
  root.querySelectorAll<HTMLElement>(selector).forEach((el) => (el.textContent = text))
}

export function initPay(root: HTMLElement): void {
  const stringsEl = root.querySelector('[data-pay-strings]')
  if (!stringsEl?.textContent) return
  const strings = JSON.parse(stringsEl.textContent) as PayStrings
  const userInput = root.querySelector<HTMLInputElement>('[data-user]')
  const seg = root.querySelector<HTMLElement>('[data-seg]')
  const planInputs = [...root.querySelectorAll<HTMLInputElement>('input[name="plan"]')]
  const periodInputs = [...root.querySelectorAll<HTMLInputElement>('input[name="period"]')]

  let sel: PaySelection = parsePayQuery(location.search)

  const render = () => {
    const plan = findPlan(sel.plan)
    const period = findPeriod(sel.period)
    planInputs.forEach((input, i) => {
      input.checked = input.value === plan.id
      if (input.checked) seg?.style.setProperty('--idx', String(i))
    })
    periodInputs.forEach((input) => (input.checked = input.value === period.id))

    for (const p of PERIODS) {
      const total = price(plan, p)
      const saved = savedPercent(plan, p)
      const priceEl = root.querySelector<HTMLElement>(`[data-period-price="${p.id}"]`)
      if (priceEl) tweenNumber(priceEl, total, rub)
      setText(root, `[data-period-per="${p.id}"]`, strings.perMonth.replace('{price}', rub(Math.round(total / p.months))))
      const saveEl = root.querySelector<HTMLElement>(`[data-period-save="${p.id}"]`)
      if (saveEl) {
        saveEl.hidden = saved === 0
        saveEl.textContent = `−${saved} %`
      }
    }

    setText(root, '[data-sum-name]', strings.plans[plan.id].name)
    setText(root, '[data-sum-seats]', strings.plans[plan.id].seats)
    setText(root, '[data-sum-title]', strings.periods[period.id].title)
    setText(root, '[data-sum-short]', strings.periods[period.id].short)
    root.querySelectorAll<HTMLElement>('[data-sum-total]').forEach((el) => tweenNumber(el, price(plan, period), rub))
    const userEl = root.querySelector<HTMLElement>('[data-sum-user]')
    if (userEl) {
      userEl.innerHTML = sel.username
        ? escapeHtml(strings.payTo).replace('{u}', `<b>@${escapeHtml(sel.username)}</b>`)
        : escapeHtml(strings.noUser)
    }
    history.replaceState(history.state, '', `${location.pathname}${payQuery(sel)}${location.hash}`)
  }

  planInputs.forEach((input) =>
    input.addEventListener('change', () => {
      sel = { ...sel, plan: input.value as PlanId }
      render()
    }),
  )
  periodInputs.forEach((input) =>
    input.addEventListener('change', () => {
      sel = { ...sel, period: input.value as PeriodId }
      render()
    }),
  )

  if (userInput) {
    userInput.value = sel.username
    const ok = root.querySelector<HTMLElement>('[data-hint-ok]')
    const bad = root.querySelector<HTMLElement>('[data-hint-bad]')
    userInput.addEventListener('input', () => {
      const raw = userInput.value.trim().replace(/^@+/, '')
      const username = normalizeUsername(raw)
      const invalid = raw.length > 0 && !username
      userInput.setAttribute('aria-invalid', String(invalid))
      if (ok) ok.hidden = invalid
      if (bad) bad.hidden = !invalid
      sel = { ...sel, username }
      render()
    })
  }

  initSheet(root)
  render()
}

/** Шторка сводки на телефоне: открывается и закрывается только нажатием (кнопка или фон). */
function initSheet(root: HTMLElement): void {
  const sum = root.querySelector<HTMLElement>('[data-sum]')
  const toggle = root.querySelector<HTMLButtonElement>('[data-sum-toggle]')
  const backdrop = root.querySelector<HTMLElement>('[data-sum-backdrop]')
  if (!sum || !toggle) return
  const setOpen = (open: boolean) => {
    sum.classList.toggle('is-open', open)
    backdrop?.classList.toggle('is-open', open)
    toggle.setAttribute('aria-expanded', String(open))
  }
  toggle.addEventListener('click', () => setOpen(!sum.classList.contains('is-open')))
  backdrop?.addEventListener('click', () => setOpen(false))
}
