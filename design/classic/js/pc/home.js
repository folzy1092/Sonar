// ПК: Главная и страница Sonar Mix.
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon } = S
  const P = S.parts
  const D = S.data
  const H = S.h
  const UP_NEXT_COUNT = 6
  const TOP_ARTISTS = ['a2', 'a1', 'a7', 'a3', 'a5', 'a4']

  const shelf = (title, body, all = '', cls = 'row') =>
    `<section class="shelf"><div class="shelf-head"><h2>${title}</h2>${all ? `<button class="link" data-act="go" data-to="${all}">Все</button>` : ''}</div>` +
    `<div class="${cls}">${body}</div></section>`

  const artistCard = (id) => {
    const a = H.artist(id)
    return P.card({ to: `artist/${a.id}`, title: a.name, sub: a.genre, color: a.color, pattern: a.pattern }, true)
  }

  const hero = (big = false) => `
    <section class="mix-hero${big ? ' big' : ''}">
      <div class="hero-copy">
        <div class="eyebrow">${icon('mix')}<span>Настроение · <span data-bind="mood-name"></span></span></div>
        <h2 class="hero-title">Sonar Mix</h2>
        <p class="hero-line" data-bind="mood-line"></p>
        <div class="hero-actions">
          ${P.playBtn('btn-hero', '<span class="lbl" data-bind="play-label">Пауза</span>')}
          <button class="icon-btn hero-ghost" data-act="dislike" aria-label="Не то — дальше" title="Не то — дальше">${icon('thumbDown')}</button>
          <button class="icon-btn hero-ghost" data-act="go" data-to="mix" aria-label="Открыть Sonar Mix" title="Открыть Sonar Mix">${icon('chevR')}</button>
        </div>
      </div>
      ${P.sonar()}
      <div class="moods">${P.moodChips('chip')}</div>
    </section>`

  const today = () => {
    const d = new Date(2026, 10, 21)
    const s = d.toLocaleDateString('ru-RU', { weekday: 'long', day: 'numeric', month: 'long' })
    return s[0].toUpperCase() + s.slice(1)
  }

  const home = (s) => `
    <div class="page-head"><h1>Главная</h1><span class="date">${today()}</span></div>
    ${hero()}
    ${shelf('Недавнее', D.RECENT.map((r) => P.card(r)).join(''), 'playlists')}
    ${shelf('Часто слушаешь', ['t2', 't1', 't8', 't3', 't10', 't5'].map((id) => P.trackRow(H.track(id))).join(''), 'stats', 'tracks')}
    ${shelf('Для тебя', D.MIXES.map((m) => P.card(m)).join(''), 'mix')}
    ${shelf('Твои исполнители', TOP_ARTISTS.map(artistCard).join(''), 'artists')}`

  const upNext = (s) => {
    const ids = S.player.order({ ...s, src: null })
    const i = ids.indexOf(H.trackOf(s).id)
    return Array.from({ length: UP_NEXT_COUNT }, (_, k) => ids[(i + 1 + k) % ids.length])
  }

  const mix = (s) => `
    <div class="page-head"><h1>Sonar Mix</h1><span class="date">Своя волна: похожие треки из всех сервисов + твои лайки и пропуски</span></div>
    ${hero(true)}
    ${shelf('Дальше в миксе', upNext(s).map((id) => P.trackRow(H.track(id))).join(''), '', 'tracks')}
    <section class="shelf"><div class="shelf-head"><h2>Как Sonar Mix подбирает</h2></div>
      <div class="mix-how">
        <div><b>${icon('heart')} Лайк</b><span>Больше похожего — и того же исполнителя</span></div>
        <div><b>${icon('thumbDown')} Не то</b><span>Пропуск сразу, такое — реже</span></div>
        <div><b>${icon('check')} Дослушал</b><span>Тихий плюс: трек попал в настроение</span></div>
        <div><b>${icon('graph')} Соседи</b><span>Похожие исполнители с карты</span></div>
      </div>
    </section>
    ${shelf('Похожие исполнители', ['a6', 'a9', 'a11', 'a14', 'a16', 'a10'].map(artistCard).join(''), 'map')}`

  S.use({
    pages: {
      home: { render: home, deps: [], empty: () => ({ icon: 'home', title: 'Здесь пока тихо', line: 'Подключи сервис — и Главная наполнится твоей музыкой.', action: { act: "settings", to: "services", label: 'Подключить сервис' } }) },
      mix: { render: mix, deps: ["mood", "index"], empty: () => ({ icon: 'mix', title: 'Sonar Mix ещё учится', line: 'Лайкни пару треков — и микс поймёт, что тебе нравится.', action: { act: 'go', to: 'search', label: 'Найти музыку' } }) },
    },
  })
})(window.Sonar)
