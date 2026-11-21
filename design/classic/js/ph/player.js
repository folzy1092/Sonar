// iPhone: полноэкранный плеер — обложка, управление, панели «Текст» (караоке) и «Очередь».
// Открывается морфом из мини-плеера (morph.js). С открытой панелью большая обложка уступает место
// компактной шапке, а панель занимает всё свободное место.
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon } = S
  const P = S.parts
  const H = S.h
  const F = Object.freeze
  const PANES = F(['lyrics', 'queue'])
  const PANE_DEPS = F({ lyrics: F(['index', 'ppane']), queue: F(['index', 'ppane', 'upnext', 'src', 'mood', 'shuffle']) })

  const artistBtn = (cls) =>
    `<button class="${cls}" data-act="go" data-bind="artist-link"><span data-bind="badge"></span><span class="sel ellipsis" data-bind="artist"></span></button>`

  const footBtn = (act, ic, label, attrs = '') =>
    `<button class="icon-btn" data-act="${act}"${attrs} aria-label="${label}">${icon(ic)}</button>`

  const html = () => `
    <section class="ph-player" aria-label="Плеер">
      <div class="pp-bg"></div>
      <div class="pp-top">
        <button class="icon-btn" data-act="close-player" aria-label="Свернуть">${icon('chevD')}</button>
        <div class="pp-from">Играет из<b class="ellipsis" data-bind="source"></b></div>
        <button class="icon-btn" data-act="ph-cur-menu" aria-label="Ещё">${icon('more')}</button>
      </div>
      <div class="ph-cover-slot">${P.coverSlot('ph-cover-art')}</div>
      <div class="pp-head">
        ${P.coverSlot('pp-head-cv')}
        <div class="pp-head-meta fade-swap" data-bind="meta"><b class="sel ellipsis" data-bind="title"></b>${artistBtn('pp-head-artist')}</div>
        ${P.likeBtn()}
      </div>
      <div class="pp-meta">
        <div class="pp-titles fade-swap" data-bind="meta">
          <div class="pp-title sel" data-bind="title"></div>
          ${artistBtn('pp-artist')}
        </div>
        ${P.likeBtn()}
      </div>
      <div class="pp-pane" data-pane></div>
      <div class="pp-ann" data-ann-host></div>
      <div class="pp-prog">
        ${P.slider('prog', 'seek', 'Перемотка')}
        <div class="pp-times"><span data-bind="cur">0:00</span><span data-bind="left">−0:00</span></div>
      </div>
      <div class="pp-ctrls">
        <button class="icon-btn" data-act="prev" aria-label="Предыдущий">${icon('prev')}</button>
        ${P.playBtn('pp-play')}
        <button class="icon-btn" data-act="next" aria-label="Следующий">${icon('next')}</button>
      </div>
      <div class="pp-vol">${icon('volLow')}${P.slider('vol', 'vol', 'Громкость')}${icon('volHigh')}</div>
      <div class="pp-foot">
        ${footBtn('shuffle', 'shuffle', 'Перемешать', ' data-bind="shuffle"')}
        ${P.speedBtn()}
        ${footBtn('ph-pane', 'lyrics', 'Текст', ' data-id="lyrics"')}
        ${footBtn('ph-pane', 'queue', 'Очередь', ' data-id="queue"')}
        ${footBtn('repeat', 'repeat', 'Повтор', ' data-bind="repeat"')}
      </div>
    </section>`

  const playerEl = () => H.ph.querySelector('.ph-player')

  const renderOpen = (prev, next) => {
    if (!H.changed(prev, next, ['popen'])) return
    S.phoneMorph(H.ph, next.popen, S.app.scale, Boolean(prev))
  }

  // Панель: текст с караоке или очередь. У караоке свой цикл кадров — при закрытии панели он стоп.
  const renderPane = (prev, next) => {
    const key = next.ppane
    const deps = key ? PANE_DEPS[key] : ['ppane']
    if (!H.changed(prev, next, deps)) return
    const el = playerEl()
    const pane = el.querySelector('[data-pane]')
    el.classList.toggle('pane-on', Boolean(key))
    el.querySelectorAll('[data-act="ph-pane"]').forEach((b) => {
      const on = b.dataset.id === key
      b.classList.toggle('on', on)
      b.setAttribute('aria-pressed', String(on))
    })
    if (!key) { S.lyrics.stop(pane); pane.innerHTML = ''; return }
    pane.classList.remove('pane-in')
    pane.innerHTML = key === 'queue' ? S.queueView(next, 'ph') : S.lyrics.pane(next)
    void pane.offsetWidth
    pane.classList.add('pane-in')
    S.app.hydrate()
    if (key === 'lyrics') S.lyrics.start(pane)
    else S.lyrics.stop(pane)
  }

  const renderAnn = (prev, next) => {
    if (!H.changed(prev, next, ['ann', 'index', 'ppane'])) return
    playerEl().querySelector('[data-ann-host]').innerHTML = next.ppane === 'lyrics' ? S.lyrics.ann(next) : ''
  }

  S.use({
    defaults: { popen: false, ppane: null },
    actions: {
      'open-player': () => ({ popen: true }),
      'close-player': () => ({ popen: false, ann: null }),
      'ph-pane': (s, el) => ({ ppane: s.ppane === el.dataset.id ? null : el.dataset.id, ann: null }),
      'ph:drawer': () => ({ popen: true, ppane: 'queue' }),
    },
    renderers: [renderPane, renderAnn, renderOpen],
    hash: {
      popen: (v) => ({ popen: v === '1' }),
      ppane: (v) => (PANES.includes(v) ? { ppane: v, popen: true } : {}),
    },
  })
  S.phonePlayer = F({ html })
})(window.Sonar)
