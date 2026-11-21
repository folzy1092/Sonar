// Общие куски разметки для ПК и iPhone. Динамика — через data-bind (main.js), клики — через data-act.
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon, cover, badge } = S
  const D = S.data

  const playSwap = () => `<span class="swap">${icon('play', 'ic-play')}${icon('pause', 'ic-pause')}</span>`

  const likeBtn = (cls = '') =>
    `<button class="icon-btn like ${cls}" data-act="like" data-bind="like" aria-label="Нравится">` +
    `<span class="swap">${icon('heart', 'ic-line')}${icon('heartFill', 'ic-fill')}</span></button>`

  const playBtn = (cls, extra = '') =>
    `<button class="${cls}" data-act="play" data-bind="play" aria-label="Пауза">${playSwap()}${extra}</button>`

  // Слот обложки текущего трека: слои сменяются плавно (main.js → swapCover)
  const coverSlot = (cls) => `<div class="cv ${cls}" data-bind="cover"></div>`

  const rings = () =>
    `<svg class="rings" viewBox="0 0 200 200" aria-hidden="true">` +
    `<circle class="ring" cx="100" cy="100" r="98"/><circle class="ring" cx="100" cy="100" r="98"/>` +
    `<circle class="ring" cx="100" cy="100" r="98"/></svg>`

  const sonar = () =>
    `<div class="hero-sonar">${rings()}${coverSlot('hero-disc')}` +
    `<div class="hero-now"><b class="ellipsis" data-bind="title"></b><span data-bind="artist"></span></div></div>`

  const moodChips = (cls) =>
    D.MOODS.map((m) => `<button class="${cls}" data-act="mood" data-id="${m.id}">${m.name}</button>`).join('')

  const card = (item, i) =>
    `<button class="card" data-act="card" data-i="${i}">` +
    `<div class="cv card-cv">${cover(item.color, item.pattern)}<span class="card-play">${icon('play')}</span></div>` +
    `<div class="card-title ellipsis">${item.title}</div><div class="card-sub ellipsis">${item.sub}</div></button>`

  const trackRow = (t, withDur = true) =>
    `<button class="trow" data-act="track" data-id="${t.id}">` +
    `<div class="cv trow-cv">${cover(t.color, t.pattern)}<span class="eq"><i></i><i></i><i></i></span></div>` +
    `<div class="trow-meta"><span class="trow-title ellipsis">${t.title}</span>` +
    `<span class="trow-artist">${badge(t.service)}<span class="ellipsis">${t.artist}</span></span></div>` +
    (withDur ? `<span class="trow-dur">${S.fmt(t.dur)}</span>` : '<span></span>') +
    `</button>`

  const speedBtn = () => `<button class="speed" data-act="speed" data-bind="speed" title="Скорость">1×</button>`

  const slider = (cls, act, label) =>
    `<div class="slider ${cls}" data-act="${act}" role="slider" aria-label="${label}">` +
    `<span class="slider-fill"></span><span class="slider-knob"></span></div>`

  const empty = () =>
    `<div class="empty"><div class="empty-icon" data-bind="empty-icon"></div>` +
    `<div class="empty-title" data-bind="empty-title"></div>` +
    `<p class="empty-line">Этот экран появится в полном прототипе — сейчас сравниваем два варианта главной и плеера.</p>` +
    `<p class="empty-hint">Вернись на «Главную», чтобы продолжить.</p></div>`

  S.parts = Object.freeze({ playSwap, likeBtn, playBtn, coverSlot, rings, sonar, moodChips, card, trackRow, speedBtn, slider, empty })
})(window.Sonar)
