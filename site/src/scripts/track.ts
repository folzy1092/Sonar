// Живая часть /t/#…: разбор хэша, шапка, кнопки сервисов, текст lrclib, плеер по «Слушать».
// Встройки YouTube и SoundCloud ведём их собственным протоколом postMessage — без их JS API на странице.
import { decodeShare, type ShareData, type SharePlayer } from '../lib/share-link'
import {
  appLink,
  bestHit,
  coverUrl,
  embedUrl,
  formatTime,
  lineAt,
  lyricsPairs,
  parseLrc,
  serviceLinks,
  type LrcLine,
  type LrclibHit,
} from '../lib/track-page'

interface Strings {
  lang: string
  play: string
  pause: string
  loading: string
  via: Record<SharePlayer, string>
  noPlayer: string
  embedError: string
  lyricsLoading: string
  lyricsNone: string
  lyricsPlain: string
  lyricsError: string
  direct: string
  search: string
  by: string
  names: Record<string, string>
}

const LRCLIB = 'https://lrclib.net/api'
const LYRICS_TIMEOUT_MS = 8000
const YT_ORIGIN = 'https://www.youtube-nocookie.com'
const SC_ORIGIN = 'https://w.soundcloud.com'

const $ = <T extends Element = HTMLElement>(root: ParentNode, sel: string) => root.querySelector<T>(sel)

// ——— плеер ———

interface Player {
  play(): void
  pause(): void
  seek(sec: number): void
}

interface Clock {
  /** Позиция из плеера и когда она пришла — между сообщениями дотягиваем сами, чтобы караоке шло плавно. */
  pos: number
  at: number
  playing: boolean
  duration: number
}

const now = (c: Clock) => (c.playing ? c.pos + (performance.now() - c.at) / 1000 : c.pos)

function youtube(frame: HTMLIFrameElement, clock: Clock, onChange: () => void, onError: () => void): Player {
  const send = (msg: object) => frame.contentWindow?.postMessage(JSON.stringify({ ...msg, id: 1, channel: 'widget' }), YT_ORIGIN)
  const cmd = (func: string, args: unknown[] = []) => send({ event: 'command', func, args })
  let ready = false
  // как www-widgetapi: «слушаю» — пока плеер не ответит
  const hello = window.setInterval(() => send({ event: 'listening' }), 250)
  frame.addEventListener('load', () => send({ event: 'listening' }))
  window.addEventListener('message', (e) => {
    if (e.origin !== YT_ORIGIN || e.source !== frame.contentWindow || typeof e.data !== 'string') return
    let m: { event?: string; info?: Record<string, unknown> | number }
    try {
      m = JSON.parse(e.data)
    } catch {
      return
    }
    // 101 / 150 — владелец запретил встраивание, 100 — ролика нет
    if (m.event === 'onError') {
      window.clearInterval(hello)
      return onError()
    }
    if (!ready && (m.event === 'onReady' || m.event === 'initialDelivery' || m.event === 'infoDelivery')) {
      ready = true
      window.clearInterval(hello)
    }
    const info = typeof m.info === 'object' && m.info ? m.info : {}
    if (typeof info.currentTime === 'number') {
      clock.pos = info.currentTime
      clock.at = performance.now()
    }
    if (typeof info.duration === 'number' && info.duration > 0) clock.duration = info.duration
    const state = m.event === 'onStateChange' ? m.info : info.playerState
    if (typeof state === 'number') {
      // 1 — играет, 3 — буферизует (считаем «играет»: время продолжит идти), остальное — стоит
      const playing = state === 1 || state === 3
      if (playing !== clock.playing) {
        clock.pos = now(clock)
        clock.at = performance.now()
        clock.playing = playing
      }
    }
    onChange()
  })
  return { play: () => cmd('playVideo'), pause: () => cmd('pauseVideo'), seek: (s) => cmd('seekTo', [s, true]) }
}

function soundcloud(frame: HTMLIFrameElement, clock: Clock, onChange: () => void, onError: () => void): Player {
  const send = (method: string, value?: unknown) =>
    frame.contentWindow?.postMessage(JSON.stringify(value === undefined ? { method } : { method, value }), SC_ORIGIN)
  window.addEventListener('message', (e) => {
    if (e.origin !== SC_ORIGIN || e.source !== frame.contentWindow) return
    let m: { method?: string; value?: unknown }
    try {
      m = typeof e.data === 'string' ? JSON.parse(e.data) : e.data
    } catch {
      return
    }
    const v = m.value as { currentPosition?: number } | number | null | undefined
    switch (m.method) {
      case 'error':
        return onError()
      case 'ready':
        for (const ev of ['playProgress', 'play', 'pause', 'finish', 'seek']) send('addEventListener', ev)
        send('getDuration')
        break
      case 'getDuration':
        if (typeof v === 'number' && v > 0) clock.duration = v / 1000
        break
      case 'play':
      case 'pause':
      case 'finish':
        clock.pos = now(clock)
        clock.at = performance.now()
        clock.playing = m.method === 'play'
        if (m.method === 'play') send('getDuration')
        break
    }
    if (v && typeof v === 'object' && typeof v.currentPosition === 'number') {
      clock.pos = v.currentPosition / 1000
      clock.at = performance.now()
      if (m.method === 'playProgress') clock.playing = true
    }
    onChange()
  })
  return { play: () => send('play'), pause: () => send('pause'), seek: (s) => send('seekTo', Math.round(s * 1000)) }
}

// ——— текст ———

type Lyrics = { kind: 'synced'; lines: LrcLine[] } | { kind: 'plain'; text: string } | { kind: 'none' }

async function getJson<T>(url: string, signal: AbortSignal): Promise<T | null> {
  const r = await fetch(url, { signal, credentials: 'omit', referrerPolicy: 'no-referrer' })
  if (r.status === 404) return null
  if (!r.ok) throw new Error(`lrclib ${r.status}`)
  return (await r.json()) as T
}

function toLyrics(hit: LrclibHit | null): Lyrics | null {
  if (!hit || hit.instrumental) return null
  if (hit.syncedLyrics) {
    const lines = parseLrc(hit.syncedLyrics)
    if (lines.length) return { kind: 'synced', lines }
  }
  if (hit.plainLyrics?.trim()) return { kind: 'plain', text: hit.plainLyrics.trim() }
  return null
}

/** lrclib: точный `/api/get` по каждой паре, потом `/api/search` — лучший по длительности. */
async function findLyrics(d: ShareData): Promise<Lyrics> {
  const ctrl = new AbortController()
  const timer = window.setTimeout(() => ctrl.abort(), LYRICS_TIMEOUT_MS)
  try {
    const pairs = lyricsPairs(d)
    for (const [artist, title] of pairs) {
      const p = new URLSearchParams({ artist_name: artist, track_name: title })
      if (d.d) p.set('duration', String(d.d))
      const got = toLyrics(await getJson<LrclibHit>(`${LRCLIB}/get?${p}`, ctrl.signal))
      if (got) return got
    }
    for (const [artist, title] of pairs) {
      const p = new URLSearchParams({ track_name: title, artist_name: artist })
      const hits = (await getJson<LrclibHit[]>(`${LRCLIB}/search?${p}`, ctrl.signal)) ?? []
      const got = toLyrics(bestHit(hits, d.d))
      if (got) return got
    }
    return { kind: 'none' }
  } finally {
    window.clearTimeout(timer)
  }
}

// ——— страница ———

export function initTrackPage(): void {
  const root = $(document, '[data-track]')
  const raw = root && $(root, 'script[data-track-strings]')?.textContent
  if (!root || !raw) return
  const s = JSON.parse(raw) as Strings
  const data = decodeShare(location.hash)
  if (!data) {
    $(root, '[data-bad]')!.hidden = false
    return
  }
  $(root, '[data-body]')!.hidden = false
  document.title = `${data.a ? `${data.a} — ` : ''}${data.t} · Sonar`

  // шапка
  $(root, '[data-title]')!.textContent = data.t
  $(root, '[data-artist]')!.textContent = data.a
  $(root, '[data-dur]')!.textContent = data.d ? formatTime(data.d) : ''
  const cover = $<HTMLImageElement>(root, '[data-cover]')!
  const src = coverUrl(data)
  if (src) {
    cover.addEventListener('load', () => {
      cover.classList.add('is-loaded')
      $(root, '.cover__ph')?.remove()
    })
    cover.addEventListener('error', () => (cover.hidden = true))
    cover.hidden = false
    cover.src = src
    // та же обложка — размытым фоном сверху
    const back = $<HTMLImageElement>(document, '[data-backdrop]')
    if (back) {
      back.addEventListener('load', () => back.classList.add('is-loaded'))
      back.hidden = false
      back.src = src
    }
  }

  // кто поделился (если вошёл в аккаунт); аватара до сервера нет — первая буква ника
  if (data.by) {
    $(root, '[data-eyebrow]')!.hidden = true
    $(root, '[data-by-av]')!.textContent = data.by[0]
    $(root, '[data-by-text]')!.textContent = s.by.replace('{nick}', `@${data.by}`)
    $(root, '[data-by]')!.hidden = false
  }

  // где послушать: найденные — первыми
  const list = $(root, '[data-links]')!
  for (const link of serviceLinks(data)) {
    const li = $(list, `[data-service="${link.service}"]`)
    if (!li) continue
    const a = $<HTMLAnchorElement>(li, 'a')!
    a.href = link.href
    a.setAttribute('aria-label', `${s.names[link.service]} — ${link.direct ? s.direct : s.search}`)
    $(li, '[data-kind]')!.textContent = link.direct ? s.direct : s.search
    li.classList.toggle('is-direct', link.direct)
    list.append(li)
  }

  // «Открыть в Sonar» — только где схема sonar:// есть (iPhone); на ПК она пока не зарегистрирована
  const open = $<HTMLAnchorElement>(root, '[data-open]')!
  const app = appLink(data)
  const ios = /iPhone|iPad|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
  if (app && ios) {
    open.href = app
    open.hidden = false
    // Sonar стоит — сразу откроется в нём. Один раз за вкладку: «назад» из приложения не зациклит.
    // Не стоит — Safari покажет «адрес недействителен», страница остаётся как есть.
    try {
      if (!sessionStorage.getItem('sonar-open')) {
        sessionStorage.setItem('sonar-open', '1')
        window.setTimeout(() => {
          if (document.visibilityState === 'visible') location.href = app
        }, 400)
      }
    } catch {
      /* хранилище закрыто — без автоперехода, кнопка есть */
    }
  }

  // текст
  const state = $(root, '[data-lyrics-state]')!
  const linesEl = $<HTMLOListElement>(root, '[data-lines]')!
  let lines: LrcLine[] = []
  let current = -2
  let player: Player | null = null
  const clock: Clock = { pos: 0, at: 0, playing: false, duration: data.d ?? 0 }
  state.textContent = s.lyricsLoading
  findLyrics(data)
    .then((ly) => {
      if (ly.kind === 'synced') {
        lines = ly.lines
        state.textContent = ''
        linesEl.replaceChildren(
          ...lines.map((l, i) => {
            const li = document.createElement('li')
            li.textContent = l.text || '♪'
            if (!l.text) li.classList.add('is-gap')
            li.dataset.i = String(i)
            return li
          }),
        )
        linesEl.hidden = false
        linesEl.classList.toggle('is-live', !!player)
      } else if (ly.kind === 'plain') {
        state.textContent = s.lyricsPlain
        const plain = $(root, '[data-plain]')!
        plain.textContent = ly.text
        plain.hidden = false
      } else state.textContent = s.lyricsNone
    })
    .catch(() => (state.textContent = s.lyricsError))

  linesEl.addEventListener('click', (e) => {
    const li = (e.target as HTMLElement).closest<HTMLElement>('li[data-i]')
    if (!li || !player) return
    const at = lines[Number(li.dataset.i)]?.at
    if (at === undefined) return
    player.seek(at)
    clock.pos = at
    clock.at = performance.now()
    player.play()
    render()
  })

  // плеер
  const listen = $<HTMLButtonElement>(root, '[data-listen]')!
  const listenLabel = $(listen, '[data-listen-label]')!
  // встройки нет или сервис запретил — «Слушать» ведёт к кнопкам сервисов
  let noEmbed = !data.play
  const toServices = () => $(root, '[data-where]')!.scrollIntoView({ behavior: 'smooth', block: 'start' })
  const live = $(root, '[data-live]')!
  const toggle = $<HTMLButtonElement>(root, '[data-toggle]')!
  const seek = $<HTMLInputElement>(root, '[data-seek]')!
  const nowEl = $(root, '[data-now]')!
  const totalEl = $(root, '[data-total]')!
  const frameBox = $(root, '[data-frame]')!
  let dragging = false

  if (!data.play) {
    $(root, '[data-start]')!.hidden = true
    const note = $(root, '[data-noplayer]')!
    note.textContent = s.noPlayer
    note.hidden = false
  }

  function scrollTo(i: number) {
    const li = linesEl.children[i] as HTMLElement | undefined
    if (!li) return
    linesEl.scrollTo({ top: li.offsetTop - linesEl.clientHeight / 2 + li.clientHeight / 2 })
  }

  function render() {
    const t = now(clock)
    if (!dragging) seek.value = String(t)
    seek.max = String(clock.duration || 0)
    nowEl.textContent = formatTime(t)
    totalEl.textContent = formatTime(clock.duration)
    toggle.classList.toggle('is-playing', clock.playing)
    toggle.setAttribute('aria-label', clock.playing ? s.pause : s.play)
    if (player) {
      listen.classList.toggle('is-playing', clock.playing)
      listenLabel.textContent = clock.playing ? s.pause : s.play
    }
    if (!lines.length) return
    const i = lineAt(lines, t)
    if (i === current) return
    for (const [j, li] of Array.from(linesEl.children).entries()) {
      li.classList.toggle('is-now', j === i)
      li.classList.toggle('is-past', j < i)
    }
    current = i
    if (i >= 0) scrollTo(i)
  }

  function frame() {
    if (clock.playing) render()
    requestAnimationFrame(frame)
  }

  listen.addEventListener('click', () => {
    if (player) return clock.playing ? player.pause() : player.play()
    const kind = data.play
    const url = embedUrl(data, location.origin)
    if (noEmbed || !kind || !url) return toServices()
    listen.disabled = true
    listenLabel.textContent = s.loading
    $(root, '[data-player]')!.scrollIntoView({ behavior: 'smooth', block: 'nearest' })
    const iframe = document.createElement('iframe')
    iframe.allow = 'autoplay; encrypted-media'
    iframe.title = s.via[kind]
    iframe.referrerPolicy = 'strict-origin-when-cross-origin'
    frameBox.dataset.kind = kind
    frameBox.replaceChildren(iframe)
    player = (kind === 'yt' ? youtube : soundcloud)(iframe, clock, () => {
      if (!live.hidden) return render()
      $(root, '[data-start]')!.hidden = true
      listen.disabled = false
      live.hidden = false
      linesEl.classList.add('is-live')
      render()
    }, () => {
      // сервис не дал играть на сайте — честно говорим и прячем плеер, кнопки сервисов остаются
      player = null
      noEmbed = true
      listen.disabled = false
      listen.classList.remove('is-playing')
      listenLabel.textContent = s.play
      frameBox.replaceChildren()
      frameBox.hidden = true
      live.hidden = true
      $(root, '[data-start]')!.hidden = true
      $(root, '[data-via]')!.hidden = true
      linesEl.classList.remove('is-live')
      const note = $(root, '[data-noplayer]')!
      note.textContent = s.embedError
      note.hidden = false
    })
    iframe.src = url
    frameBox.hidden = false
    const via = $(root, '[data-via]')!
    via.textContent = s.via[kind]
    via.hidden = false
    requestAnimationFrame(frame)
  })

  toggle.addEventListener('click', () => {
    if (!player) return
    if (clock.playing) player.pause()
    else player.play()
  })
  seek.addEventListener('input', () => {
    dragging = true
    nowEl.textContent = formatTime(Number(seek.value))
  })
  seek.addEventListener('change', () => {
    dragging = false
    const at = Number(seek.value)
    player?.seek(at)
    clock.pos = at
    clock.at = performance.now()
    render()
  })

  // ссылку поменяли прямо на странице (вставили другую) — проще перечитать
  window.addEventListener('hashchange', () => location.reload())
}
