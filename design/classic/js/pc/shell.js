// ПК: оболочка окна без рамки — левая панель, заголовок, тело (страница + выдвижная очередь),
// нижняя панель плеера и хосты слоёв (overlay, меню, тост, сцены). Страницы и слои — в соседних модулях.
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon, cover, logo } = S
  const P = S.parts
  const D = S.data
  const H = S.h
  const R = S.reg
  const LEAVE_MS = 220
  const NARROW_W = 1100
  const PC_H = 900

  const NAV_TOP = [['home', 'home', 'Главная'], ['mix', 'mix', 'Sonar Mix']]
  const NAV_LIB = [['liked', 'heart', 'Любимые'], ['playlists', 'playlist', 'Плейлисты'], ['artists', 'artist', 'Исполнители'], ['albums', 'album', 'Альбомы'], ['files', 'folder', 'Файлы']]
  const NAV_YOU = [['stats', 'stats', 'Статистика'], ['map', 'graph', 'Карта исполнителей']]
  // Какой пункт меню подсвечен для страницы
  const NAV_OF = { album: 'albums', artist: 'artists' }

  const navItem = ([id, ic, label]) =>
    `<button class="nav-item" data-act="go" data-to="${id}" data-nav="${id}" title="${label}">${icon(ic)}<span class="nav-label">${label}</span></button>`
  const navPlaylist = (p) =>
    `<button class="nav-item nav-pl" data-act="go" data-to="playlist/${p.id}" data-nav="playlist/${p.id}" title="${H.esc(p.title)}">` +
    `<span class="cv mini-cv">${cover(p.color, p.pattern)}</span>` +
    `<span class="nav-label ellipsis">${H.esc(p.title)}</span>${p.smart ? '<span class="tag">умный</span>' : ''}</button>`

  const side = () => `
    <aside class="pc-side">
      <div class="side-brand">${logo()}<b>Sonar</b></div>
      <button class="side-search" data-act="go" data-to="search" data-nav="search">${icon('search')}<span>Поиск</span><kbd>Ctrl K</kbd></button>
      <nav class="nav">
        <span class="nav-ind off"></span>
        ${NAV_TOP.map(navItem).join('')}
        <div class="nav-sec">Медиатека</div>${NAV_LIB.map(navItem).join('')}
        <div class="nav-sec">Ты</div>${NAV_YOU.map(navItem).join('')}
        <div class="nav-sec">Плейлисты <button class="icon-btn sm" data-act="new-playlist" aria-label="Новый плейлист">${icon('plus')}</button></div>
        ${D.PLAYLISTS.map(navPlaylist).join('')}
      </nav>
      <div class="side-foot">
        <button class="foot-me" data-act="settings" data-sec="profile">
          <span class="avatar">F</span><span class="foot-who"><b>Folzy</b><span>@folzy</span></span>
        </button>
        <button class="icon-btn" data-act="settings" aria-label="Настройки" title="Настройки">${icon('settings')}</button>
      </div>
    </aside>`

  const titlebar = () => `
    <header class="titlebar">
      <button class="icon-btn" data-act="back" aria-label="Назад" title="Назад (кнопка мыши 4)">${icon('chevL')}</button>
      <button class="icon-btn" data-act="fwd" aria-label="Вперёд" title="Вперёд (кнопка мыши 5)">${icon('chevR')}</button>
      <div class="drag"></div>
      <div class="win">
        <button class="w-min" data-act="noop" aria-label="Свернуть">${icon('winMin')}</button>
        <button class="w-max" data-act="noop" aria-label="Развернуть">${icon('winMax')}</button>
        <button class="w-close" data-act="tray" aria-label="Спрятать в трей" title="Спрятать в трей — музыка играет">${icon('winClose')}</button>
      </div>
    </header>`

  const bar = () => `
    <footer class="pc-bar">
      <div class="bar-now">
        <button class="bar-cv-btn" data-act="overlay" data-id="full" aria-label="Открыть плеер">${P.coverSlot('bar-cv')}<span class="bar-cv-hint">${icon('expand')}</span></button>
        <div class="bar-meta fade-swap" data-bind="meta">
          <span class="bar-title sel ellipsis" data-bind="title"></span>
          <span class="bar-artist"><span data-bind="badge"></span><span class="sel ellipsis" data-bind="artist"></span></span>
        </div>
        ${P.likeBtn()}
      </div>
      <div class="bar-center">
        <div class="ctrls">
          <button class="icon-btn" data-act="shuffle" data-bind="shuffle" aria-label="Перемешать" title="Перемешать">${icon('shuffle')}</button>
          <button class="icon-btn big" data-act="prev" aria-label="Предыдущий">${icon('prev')}</button>
          ${P.playBtn('play-btn')}
          <button class="icon-btn big" data-act="next" aria-label="Следующий">${icon('next')}</button>
          <button class="icon-btn" data-act="repeat" data-bind="repeat" aria-label="Повтор" title="Повтор трека">${icon('repeat')}</button>
        </div>
        <div class="prog-row">
          <span class="time" data-bind="cur">0:00</span>${P.slider('prog', 'seek', 'Перемотка')}<span class="time r" data-bind="dur">0:00</span>
        </div>
      </div>
      <div class="bar-right">
        ${P.speedBtn()}
        <button class="icon-btn" data-act="overlay" data-id="full" data-ov-btn="full" aria-label="Текст" title="Текст">${icon('lyrics')}</button>
        <button class="icon-btn" data-act="drawer" data-id="queue" data-drawer-btn="queue" aria-label="Очередь" title="Очередь">${icon('queue')}</button>
        <button class="icon-btn" data-act="overlay" data-id="eq" data-ov-btn="eq" aria-label="Эквалайзер" title="Эквалайзер">${icon('eq')}</button>
        <button class="icon-btn" data-act="mute" data-bind="mute" aria-label="Звук">${icon('volHigh')}</button>
        ${P.slider('vol', 'vol', 'Громкость')}
        <button class="icon-btn" data-act="scene" data-id="mini" aria-label="Мини-окно" title="Мини-окно поверх всех окон">${icon('pip')}</button>
      </div>
    </footer>`

  const shell = () => `
    <div class="pc-app">
      ${side()}
      <main class="pc-main">
        ${titlebar()}
        <div class="pc-body">
          <div class="scroll" data-host="page"></div>
          <aside class="pc-drawer" data-host="drawer"></aside>
        </div>
      </main>
      ${bar()}
      <button class="app-shield" data-act="close-overlay" aria-label="Закрыть настройки" tabindex="-1"></button>
    </div>
    <div class="pc-over" data-host="overlay"></div>
    <div class="pc-menu" data-host="menu"></div>
    <div class="pc-toast" data-host="toast"></div>
    <div class="pc-scene" data-host="scene"></div>`

  const pc = H.pc
  const host = (name) => pc.querySelector(`[data-host="${name}"]`)
  const pageOf = (route) => {
    const [name, ...rest] = String(route).split('/')
    return { name, arg: rest.join('/') }
  }

  // ── Страница ──────────────────────────────────────────
  const pageHtml = (page, s, arg) => {
    if (s.load === 'loading') return P.skeleton(page.skeleton || 'page')
    if (s.load === 'empty' && page.empty) return P.empty(page.empty(s, arg))
    return page.render(s, arg)
  }
  const mountPage = (s, animate) => {
    const el = host('page')
    const { name, arg } = pageOf(s.route)
    const page = R.pages[name]
    const top = el.scrollTop
    el.innerHTML = `<div class="page${animate ? '' : ' still'}" data-page="${name}">${pageHtml(page, s, arg)}</div>`
    el.scrollTop = animate ? 0 : top
    S.app.hydrate()
    if (animate) H.countUp(el)
    if (page.after && s.load === 'normal') page.after(el, s, arg)
  }
  const renderPage = (prev, next) => {
    const page = R.pages[pageOf(next.route).name]
    if (H.changed(prev, next, ['route', 'load'])) { mountPage(next, true); return }
    if (H.changed(prev, next, page.deps || [])) { mountPage(next, false); return }
    if (page.update && next.load === 'normal') page.update(host('page'), prev, next)
  }

  // ── Меню слева: подсветка и индикатор ─────────────────
  const navKey = (route) => {
    const { name } = pageOf(route)
    return name === 'playlist' ? route : NAV_OF[name] || name
  }
  const renderNav = (prev, next) => {
    if (!H.changed(prev, next, ['route', 'fontsReady', 'width'])) return
    const key = navKey(next.route)
    const items = [...pc.querySelectorAll('[data-nav]')]
    items.forEach((b) => b.classList.toggle('on', b.dataset.nav === key))
    const ind = pc.querySelector('.nav-ind')
    const on = pc.querySelector(`.nav-item[data-nav="${CSS.escape(key)}"]`)
    if (!on) { ind.classList.add('off'); return }
    const first = ind.classList.contains('off')
    ind.classList.toggle('no-anim', first)
    ind.style.setProperty('--y', `${on.offsetTop}px`)
    ind.style.height = `${on.offsetHeight}px`
    void ind.offsetWidth
    ind.classList.remove('off', 'no-anim')
  }
  const renderHist = (prev, next) => {
    if (!H.changed(prev, next, ['hi', 'hist'])) return
    pc.querySelector('[data-act="back"]').disabled = next.hi <= 0
    pc.querySelector('[data-act="fwd"]').disabled = next.hi >= next.hist.length - 1
  }

  // ── Слои поверх окна ──────────────────────────────────
  const leave = (el) => { el.classList.add('leaving'); setTimeout(() => el.remove(), LEAVE_MS) }
  const mountOverlay = (s) => {
    const ov = R.overlays[s.overlay]
    const scrim = ov.scrim === false ? '' : `<div class="ov-scrim" data-act="close-overlay"></div>`
    host('overlay').insertAdjacentHTML('beforeend', `<div class="ov ov-${s.overlay}" data-ov="${s.overlay}">${scrim}<div class="ov-body">${ov.render(s)}</div></div>`)
    const el = host('overlay').lastElementChild
    S.app.hydrate()
    if (ov.after) ov.after(el, s)
  }
  const renderOverlay = (prev, next) => {
    if (H.changed(prev, next, ['overlay'])) {
      host('overlay').querySelectorAll('.ov:not(.leaving)').forEach((el) => {
        const ov = R.overlays[el.dataset.ov]
        if (ov && ov.leave) ov.leave(el)
        leave(el)
      })
      pc.dataset.overlay = next.overlay || ''
      pc.querySelectorAll('[data-ov-btn]').forEach((b) => b.classList.toggle('on', b.dataset.ovBtn === next.overlay))
      if (next.overlay) mountOverlay(next)
      return
    }
    const ov = next.overlay && R.overlays[next.overlay]
    const el = ov && host('overlay').querySelector(`.ov[data-ov="${next.overlay}"]:not(.leaving) .ov-body`)
    if (!el) return
    if (H.changed(prev, next, ov.deps || [])) {
      el.innerHTML = ov.render(next)
      S.app.hydrate()
      if (ov.after) ov.after(el.parentElement, next)
      return
    }
    if (ov.update) ov.update(el.parentElement, prev, next)
  }

  // ── Выдвижная очередь справа ──────────────────────────
  const QUEUE_DEPS = ['drawer', 'upnext', 'index', 'src', 'mood', 'shuffle']
  const renderDrawer = (prev, next) => {
    if (!H.changed(prev, next, QUEUE_DEPS)) return
    const el = host('drawer')
    pc.querySelector('.pc-body').classList.toggle('has-drawer', Boolean(next.drawer))
    pc.querySelectorAll('[data-drawer-btn]').forEach((b) => b.classList.toggle('on', b.dataset.drawerBtn === next.drawer))
    if (!next.drawer || !S.queueView) return
    el.innerHTML = `<div class="drawer-in">${S.queueView(next, 'drawer')}</div>`
    S.app.hydrate()
  }

  // ── Ширина окна ───────────────────────────────────────
  const renderWidth = (prev, next) => {
    if (!H.changed(prev, next, ['width'])) return
    pc.style.width = `${next.width}px`
    pc.classList.toggle('narrow', next.width <= NARROW_W)
    const cap = document.querySelector('.frame-pc .frame-cap')
    if (cap) cap.innerHTML = `<b>Windows</b> · ${next.width} × ${PC_H}, окно без рамки`
  }

  S.pcShell = Object.freeze({ host, pageOf })

  S.use({
    init: () => { pc.innerHTML = shell() },
    actions: {
      tray: (s) => S.app.toast('Sonar свёрнут в трей — музыка играет'),
      'new-playlist': () => ({ menu: null, ...S.app.toast('Новый плейлист «Без названия» создан') }),
    },
    renderers: [renderWidth, renderPage, renderNav, renderHist, renderOverlay, renderDrawer],
  })
})(window.Sonar)
