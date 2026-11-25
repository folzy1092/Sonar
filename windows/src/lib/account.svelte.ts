// Аккаунт Sonar на ПК (API.md §1, Rust — src-tauri/src/account.rs). Сессия живёт в keyring, сюда
// приходит только `User`. Вход обязателен (решение владельца 2026-11-25), но ворота встают, только
// когда сервер отвечает: офлайн-режим и недоступный сервер пускают в Sonar как раньше.
import { invoke } from '@tauri-apps/api/core'
import { isTauri } from './tauri'
import { settings } from './settings.svelte'
import { offline } from './offline.svelte'

export interface AccountUser {
  id: string
  login: string
  username: string
  display_name: string
  number: number | null
  avatar_url: string | null
  created_at: number
  telegram: { id: number; username: string | null } | null
  has_password: boolean
}

export interface AccountDevice {
  id: string
  name: string
  platform: 'windows' | 'ios' | 'android' | string
  os: string | null
  app_version: string | null
  build: number | null
  created_at: number
  last_seen_at: number
  current: boolean
}

export interface TelegramStart {
  request_id: string
  link: string
  expires_at: number
}

export interface QuickLink {
  code: string
  url: string
  bot_url: string
  expires_at: number
}

/** Ключ API (API.md §7): один на аккаунт, общий с ботом. Ключа нет — `key: null`. */
export interface ApiKey {
  key: string | null
  created_at: number | null
}

export type PollStatus = 'pending' | 'approved' | 'rejected' | 'expired'

export interface LinkInfo {
  code: string
  for: { kind: 'telegram' | 'device'; name: string; platform?: string }
  created_at: number
  expires_at: number
}

/** Завершать другие сессии — только когда своя старше суток (правило сервера, `session_too_new`). */
export const REVOKE_DELAY_MS = 24 * 3600_000

export function canRevokeOthers(devices: AccountDevice[], now = Date.now()): boolean {
  const me = devices.find((d) => d.current)
  return !!me && now - me.created_at >= REVOKE_DELAY_MS
}

/** Сначала это устройство, дальше — кто был в сети позже. */
export function sortDevices(devices: AccountDevice[]): AccountDevice[] {
  return [...devices].sort((a, b) => (a.current !== b.current ? (a.current ? -1 : 1) : b.last_seen_at - a.last_seen_at))
}

/** Логин по правилам сервера: 3–24 символа, латиница, цифры, «_» и «.». */
export function loginProblem(raw: string): string | null {
  const login = raw.trim().replace(/^@/, '').toLowerCase()
  if (login.length < 3 || login.length > 24) return 'Логин — от 3 до 24 символов'
  if (!/^[a-z0-9_.]+$/.test(login)) return 'Только латиница, цифры, «_» и «.»'
  return null
}

export const passwordProblem = (p: string): string | null => (p.length < 8 ? 'Пароль — от 8 символов' : null)

/** Нужен ли экран входа: сервер ответил, а сессии нет. Офлайн-режим — никогда. */
export function needsGate(s: { signedIn: boolean; reachable: boolean; offline: boolean }): boolean {
  return !s.offline && s.reachable && !s.signedIn
}

const call = <T>(cmd: string, args?: Record<string, unknown>) => invoke<T>(cmd, args)

class Account {
  user = $state<AccountUser | null>(null)
  signedIn = $state(false)
  /** Сервер ответил на `/health` при последней проверке. */
  reachable = $state(false)
  checked = $state(false)
  server = $state('')

  readonly gate = $derived(needsGate({ signedIn: this.signedIn, reachable: this.reachable, offline: offline.on }))

  async init() {
    if (!isTauri) return
    const st = await call<{ server: string; signed_in: boolean; user: AccountUser | null }>('account_status')
    this.server = st.server
    this.signedIn = st.signed_in
    this.user = st.user
    this.reachable = await call<boolean>('account_ping').catch(() => false)
    this.checked = true
    if (this.signedIn && this.reachable) {
      void this.refresh()
      void call('account_report_device').catch(() => {})
    }
  }

  /** Перепроверить сервер (кнопка «Повторить» на плашке, смена офлайн-режима). */
  async ping() {
    this.reachable = await call<boolean>('account_ping').catch(() => false)
  }

  /** Ошибка `signed_out` — сессию отозвали на другом устройстве: показываем вход. */
  private guard = (e: unknown): never => {
    if (String(e) === 'signed_out') this.dropLocal()
    throw e
  }

  private dropLocal() {
    this.signedIn = false
    this.user = null
  }

  private apply(user: AccountUser) {
    const fresh = !this.signedIn
    this.user = user
    this.signedIn = true
    // только что вошли — сразу синк с сервером (лайки, плейлисты, настройки с других устройств)
    if (fresh) void call('account_sync').catch(() => {})
    // Профиль на ПК — из аккаунта: имя и @username те же, что видят друзья и сайт.
    settings.set('profile.name', user.display_name)
    settings.set('profile.username', user.username)
  }

  async refresh() {
    try {
      this.apply(await call<AccountUser>('account_me'))
    } catch (e) {
      if (String(e) === 'signed_out') this.dropLocal()
    }
  }

  async login(login: string, password: string) {
    this.apply(await call<AccountUser>('account_login', { login: login.trim().replace(/^@/, ''), password }))
    void call('account_report_device').catch(() => {})
  }

  async register(login: string, password: string) {
    this.apply(await call<AccountUser>('account_register', { login: login.trim().replace(/^@/, '').toLowerCase(), password }))
  }

  async logout() {
    await call('account_logout').catch(() => {})
    this.dropLocal()
  }

  async update(patch: { username?: string; display_name?: string }) {
    this.apply(await call<AccountUser>('account_update', { username: patch.username ?? null, displayName: patch.display_name ?? null }).catch(this.guard))
  }

  changePassword(oldPassword: string | null, newPassword: string) {
    return call<void>('account_password', { oldPassword, newPassword }).catch(this.guard)
  }

  async devices() {
    return sortDevices(await call<AccountDevice[]>('account_devices').catch(this.guard))
  }

  renameDevice(id: string, name: string) {
    return call<AccountDevice>('account_rename_device', { id, name }).catch(this.guard)
  }

  revokeDevice(id: string) {
    return call<void>('account_revoke_device', { id }).catch(this.guard)
  }

  apiKey() {
    return call<ApiKey>('account_api_key').catch(this.guard)
  }

  newApiKey() {
    return call<ApiKey>('account_api_key_new').catch(this.guard)
  }

  deleteApiKey() {
    return call<void>('account_api_key_delete').catch(this.guard)
  }

  telegramStart(purpose: 'login' | 'link') {
    return call<TelegramStart>('account_tg_start', { purpose })
  }

  /** Опрос входа через Telegram или другое устройство; пришла сессия — уже вошли. */
  async poll(kind: 'telegram' | 'link', id: string): Promise<PollStatus> {
    const out = kind === 'telegram'
      ? await call<{ status: PollStatus; user: AccountUser | null }>('account_tg_poll', { id })
      : await call<{ status: PollStatus; user: AccountUser | null }>('account_link_poll', { code: id })
    if (out.status === 'approved' && out.user) {
      this.apply(out.user)
      void call('account_report_device').catch(() => {})
    }
    return out.status
  }

  unlinkTelegram() {
    return call<void>('account_tg_unlink').catch(this.guard)
  }

  quickLink() {
    return call<QuickLink>('account_link_create')
  }

  linkInfo(link: string) {
    return call<LinkInfo>('account_link_info', { link }).catch(this.guard)
  }

  decideLink(code: string, approve: boolean) {
    return call<void>('account_link_decide', { code, approve }).catch(this.guard)
  }
}

export const account = new Account()
