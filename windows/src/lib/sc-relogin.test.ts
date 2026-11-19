import { describe, expect, it, vi } from 'vitest'
import { relogin, showReloginNotice, RELOGIN_TOAST_MS } from './sc-relogin'
import { toast } from './toast.svelte'
import en from '../i18n/en/services'
import uk from '../i18n/uk/services'

describe('плашка «Войди в SoundCloud заново»', () => {
  it('держится долго и несёт кнопку входа', () => {
    const show = vi.spyOn(toast, 'show')
    showReloginNotice()
    const [text, ms, action] = show.mock.calls.at(-1)!
    expect(text).toBe('Войди в SoundCloud заново')
    expect(ms).toBe(RELOGIN_TOAST_MS)
    expect(action?.label).toBe('Войти заново')
    show.mockRestore()
  })

  it('удачный вход — короткое «снова подключён»', async () => {
    const show = vi.spyOn(toast, 'show')
    await relogin(() => Promise.resolve())
    expect(show.mock.calls.at(-1)?.[0]).toBe('SoundCloud снова подключён')
    show.mockRestore()
  })

  it('вход не вышел — показывает ошибку, не падает', async () => {
    const show = vi.spyOn(toast, 'show')
    await relogin(() => Promise.reject(new Error('Вход отменён — окно закрыто')))
    expect(show.mock.calls.at(-1)?.[0]).toContain('Вход отменён')
    show.mockRestore()
  })

  it('строки переведены на en и uk', () => {
    for (const key of ['Войди в SoundCloud заново', 'SoundCloud снова подключён']) {
      expect(en, key).toHaveProperty([key])
      expect(uk, key).toHaveProperty([key])
    }
  })
})
