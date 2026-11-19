// SoundCloud ответил 401 на своих ключах, и ни свежий client_id, ни тихий вход не помогли
// (services/sc_repair.rs, docs/POLISH_PROMPT.md п. 8) — одна плашка «Войди в SoundCloud заново»
// с кнопкой входа. Ядро шлёт сигнал один раз до нового входа, плашка держится дольше обычной.

import { api, errorText, onSoundCloudRelogin } from './api'
import { t } from './i18n.svelte'
import { toast } from './toast.svelte'

/** Сколько висит плашка (мс): кнопку должно быть видно, а не мелькнуть. */
export const RELOGIN_TOAST_MS = 20_000

export async function relogin(login: () => Promise<unknown> = () => api.loginService('soundcloud')): Promise<void> {
  try {
    await login()
    toast.show(t('SoundCloud снова подключён'))
  } catch (e) {
    toast.show(errorText(e))
  }
}

export function showReloginNotice(): void {
  toast.show(t('Войди в SoundCloud заново'), RELOGIN_TOAST_MS, { label: t('Войти заново'), run: () => relogin() })
}

export function initScRelogin(): () => void {
  return onSoundCloudRelogin(showReloginNotice)
}
