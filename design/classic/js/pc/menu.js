// ПК: меню трека — по кнопке ⋯ и правым кликом. Закрывается только кликом (снаружи или по пункту).
// «В плейлист ▸» раскрывает подменю тоже по клику, не по наведению.
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon, badge } = S
  const D = S.data
  const H = S.h
  const MENU_W = 264
  const MENU_H = 420
  const EDGE = 12
  const LEAVE_MS = 160
  const ALT_SERVICE = { sc: 'ym', ym: 'sc', sp: 'ym', yt: 'sc', vk: 'ym', file: 'sc' }

  // Точка меню в координатах окна ПК (окно масштабируется под экран)
  const pointOf = (el, ev) => {
    const box = H.pc.getBoundingClientRect()
    const k = S.app.scale
    const fromEl = !ev || ev.type === 'click'
    const r = el.getBoundingClientRect()
    const cx = fromEl ? r.right - 4 : ev.clientX
    const cy = fromEl ? r.bottom + 4 : ev.clientY
    const x = (cx - box.left) / k - (fromEl ? MENU_W : 0)
    const y = (cy - box.top) / k
    const w = box.width / k
    const h = box.height / k
    return { x: Math.round(Math.max(EDGE, Math.min(x, w - MENU_W - EDGE))), y: Math.round(Math.max(EDGE, Math.min(y, h - MENU_H - EDGE))) }
  }

  const item = (act, ic, label, extra = '', attrs = '') =>
    `<button class="m-item" data-act="${act}"${attrs}>${icon(ic)}<span>${label}</span>${extra}</button>`

  const plList = (m) => `<div class="m-sub">` +
    D.PLAYLISTS.filter((p) => !p.smart).map((p) =>
      `<button class="m-item" data-act="add-pl" data-tid="${m.tid}" data-id="${p.id}"><span class="cv m-cv">${S.cover(p.color, p.pattern)}</span><span>${H.esc(p.title)}</span>` +
      `${p.tracks.includes(m.tid) ? icon('check', 'm-tail') : ''}</button>`).join('') +
    item('new-playlist', 'plus', 'Новый плейлист') + `</div>`

  // Шапка и пункты меню — их же показывает нижний лист на iPhone
  const items = (m, s) => {
    const t = H.track(m.tid)
    const liked = s.liked.includes(t.id)
    const alt = D.SERVICES[ALT_SERVICE[t.service]]
    const tid = ` data-tid="${t.id}"`
    return `<div class="m-head"><span class="cv m-cv">${S.cover(t.color, t.pattern)}</span><span class="m-meta"><b class="ellipsis sel">${H.esc(t.title)}</b><span class="sel">${badge(t.service)}${H.esc(t.artist)}</span></span></div>` +
      item('play-next', 'next', 'Сыграть следующим', '', tid) +
      item('add-queue', 'queue', 'Добавить в очередь', '', tid) +
      item('menu-sub', 'playlist', 'Добавить в плейлист', icon(m.sub ? 'chevD' : 'chevR', 'm-tail'), ` aria-expanded="${Boolean(m.sub)}"`) +
      (m.sub ? plList(m) : '') +
      `<hr>` +
      (t.aid ? item('menu-go', 'artist', 'К исполнителю', '', ` data-to="artist/${t.aid}"`) : '') +
      (t.al ? item('menu-go', 'album', 'К альбому', '', ` data-to="album/${t.al}"`) : '') +
      item('menu-alt', 'refresh', `Играть из ${alt.name}`, '', ` data-svc="${ALT_SERVICE[t.service]}"`) +
      `<hr>` +
      item('menu-toast', 'link', 'Скопировать ссылку', '<kbd>Ctrl C</kbd>', ` data-text="Ссылка на трек скопирована"`) +
      item('menu-toast', 'download', 'Скачать', '', ` data-text="Скачивание началось — файл появится в «Файлах»"`) +
      item('menu-like', liked ? 'heartFill' : 'heart', liked ? 'Убрать из любимых' : 'В любимые', '', tid) +
      item('menu-dislike', 'thumbDown', 'Не рекомендовать', '', tid)
  }
  const menuHtml = (s) => `<div class="menu" role="menu" style="left:${s.menu.x}px;top:${s.menu.y}px">${items(s.menu, s)}</div>`
  S.menuView = Object.freeze({ items })

  const renderMenu = (prev, next) => {
    if (!H.changed(prev, next, ['menu', 'liked'])) return
    const host = S.pcShell.host('menu')
    host.querySelectorAll('.menu:not(.leaving)').forEach((el) => {
      if (next.menu && prev && prev.menu && prev.menu.tid === next.menu.tid && prev.menu.x === next.menu.x) return
      el.classList.add('leaving')
      setTimeout(() => el.remove(), LEAVE_MS)
    })
    if (!next.menu) return
    const same = prev && prev.menu && prev.menu.tid === next.menu.tid && prev.menu.x === next.menu.x
    const old = host.querySelector('.menu:not(.leaving)')
    if (same && old) { old.outerHTML = menuHtml(next); host.querySelector('.menu:not(.leaving)').classList.add('still'); return }
    host.insertAdjacentHTML('beforeend', menuHtml(next))
  }

  const close = { menu: null }
  S.use({
    defaults: { notRec: [] },
    actions: {
      menu: (s, el, ev) => (s.menu && s.menu.tid === el.dataset.tid && ev && ev.type === 'click' ? close : { menu: { tid: el.dataset.tid, sub: false, ...pointOf(el, ev) }, ann: null }),
      'menu-sub': (s) => ({ menu: { ...s.menu, sub: !s.menu.sub } }),
      'menu-go': (s, el) => { S.app.go(el.dataset.to); return close },
      'menu-alt': (s, el) => ({ ...close, ...S.app.toast(`Нашли в ${D.SERVICES[el.dataset.svc].name} — будет играть оттуда`) }),
      'menu-toast': (s, el) => ({ ...close, ...S.app.toast(el.dataset.text) }),
      'menu-like': (s, el) => {
        const id = el.dataset.tid
        const on = s.liked.includes(id)
        return { ...close, liked: Object.freeze(on ? s.liked.filter((x) => x !== id) : [...s.liked, id]), ...S.app.toast(on ? 'Убрано из любимых' : 'Добавлено в любимые', on ? { liked: s.liked } : null) }
      },
      'menu-dislike': (s, el) => ({ ...close, notRec: Object.freeze([...s.notRec, el.dataset.tid]), ...S.app.toast('Больше не будем рекомендовать', { notRec: s.notRec }) }),
      'add-pl': (s, el) => {
        const p = H.playlist(el.dataset.id)
        return { ...close, ...S.app.toast(p.tracks.includes(el.dataset.tid) ? `Уже есть в «${p.title}»` : `Добавлено в «${p.title}»`) }
      },
    },
    renderers: [renderMenu],
  })
})(window.Sonar)
