// Ядро прототипа: реестр модулей и общие помощники.
// Каждый экран — отдельный модуль: он регистрирует своё начальное состояние, действия (клики по
// data-act), отрисовщики и клавиши через S.use(). main.js собирает всё в одно неизменяемое состояние.
window.Sonar = window.Sonar || {}
;(function (S) {
  const D = S.data
  const reg = { defaults: {}, actions: {}, renderers: [], inits: [], keys: [], pages: {}, overlays: {}, screens: {}, hash: {} }

  // renderer: { fn(prev, next), content } — content: true значит «перезапустить после вставки экрана»
  // pages — экраны ПК по адресу (home, artist/a2…), overlays — слои поверх окна ПК,
  // screens — вкладки и вложенные экраны iPhone. У экрана: render(s, arg), deps — ключи состояния,
  // от которых он перерисовывается целиком, empty(s, arg) — свой текст пустого состояния.
  // keys(ev, s) → patch | null — свои клавиши модуля (первый, кто вернул patch, побеждает).
  // hash — правила адреса страницы: { ключ: (строка) → patch }, чтобы открыть прототип сразу на нужном экране.
  S.use = ({ defaults = {}, actions = {}, renderers = [], init, keys, pages = {}, overlays = {}, screens = {}, hash = {} } = {}) => {
    reg.hash = { ...reg.hash, ...hash }
    reg.defaults = { ...reg.defaults, ...defaults }
    reg.actions = { ...reg.actions, ...actions }
    reg.pages = { ...reg.pages, ...pages }
    reg.overlays = { ...reg.overlays, ...overlays }
    reg.screens = { ...reg.screens, ...screens }
    reg.renderers = [...reg.renderers, ...renderers.map((r) => (typeof r === 'function' ? { fn: r } : r))]
    if (init) reg.inits = [...reg.inits, init]
    if (keys) reg.keys = [...reg.keys, keys]
  }
  S.reg = reg

  const pc = document.getElementById('pc')
  const ph = document.getElementById('ph')
  const roots = [pc, ph]

  const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ESC[c])
  const all = (sel, scope = roots) => scope.flatMap((r) => [...r.querySelectorAll(sel)])
  const bound = (key) => all(`[data-bind="${key}"]`)
  const setText = (key, text) => bound(key).forEach((el) => { el.textContent = text })
  const changed = (prev, next, keys) => !prev || keys.some((k) => prev[k] !== next[k])
  const byId = (list, id) => list.find((x) => x.id === id)
  const track = (id) => byId(D.TRACKS, id)
  const trackOf = (s) => D.TRACKS[s.index]
  const artist = (id) => byId(D.ARTISTS, id)
  const album = (id) => byId(D.ALBUMS, id)
  const playlist = (id) => byId(D.PLAYLISTS, id)
  const sum = (xs) => xs.reduce((a, b) => a + b, 0)

  // Русское множественное: tn(5, ['трек', 'трека', 'треков'])
  const tn = (n, [one, few, many]) => {
    const a = Math.abs(n) % 100
    const b = a % 10
    const word = a > 10 && a < 20 ? many : b === 1 ? one : b > 1 && b < 5 ? few : many
    return `${n.toLocaleString('ru-RU')} ${word}`
  }
  const dur = (sec) => {
    const m = Math.round(sec / 60)
    return m < 60 ? `${m} мин` : `${Math.floor(m / 60)} ч ${m % 60} мин`
  }

  // Коллекция по адресу: playlist/pl0, album/al1, artist/a2, liked
  const collection = (to, s) => {
    const [kind, id] = to.split('/')
    if (kind === 'liked') return { kind, title: 'Любимые', color: '#ff2d95', pattern: 'orbit', tracks: s ? s.liked : [] }
    if (kind === 'playlist') { const p = playlist(id); return p && { kind, ...p } }
    if (kind === 'album') {
      const a = album(id)
      return a && { kind, ...a, tracks: D.TRACKS.filter((t) => t.al === id).map((t) => t.id) }
    }
    if (kind === 'artist') {
      const a = artist(id)
      return a && { kind, ...a, title: a.name, tracks: D.TRACKS.filter((t) => t.aid === id).map((t) => t.id) }
    }
    return null
  }

  // Плавная смена обложки: новый слой проявляется поверх старого
  const COVER_FADE_MS = 480
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

  // Число «докручивается» до значения (статистика, цены)
  const COUNT_MS = 450
  // Меньше движения — системное или переключатель в настройках прототипа
  const reducedMotion = (el) => matchMedia('(prefers-reduced-motion: reduce)').matches || Boolean(el.closest('[data-motion="reduced"]'))
  const countUp = (scope) => scope.querySelectorAll('[data-count]').forEach((el) => {
    const to = Number(el.dataset.count)
    if (reducedMotion(el)) { el.textContent = to.toLocaleString('ru-RU'); return }
    const t0 = performance.now()
    const stepFrame = (now) => {
      const k = Math.min(1, (now - t0) / COUNT_MS)
      const eased = 1 - Math.pow(1 - k, 3)
      el.textContent = Math.round(to * eased).toLocaleString('ru-RU')
      if (k < 1) requestAnimationFrame(stepFrame)
    }
    requestAnimationFrame(stepFrame)
  })

  S.h = Object.freeze({
    pc, ph, roots, esc, all, bound, setText, changed, byId, track, trackOf, artist, album, playlist,
    sum, tn, dur, collection, swapCover, countUp, reducedMotion,
  })
})(window.Sonar)
