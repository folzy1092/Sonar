// iPhone: вкладки Главная, Поиск, Медиатека, Профиль и экран раздела настроек.
// Страницы ПК (альбом, плейлист, исполнитель, Sonar Mix…) открываются как вложенные экраны —
// их разметку берём из R.pages, стили под ширину телефона — css/ph/screens.css.
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon } = S
  const P = S.parts
  const D = S.data
  const H = S.h
  const R = S.reg
  const V = S.settingsView
  const F = Object.freeze
  const OFTEN = F(['t2', 't1', 't8', 't3', 't10'])
  const VERSION = '0.1.0 (528)'

  const head = (title, extra = '') => `<header class="ph-head"><h1>${title}</h1>${extra}</header>`
  const shelf = (title, body, cls = 'ph-row') =>
    `<section class="ph-shelf"><h2>${title}</h2><div class="${cls}">${body}</div></section>`
  const avatar = () => `<button class="ph-ava" data-act="ph-tab" data-id="profile" aria-label="Профиль">F</button>`
  const about = () =>
    `<div class="about">${S.logo()}<div><b>Sonar ${VERSION}</b><span>iPhone · канал обновлений @SonarUpdates</span></div></div>`

  // ── Главная ───────────────────────────────────────────
  const hero = () => `
    <section class="ph-hero" data-act="go" data-to="mix" role="button" tabindex="0" aria-label="Открыть Sonar Mix">
      <div class="eyebrow">${icon('mix')}<span data-bind="mood-name"></span></div>
      ${P.sonar()}
      <div class="ph-hero-foot">
        <div><h2>Sonar Mix</h2><p class="hero-line" data-bind="mood-line"></p></div>
        ${P.playBtn('hero-play')}
      </div>
    </section>`

  const home = () =>
    head('Главная', avatar()) + hero() +
    `<div class="ph-moods">${P.moodChips('chip-plain')}</div>` +
    shelf('Недавнее', D.RECENT.map((r) => P.card(r)).join('')) +
    shelf('Часто слушаешь', OFTEN.map((id) => P.trackRow(H.track(id))).join(''), 'ph-list') +
    shelf('Для тебя', D.MIXES.map((m) => P.card(m)).join(''))

  // ── Медиатека ─────────────────────────────────────────
  const libRow = (to, ic, title, count) =>
    `<button class="lib-row" data-act="go" data-to="${to}">${icon(ic, 'lib-ic')}<b>${title}</b>` +
    `<span class="lib-n">${count}</span>${icon('chevR', 'lib-chev')}</button>`

  const library = (s) =>
    head('Медиатека', avatar()) +
    `<nav class="lib-list">` +
    libRow('liked', 'heart', 'Любимые', s.liked.length) +
    libRow('playlists', 'playlist', 'Плейлисты', D.PLAYLISTS.length) +
    libRow('artists', 'artist', 'Исполнители', D.ARTISTS.length) +
    libRow('albums', 'album', 'Альбомы', s.savedAlbums.length) +
    libRow('files', 'folder', 'Файлы', D.LOCAL_FILES.tracks.length) +
    `</nav>` +
    shelf('Недавно добавленные', D.RECENT.slice(0, 6).map((r) => P.card(r)).join(''), 'grid')

  // ── Профиль ───────────────────────────────────────────
  const profile = () =>
    head('Профиль') +
    `<button class="ph-prof" data-act="settings" data-sec="profile">` +
    `<span class="ph-prof-ava">F</span><span class="ph-prof-meta"><b class="sel">Folzy</b><span class="sel">@folzy · Sonar Deep: Dev</span></span>${icon('chevR', 'lib-chev')}</button>` +
    `<nav class="lib-list">${V.SECTIONS.filter(([id]) => id !== 'profile').map(([id, ic, label]) =>
      `<button class="lib-row" data-act="settings" data-sec="${id}">${icon(ic, 'lib-ic')}<b>${label}</b>` +
      `${id === 'deep' ? '<span class="tag">Deep</span>' : '<span></span>'}${icon('chevR', 'lib-chev')}</button>`).join('')}</nav>` +
    about()

  // ── Раздел настроек ───────────────────────────────────
  // «Система» у ПК — про окно Windows; у iPhone свои пункты
  const system = (s) =>
    V.group('Обновления',
      V.row('Автообновление', 'Новая сборка ставится сама — через твой сертификат', V.tgl('autoUpdate', 'Автообновление')) +
      V.row(`Версия ${VERSION}`, 'Канал @SonarUpdates', `<button class="btn btn-soft sm" data-act="ph-check-update">Проверить</button>`)) +
    V.group('Хранилище', V.part('storage', s)) + about()

  const sectionOf = (arg) => (V.PANES[arg] ? arg : 'look')
  const labelOf = (arg) => (V.SECTIONS.find(([id]) => id === sectionOf(arg)) || [])[2] || 'Настройки'
  const setPane = (s, arg) => {
    const sec = sectionOf(arg)
    return `<h1 class="ph-set-title">${labelOf(sec)}</h1><div class="ph-set">${sec === 'system' ? system(s) : V.PANES[sec](s)}</div>`
  }
  const setAfter = (el, s) => { V.syncControls(el, s); H.countUp(el) }
  const setUpdate = (el, prev, next) => {
    el.querySelectorAll('[data-part]').forEach((p) => {
      const def = V.PARTS[p.dataset.part]
      if (!H.changed(prev, next, def.deps)) return
      p.innerHTML = def.html(next)
      H.countUp(p)
    })
    V.syncControls(el, next)
  }

  // ── Поиск: страница ПК без автофокуса (на телефоне клавиатура не выезжает сама) ──
  const search = R.pages.search
  const PAGE_TITLES = F({ liked: 'Любимые', playlists: 'Плейлисты', artists: 'Исполнители', albums: 'Альбомы', files: 'Файлы', mix: 'Sonar Mix' })

  S.use({
    actions: { 'ph-check-update': () => S.app.toast(`У тебя последняя версия — ${VERSION}`) },
    screens: {
      'tab:home': { render: home, deps: [], empty: R.pages.home.empty },
      'tab:search': { render: (s) => head('Поиск') + search.render(s), update: search.update, deps: [], empty: search.empty },
      'tab:library': { render: library, deps: ['liked', 'savedAlbums'], empty: () => ({ icon: 'playlist', title: 'Медиатека пуста', line: 'Лайкай треки и сохраняй альбомы — всё соберётся здесь.', action: { act: 'go', to: 'search', label: 'Найти музыку' } }) },
      'tab:profile': { render: profile, deps: [], skeleton: false },
      set: { render: setPane, title: (s, arg) => labelOf(arg), deps: [], skeleton: false, after: setAfter, update: setUpdate },
      ...Object.fromEntries(Object.entries(PAGE_TITLES).map(([k, title]) => [k, { ...R.pages[k], title }])),
    },
  })
})(window.Sonar)
