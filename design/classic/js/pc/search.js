// ПК: поиск (единый, по всем сервисам; ссылка → перенос в Sonar) и быстрый переход Ctrl+K.
// Результаты перерисовываются отдельно от поля ввода, чтобы оно не теряло фокус.
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon, badge } = S
  const P = S.parts
  const D = S.data
  const M = S.more
  const H = S.h
  const SEARCH_DELAY_MS = 350
  const QUICK_LIMIT = 8
  const LINK_RE = /^https?:\/\/(\S+)$/i
  const LINK_SERVICES = [
    ['spotify.com', 'sp', 'Плейлист Spotify', 50, 47], ['music.yandex', 'ym', 'Плейлист Яндекс Музыки', 64, 64],
    ['soundcloud.com', 'sc', 'Сет SoundCloud', 18, 18], ['youtube.com', 'yt', 'Плейлист YouTube Music', 32, 29],
    ['vk.com', 'vk', 'Плейлист VK Музыки', 41, 38], ['music.apple.com', 'file', 'Плейлист Apple Music', 25, 22],
  ]

  let searchTimer = 0
  const norm = (v) => String(v).toLowerCase().replace(/ё/g, 'е').trim()
  const hit = (q) => (text) => norm(text).includes(q)

  const find = (query, filter) => {
    const q = norm(query)
    const has = hit(q)
    const svcOk = (svc) => filter === 'all' || svc === filter
    const tracks = D.TRACKS.filter((t) => svcOk(t.service) && (has(t.title) || has(t.artist)))
    const artists = filter === 'all' || filter !== 'file' ? D.ARTISTS.filter((a) => has(a.name) || has(a.genre)) : []
    const albums = D.ALBUMS.filter((a) => has(a.title) || has(H.artist(a.aid).name))
    return { tracks, artists: filter === 'all' ? artists : artists.filter((a) => tracks.some((t) => t.aid === a.id)), albums: filter === 'all' ? albums : [] }
  }

  const linkOf = (query) => {
    const m = LINK_RE.exec(query.trim())
    if (!m) return null
    const svc = LINK_SERVICES.find(([host]) => m[1].includes(host))
    return svc ? { host: svc[0], service: svc[1], kind: svc[2], total: svc[3], found: svc[4], url: query.trim() } : { unknown: true, url: query.trim() }
  }

  // ── Куски результатов ─────────────────────────────────
  const section = (title, body) => `<section class="shelf"><div class="shelf-head"><h2>${title}</h2></div>${body}</section>`
  const best = (r) => {
    const a = r.artists[0]
    if (a) {
      return `<button class="best" data-act="go" data-to="artist/${a.id}"><span class="cv best-cv round">${S.cover(a.color, a.pattern)}</span>` +
        `<b class="best-title">${H.esc(a.name)}</b><span class="best-sub">Исполнитель · ${a.listeners} слушателей</span></button>`
    }
    const t = r.tracks[0]
    return `<div class="best" data-act="track" data-id="${t.id}" role="button" tabindex="0"><span class="cv best-cv">${S.cover(t.color, t.pattern)}</span>` +
      `<b class="best-title">${H.esc(t.title)}</b><span class="best-sub">${badge(t.service)}Трек · ${H.esc(t.artist)}</span></div>`
  }

  const linkCard = (l, s) => {
    if (l.unknown) {
      return P.empty({ icon: 'link', title: 'Эту ссылку Sonar не знает', line: 'Поддерживаются Spotify, Яндекс Музыка, SoundCloud, YouTube Music, VK Музыка и Apple Music.' })
    }
    const done = s.linkMoved === l.url
    return `<div class="link-card">` +
      `<div class="cv link-cv">${S.cover('#1f6f4a', 'grid')}<span class="link-badge">${badge(l.service)}</span></div>` +
      `<div class="link-info"><div class="coll-kind">${icon('link')} Ссылка · ${l.kind}</div>` +
      `<h2 class="link-title">Night Drive — Phonk &amp; Slowed</h2>` +
      `<p class="link-line">${H.tn(l.total, ['трек', 'трека', 'треков'])} · нашли в твоих сервисах <b>${l.found} из ${l.total}</b>${l.found < l.total ? ' — остальные подберём из резерва' : ''}</p>` +
      `<div class="coll-actions">` +
      (done
        ? `<button class="btn btn-soft on" data-act="go" data-to="playlist/pl0">${icon('check')}<span>Перенесён — открыть</span></button>`
        : `<button class="btn btn-accent" data-act="import-link">${icon('transfer')}<span>Перенести в Sonar</span></button>`) +
      `<button class="btn btn-soft" data-act="noop">${icon('play')}<span>Послушать сначала</span></button></div></div></div>`
  }

  const browse = () =>
    section('Недавние запросы', `<div class="recent-q">${M.SEARCH_RECENT.map((q) =>
      `<button class="rq" data-act="set" data-key="query" data-val="${H.esc(q)}">${icon(q.startsWith('http') ? 'link' : 'clock')}<span class="ellipsis">${H.esc(q)}</span></button>`).join('')}</div>`) +
    section('Настроения Sonar Mix', `<div class="tiles">${D.MOODS.map((m, i) =>
      `<button class="tile" data-act="mood" data-id="${m.id}" style="--h:${(i * 41) % 360}"><b>${m.name}</b><span>${m.line}</span></button>`).join('')}</div>`)

  const results = (s) => {
    if (s.searching) return P.skeleton('page')
    if (!s.query.trim()) return browse()
    const l = linkOf(s.query)
    if (l) return linkCard(l, s)
    const r = find(s.query, s.sfilter)
    if (!r.tracks.length && !r.artists.length && !r.albums.length) {
      return P.empty({ icon: 'search', title: `Ничего не нашлось по «${s.query.trim()}»`, line: 'Проверь написание, выбери «Все» сервисы — или вставь ссылку на трек или плейлист.' })
    }
    const top = `<div class="search-top"><div><h2 class="mini-h">Лучшее совпадение</h2>${best(r)}</div>` +
      `<div><h2 class="mini-h">Треки</h2><div class="tracks one">${r.tracks.slice(0, 4).map((t) => P.trackRow(t)).join('') || '<p class="coll-note">Треков нет</p>'}</div></div></div>`
    return top +
      (r.artists.length ? section('Исполнители', `<div class="row">${r.artists.map((a) => P.card({ to: `artist/${a.id}`, title: a.name, sub: a.genre, color: a.color, pattern: a.pattern }, true)).join('')}</div>`) : '') +
      (r.albums.length ? section('Альбомы', `<div class="row">${r.albums.map((a) => P.card({ to: `album/${a.id}`, title: a.title, sub: H.artist(a.aid).name, color: a.color, pattern: a.pattern })).join('')}</div>`) : '')
  }

  const filters = (s) => M.SEARCH_FILTERS.map(([id, name]) =>
    `<button class="fchip${s.sfilter === id ? ' on' : ''}" data-act="set" data-key="sfilter" data-val="${id}">${id === 'all' ? name : `${badge(id)}${name}`}</button>`).join('')

  const page = (s) => `
    <div class="search-head">
      <label class="search-field">${icon('search')}
        <input data-input="search" type="text" placeholder="Трек, исполнитель, альбом — или ссылка на плейлист" value="${H.esc(s.query)}" spellcheck="false" autocomplete="off">
        <button class="icon-btn sm clear" data-act="set" data-key="query" data-val="" aria-label="Очистить">${icon('close')}</button>
      </label>
      <div class="fchips">${filters(s)}</div>
    </div>
    <div class="search-res" data-results>${results(s)}</div>`

  const update = (host, prev, next) => {
    if (!H.changed(prev, next, ['query', 'sfilter', 'searching', 'linkMoved'])) return
    const input = host.querySelector('[data-input="search"]')
    if (input && input.value !== next.query) input.value = next.query
    host.querySelector('.search-field').classList.toggle('has-text', Boolean(next.query))
    host.querySelector('.fchips').innerHTML = filters(next)
    const res = host.querySelector('[data-results]')
    res.innerHTML = results(next)
    if (prev.searching && !next.searching) res.classList.remove('res-in'), void res.offsetWidth, res.classList.add('res-in')
    S.app.hydrate()
  }

  const startSearch = (query) => {
    clearTimeout(searchTimer)
    searchTimer = setTimeout(() => S.app.set({ searching: false }), SEARCH_DELAY_MS)
    return { query, searching: Boolean(query.trim()) && !LINK_RE.test(query.trim()) }
  }

  // ── Ctrl+K ────────────────────────────────────────────
  const PAGES = [['home', 'home', 'Главная'], ['mix', 'mix', 'Sonar Mix'], ['liked', 'heart', 'Любимые'], ['playlists', 'playlist', 'Плейлисты'],
    ['stats', 'stats', 'Статистика'], ['map', 'graph', 'Карта исполнителей'], ['search', 'search', 'Поиск']]
  const COMMANDS = [
    ['Настройки', 'settings', () => ({ overlay: 'settings' })],
    ['Эквалайзер', 'eq', () => ({ overlay: 'eq' })],
    ['Сейчас играет — полный экран', 'expand', () => ({ overlay: 'full' })],
    ['Тема: светлая / тёмная', 'palette', (s) => ({ theme: s.theme === 'dark' ? 'light' : 'dark', overlay: null })],
    ['Итоги года', 'flame', () => ({ overlay: 'recap' })],
  ]
  const quickItems = (q) => {
    const has = hit(norm(q))
    const pages = PAGES.filter(([, , n]) => has(n)).map(([to, ic, n]) => ({ ic, label: n, sub: 'Раздел', run: () => { S.app.go(to); return {} } }))
    const cmds = COMMANDS.filter(([n]) => has(n)).map(([n, ic, fn]) => ({ ic, label: n, sub: 'Команда', run: fn }))
    const tracks = q.trim() ? D.TRACKS.filter((t) => has(t.title) || has(t.artist)).map((t) => ({ cv: t, label: t.title, sub: t.artist, svc: t.service, run: () => ({ index: S.player.indexOf(t.id), pos: 0, playing: true, overlay: null }) })) : []
    const artists = q.trim() ? D.ARTISTS.filter((a) => has(a.name)).map((a) => ({ cv: a, round: true, label: a.name, sub: 'Исполнитель', run: () => { S.app.go(`artist/${a.id}`); return {} } })) : []
    return [...tracks, ...artists, ...pages, ...cmds].slice(0, QUICK_LIMIT)
  }
  const quickRow = (it, i, qi) =>
    `<button class="q-item${i === qi ? ' on' : ''}" data-act="quick-run" data-i="${i}">` +
    (it.cv ? `<span class="cv q-cv${it.round ? ' round' : ''}">${S.cover(it.cv.color, it.cv.pattern)}</span>` : `<span class="q-ic">${icon(it.ic)}</span>`) +
    `<span class="q-meta"><b class="ellipsis">${H.esc(it.label)}</b><span>${it.svc ? badge(it.svc) : ''}${H.esc(it.sub)}</span></span>` +
    `${i === qi ? '<kbd>Enter</kbd>' : ''}</button>`
  const quickList = (s) => {
    const items = quickItems(s.qq)
    return items.length ? items.map((it, i) => quickRow(it, i, s.qi)).join('') : `<div class="q-none">Ничего — попробуй иначе</div>`
  }
  const quick = {
    render: (s) => `<div class="quick" role="dialog" aria-label="Быстрый переход">
      <label class="q-field">${icon('search')}<input data-input="quick" placeholder="Куда перейти или что включить?" value="${H.esc(s.qq)}" autocomplete="off" spellcheck="false"><kbd>Esc</kbd></label>
      <div class="q-list">${quickList(s)}</div>
      <div class="q-foot"><span><kbd>↑</kbd><kbd>↓</kbd> выбрать</span><span><kbd>Enter</kbd> открыть</span><span><kbd>Ctrl</kbd><kbd>K</kbd> из любого места</span></div></div>`,
    after: (el) => el.querySelector('input').focus(),
    update: (el, prev, next) => {
      if (!H.changed(prev, next, ['qq', 'qi'])) return
      el.querySelector('.q-list').innerHTML = quickList(next)
    },
  }
  const runQuick = (s, i) => {
    const it = quickItems(s.qq)[i]
    return it ? { overlay: null, ...it.run(s) } : {}
  }

  const keys = (ev, s) => {
    if ((ev.ctrlKey || ev.metaKey) && ev.key.toLowerCase() === 'k') return { overlay: 'quick', qq: '', qi: 0, menu: null }
    if (s.overlay !== 'quick') return null
    const n = quickItems(s.qq).length
    if (ev.key === 'ArrowDown') return { qi: n ? (s.qi + 1) % n : 0 }
    if (ev.key === 'ArrowUp') return { qi: n ? (s.qi - 1 + n) % n : 0 }
    if (ev.key === 'Enter') return runQuick(s, s.qi)
    return null
  }

  S.use({
    defaults: { query: '', sfilter: 'all', searching: false, linkMoved: null, qq: '', qi: 0 },
    actions: {
      'input:search': (s, el) => startSearch(el.value),
      'input:quick': (s, el) => ({ qq: el.value, qi: 0 }),
      'quick-run': (s, el) => runQuick(s, Number(el.dataset.i)),
      'import-link': (s) => ({ linkMoved: s.query.trim(), ...S.app.toast('Плейлист перенесён в Sonar: 47 треков, 3 — из резерва') }),
    },
    keys,
    pages: {
      search: {
        render: page, update, deps: [],
        after: (el) => { const i = el.querySelector('[data-input="search"]'); i.focus(); i.setSelectionRange(i.value.length, i.value.length) },
        empty: () => ({ icon: 'search', title: 'Поиск недоступен', line: 'Ни один сервис не подключён — подключи хотя бы один в настройках.', action: { act: 'settings', to: 'services', label: 'Подключить сервис' } }),
      },
    },
    overlays: { quick },
    hash: { q: (v) => ({ query: v }) },
  })
})(window.Sonar)
