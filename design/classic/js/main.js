// Движок прототипа: одно неизменяемое состояние, адрес страницы, клики, клавиши, ход времени, панель сверху.
// Экраны и плеер регистрируются в core.js (S.use) — здесь только склейка.
window.Sonar = window.Sonar || {}
;(function (S) {
  const D = S.data
  const H = S.h
  const R = S.reg
  const F = Object.freeze
  const TICK_MS = 250
  const TOAST_MS = 3200
  const TOAST_LEAVE_MS = 220
  const MOUSE_BACK = 3
  const MOUSE_FWD = 4
  const WIDTHS = F([960, 1280, 1440, 1920, 2560])

  const stage = document.querySelector('.stage')
  const stageInner = document.querySelector('.stage-inner')
  const { pc, ph, roots } = H

  // ── Начальное состояние и адрес ───────────────────────
  // Пример: #route=artist/a2&overlay=full&theme=light&cover=%23ff2d95&width=1920&load=empty
  const BASE = F({
    theme: 'dark', view: 'both', width: 1440, load: 'normal', motion: 'full',
    route: 'home', hist: F(['home']), hi: 0,
    overlay: null, drawer: null, menu: null, toast: null, ann: null,
  })
  const routeOk = (r) => Boolean(R.pages[String(r).split('/')[0]])
  const HASH_RULES = {
    theme: (v) => (['dark', 'light'].includes(v) ? { theme: v } : {}),
    view: (v) => (['both', 'pc', 'phone'].includes(v) ? { view: v } : {}),
    route: (v) => (routeOk(v) ? { route: v, hist: F(['home', v]), hi: 1 } : {}),
    overlay: (v) => (R.overlays[v] ? { overlay: v } : {}),
    drawer: (v) => (v === 'queue' ? { drawer: v } : {}),
    load: (v) => (['normal', 'loading', 'empty'].includes(v) ? { load: v } : {}),
    width: (v) => (WIDTHS.includes(Number(v)) ? { width: Number(v) } : {}),
    motion: (v) => (['full', 'reduced'].includes(v) ? { motion: v } : {}),
  }
  const fromHash = () => {
    const rules = { ...HASH_RULES, ...R.hash }
    return [...new URLSearchParams(location.hash.slice(1))]
      .reduce((acc, [k, v]) => ({ ...acc, ...(rules[k] ? rules[k](v, acc) : {}) }), {})
  }

  let scale = 1
  let state = F({ ...R.defaults, ...BASE, ...fromHash() })
  let lastTick = performance.now()
  let toastTimer = 0

  // ── Отрисовка ─────────────────────────────────────────
  const markSeg = (tb, val) =>
    document.querySelectorAll(`[data-tb="${tb}"]`).forEach((b) => b.classList.toggle('on', b.dataset.val === String(val)))

  const renderLook = (prev, next) => {
    if (!H.changed(prev, next, ['theme', 'motion'])) return
    roots.forEach((r) => { r.dataset.theme = next.theme; r.dataset.motion = next.motion })
    document.body.dataset.theme = next.theme
    markSeg('theme', next.theme)
    markSeg('motion', next.motion)
  }

  const renderView = (prev, next) => {
    if (!H.changed(prev, next, ['view', 'width', 'load'])) return
    stage.dataset.view = next.view
    markSeg('view', next.view)
    markSeg('width', next.width)
    markSeg('load', next.load)
  }

  const toastHtml = (t) =>
    `<div class="toast" role="status"><span>${H.esc(t.text)}</span>` +
    (t.undo ? `<button class="toast-undo" data-act="toast-undo">Отменить</button>` : '') + `</div>`

  const renderToast = (prev, next) => {
    if (!H.changed(prev, next, ['toast'])) return
    H.all('[data-host="toast"]').forEach((host) => {
      host.querySelectorAll('.toast').forEach((old) => { old.classList.add('leaving'); setTimeout(() => old.remove(), TOAST_LEAVE_MS) })
      if (next.toast) host.insertAdjacentHTML('beforeend', toastHtml(next.toast))
    })
    clearTimeout(toastTimer)
    if (!next.toast) return
    const id = next.toast.id
    toastTimer = setTimeout(() => { if (state.toast && state.toast.id === id) setState({ toast: null }) }, TOAST_MS)
  }

  const ENGINE_RENDERERS = [renderLook, renderView, renderToast].map((fn) => ({ fn }))
  const render = (prev, next) => {
    ;[...ENGINE_RENDERERS, ...R.renderers].forEach((r) => r.fn(prev, next))
    if (H.changed(prev, next, ['view', 'width'])) fit()
  }

  function setState(patch) {
    if (!patch || !Object.keys(patch).length) return
    const prev = state
    state = F({ ...state, ...patch })
    render(prev, state)
  }

  // ── Действия движка ───────────────────────────────────
  const CLOSE_LAYERS = F({ overlay: null, menu: null, ann: null })
  const go = (s, to) => {
    if (!to || !routeOk(to)) return {}
    if (to === s.route) return CLOSE_LAYERS
    return { ...CLOSE_LAYERS, route: to, hist: F([...s.hist.slice(0, s.hi + 1), to]), hi: s.hi + 1 }
  }
  const moveHist = (s, dir) => {
    const hi = s.hi + dir
    return hi < 0 || hi >= s.hist.length ? {} : { ...CLOSE_LAYERS, route: s.hist[hi], hi }
  }
  const parseVal = (el) => {
    const { val, type } = el.dataset
    if (type === 'num') return Number(val)
    if (type === 'null' || val === undefined) return null
    return val
  }

  let toastSeq = 0
  const ACTIONS = {
    go: (s, el) => go(s, el.dataset.to),
    back: (s) => moveHist(s, -1),
    fwd: (s) => moveHist(s, 1),
    overlay: (s, el) => ({ overlay: el.dataset.id, menu: null, ann: null }),
    'close-overlay': () => ({ overlay: null }),
    drawer: (s, el) => ({ drawer: s.drawer === el.dataset.id ? null : el.dataset.id }),
    set: (s, el) => ({ [el.dataset.key]: parseVal(el) }),
    toggle: (s, el) => ({ [el.dataset.key]: !s[el.dataset.key] }),
    'toast-undo': (s) => ({ ...(s.toast && s.toast.undo), toast: null }),
    noop: () => ({}),
  }

  const actionFor = (el) => {
    const act = el.dataset.act
    const inPhone = ph.contains(el)
    return (inPhone && R.actions[`ph:${act}`]) || R.actions[act] || ACTIONS[act]
  }

  // Всплывашки закрываются только кликом: открытое меню съедает клик снаружи, пояснение — нет
  const onClick = (ev) => {
    if (!(ev.target instanceof Element)) return
    const s = state
    if (s.menu && !ev.target.closest('.menu')) { ev.stopPropagation(); setState({ menu: null }); return }
    const base = s.ann && !ev.target.closest('.ann, [data-act="ann"]') ? { ann: null } : {}
    const el = ev.target.closest('[data-act]')
    const fn = el && !el.disabled && !el.closest('[inert]') ? actionFor(el) : null
    if (!fn) { setState(base); return }
    ev.stopPropagation()
    setState({ ...base, ...fn(s, el, ev) })
  }

  const onContext = (ev) => {
    const el = ev.target instanceof Element && ev.target.closest('[data-tid]')
    if (!el || !R.actions.menu) return
    ev.preventDefault()
    setState(R.actions.menu(state, el, ev))
  }

  const onInput = (ev) => {
    const el = ev.target instanceof Element && ev.target.closest('[data-input]')
    const fn = el && R.actions[`input:${el.dataset.input}`]
    if (fn) setState(fn(state, el, ev))
  }

  roots.forEach((r) => {
    r.addEventListener('click', onClick)
    r.addEventListener('input', onInput)
  })
  pc.addEventListener('contextmenu', onContext)
  pc.addEventListener('mouseup', (ev) => {
    if (ev.button === MOUSE_BACK) setState(moveHist(state, -1))
    if (ev.button === MOUSE_FWD) setState(moveHist(state, 1))
  })

  // ── Клавиши ───────────────────────────────────────────
  const escPatch = (s) => (s.menu ? { menu: null } : s.ann ? { ann: null } : s.overlay ? { overlay: null } : s.drawer ? { drawer: null } : null)
  const PLAYER_KEYS = {
    ' ': (s) => R.actions.play(s),
    ArrowRight: (s) => R.actions.next(s),
    ArrowLeft: (s) => R.actions.prev(s),
  }
  document.addEventListener('keydown', (ev) => {
    const typing = ev.target instanceof Element && ev.target.closest('input, textarea')
    if (ev.key === 'Escape') {
      const p = escPatch(state)
      if (p) { ev.preventDefault(); setState(p); return }
    }
    for (const k of R.keys) {
      const p = k(ev, state)
      if (p) { ev.preventDefault(); setState(p); return }
    }
    const fn = !typing && !ev.ctrlKey && !ev.metaKey && PLAYER_KEYS[ev.key]
    if (!fn) return
    ev.preventDefault()
    setState(fn(state))
  })

  // ── Ход времени ───────────────────────────────────────
  const rate = () => S.player.SPEEDS[state.speed].rate
  setInterval(() => {
    lastTick = performance.now()
    if (!state.playing) return
    const pos = state.pos + (TICK_MS / 1000) * rate()
    if (pos < H.trackOf(state).dur) { setState({ pos }); return }
    setState(state.repeat ? { pos: 0 } : S.player.step(state, 1))
  }, TICK_MS)

  // ── Панель сверху ─────────────────────────────────────
  const TOOLBAR = {
    theme: (v) => ({ theme: v }),
    view: (v) => ({ view: v }),
    cover: (v) => ({ coverOverride: v === 'auto' ? null : v }),
    width: (v) => ({ width: Number(v), view: state.view === 'phone' ? 'both' : state.view }),
    load: (v) => ({ load: v }),
    motion: (v) => ({ motion: v }),
    scene: (v, b) => (R.actions.scene ? R.actions.scene(state, b) : {}),
  }
  document.querySelector('.toolbar').addEventListener('click', (ev) => {
    const b = ev.target instanceof Element && ev.target.closest('[data-tb]')
    const fn = b && TOOLBAR[b.dataset.tb]
    if (fn) setState(fn(b.dataset.val, b))
  })
  document.querySelector('.sws').insertAdjacentHTML('beforeend', D.SWATCHES.map((w) =>
    `<button class="sw" data-tb="cover" data-val="${w.color}" title="${w.name}" style="background:${w.color}"></button>`).join(''))

  // ── Масштаб сцены под окно ────────────────────────────
  const fit = () => {
    const w = stageInner.offsetWidth
    const h = stageInner.offsetHeight
    scale = Math.min(1, stage.clientWidth / w, stage.clientHeight / h)
    stageInner.style.setProperty('--s', scale.toFixed(4))
  }
  window.addEventListener('resize', fit)

  // ── Наружу ────────────────────────────────────────────
  S.app = F({
    get state() { return state },
    get scale() { return scale },
    set: setState,
    fit,
    // Перезапустить отрисовщики «по содержимому» после вставки нового экрана
    hydrate: () => R.renderers.filter((r) => r.content).forEach((r) => r.fn(null, state)),
    toast: (text, undo = null) => ({ toast: F({ id: ++toastSeq, text, undo }) }),
    // Позиция между тиками — для плавного караоке
    posNow: () => (state.playing ? Math.min(H.trackOf(state).dur, state.pos + ((performance.now() - lastTick) / 1000) * rate()) : state.pos),
    go: (to) => setState(go(state, to)),
  })

  R.inits.forEach((init) => init())
  render(null, state)
  document.fonts.ready.then(() => { fit(); setState({ fontsReady: true }) })
})(window.Sonar)
