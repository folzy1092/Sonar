// iPhone: морф мини-плеер ⇄ полноэкранный плеер. Обложка мини-плеера вырастает в большую,
// фон проявляется, части плеера всплывают лесенкой. «Меньше движения» и открытая панель
// (текст или очередь — большой обложки нет) — только прозрачность.
window.Sonar = window.Sonar || {}
;(function (S) {
  const H = S.h
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

  const coverHidden = (root) => root.querySelector('.ph-cover-slot').getBoundingClientRect().width === 0

  S.phoneMorph = (root, open, scale, animate) => {
    const id = ++run
    live.forEach((a) => a.cancel())
    live = []
    const finishClose = () => { if (id === run) root.classList.remove('player-open') }
    if (open) root.classList.add('player-open')
    if (!animate) { if (!open) root.classList.remove('player-open'); return }
    if (H.reducedMotion(root) || coverHidden(root)) { fadePlayer(root, open, finishClose); return }
    if (open) animateOpen(root, scale)
    else animateClose(root, scale, finishClose)
  }
})(window.Sonar)
