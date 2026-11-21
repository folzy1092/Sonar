// iPhone: главная со вкладками, мини-плеер над ними и полноэкранный плеер,
// в который мини-плеер «перетекает» (FLIP: обложка летит из мини-плеера на своё место).
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon, logo } = S
  const P = S.parts
  const D = S.data

  const OPEN_MS = 450
  const CLOSE_MS = 380
  const BG_MS = 320
  const PART_MS = 320
  const PART_DELAY_MS = 70
  const PART_STEP_MS = 28
  const REDUCED_MS = 220
  const MINI_RADIUS = 9
  const SAFETY_MS = 80
  const EASE_OUT = 'cubic-bezier(.16, 1, .3, 1)'
  const EASE_STD = 'cubic-bezier(.4, 0, .2, 1)'

  const TABS = [
    { id: 'home', icon: 'home', label: 'Главная' },
    { id: 'search', icon: 'search', label: 'Поиск' },
    { id: 'library', icon: 'playlist', label: 'Медиатека' },
    { id: 'profile', icon: 'artist', label: 'Профиль' },
  ]

  const status = () => `
    <div class="ph-status">
      <span>9:41</span><span class="island"></span>
      <span class="st-icons">${icon('signal')}<span class="battery"></span></span>
    </div>`

  const hero = () => `
    <section class="ph-hero">
      <div class="eyebrow">${icon('mix')}<span data-bind="mood-name"></span></div>
      ${P.sonar()}
      <div class="ph-hero-foot">
        <div>
          <h2 class="hero-title">Sonar Mix</h2>
          <p class="hero-line" data-bind="mood-line"></p>
        </div>
        ${P.playBtn('hero-play')}
      </div>
    </section>`

  const home = () => `
    <div class="page" data-ppage="home">
      <div class="ph-head"><h1>Главная</h1><span class="avatar">F</span></div>
      ${hero()}
      <div class="ph-moods">${P.moodChips('chip-plain')}</div>
      <section class="ph-shelf">
        <div class="shelf-head"><h2>Недавнее</h2><button class="link">Все</button></div>
        <div class="ph-row">${D.RECENT.map((r, i) => P.card(r, i)).join('')}</div>
      </section>
      <section class="ph-shelf">
        <div class="shelf-head"><h2>Часто слушаешь</h2></div>
        <div class="ph-tracks">${D.TRACKS.slice(0, 5).map((t) => P.trackRow(t, false)).join('')}</div>
      </section>
      <section class="ph-shelf">
        <div class="shelf-head"><h2>Для тебя</h2></div>
        <div class="ph-row">${D.MIXES.map((m, i) => P.card(m, i + 10)).join('')}</div>
      </section>
    </div>`

  const mini = () => `
    <div class="ph-mini" data-act="open-player" role="button" aria-label="Открыть плеер">
      ${P.coverSlot('ph-mini-cv')}
      <div class="ph-mini-meta fade-swap" data-bind="meta">
        <b class="ellipsis" data-bind="title"></b><span class="ellipsis" data-bind="artist"></span>
      </div>
      ${P.playBtn('icon-btn')}
      <button class="icon-btn" data-act="next" aria-label="Следующий">${icon('next')}</button>
      <span class="ph-mini-prog"><i></i></span>
    </div>`

  const tabs = () => `
    <nav class="ph-tabs">
      ${TABS.map((t) => `<button class="ph-tab" data-act="tab" data-id="${t.id}" data-icon="${t.icon}" data-label="${t.label}">${icon(t.icon)}<span>${t.label}</span></button>`).join('')}
    </nav>`

  const player = () => `
    <section class="ph-player" aria-label="Плеер">
      <div class="pp-bg"></div>
      <div class="pp-top">
        <button class="icon-btn" data-act="close-player" aria-label="Свернуть">${icon('chevD')}</button>
        <div class="pp-from">Играет из<b>Sonar Mix · <span data-bind="mood-name"></span></b></div>
        <button class="icon-btn" aria-label="Ещё">${icon('more')}</button>
      </div>
      <div class="ph-cover-slot">${P.coverSlot('ph-cover-art')}</div>
      <div class="pp-meta">
        <div class="fade-swap" data-bind="meta">
          <div class="pp-title sel" data-bind="title"></div>
          <div class="pp-artist"><span data-bind="badge"></span><span class="sel ellipsis" data-bind="artist"></span></div>
        </div>
        ${P.likeBtn()}
      </div>
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
        <button class="icon-btn" data-act="shuffle" data-bind="shuffle" aria-label="Перемешать">${icon('shuffle')}</button>
        ${P.speedBtn()}
        <button class="icon-btn" aria-label="Текст">${icon('lyrics')}</button>
        <button class="icon-btn" aria-label="Очередь">${icon('queue')}</button>
        <button class="icon-btn" data-act="repeat" data-bind="repeat" aria-label="Повтор">${icon('repeat')}</button>
      </div>
    </section>`

  S.renderPhone = (root) => {
    root.innerHTML = `
      ${status()}
      <div class="ph-screen">
        ${home()}
        <div class="page" data-ppage="empty" hidden>${P.empty()}</div>
      </div>
      ${mini()}
      ${tabs()}
      ${player()}`
  }

  // ── Морф мини-плеер ⇄ полноэкранный плеер ─────────────
  let run = 0
  let live = []
  const track = (a) => { live = [...live, a]; return a }
  const PARTS = ['.pp-top', '.pp-meta', '.pp-prog', '.pp-ctrls', '.pp-vol', '.pp-foot']

  // Где обложка мини-плеера относительно места большой обложки (в единицах фрейма, без масштаба сцены)
  const miniOffset = (root, scale) => {
    const from = root.querySelector('.ph-mini-cv').getBoundingClientRect()
    const to = root.querySelector('.ph-cover-slot').getBoundingClientRect()
    const k = from.width / to.width
    return { dx: (from.left - to.left) / scale, dy: (from.top - to.top) / scale, k }
  }

  const finalRadius = (art) => parseFloat(getComputedStyle(art).borderTopLeftRadius) || 20

  const animateOpen = (root, scale) => {
    const slot = root.querySelector('.ph-cover-slot')
    const art = root.querySelector('.ph-cover-art')
    const { dx, dy, k } = miniOffset(root, scale)
    const r = finalRadius(art)
    track(slot.animate(
      [{ transform: `translate(${dx}px, ${dy}px) scale(${k})` }, { transform: 'none' }],
      { duration: OPEN_MS, easing: EASE_OUT },
    ))
    track(art.animate([{ borderRadius: `${MINI_RADIUS / k}px` }, { borderRadius: `${r}px` }], { duration: OPEN_MS, easing: EASE_OUT }))
    track(root.querySelector('.pp-bg').animate([{ opacity: 0 }, { opacity: 1 }], { duration: BG_MS, easing: EASE_STD }))
    PARTS.forEach((sel, i) => {
      track(root.querySelector(sel).animate(
        [{ opacity: 0, transform: 'translateY(14px)' }, { opacity: 1, transform: 'none' }],
        { duration: PART_MS, delay: PART_DELAY_MS + i * PART_STEP_MS, easing: EASE_OUT, fill: 'backwards' },
      ))
    })
  }

  const animateClose = (root, scale, done) => {
    const slot = root.querySelector('.ph-cover-slot')
    const art = root.querySelector('.ph-cover-art')
    const { dx, dy, k } = miniOffset(root, scale)
    const r = finalRadius(art)
    const opts = { duration: CLOSE_MS, easing: EASE_STD, fill: 'forwards' }
    const anims = [
      slot.animate([{ transform: 'none' }, { transform: `translate(${dx}px, ${dy}px) scale(${k})` }], opts),
      art.animate([{ borderRadius: `${r}px` }, { borderRadius: `${MINI_RADIUS / k}px` }], opts),
      root.querySelector('.pp-bg').animate([{ opacity: 1 }, { opacity: 0 }], opts),
      ...PARTS.map((sel) =>
        root.querySelector(sel).animate([{ opacity: 1 }, { opacity: 0, transform: 'translateY(10px)' }], { ...opts, duration: CLOSE_MS / 2 }),
      ),
    ].map(track)
    afterAnim(anims[0], CLOSE_MS, () => { done(); anims.forEach((a) => a.cancel()) })
  }

  // Конец анимации со страховкой: если вкладка не рисует кадры, таймер всё равно закончит дело
  const afterAnim = (anim, ms, fn) => {
    let fired = false
    const once = () => { if (!fired) { fired = true; fn() } }
    anim.finished.then(once).catch(() => {})
    setTimeout(once, ms + SAFETY_MS)
  }

  const fadePlayer = (root, open, done) => {
    const a = track(root.querySelector('.ph-player').animate(
      [{ opacity: open ? 0 : 1 }, { opacity: open ? 1 : 0 }],
      { duration: REDUCED_MS, easing: EASE_STD, fill: open ? 'none' : 'forwards' },
    ))
    if (!open) afterAnim(a, REDUCED_MS, () => { done(); a.cancel() })
  }

  S.phoneMorph = (root, open, scale, animate) => {
    const id = ++run
    live.forEach((a) => a.cancel())
    live = []
    const finishClose = () => { if (id === run) root.classList.remove('player-open') }
    if (open) root.classList.add('player-open')
    if (!animate) { if (!open) root.classList.remove('player-open'); return }
    const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches
    if (reduced) { fadePlayer(root, open, finishClose); return }
    if (open) animateOpen(root, scale)
    else animateClose(root, scale, finishClose)
  }
})(window.Sonar)
