// Бета-обновления — только владельцу (решение 2026-11-26). Источник беты — сборки CI прямо с GitHub, но клиент ходит не
// туда, а на свой сервер: он проверяет сессию и отдаёт бету логинам из `SONAR_BETA_USERS` (по умолчанию `folzy`), а всем
// остальным отвечает как на релиз. Здесь тот же список — чтобы чужим не показывать переключатель и не слать запрос беты зря.
// Релиз всех остальных берётся только с сайта (то, что владелец выпустил в админке «Сборки»), GitHub у них не опрашивается.

export const BETA_LOGINS: readonly string[] = ['folzy']

export const betaAllowed = (login: string | null | undefined): boolean => !!login && BETA_LOGINS.includes(login.trim().toLowerCase())

/** Канал обновлений: «Бета» включена в настройках **и** вошёл свой логин; иначе релиз. */
export function updateChannel(setting: unknown, login: string | null | undefined): 'beta' | 'release' {
  return setting === 'beta' && betaAllowed(login) ? 'beta' : 'release'
}
