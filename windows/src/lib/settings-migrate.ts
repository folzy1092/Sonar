// Старые значения настроек, которые больше не существуют, — к их замене. Чистая функция: на входе то,
// что прочитано из базы, на выходе новый объект (исходный не меняется). В базе значение поправится
// при следующей записи этой настройки.

/** Ключ → (старое значение → новое). */
const LEGACY: Record<string, Record<string, unknown>> = {
  // «Незнакомое» убрано из Sonar Mix (решение владельца 2026-11-18) — сохранённое читается как «Обычное»
  'wave.mode': { new: 'own' },
}

export function migrateSettings(values: Record<string, unknown>): Record<string, unknown> {
  const fixes = Object.entries(LEGACY).flatMap(([key, map]) => {
    const v = values[key]
    return typeof v === 'string' && v in map ? [[key, map[v]] as const] : []
  })
  return fixes.length ? { ...values, ...Object.fromEntries(fixes) } : values
}
