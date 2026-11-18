// Кнопки окна (Интерфейс → Вид → Форма): «Авто» — как в системе, где запущен Sonar; exe собирается только
// под Windows, но в браузере для проверки вёрстки на Mac «Авто» честно показывает кружки.

export type WindowButtons = 'auto' | 'windows' | 'macos'

/** Какие кнопки рисовать: настройка + строка платформы (`navigator.platform` / userAgent). */
export function windowButtonsLook(setting: WindowButtons, platform: string): 'windows' | 'macos' {
  if (setting !== 'auto') return setting
  return /mac/i.test(platform) ? 'macos' : 'windows'
}
