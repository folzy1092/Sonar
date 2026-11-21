// Плеер: что играет, порядок, лайки, скорость, громкость, настроение Sonar Mix.
// Общий для ПК и iPhone: всё, что показывает текущий трек, помечено data-bind и обновляется здесь.
window.Sonar = window.Sonar || {}
;(function (S) {
  const D = S.data
  const H = S.h
  const F = Object.freeze

  const SPEEDS = F([
    F({ rate: 1, label: '1×' }),
    F({ rate: 0.85, label: 'Slowed' }),
    F({ rate: 1.2, label: 'Sped up' }),
  ])
  const PREV_RESTART_SEC = 3
  const DEFAULT_VOLUME = 0.72
  const TEXT_SWAP_MS = 140

  const indexOf = (id) => D.TRACKS.findIndex((t) => t.id === id)

  // Порядок воспроизведения: сначала «Далее в очереди», потом источник (плейлист, альбом…), иначе — всё подряд
  const order = (s) => {
    const ids = s.src ? (H.collection(s.src, s)?.tracks || []) : []
    return ids.includes(H.trackOf(s).id) ? ids : D.TRACKS.map((t) => t.id)
  }
  const step = (s, dir) => {
    if (dir > 0 && s.upnext.length) {
      return { index: indexOf(s.upnext[0]), upnext: F(s.upnext.slice(1)), pos: 0, playing: true }
    }
    const ids = order(s)
    const n = ids.length
    const i = ids.indexOf(H.trackOf(s).id)
    const j = s.shuffle && dir > 0 && n > 1 ? (i + 1 + Math.floor(Math.random() * (n - 1))) % n : (i + dir + n) % n
    return { index: indexOf(ids[j]), pos: 0, playing: true }
  }
  const ratioAt = (el, ev) => {
    const r = el.getBoundingClientRect()
    return Math.min(1, Math.max(0, (ev.clientX - r.left) / r.width))
  }
  const toggleIn = (list, id) => F(list.includes(id) ? list.filter((x) => x !== id) : [...list, id])

  // ── Действия ──────────────────────────────────────────
  const actions = {
    play: (s) => ({ playing: !s.playing }),
    next: (s) => step(s, 1),
    prev: (s) => (s.pos > PREV_RESTART_SEC ? { pos: 0 } : step(s, -1)),
    dislike: (s) => ({ ...step(s, 1), ...S.app.toast('Меньше такого в Sonar Mix', { index: s.index, pos: s.pos }) }),
    like: (s, el) => {
      const id = el.dataset.tid || H.trackOf(s).id
      return { liked: toggleIn(s.liked, id) }
    },
    speed: (s) => ({ speed: (s.speed + 1) % SPEEDS.length }),
    mood: (s, el) => (el.dataset.id === s.mood && s.src === null ? { playing: true } : { mood: el.dataset.id, src: null, ...step({ ...s, src: null, upnext: F([]) }, 1) }),
    track: (s, el) => {
      const index = indexOf(el.dataset.id)
      if (index < 0) return {}
      if (index === s.index) return { playing: !s.playing }
      const host = el.closest('[data-src]')
      return { index, pos: 0, playing: true, src: host && host.dataset.src ? host.dataset.src : s.src }
    },
    'play-coll': (s, el) => {
      const c = H.collection(el.dataset.to, s)
      if (!c || !c.tracks.length) return {}
      const shuffle = Boolean(el.dataset.shuffle)
      const id = shuffle ? c.tracks[Math.floor(Math.random() * c.tracks.length)] : c.tracks[0]
      return { index: indexOf(id), pos: 0, playing: true, src: el.dataset.to, shuffle: shuffle || s.shuffle, upnext: F([]) }
    },
    shuffle: (s) => ({ shuffle: !s.shuffle }),
    repeat: (s) => ({ repeat: !s.repeat }),
    seek: (s, el, ev) => ({ pos: ratioAt(el, ev) * H.trackOf(s).dur }),
    vol: (s, el, ev) => ({ volume: ratioAt(el, ev) }),
    mute: (s) => ({ volume: s.volume > 0 ? 0 : DEFAULT_VOLUME }),
    'play-next': (s, el) => ({ upnext: F([el.dataset.tid, ...s.upnext.filter((x) => x !== el.dataset.tid)]), menu: null, ...S.app.toast('Сыграет следующим') }),
    'add-queue': (s, el) => ({ upnext: F([...s.upnext, el.dataset.tid]), menu: null, ...S.app.toast('Добавлено в очередь') }),
    'drop-queue': (s, el) => ({ upnext: F(s.upnext.filter((_, i) => i !== Number(el.dataset.i))) }),
    'clear-queue': () => ({ upnext: F([]) }),
  }

  // ── Отрисовка ─────────────────────────────────────────
  const setTrackText = (t) => {
    H.setText('title', t.title)
    H.setText('artist', t.artist)
    H.bound('badge').forEach((el) => { el.innerHTML = S.badge(t.service) })
    H.bound('artist-link').forEach((el) => { el.dataset.to = t.aid ? `artist/${t.aid}` : ''; el.disabled = !t.aid })
  }

  const markSeg = (tb, val) =>
    document.querySelectorAll(`[data-tb="${tb}"]`).forEach((b) => b.classList.toggle('on', b.dataset.val === val))

  const renderCover = (prev, next) => {
    if (!H.changed(prev, next, ['index', 'coverOverride'])) return
    const t = H.trackOf(next)
    const color = next.coverOverride || t.color
    H.roots.forEach((r) => r.style.setProperty('--cover', color))
    const html = S.cover(color, t.pattern)
    const animate = Boolean(prev) && prev.index !== next.index
    H.bound('cover').forEach((el) => S.h.swapCover(el, html, animate || (Boolean(prev) && el.children.length > 0)))
    markSeg('cover', next.coverOverride || 'auto')
  }

  const renderTrack = (prev, next) => {
    if (!H.changed(prev, next, ['index'])) return
    const t = H.trackOf(next)
    H.roots.forEach((r) => r.style.setProperty('--bpm', t.bpm))
    H.setText('dur', S.fmt(t.dur))
    H.all('.trow').forEach((row) => row.classList.toggle('is-current', row.dataset.id === t.id))
    if (!prev) { setTrackText(t); return }
    const metas = H.bound('meta')
    metas.forEach((m) => m.classList.add('out'))
    setTimeout(() => {
      setTrackText(t)
      metas.forEach((m) => m.classList.remove('out'))
    }, TEXT_SWAP_MS)
  }

  const renderPlaying = (prev, next) => {
    if (!H.changed(prev, next, ['playing'])) return
    H.roots.forEach((r) => r.classList.toggle('is-playing', next.playing))
    H.bound('play').forEach((b) => b.setAttribute('aria-label', next.playing ? 'Пауза' : 'Слушать'))
    H.setText('play-label', next.playing ? 'Пауза' : 'Слушать')
  }

  // Сердце: у текущего трека (data-bind="like") и у строк с data-like="t5"
  const renderLike = (prev, next) => {
    if (!H.changed(prev, next, ['liked', 'index'])) return
    const id = H.trackOf(next).id
    const pop = (b, on, was) => {
      b.classList.toggle('on', on)
      b.setAttribute('aria-pressed', String(on))
      if (!on || was !== false) return
      b.classList.remove('pop')
      void b.offsetWidth
      b.classList.add('pop')
    }
    const sameTrack = prev && prev.index === next.index
    H.bound('like').forEach((b) => pop(b, next.liked.includes(id), sameTrack ? prev.liked.includes(id) : null))
    H.all('[data-like]').forEach((b) => {
      const tid = b.dataset.like
      pop(b, next.liked.includes(tid), prev ? prev.liked.includes(tid) : null)
    })
  }

  const renderProgress = (prev, next) => {
    if (!H.changed(prev, next, ['pos', 'index'])) return
    const t = H.trackOf(next)
    const p = Math.min(1, next.pos / t.dur)
    H.roots.forEach((r) => r.style.setProperty('--p', p.toFixed(4)))
    H.setText('cur', S.fmt(next.pos))
    H.setText('left', `−${S.fmt(t.dur - next.pos)}`)
  }

  const renderSpeed = (prev, next) => {
    if (!H.changed(prev, next, ['speed'])) return
    H.bound('speed').forEach((b) => {
      b.textContent = SPEEDS[next.speed].label
      b.classList.toggle('on', next.speed !== 0)
    })
  }

  const renderMood = (prev, next) => {
    if (!H.changed(prev, next, ['mood'])) return
    const m = D.MOODS.find((x) => x.id === next.mood)
    H.all('[data-act="mood"][data-chip]').forEach((c) => c.classList.toggle('on', c.dataset.id === next.mood))
    H.setText('mood-name', m.name)
    H.setText('mood-line', m.line)
  }

  const renderModes = (prev, next) => {
    if (!H.changed(prev, next, ['shuffle', 'repeat'])) return
    H.bound('shuffle').forEach((b) => b.classList.toggle('on', next.shuffle))
    H.bound('repeat').forEach((b) => b.classList.toggle('on', next.repeat))
  }

  const renderVolume = (prev, next) => {
    if (!H.changed(prev, next, ['volume'])) return
    H.roots.forEach((r) => r.style.setProperty('--v', next.volume.toFixed(3)))
    H.bound('mute').forEach((b) => { b.innerHTML = S.icon(next.volume === 0 ? 'volLow' : 'volHigh') ; b.classList.toggle('on', next.volume === 0) })
  }

  // «Играет из …» — подпись источника
  const sourceLabel = (s) => {
    if (!s.src) return `Sonar Mix · ${D.MOODS.find((m) => m.id === s.mood).name}`
    const c = H.collection(s.src, s)
    return c ? c.title : 'Sonar'
  }
  const renderSource = (prev, next) => {
    if (!H.changed(prev, next, ['src', 'mood'])) return
    H.setText('source', sourceLabel(next))
  }

  const content = (fn) => ({ fn, content: true })

  S.use({
    defaults: {
      index: 0, playing: true, pos: 0, speed: 0, mood: 'night', shuffle: false, repeat: false,
      volume: DEFAULT_VOLUME, coverOverride: null, src: null, upnext: F([]),
      liked: F(['t1', 't2', 't5', 't8', 't3', 't10', 't12', 't9']),
    },
    actions,
    renderers: [renderCover, renderTrack, renderPlaying, renderLike, renderProgress, renderSpeed, renderMood, renderModes, renderVolume, renderSource].map(content),
    hash: {
      cover: (v) => (D.SWATCHES.some((w) => w.color === v) ? { coverOverride: v } : {}),
      track: (v) => (D.TRACKS[Number(v)] ? { index: Number(v) } : {}),
      pos: (v) => (Number(v) >= 0 ? { pos: Number(v) } : {}),
      paused: () => ({ playing: false }),
    },
  })

  S.player = F({ SPEEDS, order, step, indexOf, sourceLabel, DEFAULT_VOLUME })
})(window.Sonar)
