// ПК: полноэкранный плеер — обложка, управление и текст с караоке по словам, пояснения к строкам.
// Ещё здесь S.queueView(s, where) — очередь для выдвижной панели, вкладки плеера и iPhone,
// и S.lyrics — текст с караоке, его же показывает плеер iPhone.
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon, badge } = S
  const P = S.parts
  const M = S.more
  const H = S.h
  const LINE_ANCHOR = 0.36
  const NEXT_SHOWN = 6

  // ── Очередь ───────────────────────────────────────────
  const qRow = (t, extra = '') =>
    `<div class="q-row trow" data-act="track" data-id="${t.id}" data-tid="${t.id}" role="button" tabindex="0">` +
    `<span class="cv q-cv">${S.cover(t.color, t.pattern)}<span class="eq"><i></i><i></i><i></i></span></span>` +
    `<span class="trow-meta"><span class="trow-title ellipsis">${H.esc(t.title)}</span><span class="trow-artist">${badge(t.service)}<span class="ellipsis">${H.esc(t.artist)}</span></span></span>` +
    `${extra || `<span class="trow-dur">${S.fmt(t.dur)}</span>`}</div>`

  const upcoming = (s) => {
    const ids = S.player.order(s)
    const i = ids.indexOf(H.trackOf(s).id)
    return Array.from({ length: Math.min(NEXT_SHOWN, ids.length - 1) }, (_, k) => H.track(ids[(i + 1 + k) % ids.length]))
  }

  S.queueView = (s, where) => {
    const cur = H.trackOf(s)
    const up = s.upnext.map(H.track)
    const drop = (i) => `<button class="icon-btn sm" data-act="drop-queue" data-i="${i}" aria-label="Убрать из очереди">${icon('close')}</button>`
    return `<div class="queue queue-${where}">` +
      (where === 'drawer' ? `<div class="q-top"><h2>Очередь</h2><button class="icon-btn sm" data-act="drawer" data-id="queue" aria-label="Закрыть">${icon('close')}</button></div>` : '') +
      `<div class="q-label">Сейчас играет</div>${qRow(cur)}` +
      `<div class="q-label">Далее в очереди${up.length ? `<button class="tlink" data-act="clear-queue">Очистить</button>` : ''}</div>` +
      (up.length
        ? up.map((t, i) => qRow(t, drop(i))).join('')
        : `<p class="q-empty">Пусто. «Сыграть следующим» в меню трека добавит сюда.</p>`) +
      `<div class="q-label">Дальше из: <b data-bind="source">${H.esc(S.player.sourceLabel(s))}</b>${s.shuffle ? ` · ${icon('shuffle', 'q-ic')} вперемешку` : ''}</div>` +
      upcoming(s).map((t) => qRow(t)).join('') + `</div>`
  }

  // ── Текст ─────────────────────────────────────────────
  const lyricsOf = (s) => M.LYRICS[H.trackOf(s).id] || null

  // Слова строки с долями времени: длинное слово поётся дольше
  const wordsHtml = (text) => {
    const words = text.split(' ')
    const total = H.sum(words.map((w) => w.length + 1))
    let acc = 0
    return words.map((w) => {
      const a = acc / total
      acc += w.length + 1
      return `<span class="w" data-a="${a.toFixed(4)}" data-b="${(acc / total).toFixed(4)}">${H.esc(w)}</span>`
    }).join(' ')
  }

  const lineHtml = (l, i, lines) => {
    if (l.end) return ''
    if (!l.text) return `<div class="ly-line ly-gap" data-i="${i}"><span class="dots"><i></i><i></i><i></i></span></div>`
    return `<div class="ly-line" data-i="${i}" data-t="${l.t}" data-e="${lines[i + 1].t}">` +
      `<button class="ly-text" data-act="ly-seek" data-t="${l.t}">${wordsHtml(l.text)}</button>` +
      (l.ann ? `<button class="ann-btn" data-act="ann" data-i="${i}" aria-label="Пояснение">${icon('info')}</button>` : '') + `</div>`
  }

  const annHtml = (s) => {
    const lines = lyricsOf(s)
    const l = lines && s.ann !== null ? lines[s.ann] : null
    if (!l || !l.ann) return ''
    return `<div class="ann" role="dialog"><div class="ann-q">«${H.esc(l.text)}»</div><p>${H.esc(l.ann)}</p>` +
      `<div class="ann-src">${icon('external')} Genius · пояснение сообщества</div></div>`
  }

  const lyricsPane = (s) => {
    const lines = lyricsOf(s)
    if (!lines) {
      return `<div class="ly-none">${P.empty({ icon: 'lyrics', title: 'Текста пока нет', line: 'Ни lrclib, ни Genius не знают эту песню. Можно найти вручную — Sonar запомнит.', action: { act: 'noop', label: 'Найти текст' } })}</div>`
    }
    return `<div class="ly-scroll"><div class="ly-track">${lines.map(lineHtml).join('')}</div></div>` +
      `<div class="ly-src">Текст: lrclib · синхронизация по словам</div>`
  }

  const tabs = (s) => [['lyrics', 'Текст'], ['queue', 'Очередь']].map(([id, n]) =>
    `<button class="seg-b${s.fullTab === id ? ' on' : ''}" data-act="set" data-key="fullTab" data-val="${id}">${n}</button>`).join('')

  const render = (s) => `
    <div class="full">
      <div class="full-bg" aria-hidden="true"><i></i><i></i><i></i></div>
      <header class="full-top">
        <button class="icon-btn" data-act="close-overlay" aria-label="Свернуть">${icon('chevD')}</button>
        <div class="full-src">Играет из <b data-bind="source"></b></div>
        <div class="seg">${tabs(s)}</div>
      </header>
      <section class="full-left">
        <div class="full-cv-wrap">${P.coverSlot('full-cv')}</div>
        <div class="full-meta" data-bind="meta">
          <div class="full-titles"><h1 class="full-title sel" data-bind="title"></h1>
          <button class="full-artist sel" data-bind="artist-link" data-act="go"><span data-bind="badge"></span><span data-bind="artist"></span></button></div>
          ${P.likeBtn('lg')}
        </div>
        <div class="prog-row"><span class="time" data-bind="cur">0:00</span>${P.slider('prog', 'seek', 'Перемотка')}<span class="time" data-bind="left"></span></div>
        <div class="ctrls lg">
          <button class="icon-btn" data-act="shuffle" data-bind="shuffle" aria-label="Перемешать">${icon('shuffle')}</button>
          <button class="icon-btn" data-act="prev" aria-label="Назад">${icon('prev')}</button>
          ${P.playBtn('play-btn xl')}
          <button class="icon-btn" data-act="next" aria-label="Дальше">${icon('next')}</button>
          <button class="icon-btn" data-act="repeat" data-bind="repeat" aria-label="Повтор">${icon('repeat')}</button>
        </div>
        <div class="full-tools">${P.speedBtn()}<button class="icon-btn" data-act="overlay" data-id="eq" aria-label="Эквалайзер">${icon('eq')}</button>
          <button class="icon-btn" data-act="mute" data-bind="mute" aria-label="Звук">${icon('volHigh')}</button>${P.slider('vol', 'vol', 'Громкость')}</div>
      </section>
      <section class="full-right" data-pane>${s.fullTab === 'queue' ? S.queueView(s, 'full') : lyricsPane(s)}</section>
      <div data-ann-host>${annHtml(s)}</div>
    </div>`

  // ── Караоке: кадр за кадром по S.app.posNow() ─────────
  // Свой цикл у каждого слоя с текстом (ПК и iPhone могут показывать текст одновременно)
  const frame = (el) => () => {
    if (!el.isConnected) { el._raf = 0; return }
    el._raf = requestAnimationFrame(frame(el))
    const track = el.querySelector('.ly-track')
    if (!track) return
    const pos = S.app.posNow()
    const lines = [...track.querySelectorAll('.ly-line')]
    let cur = -1
    lines.forEach((ln, i) => {
      const t = Number(ln.dataset.t ?? Number.POSITIVE_INFINITY)
      if (ln.dataset.t !== undefined && pos >= t) cur = i
      else if (ln.classList.contains('ly-gap')) {
        const prev = lines[i - 1]
        if (prev && pos >= Number(prev.dataset.e)) cur = i
      }
    })
    lines.forEach((ln, i) => {
      ln.classList.toggle('on', i === cur)
      ln.classList.toggle('past', i < cur)
      if (i !== cur || ln.dataset.t === undefined) return
      const k = (pos - Number(ln.dataset.t)) / (Number(ln.dataset.e) - Number(ln.dataset.t))
      ln.querySelectorAll('.w').forEach((w) => {
        const a = Number(w.dataset.a)
        const b = Number(w.dataset.b)
        w.style.setProperty('--k', Math.max(0, Math.min(1, (k - a) / (b - a))).toFixed(3))
      })
    })
    const on = lines[Math.max(0, cur)]
    const box = el.querySelector('.ly-scroll')
    if (!on || !box || track.dataset.cur === String(cur)) return
    track.dataset.cur = String(cur)
    track.style.transform = `translateY(${Math.round(box.clientHeight * LINE_ANCHOR - on.offsetTop - on.offsetHeight / 2)}px)`
  }
  const stopKaraoke = (el) => { cancelAnimationFrame(el._raf || 0); el._raf = 0 }
  const startKaraoke = (el) => { stopKaraoke(el); el._raf = requestAnimationFrame(frame(el)) }
  S.lyrics = Object.freeze({ pane: lyricsPane, ann: annHtml, start: startKaraoke, stop: stopKaraoke })

  const update = (el, prev, next) => {
    const pane = el.querySelector('[data-pane]')
    const swapLyrics = next.fullTab === 'lyrics' && H.changed(prev, next, ['index', 'fullTab'])
    const swapQueue = next.fullTab === 'queue' && H.changed(prev, next, ['index', 'fullTab', 'upnext', 'src', 'mood', 'shuffle'])
    if (H.changed(prev, next, ['fullTab'])) el.querySelector('.seg').innerHTML = tabs(next)
    if (swapLyrics || swapQueue) {
      pane.classList.remove('pane-in')
      pane.innerHTML = next.fullTab === 'queue' ? S.queueView(next, 'full') : lyricsPane(next)
      void pane.offsetWidth
      pane.classList.add('pane-in')
      S.app.hydrate()
    }
    if (H.changed(prev, next, ['ann', 'index'])) el.querySelector('[data-ann-host]').innerHTML = annHtml(next)
  }

  S.use({
    defaults: { fullTab: 'lyrics' },
    actions: {
      'ly-seek': (s, el) => ({ pos: Number(el.dataset.t), playing: true }),
      ann: (s, el) => ({ ann: s.ann === Number(el.dataset.i) ? null : Number(el.dataset.i) }),
    },
    overlays: {
      full: { render, update, after: (el) => startKaraoke(el), leave: stopKaraoke },
    },
    hash: { tab: (v) => (['lyrics', 'queue'].includes(v) ? { fullTab: v } : {}), ann: (v) => ({ ann: Number(v) }) },
  })
})(window.Sonar)
