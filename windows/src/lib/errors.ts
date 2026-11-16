// Ошибки интерфейса — в журнал сессии (crashlog.rs): необработанные исключения и отказы промисов.
// Одинаковые подряд не повторяем, всего за сессию — не больше 60 (столько же держит Rust).
import { api } from './api'

let last = ''
let count = 0

function report(message: string, level: 'error' | 'warn' = 'error') {
  if (!message || message === last || count >= 60) return
  last = message
  count++
  void api.logFrontend(level, message).catch(() => {})
}

const describe = (e: unknown) =>
  e instanceof Error ? `${e.name}: ${e.message}${e.stack ? `\n${e.stack.split('\n').slice(1, 6).join('\n')}` : ''}` : String(e)

export function catchErrors() {
  window.addEventListener('error', (e) => {
    // ошибки загрузки картинок и т.п. приходят без error — это не сбой интерфейса
    if (!e.error && !e.message) return
    report(`${describe(e.error ?? e.message)}${e.filename ? ` @ ${e.filename.split('/').pop()}:${e.lineno}` : ''}`)
  })
  // отказ строкой — это ошибка команды Rust (нет сети, сервис не ответил): ожидаемое, только для
  // истории; отказ объектом Error — сбой самого интерфейса
  window.addEventListener('unhandledrejection', (e) =>
    report(`Promise: ${describe(e.reason)}`, typeof e.reason === 'string' ? 'warn' : 'error'),
  )
}
