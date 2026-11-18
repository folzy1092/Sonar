// Старые значения настроек, которые больше не существуют, — к их замене. Чистая функция: на входе то,
// что прочитано из базы, на выходе новый объект (исходный не меняется). В базе значение поправится
// при следующей записи этой настройки.

/** Ключ → (старое значение → новое). */
const LEGACY: Record<string, Record<string, unknown>> = {
  // «Незнакомое» убрано из Sonar Mix (решение владельца 2026-11-18) — сохранённое читается как «Обычное»
  'wave.mode': { new: 'own' },
  // стиль вкладок «Полный» от «По умолчанию» не отличался и убран из «Вида» (2026-11-18)
  'tabs.style': { full: 'default' },
}

/** Ключ, заменённый другим: из старого значения выводится новое, если новое ещё не сохранено. */
const RENAMED: { from: string; to: string; value: (old: unknown) => unknown }[] = [
  // переключатель «Горячие клавиши по всей системе» → область «В приложении · Поверх окон · Везде» (2026-11-18)
  { from: 'hotkeys.enabled', to: 'hotkeys.scope', value: (on) => (on === true ? 'global' : 'app') },
]

export function migrateSettings(values: Record<string, unknown>): Record<string, unknown> {
  const fixes = Object.entries(LEGACY).flatMap(([key, map]) => {
    const v = values[key]
    return typeof v === 'string' && v in map ? [[key, map[v]] as const] : []
  })
  const renamed = RENAMED.flatMap((r) => (r.from in values && !(r.to in values) ? [[r.to, r.value(values[r.from])] as const] : []))
  const all = [...fixes, ...renamed]
  return all.length ? { ...values, ...Object.fromEntries(all) } : values
}
