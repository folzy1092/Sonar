// ПК: сцены поверх всего окна — мини-окно на «рабочем столе», заставка при запуске и путь обновления
// (всплывашка → загрузка → перезапуск → заставка → тост). Включаются кнопками панели сверху или из интерфейса.
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon, logo } = S
  const P = S.parts
  const M = S.more
  const H = S.h
  const LEAVE_MS = 220
  const SPLASH_MS = 1400
  const PROGRESS_MS = 2400
  const RESTART_MS = 600

  let timers = []
  const later = (ms, fn) => { timers = [...timers, setTimeout(fn, ms)] }
  const stopTimers = () => { timers.forEach(clearTimeout); timers = [] }
  const set = (patch) => S.app.set(patch)

  // Заставка: знак проявляется, кольца расходятся — как при запуске и Ctrl+R
  const splash = (s) => `
    <div class="sc-splash"><div class="splash-mark">${P.rings()}${logo('splash-logo')}</div>
      <b class="splash-name">Sonar</b><span class="splash-line">${s.updateStage === 'done' ? `Версия ${M.UPDATE.version}` : 'Загружаем медиатеку…'}</span></div>`

  // Мини-окно: 340×96, поверх чужих окон, без перемотки — только управление и лайк
  const mini = () => `
    <div class="sc-desk">
      <div class="desk-win" aria-hidden="true"><div class="desk-bar"><i></i><i></i><i></i><span>Документ — Редактор</span></div>
        <div class="desk-lines">${Array.from({ length: 9 }, (_, i) => `<i style="--w:${[92, 80, 86, 60, 0, 88, 74, 90, 40][i]}%"></i>`).join('')}</div></div>
      <div class="mini" role="dialog" aria-label="Мини-плеер">
        ${P.coverSlot('mini-cv')}
        <div class="mini-meta fade-swap" data-bind="meta"><b class="sel ellipsis" data-bind="title"></b><span class="sel ellipsis" data-bind="artist"></span></div>
        <div class="mini-ctrls">
          <button class="icon-btn" data-act="prev" aria-label="Предыдущий">${icon('prev')}</button>
          ${P.playBtn('play-btn sm')}
          <button class="icon-btn" data-act="next" aria-label="Следующий">${icon('next')}</button>
        </div>
        <div class="mini-side">${P.likeBtn('sm')}<button class="icon-btn sm" data-act="scene-close" aria-label="Вернуть в окно" title="Вернуть в окно Sonar">${icon('expand')}</button></div>
        <span class="mini-prog"><i></i></span>
      </div>
      <div class="desk-task" aria-hidden="true"><span class="task-start"></span><span class="task-app on">${logo()}</span><span class="task-app"></span><span class="task-app"></span><span class="task-clock">22:41</span></div>
    </div>`

  const updateCard = (s) => {
    const u = M.UPDATE
    if (s.updateStage === 'card') {
      return `<div class="upd" role="dialog" aria-label="Доступно обновление">
        <div class="upd-head"><span class="upd-mark">${icon('download')}</span><div><b>Доступно обновление</b><span>Sonar ${u.version} · ${u.size}</span></div>
          <button class="icon-btn sm" data-act="scene-close" aria-label="Позже">${icon('close')}</button></div>
        <ul class="upd-notes">${u.notes.map((n, i) => `<li style="--i:${i}">${H.esc(n)}</li>`).join('')}</ul>
        <div class="upd-btns"><button class="btn btn-soft sm" data-act="scene-close">Позже</button><button class="btn btn-accent sm" data-act="update-go">Обновить сейчас</button></div>
      </div>`
    }
    const restart = s.updateStage === 'restart'
    return `<div class="upd upd-run" role="status"><div class="upd-head"><span class="upd-mark spin">${icon(restart ? 'refresh' : 'download')}</span>
      <div><b>${restart ? 'Перезапуск…' : 'Загружаем обновление'}</b><span>${restart ? 'Музыка продолжится с того же места' : `Sonar ${u.version} · ${u.size}`}</span></div></div>
      <span class="upd-bar${restart ? ' full' : ''}" style="--ms:${PROGRESS_MS}ms"><i></i></span></div>`
  }

  const sceneHtml = (s) => {
    if (s.scene === 'mini') return mini()
    if (s.scene === 'splash') return splash(s)
    if (s.scene === 'update') return updateCard(s)
    return ''
  }

  const renderScene = (prev, next) => {
    if (!H.changed(prev, next, ['scene', 'updateStage'])) return
    const host = S.pcShell.host('scene')
    host.querySelectorAll('.scene:not(.leaving)').forEach((el) => { el.classList.add('leaving'); setTimeout(() => el.remove(), LEAVE_MS) })
    H.pc.dataset.scene = next.scene || ''
    if (!next.scene) return
    host.insertAdjacentHTML('beforeend', `<div class="scene scene-${next.scene}">${sceneHtml(next)}</div>`)
    S.app.hydrate()
  }

  const runSplash = (then = {}) => {
    later(SPLASH_MS, () => set({ scene: null, updateStage: null, ...then }))
    return { scene: 'splash' }
  }

  const SCENES = {
    toast: () => ({ menu: null, ...S.app.toast('Добавлено в «Ночной город»') }),
    mini: () => ({ scene: 'mini', overlay: null }),
    splash: () => runSplash(),
    update: () => ({ scene: 'update', updateStage: 'card' }),
  }

  S.use({
    defaults: { scene: null, updateStage: null },
    actions: {
      scene: (s, el) => {
        stopTimers()
        const fn = SCENES[el.dataset.id || el.dataset.val]
        return fn ? fn(s) : {}
      },
      'scene-close': () => { stopTimers(); return { scene: null, updateStage: null } },
      'update-go': () => {
        stopTimers()
        later(PROGRESS_MS, () => set({ updateStage: 'restart' }))
        later(PROGRESS_MS + RESTART_MS, () => set({ updateStage: 'done', ...runSplash(S.app.toast(`Sonar обновлён до ${M.UPDATE.version}`)) }))
        return { updateStage: 'progress' }
      },
    },
    renderers: [{ fn: renderScene }],
    keys: (ev, s) => (ev.key === 'Escape' && s.scene ? (stopTimers(), { scene: null, updateStage: null }) : null),
    hash: { scene: (v) => (SCENES[v] && v !== 'toast' ? (v === 'update' ? { scene: v, updateStage: 'card' } : { scene: v }) : {}) },
  })
})(window.Sonar)
