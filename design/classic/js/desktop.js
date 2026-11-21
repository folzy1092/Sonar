// ПК: окно без рамки — левая панель, заголовок со своими кнопками окна, главная, панель плеера.
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon, cover, logo } = S
  const P = S.parts
  const D = S.data

  const NAV_TOP = [
    { id: 'home', icon: 'home', label: 'Главная' },
    { id: 'mix', icon: 'mix', label: 'Sonar Mix' },
  ]
  const NAV_LIB = [
    { id: 'liked', icon: 'heart', label: 'Любимые' },
    { id: 'playlists', icon: 'playlist', label: 'Плейлисты' },
    { id: 'artists', icon: 'artist', label: 'Исполнители' },
    { id: 'albums', icon: 'album', label: 'Альбомы' },
    { id: 'files', icon: 'folder', label: 'Файлы' },
  ]
  const NAV_YOU = [
    { id: 'stats', icon: 'stats', label: 'Статистика' },
    { id: 'map', icon: 'graph', label: 'Карта исполнителей' },
  ]

  const navItem = (n) =>
    `<button class="nav-item" data-act="nav" data-id="${n.id}" data-icon="${n.icon}" data-label="${n.label}">` +
    `${icon(n.icon)}<span class="nav-label">${n.label}</span></button>`

  const navPlaylist = (p, i) =>
    `<button class="nav-item nav-pl" data-act="nav" data-id="pl${i}" data-icon="playlist" data-label="${p.title}">` +
    `<span class="cv mini-cv">${cover(p.color, p.pattern)}</span>` +
    `<span class="nav-label ellipsis">${p.title}</span>${p.smart ? '<span class="tag">умный</span>' : ''}</button>`

  const side = () => `
    <aside class="pc-side">
      <div class="side-brand">${logo()}<b>Sonar</b></div>
      <button class="side-search" data-act="nav" data-id="search" data-icon="search" data-label="Поиск">
        ${icon('search')}<span>Поиск</span><kbd>Ctrl K</kbd>
      </button>
      <nav class="nav">
        <span class="nav-ind" data-bind="nav-ind"></span>
        ${NAV_TOP.map(navItem).join('')}
        <div class="nav-sec">Медиатека</div>
        ${NAV_LIB.map(navItem).join('')}
        <div class="nav-sec">Ты</div>
        ${NAV_YOU.map(navItem).join('')}
        <div class="nav-sec">Плейлисты</div>
        ${D.PLAYLISTS.map(navPlaylist).join('')}
      </nav>
      <div class="side-foot">
        <span class="avatar">F</span>
        <span class="foot-who"><b>Folzy</b><span>@folzy</span></span>
        <button class="icon-btn" data-act="nav" data-id="settings" data-icon="settings" data-label="Настройки" aria-label="Настройки">${icon('settings')}</button>
      </div>
    </aside>`

  const titlebar = () => `
    <header class="titlebar">
      <button class="icon-btn" aria-label="Назад" disabled>${icon('chevL')}</button>
      <button class="icon-btn" aria-label="Вперёд" disabled>${icon('chevR')}</button>
      <div class="drag"></div>
      <div class="win">
        <button class="w-min" aria-label="Свернуть">${icon('winMin')}</button>
        <button class="w-max" aria-label="Развернуть">${icon('winMax')}</button>
        <button class="w-close" aria-label="Спрятать в трей">${icon('winClose')}</button>
      </div>
    </header>`

  const hero = () => `
    <section class="mix-hero">
      <div class="hero-copy">
        <div class="eyebrow">${icon('mix')}<span>Настроение · <span data-bind="mood-name"></span></span></div>
        <h2 class="hero-title">Sonar Mix</h2>
        <p class="hero-line" data-bind="mood-line"></p>
        <div class="hero-actions">
          ${P.playBtn('btn-hero', '<span class="lbl" data-bind="play-label">Пауза</span>')}
          <button class="icon-btn hero-ghost" data-act="dislike" aria-label="Не то — дальше" title="Не то — дальше">${icon('thumbDown')}</button>
        </div>
      </div>
      ${P.sonar()}
      <div class="moods">${P.moodChips('chip')}</div>
    </section>`

  const homePage = () => `
    <div class="page" data-page="home">
      <div class="page-head"><h1>Главная</h1><span class="date">Суббота, 21 ноября</span></div>
      ${hero()}
      <section class="shelf">
        <div class="shelf-head"><h2>Недавнее</h2><button class="link">Все</button></div>
        <div class="row">${D.RECENT.map((r, i) => P.card(r, i)).join('')}</div>
      </section>
      <section class="shelf">
        <div class="shelf-head"><h2>Часто слушаешь</h2><button class="link">Все</button></div>
        <div class="tracks">${D.TRACKS.map((t) => P.trackRow(t)).join('')}</div>
      </section>
      <section class="shelf">
        <div class="shelf-head"><h2>Для тебя</h2><button class="link">Все</button></div>
        <div class="row">${D.MIXES.map((m, i) => P.card(m, i + 10)).join('')}</div>
      </section>
    </div>`

  const bar = () => `
    <footer class="pc-bar">
      <div class="bar-now">
        ${P.coverSlot('bar-cv')}
        <div class="bar-meta fade-swap" data-bind="meta">
          <span class="bar-title sel ellipsis" data-bind="title"></span>
          <span class="bar-artist"><span data-bind="badge"></span><span class="sel" data-bind="artist"></span></span>
        </div>
        ${P.likeBtn()}
      </div>
      <div class="bar-center">
        <div class="ctrls">
          <button class="icon-btn" data-act="shuffle" data-bind="shuffle" aria-label="Перемешать">${icon('shuffle')}</button>
          <button class="icon-btn big" data-act="prev" aria-label="Предыдущий">${icon('prev')}</button>
          ${P.playBtn('play-btn')}
          <button class="icon-btn big" data-act="next" aria-label="Следующий">${icon('next')}</button>
          <button class="icon-btn" data-act="repeat" data-bind="repeat" aria-label="Повтор">${icon('repeat')}</button>
        </div>
        <div class="prog-row">
          <span class="time" data-bind="cur">0:00</span>
          ${P.slider('prog', 'seek', 'Перемотка')}
          <span class="time r" data-bind="dur">0:00</span>
        </div>
      </div>
      <div class="bar-right">
        ${P.speedBtn()}
        <button class="icon-btn" aria-label="Текст">${icon('lyrics')}</button>
        <button class="icon-btn" aria-label="Очередь">${icon('queue')}</button>
        <button class="icon-btn" data-act="mute" aria-label="Громкость">${icon('volHigh')}</button>
        ${P.slider('vol', 'vol', 'Громкость')}
        <button class="icon-btn" aria-label="Мини-окно">${icon('pip')}</button>
      </div>
    </footer>`

  S.renderDesktop = (root) => {
    root.innerHTML = `
      ${side()}
      <main class="pc-main">
        ${titlebar()}
        <div class="scroll">
          ${homePage()}
          <div class="page" data-page="empty" hidden>${P.empty()}</div>
        </div>
      </main>
      ${bar()}`
  }
})(window.Sonar)
