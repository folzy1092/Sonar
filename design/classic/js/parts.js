// Общие куски разметки для ПК и iPhone. Динамика — через data-bind (main.js), клики — через data-act.
// data-tid на строке трека — для меню трека (кнопка ⋯ и правый клик).
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon, cover, badge } = S
  const D = S.data
  const H = S.h

  const playSwap = () => `<span class="swap">${icon('play', 'ic-play')}${icon('pause', 'ic-pause')}</span>`

  const likeBtn = (cls = '') =>
    `<button class="icon-btn like ${cls}" data-act="like" data-bind="like" aria-label="Нравится">` +
    `<span class="swap">${icon('heart', 'ic-line')}${icon('heartFill', 'ic-fill')}</span></button>`

  const playBtn = (cls, extra = '') =>
    `<button class="${cls}" data-act="play" data-bind="play" aria-label="Пауза">${playSwap()}${extra}</button>`

  // Слот обложки текущего трека: слои сменяются плавно (core.js → swapCover)
  const coverSlot = (cls) => `<div class="cv ${cls}" data-bind="cover"></div>`

  const rings = () =>
    `<svg class="rings" viewBox="0 0 200 200" aria-hidden="true">` +
    `<circle class="ring" cx="100" cy="100" r="98"/><circle class="ring" cx="100" cy="100" r="98"/>` +
    `<circle class="ring" cx="100" cy="100" r="98"/></svg>`

  const sonar = () =>
    `<div class="hero-sonar">${rings()}${coverSlot('hero-disc')}` +
    `<div class="hero-now"><b class="ellipsis" data-bind="title"></b><span data-bind="artist"></span></div></div>`

  const moodChips = (cls) =>
    D.MOODS.map((m) => `<button class="${cls}" data-act="mood" data-chip data-id="${m.id}">${m.name}</button>`).join('')

  // Карточка: клик — открыть, круглая кнопка — сразу слушать
  const card = (item, round = false) => {
    const open = item.to ? `data-act="go" data-to="${item.to}"` : `data-act="mood" data-id="${item.mood}"`
    const play = item.to ? `data-act="play-coll" data-to="${item.to}"` : `data-act="mood" data-id="${item.mood}"`
    return `<div class="card${round ? ' card-round' : ''}" ${open} role="button" tabindex="0">` +
      `<div class="cv card-cv">${cover(item.color, item.pattern)}` +
      `<button class="card-play" ${play} aria-label="Слушать">${icon('play')}</button></div>` +
      `<div class="card-title ellipsis">${H.esc(item.title)}</div><div class="card-sub ellipsis">${H.esc(item.sub)}</div></div>`
  }

  const moreBtn = (tid, cls = '') =>
    `<button class="icon-btn more-btn ${cls}" data-act="menu" data-tid="${tid}" aria-label="Ещё">${icon('more')}</button>`

  const trackRow = (t, withDur = true, src = '') =>
    `<div class="trow" data-act="track" data-id="${t.id}" data-tid="${t.id}"${src ? ` data-src="${src}"` : ''} role="button" tabindex="0">` +
    `<div class="cv trow-cv">${cover(t.color, t.pattern)}<span class="eq"><i></i><i></i><i></i></span></div>` +
    `<div class="trow-meta"><span class="trow-title ellipsis">${H.esc(t.title)}</span>` +
    `<span class="trow-artist">${badge(t.service)}<span class="ellipsis">${H.esc(t.artist)}</span></span></div>` +
    (withDur ? `<span class="trow-dur">${S.fmt(t.dur)}</span>` : '<span></span>') +
    moreBtn(t.id) + `</div>`

  // Таблица треков (медиатека, плейлист, альбом): # · трек · альбом · добавлен · время · ⋯
  const ttable = (ids, { src = '', album = true, added = true, num = 'index' } = {}) => {
    const rows = ids.map(H.track).filter(Boolean)
    const head = `<div class="tt-head"><span>#</span><span>Название</span>` +
      `${album ? '<span>Альбом</span>' : ''}${added ? '<span>Добавлен</span>' : ''}<span>${icon('clock')}</span><span></span></div>`
    const row = (t, i) => {
      const al = t.al ? H.album(t.al) : null
      return `<div class="tt-row trow" data-act="track" data-id="${t.id}" data-tid="${t.id}" data-src="${src}" role="button" tabindex="0">` +
        `<span class="tt-num"><b>${num === 'index' ? i + 1 : ''}</b><span class="eq"><i></i><i></i><i></i></span>${icon('play', 'tt-play')}</span>` +
        `<span class="tt-main"><span class="cv tt-cv">${cover(t.color, t.pattern)}</span>` +
        `<span class="tt-meta"><span class="trow-title ellipsis">${H.esc(t.title)}</span>` +
        `<span class="trow-artist">${badge(t.service)}<span class="ellipsis">${H.esc(t.artist)}</span></span></span></span>` +
        (album ? `<span class="tt-al ellipsis">${al ? `<button class="tlink" data-act="go" data-to="album/${al.id}">${H.esc(al.title)}</button>` : '—'}</span>` : '') +
        (added ? `<span class="tt-added">${t.added}</span>` : '') +
        `<span class="tt-dur">${S.fmt(t.dur)}</span>${moreBtn(t.id)}</div>`
    }
    const cls = `ttable${album ? '' : ' no-al'}${added ? '' : ' no-added'}`
    return `<div class="${cls}" data-src="${src}">${head}${rows.map(row).join('')}</div>`
  }

  const speedBtn = () => `<button class="speed" data-act="speed" data-bind="speed" title="Скорость">1×</button>`

  const slider = (cls, act, label) =>
    `<div class="slider ${cls}" data-act="${act}" role="slider" aria-label="${label}">` +
    `<span class="slider-fill"></span><span class="slider-knob"></span></div>`

  // Пустое состояние: значок, заголовок, строка и (по желанию) одно действие
  const empty = ({ icon: ic = 'note', title, line = '', action } = {}) =>
    `<div class="empty"><div class="empty-icon">${icon(ic)}</div>` +
    `<div class="empty-title">${H.esc(title)}</div>` +
    (line ? `<p class="empty-line">${H.esc(line)}</p>` : '') +
    (action ? `<button class="btn btn-soft" data-act="${action.act}"${action.to ? ` data-to="${action.to}"` : ''}>${H.esc(action.label)}</button>` : '') +
    `</div>`

  // Скелет загрузки: шапка, полка карточек и строки
  const skeleton = (kind = 'page') => {
    const rows = Array.from({ length: 7 }, (_, i) => `<div class="sk-row" style="--i:${i}"><i class="sk sk-cv"></i><span><i class="sk sk-l1"></i><i class="sk sk-l2"></i></span><i class="sk sk-d"></i></div>`).join('')
    const cards = Array.from({ length: 6 }, (_, i) => `<div class="sk-card" style="--i:${i}"><i class="sk sk-sq"></i><i class="sk sk-l1"></i><i class="sk sk-l2"></i></div>`).join('')
    const head = kind === 'coll'
      ? `<div class="sk-coll"><i class="sk sk-big"></i><span><i class="sk sk-l2"></i><i class="sk sk-h"></i><i class="sk sk-l1"></i></span></div>`
      : `<i class="sk sk-h"></i>`
    return `<div class="skel" aria-busy="true" aria-label="Загрузка">${head}${kind === 'coll' ? '' : `<div class="sk-cards">${cards}</div>`}<div class="sk-rows">${rows}</div></div>`
  }

  const services = (ids) => [...new Set(ids.map((id) => H.track(id)?.service).filter(Boolean))].map(badge).join('')

  // Шапка коллекции: большая обложка, тип, название, строка сведений, кнопки
  const collHead = (c, to, { kindLabel, sub, extra = '' }) =>
    `<header class="coll-head">` +
    `<div class="cv coll-cv${c.kind === 'artist' ? ' round' : ''}">${cover(c.color, c.pattern)}</div>` +
    `<div class="coll-info"><div class="coll-kind">${kindLabel}</div>` +
    `<h1 class="coll-title sel">${H.esc(c.title)}</h1>` +
    `<div class="coll-sub">${sub}</div>` +
    `<div class="coll-actions">` +
    `<button class="btn btn-accent" data-act="play-coll" data-to="${to}">${icon('play')}<span>Слушать</span></button>` +
    `<button class="btn btn-soft" data-act="play-coll" data-to="${to}" data-shuffle="1">${icon('shuffle')}<span>Перемешать</span></button>` +
    `${extra}</div></div></header>`

  S.parts = Object.freeze({
    playSwap, likeBtn, playBtn, coverSlot, rings, sonar, moodChips, card, moreBtn, trackRow, ttable,
    speedBtn, slider, empty, skeleton, services, collHead,
  })
})(window.Sonar)
