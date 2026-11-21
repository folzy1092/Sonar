// iPhone: оболочка — строка состояния, стек экранов, мини-плеер, таб-бар, нижний лист меню трека.
// Вкладки и свои экраны регистрирует screens.js (S.use({ screens })); страницы ПК (альбом, плейлист…)
// открываются здесь же как вложенные экраны со своей кнопкой «Назад».
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon } = S
  const P = S.parts
  const H = S.h
  const R = S.reg
  const F = Object.freeze
  const LEAVE_MS = 220
  const REDUCED_MS = 220

  const TABS = F([['home', 'home', 'Главная'], ['search', 'search', 'Поиск'], ['library', 'playlist', 'Медиатека'], ['profile', 'user', 'Профиль']])
  const TAB_IDS = F(TABS.map(([id]) => id))
  // Адреса ПК, которые на iPhone — это вкладки
  const TAB_ROUTES = F({ home: 'home', search: 'search', library: 'library' })
  // Только на ПК: широкие графики и карта
  const PC_ONLY = F(['map', 'stats'])

  const ph = H.ph
  const host = (name) => ph.querySelector(`[data-host="${name}"]`)

  // ── Разметка оболочки ─────────────────────────────────
  const status = () =>
    `<div class="ph-status" aria-hidden="true"><span>9:41</span><i class="island"></i>` +
    `<span class="st-icons">${icon('signal')}<i class="battery"><b></b></i></span></div>`

  const mini = () =>
    `<div class="ph-mini" data-act="open-player" role="button" tabindex="0" aria-label="Открыть плеер">` +
    `${P.coverSlot('ph-mini-cv')}` +
    `<div class="ph-mini-meta fade-swap" data-bind="meta"><b class="ellipsis" data-bind="title"></b><span class="ellipsis" data-bind="artist"></span></div>` +
    `${P.playBtn('icon-btn ph-mini-btn')}` +
    `<button class="icon-btn ph-mini-btn" data-act="next" aria-label="Дальше">${icon('next')}</button>` +
    `<span class="ph-mini-prog"><i></i></span></div>`

  const tabs = () => `<nav class="ph-tabs">${TABS.map(([id, ic, label]) =>
    `<button class="ph-tab" data-act="ph-tab" data-id="${id}">${icon(ic)}<span>${label}</span></button>`).join('')}</nav>`

  const shell = () =>
    status() +
    `<div class="ph-screens" data-host="screens"></div>` +
    mini() + tabs() +
    S.phonePlayer.html() +
    `<div class="ph-sheet-host" data-host="sheet"></div>` +
    `<div class="ph-toast" data-host="toast"></div>`

  // ── Экран по ключу: вкладка, свой экран или страница ПК ──
  const keyOf = (s) => (s.pstack.length ? s.pstack[s.pstack.length - 1] : `tab:${s.ptab}`)
  const screenOf = (key) => {
    const [name, ...rest] = key.split('/')
    return { name, arg: rest.join('/'), def: R.screens[name] || R.pages[name] }
  }
  const known = (key) => Boolean(screenOf(key).def)

  // Короткое имя экрана — подпись кнопки «Назад» у следующего
  const titleOf = (key, s) => {
    const { name, arg, def } = screenOf(key)
    const tab = TABS.find(([id]) => `tab:${id}` === name)
    if (tab) return tab[2]
    if (def && def.title) return typeof def.title === 'function' ? def.title(s, arg) : def.title
    const c = H.collection(key, s)
    return c ? c.title : ''
  }

  const bodyHtml = (def, s, arg) => {
    if (s.load === 'loading' && def.skeleton !== false) return P.skeleton(def.skeleton || 'page')
    if (s.load === 'empty' && def.empty) return P.empty(def.empty(s, arg))
    return def.render(s, arg)
  }
  const backBar = (s) => {
    const prevKey = s.pstack.length > 1 ? s.pstack[s.pstack.length - 2] : `tab:${s.ptab}`
    return `<div class="ph-nav"><button class="ph-back" data-act="ph-back">${icon('chevL')}<span>${H.esc(titleOf(prevKey, s))}</span></button></div>`
  }
  const screenHtml = (key, s) => {
    const { name, arg, def } = screenOf(key)
    const pushed = !name.startsWith('tab:')
    return (pushed ? backBar(s) : '') + `<div class="page still" data-page="${H.esc(name)}">${bodyHtml(def, s, arg)}</div>`
  }

  // ── Отрисовка стека ───────────────────────────────────
  let scrollMemo = F({})
  const motionOf = (prev, next) => {
    if (prev.ptab !== next.ptab) return 'in-tab'
    if (next.pstack.length > prev.pstack.length) return 'in-push'
    if (next.pstack.length < prev.pstack.length) return 'in-pop'
    return 'in-tab'
  }
  const afterMount = (el, key, s, animate) => {
    const { arg, def } = screenOf(key)
    S.app.hydrate()
    if (s.load !== 'normal') return
    if (animate) H.countUp(el)
    if (def.after) def.after(el, s, arg)
  }
  const mount = (prev, next, animate) => {
    const hostEl = host('screens')
    const key = keyOf(next)
    const old = hostEl.querySelector('.ph-screen')
    if (old && prev) scrollMemo = F({ ...scrollMemo, [keyOf(prev)]: old.scrollTop })
    const cls = animate ? motionOf(prev, next) : ''
    hostEl.innerHTML = `<div class="ph-screen ${cls}" data-screen="${H.esc(key)}">${screenHtml(key, next)}</div>`
    const el = hostEl.firstElementChild
    // Назад и перерисовка — на прежнее место прокрутки, вперёд и на вкладку — с начала
    const keep = !animate || cls === 'in-pop'
    el.scrollTop = keep ? scrollMemo[key] || 0 : 0
    if (animate && H.reducedMotion(el)) el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: REDUCED_MS, easing: 'linear' })
    afterMount(el, key, next, animate)
  }

  const renderScreens = (prev, next) => {
    const key = keyOf(next)
    if (!prev || keyOf(prev) !== key || prev.load !== next.load) { mount(prev, next, Boolean(prev)); return }
    const { arg, def } = screenOf(key)
    if (H.changed(prev, next, def.deps || [])) { mount(prev, next, false); return }
    const el = host('screens').querySelector('.ph-screen')
    if (def.update && next.load === 'normal') def.update(el, prev, next, arg)
  }

  const renderTabs = (prev, next) => {
    if (!H.changed(prev, next, ['ptab'])) return
    ph.querySelectorAll('.ph-tab').forEach((b) => {
      const on = b.dataset.id === next.ptab
      b.classList.toggle('on', on)
      b.setAttribute('aria-current', on ? 'page' : 'false')
    })
  }

  // ── Нижний лист: меню трека ───────────────────────────
  const sheetHtml = (s) =>
    `<div class="ph-sheet-wrap"><button class="ph-scrim" data-act="sheet-close" aria-label="Закрыть"></button>` +
    `<div class="ph-sheet" role="menu"><i class="grabber" aria-hidden="true"></i><div class="ph-sheet-body">${S.menuView.items(s.sheet, s)}</div></div></div>`
  const renderSheet = (prev, next) => {
    if (!H.changed(prev, next, ['sheet', 'liked'])) return
    const hostEl = host('sheet')
    const old = hostEl.querySelector('.ph-sheet-wrap:not(.leaving)')
    const same = old && next.sheet && prev && prev.sheet && prev.sheet.tid === next.sheet.tid
    if (same) { old.querySelector('.ph-sheet-body').innerHTML = S.menuView.items(next.sheet, next); return }
    if (old) { old.classList.add('leaving'); setTimeout(() => old.remove(), LEAVE_MS) }
    if (next.sheet) hostEl.insertAdjacentHTML('beforeend', sheetHtml(next))
  }

  // ── Действия ──────────────────────────────────────────
  const NO_LAYERS = F({ sheet: null, ann: null })
  const toTab = (id) => ({ ...NO_LAYERS, ptab: id, pstack: F([]) })
  const push = (s, to) => {
    if (!to) return NO_LAYERS
    const name = to.split('/')[0]
    if (TAB_ROUTES[name]) return toTab(TAB_ROUTES[name])
    if (PC_ONLY.includes(name)) return { ...NO_LAYERS, ...S.app.toast('Статистика и карта исполнителей — пока только на ПК') }
    if (!known(to) || keyOf(s) === to) return { ...NO_LAYERS, popen: false, ppane: null }
    return { ...NO_LAYERS, pstack: F([...s.pstack, to]), popen: false, ppane: null }
  }
  // Пункт меню делает своё и закрывает лист
  const closing = (name) => (s, el, ev) => ({ ...R.actions[name](s, el, ev), ...NO_LAYERS, menu: null })
  const SHEET_ACTS = F(['play-next', 'add-queue', 'add-pl', 'menu-like', 'menu-dislike', 'menu-alt', 'menu-toast'])
  const settingsSec = (el) => [el.dataset.sec, el.dataset.to].find((x) => x && S.settingsView.PANES[x]) || 'look'

  const actions = {
    'ph-tab': (s, el) => (el.dataset.id === s.ptab && !s.pstack.length ? NO_LAYERS : toTab(el.dataset.id)),
    'ph-back': (s) => ({ ...NO_LAYERS, pstack: F(s.pstack.slice(0, -1)) }),
    'ph:go': (s, el) => push(s, el.dataset.to),
    'ph:menu': (s, el) => ({ sheet: F({ tid: el.dataset.tid, sub: false }), ann: null }),
    'ph-cur-menu': (s) => ({ sheet: F({ tid: H.trackOf(s).id, sub: false }), ann: null }),
    'sheet-close': () => NO_LAYERS,
    'ph:menu-sub': (s) => ({ sheet: F({ ...s.sheet, sub: !s.sheet.sub }) }),
    'ph:menu-go': (s, el) => push(s, el.dataset.to),
    'ph:new-playlist': () => ({ ...NO_LAYERS, ...S.app.toast('Новый плейлист создан — трек уже в нём') }),
    ...Object.fromEntries(SHEET_ACTS.map((a) => [`ph:${a}`, closing(a)])),
    'ph:settings': (s, el) => push(s, `set/${settingsSec(el)}`),
    'ph:deep-lock': (s) => ({ ...push(s, 'set/deep'), ...S.app.toast('3D, 8D, 12D, 16D и реверб — в Sonar Deep') }),
    'ph:overlay': (s, el) => (el.dataset.id === 'full'
      ? { popen: true, ppane: 'lyrics' }
      : S.app.toast('Эквалайзер на iPhone — в плеере, в этом прототипе не нарисован')),
    'ph:scene': () => S.app.toast('У тебя последняя версия — 0.1.0 (528)'),
    'ph:add-folder': () => S.app.toast('На iPhone файлы добавляются через «Файлы» → «Поделиться» → Sonar'),
  }

  // Escape на iPhone: лист → панель плеера → плеер → назад по стеку
  const keys = (ev, s) => {
    if (ev.key !== 'Escape' || s.view === 'pc') return null
    if (s.sheet) return { sheet: null }
    if (s.ppane) return { ppane: null }
    if (s.popen) return { popen: false }
    if (s.pstack.length) return { pstack: F(s.pstack.slice(0, -1)) }
    return null
  }

  const stackFrom = (v) => F(String(v).split(',').filter(known))

  S.use({
    defaults: { ptab: 'home', pstack: F([]), sheet: null },
    actions,
    keys,
    init: () => { ph.innerHTML = shell() },
    renderers: [renderScreens, renderTabs, renderSheet],
    hash: {
      ptab: (v) => (TAB_IDS.includes(v) ? { ptab: v } : {}),
      psub: (v) => ({ pstack: stackFrom(v) }),
      sheet: (v) => (H.track(v) ? { sheet: F({ tid: v, sub: false }) } : {}),
    },
  })
  S.phoneShell = F({ host, keyOf, titleOf })
})(window.Sonar)
