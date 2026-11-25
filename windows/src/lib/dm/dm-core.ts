// Личные сообщения (docs/DM.md): сообщения, вложения, ссылки `sonar://` в тексте, правка и прочитанность.
// Чистое ядро без сети. До сервера им живёт демо-чат; потом сервер хранит то же (`dm_threads`, `dm_messages`,
// `dm_attachments` — docs/DB.md). Чат комнаты — тот же механизм, тред привязан к `room_id`.
// iPhone — `Core/DM/DMCore.swift`, правила менять в обоих местах.

export type DMAttachment =
  | { kind: 'track'; ref: string; title: string; artist: string; cover_url: string | null }
  | { kind: 'playlist'; id: string; title: string; count: number; cover_url: string | null }
  | { kind: 'room'; room_id: string; host: string; title: string }

export interface DMMessage {
  id: string
  thread_id: string
  from: string
  text: string
  attachments: DMAttachment[]
  /** Ответ на сообщение (id), удалённое — всё равно показываем «сообщение удалено». */
  reply_to: string | null
  sent_at: number
  edited_at: number | null
  deleted: boolean
}

export interface DMThread {
  id: string
  /** Собеседник (личный чат) или null — чат комнаты. */
  peer: string | null
  room_id: string | null
  /** До какого сообщения (sent_at) собеседник прочитал наши. */
  peer_read_at: number
  /** До какого мы прочитали его. */
  my_read_at: number
}

/** Предел длины сообщения (сервер режет так же). */
export const DM_MAX_TEXT = 2000
/** Сколько сервер хранит сообщения (решение владельца 2026-11-25). */
export const DM_RETENTION_MS = 30 * 24 * 3600_000

/** Убрать сообщения старше срока хранения — так же их стирает сервер. */
export function dropExpired(messages: readonly DMMessage[], now: number): DMMessage[] {
  return messages.filter((m) => now - m.sent_at <= DM_RETENTION_MS)
}

/** Свои сообщения можно править столько после отправки. */
export const DM_EDIT_WINDOW_MS = 48 * 3600_000

export type SonarLink = { kind: 'track' | 'album' | 'playlist' | 'room' | 'user'; value: string }

const LINK = /sonar:\/\/(track|album|playlist|room|user)\/([^\s<>"'`]+)/gi

/** Ссылка на трек для чата и «Поделиться»: ref как есть, `:` в пути разрешён. */
export function sonarLink(kind: SonarLink['kind'], value: string): string {
  return `sonar://${kind}/${encodeURI(value)}`
}

/** Все ссылки `sonar://…` в тексте по порядку, без повторов; хвостовая пунктуация — не часть ссылки. */
export function parseSonarLinks(text: string): SonarLink[] {
  const out: SonarLink[] = []
  const seen = new Set<string>()
  for (const m of text.matchAll(LINK)) {
    let value = m[2].replace(/[.,;:!?)\]]+$/, '')
    try {
      value = decodeURI(value)
    } catch {
      continue
    }
    if (!value) continue
    const kind = m[1].toLowerCase() as SonarLink['kind']
    const key = `${kind}/${value}`
    if (seen.has(key)) continue
    seen.add(key)
    out.push({ kind, value })
  }
  return out
}

/** Куда ведёт вложение: ссылка `sonar://` (её же понимает iPhone `DeepLink`). */
export function attachmentLink(a: DMAttachment): string {
  if (a.kind === 'track') return sonarLink('track', a.ref)
  if (a.kind === 'playlist') return sonarLink('playlist', a.id)
  return sonarLink('room', a.room_id)
}

export type DraftError = 'empty' | 'too_long' | 'too_many'

/** Вложений в одном сообщении. */
export const DM_MAX_ATTACHMENTS = 4

/** Проверить черновик перед отправкой: текст обрезается по краям, пустое без вложений не уходит. */
export function checkDraft(text: string, attachments: readonly DMAttachment[]): { ok: true; text: string } | { ok: false; error: DraftError } {
  const clean = text.trim()
  if (!clean && attachments.length === 0) return { ok: false, error: 'empty' }
  if ([...clean].length > DM_MAX_TEXT) return { ok: false, error: 'too_long' }
  if (attachments.length > DM_MAX_ATTACHMENTS) return { ok: false, error: 'too_many' }
  return { ok: true, text: clean }
}

/** Можно ли править: своё, не удалённое, в окне правки. Удалить своё можно всегда. */
export function canEdit(msg: DMMessage, me: string, now: number): boolean {
  return msg.from === me && !msg.deleted && now - msg.sent_at <= DM_EDIT_WINDOW_MS
}

export function canDelete(msg: DMMessage, me: string): boolean {
  return msg.from === me && !msg.deleted
}

/** Правка: новый текст, отметка времени. Вложения не трогаем. Нельзя или ничего не поменялось — null. */
export function editMessage(msg: DMMessage, me: string, text: string, now: number): DMMessage | null {
  if (!canEdit(msg, me, now)) return null
  const draft = checkDraft(text, msg.attachments)
  if (!draft.ok || draft.text === msg.text) return null
  return { ...msg, text: draft.text, edited_at: now }
}

/** Удаление: текст и вложения стираются, место в ленте остаётся («Сообщение удалено»). */
export function deleteMessage(msg: DMMessage, me: string): DMMessage | null {
  if (!canDelete(msg, me)) return null
  return { ...msg, text: '', attachments: [], deleted: true }
}

/** Непрочитанные чужие сообщения в треде. */
export function unreadCount(thread: DMThread, messages: readonly DMMessage[], me: string): number {
  return messages.filter((m) => m.thread_id === thread.id && m.from !== me && !m.deleted && m.sent_at > thread.my_read_at).length
}

/** Прочитано ли собеседником наше сообщение (галочка). */
export function seenByPeer(thread: DMThread, msg: DMMessage, me: string): boolean {
  return msg.from === me && msg.sent_at <= thread.peer_read_at
}

/** Цитата для ответа: первая строка, не длиннее `max` символов; удалённое — null. */
export function replyPreview(msg: DMMessage | undefined, max = 80): string | null {
  if (!msg || msg.deleted) return null
  const line = msg.text.split('\n', 1)[0].trim()
  if (line) return [...line].length > max ? [...line].slice(0, max - 1).join('') + '…' : line
  const a = msg.attachments[0]
  if (!a) return null
  return a.kind === 'track' ? `${a.artist} — ${a.title}` : a.title
}

/** Лента треда по времени (сервер может прислать вперемешку после обрыва), дубли по id — последний. */
export function timeline(messages: readonly DMMessage[], threadId: string): DMMessage[] {
  const byId = new Map<string, DMMessage>()
  for (const m of messages) if (m.thread_id === threadId) byId.set(m.id, m)
  return [...byId.values()].sort((a, b) => a.sent_at - b.sent_at || a.id.localeCompare(b.id))
}

/** Разбить ленту на группы «одного автора подряд» (аватар — один раз на группу, как в мессенджерах). */
export function groupRuns(messages: readonly DMMessage[], gapMs = 5 * 60_000): DMMessage[][] {
  const runs: DMMessage[][] = []
  for (const m of messages) {
    const last = runs.at(-1)
    const prev = last?.at(-1)
    if (last && prev && prev.from === m.from && m.sent_at - prev.sent_at <= gapMs) last.push(m)
    else runs.push([m])
  }
  return runs
}
