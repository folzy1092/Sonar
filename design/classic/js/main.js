// Состояние прототипа и его отрисовка. Состояние не меняется на месте: каждое действие даёт новый
// замороженный объект, render(prev, next) правит только то, что поменялось.
window.Sonar = window.Sonar || {}
;(function (S) {
  const D = S.data
  const SPEEDS = Object.freeze([
    { rate: 1, label: '1×' },
    { rate: 0.85, label: 'Slowed' },
    { rate: 1.2, label: 'Sped up' },
  ])
  const TICK_MS = 250
  const COVER_FADE_MS = 480
  const TEXT_SWAP_MS = 140
  const PREV_RESTART_SEC = 3
  const DEFAULT_VOLUME = 0.72

  const stage = document.querySelector('.stage')
  const stageInner = document.querySelector('.stage-inner')
  const pc = document.getElementById('pc')
  const ph = document.getElementById('ph')
  const roots = [pc, ph]

  S.renderDesktop(pc)
  S.renderPhone(ph)

  // Начальный вид можно задать в адресе: #variant=calm&theme=light&view=pc&cover=%232740b8&track=3&player=0
  const HASH_RULES = Object.freeze({
    variant: (v) => (['vivid', 'calm'].includes(v) ? { variant: v } : {}),
    theme: (v) => (['dark', 'light'].includes(v) ? { theme: v } : {}),
    view: (v) => (['both', 'pc', 'phone'].includes(v) ? { view: v } : {}),
    cover: (v) => (D.SWATCHES.some((w) => w.color === v) ? { coverOverride: v } : {}),
    track: (v) => (D.TRACKS[Number(v)] ? { index: Number(v) } : {}),
    player: (v) => ({ phoneOpen: v !== '0' }),
  })
  const fromHash = () => [...new URLSearchParams(location.hash.slice(1))]
    .reduce((acc, [k, v]) => ({ ...acc, ...(HASH_RULES[k] ? HASH_RULES[k](v) : {}) }), {})

  let scale = 1
  let state = Object.freeze({
    variant: 'vivid', theme: 'dark', view: 'both',
    index: 0, playing: true, pos: 0, liked: Object.freeze(['t2', 't5']), speed: 0,
    mood: 'night', nav: 'home', tab: 'home', phoneOpen: true,
    coverOverride: null, shuffle: false, repeat: false, volume: DEFAULT_VOLUME,
    ...fromHash(),
  })

  // ── Помощники ─────────────────────────────────────────
  const all = (sel) => roots.flatMap((r) => [...r.querySelectorAll(sel)])
  const bound = (key) => all(`[data-bind="${key}"]`)
  const setText = (key, text) => bound(key).forEach((el) => { el.textContent = text })
  const trackOf = (s) => D.TRACKS[s.index]
  const coverColor = (s) => s.coverOverride || trackOf(s).color
  const changed = (prev, next, keys) => !prev || keys.some((k) => prev[k] !== next[k])

  const swapCover = (el, html, animate) => {
    const old = [...el.children]
    const layer = document.createElement('div')
    layer.className = animate ? 'cv-layer entering' : 'cv-layer'
    layer.innerHTML = html
    el.appendChild(layer)
    if (!animate) { old.forEach((n) => n.remove()); return }
    void layer.offsetWidth
    layer.classList.remove('entering')
    setTimeout(() => old.forEach((n) => n.remove()), COVER_FADE_MS)
  }

  const setTrackText = (t) => {
    setText('title', t.title)
    setText('artist', t.artist)
    bound('badge').forEach((el) => { el.innerHTML = S.badge(t.service) })
  }

  const markSeg = (tb, val) =>
    document.querySelectorAll(`[data-tb="${tb}"]`).forEach((b) => b.classList.toggle('on', b.dataset.val === val))

  // ── Отрисовка по частям ───────────────────────────────
  const renderLook = (prev, next) => {
    if (!changed(prev, next, ['variant', 'theme'])) return
    roots.forEach((r) => { r.dataset.variant = next.variant; r.dataset.theme = next.theme })
    document.body.dataset.theme = next.theme
    markSeg('variant', next.variant)
    markSeg('theme', next.theme)
    if (prev) requestAnimationFrame(() => placeNavIndicator(next, false))
  }

  const renderView = (prev, next) => {
    if (!changed(prev, next, ['view'])) return
    stage.dataset.view = next.view
    markSeg('view', next.view)
    fit()
  }

  const renderCover = (prev, next) => {
    if (!changed(prev, next, ['index', 'coverOverride'])) return
    const color = coverColor(next)
    roots.forEach((r) => r.style.setProperty('--cover', color))
    const html = S.cover(color, trackOf(next).pattern)
    bound('cover').forEach((el) => swapCover(el, html, Boolean(prev)))
    markSeg('cover', next.coverOverride || 'auto')
  }

  const renderTrack = (prev, next) => {
    if (!changed(prev, next, ['index'])) return
    const t = trackOf(next)
    roots.forEach((r) => r.style.setProperty('--bpm', t.bpm))
    setText('dur', S.fmt(t.dur))
    all('.trow').forEach((row) => row.classList.toggle('is-current', row.dataset.id === t.id))
    if (!prev) { setTrackText(t); return }
    const metas = bound('meta')
    metas.forEach((m) => m.classList.add('out'))
    setTimeout(() => {
      setTrackText(t)
      metas.forEach((m) => m.classList.remove('out'))
    }, TEXT_SWAP_MS)
  }

  const renderPlaying = (prev, next) => {
    if (!changed(prev, next, ['playing'])) return
    roots.forEach((r) => r.classList.toggle('is-playing', next.playing))
    bound('play').forEach((b) => b.setAttribute('aria-label', next.playing ? 'Пауза' : 'Слушать'))
    setText('play-label', next.playing ? 'Пауза' : 'Слушать')
  }

  const renderLike = (prev, next) => {
    if (!changed(prev, next, ['liked', 'index'])) return
    const id = trackOf(next).id
    const on = next.liked.includes(id)
    const justLiked = prev && prev.index === next.index && on && !prev.liked.includes(id)
    bound('like').forEach((b) => {
      b.classList.toggle('on', on)
      b.setAttribute('aria-pressed', String(on))
      if (!justLiked) return
      b.classList.remove('pop')
      void b.offsetWidth
      b.classList.add('pop')
    })
  }

  const renderProgress = (prev, next) => {
    if (!changed(prev, next, ['pos', 'index'])) return
    const t = trackOf(next)
    const p = Math.min(1, next.pos / t.dur)
    roots.forEach((r) => r.style.setProperty('--p', p.toFixed(4)))
    setText('cur', S.fmt(next.pos))
    setText('left', `−${S.fmt(t.dur - next.pos)}`)
  }

  const renderSpeed = (prev, next) => {
    if (!changed(prev, next, ['speed'])) return
    bound('speed').forEach((b) => {
      b.textContent = SPEEDS[next.speed].label
      b.classList.toggle('on', next.speed !== 0)
    })
  }

  const renderMood = (prev, next) => {
    if (!changed(prev, next, ['mood'])) return
    const m = D.MOODS.find((x) => x.id === next.mood)
    all('[data-act="mood"]').forEach((c) => c.classList.toggle('on', c.dataset.id === next.mood))
    setText('mood-name', m.name)
    setText('mood-line', m.line)
  }

  const renderModes = (prev, next) => {
    if (!changed(prev, next, ['shuffle', 'repeat'])) return
    bound('shuffle').forEach((b) => b.classList.toggle('on', next.shuffle))
    bound('repeat').forEach((b) => b.classList.toggle('on', next.repeat))
  }

  const renderVolume = (prev, next) => {
    if (!changed(prev, next, ['volume'])) return
    roots.forEach((r) => r.style.setProperty('--v', next.volume.toFixed(3)))
  }

  // Индикатор активного пункта левой панели — плывёт к нему
  const placeNavIndicator = (s, animate) => {
    const ind = pc.querySelector('.nav-ind')
    const item = pc.querySelector(`.nav .nav-item[data-id="${s.nav}"]`)
    ind.classList.toggle('no-anim', !animate)
    ind.classList.toggle('off', !item)
    if (item) {
      ind.style.setProperty('--y', `${item.offsetTop}px`)
      ind.style.height = `${item.offsetHeight}px`
    }
    if (!animate) requestAnimationFrame(() => ind.classList.remove('no-anim'))
  }

  const showPage = (root, attr, isHome, src) => {
    root.querySelector(`[${attr}="home"]`).hidden = !isHome
    root.querySelector(`[${attr}="empty"]`).hidden = isHome
    if (isHome || !src) return
    root.querySelector('[data-bind="empty-icon"]').innerHTML = S.icon(src.dataset.icon)
    root.querySelector('[data-bind="empty-title"]').textContent = src.dataset.label
  }

  const renderNav = (prev, next) => {
    if (!changed(prev, next, ['nav'])) return
    const src = pc.querySelector(`[data-act="nav"][data-id="${next.nav}"]`)
    pc.querySelectorAll('[data-act="nav"]').forEach((n) => n.classList.toggle('on', n.dataset.id === next.nav))
    placeNavIndicator(next, Boolean(prev))
    showPage(pc, 'data-page', next.nav === 'home', src)
    if (prev) pc.querySelector('.scroll').scrollTop = 0
  }

  const renderTab = (prev, next) => {
    if (!changed(prev, next, ['tab'])) return
    const src = ph.querySelector(`.ph-tab[data-id="${next.tab}"]`)
    ph.querySelectorAll('.ph-tab').forEach((t) => t.classList.toggle('on', t.dataset.id === next.tab))
    showPage(ph, 'data-ppage', next.tab === 'home', src)
    if (prev) ph.querySelector('.ph-screen').scrollTop = 0
  }

  const renderPhone = (prev, next) => {
    if (!changed(prev, next, ['phoneOpen'])) return
    S.phoneMorph(ph, next.phoneOpen, scale, Boolean(prev))
  }

  const RENDERERS = [
    renderLook, renderView, renderCover, renderTrack, renderPlaying, renderLike,
    renderProgress, renderSpeed, renderMood, renderModes, renderVolume, renderNav, renderTab, renderPhone,
  ]
  const render = (prev, next) => RENDERERS.forEach((r) => r(prev, next))

  const setState = (patch) => {
    const prev = state
    state = Object.freeze({ ...state, ...patch })
    render(prev, state)
  }

  // ── Действия ──────────────────────────────────────────
  const randomOther = (i) => {
    const n = D.TRACKS.length
    return (i + 1 + Math.floor(Math.random() * (n - 1))) % n
  }
  const step = (s, dir) => {
    const n = D.TRACKS.length
    const index = s.shuffle && dir > 0 ? randomOther(s.index) : (s.index + dir + n) % n
    return { index, pos: 0, playing: true }
  }
  const ratioAt = (el, ev) => {
    const r = el.getBoundingClientRect()
    return Math.min(1, Math.max(0, (ev.clientX - r.left) / r.width))
  }

  const ACTIONS = {
    play: (s) => ({ playing: !s.playing }),
    next: (s) => step(s, 1),
    prev: (s) => (s.pos > PREV_RESTART_SEC ? { pos: 0 } : step(s, -1)),
    dislike: (s) => step(s, 1),
    like: (s) => {
      const id = trackOf(s).id
      const liked = s.liked.includes(id) ? s.liked.filter((x) => x !== id) : [...s.liked, id]
      return { liked: Object.freeze(liked) }
    },
    speed: (s) => ({ speed: (s.speed + 1) % SPEEDS.length }),
    mood: (s, el) => (el.dataset.id === s.mood ? {} : { mood: el.dataset.id, ...step(s, 1) }),
    track: (s, el) => {
      const index = D.TRACKS.findIndex((t) => t.id === el.dataset.id)
      return index === s.index ? { playing: !s.playing } : { index, pos: 0, playing: true }
    },
    card: (s, el) => ({ index: Number(el.dataset.i) % D.TRACKS.length, pos: 0, playing: true }),
    nav: (s, el) => ({ nav: el.dataset.id }),
    tab: (s, el) => ({ tab: el.dataset.id }),
    'open-player': () => ({ phoneOpen: true }),
    'close-player': () => ({ phoneOpen: false }),
    shuffle: (s) => ({ shuffle: !s.shuffle }),
    repeat: (s) => ({ repeat: !s.repeat }),
    seek: (s, el, ev) => ({ pos: ratioAt(el, ev) * trackOf(s).dur }),
    vol: (s, el, ev) => ({ volume: ratioAt(el, ev) }),
    mute: (s) => ({ volume: s.volume > 0 ? 0 : DEFAULT_VOLUME }),
  }

  const onClick = (ev) => {
    const el = ev.target.closest('[data-act]')
    if (!el || el.disabled) return
    const action = ACTIONS[el.dataset.act]
    if (!action) return
    ev.stopPropagation()
    setState(action(state, el, ev))
  }
  roots.forEach((r) => r.addEventListener('click', onClick))

  // ── Ход времени ───────────────────────────────────────
  setInterval(() => {
    if (!state.playing) return
    const pos = state.pos + (TICK_MS / 1000) * SPEEDS[state.speed].rate
    if (pos < trackOf(state).dur) { setState({ pos }); return }
    setState(state.repeat ? { pos: 0 } : step(state, 1))
  }, TICK_MS)

  // ── Клавиши ───────────────────────────────────────────
  document.addEventListener('keydown', (ev) => {
    if (ev.target instanceof Element && ev.target.closest('input, textarea')) return
    const keys = {
      ' ': () => ACTIONS.play(state),
      ArrowRight: () => ACTIONS.next(state),
      ArrowLeft: () => ACTIONS.prev(state),
      Escape: () => ({ phoneOpen: false }),
    }
    const fn = keys[ev.key]
    if (!fn) return
    ev.preventDefault()
    setState(fn())
  })

  // ── Панель сравнения ──────────────────────────────────
  document.querySelector('.toolbar').addEventListener('click', (ev) => {
    const b = ev.target.closest('[data-tb]')
    if (!b) return
    const { tb, val } = b.dataset
    const patch = {
      variant: { variant: val },
      theme: { theme: val },
      view: { view: val },
      cover: { coverOverride: val === 'auto' ? null : val },
    }[tb]
    if (patch) setState(patch)
  })

  const swatches = document.querySelector('.sws')
  swatches.insertAdjacentHTML('beforeend', D.SWATCHES.map((w) =>
    `<button class="sw" data-tb="cover" data-val="${w.color}" title="${w.name}" style="background:${w.color}"></button>`).join(''))

  // ── Масштаб сцены под окно ────────────────────────────
  function fit() {
    const w = stageInner.offsetWidth
    const h = stageInner.offsetHeight
    scale = Math.min(1, stage.clientWidth / w, stage.clientHeight / h)
    stageInner.style.setProperty('--s', scale.toFixed(4))
  }
  window.addEventListener('resize', fit)

  render(null, state)
  document.fonts.ready.then(() => { fit(); placeNavIndicator(state, false) })
})(window.Sonar)
