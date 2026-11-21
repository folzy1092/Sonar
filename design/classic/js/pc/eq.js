// ПК: эквалайзер на 12 полос, ±12 дБ. Ползунки тянутся мышью, кривая — сглаженный SVG-путь.
// Тронул полосу — пресет становится «Свой». Выключен — кривая гаснет, звук идёт ровно.
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon } = S
  const M = S.more
  const H = S.h
  const F = Object.freeze
  const DB_MAX = 12
  const CURVE_W = 600
  const CURVE_H = 140

  const toY = (db) => CURVE_H / 2 - (db / DB_MAX) * (CURVE_H / 2 - 8)
  // Кривая Катмулла — Рома через точки полос, переведённая в кубические Безье
  const curvePath = (bands) => {
    const pts = bands.map((db, i) => [(i / (bands.length - 1)) * CURVE_W, toY(db)])
    const at = (i) => pts[Math.max(0, Math.min(pts.length - 1, i))]
    return pts.reduce((d, p, i) => {
      if (i === 0) return `M${p[0]},${p[1].toFixed(1)}`
      const [p0, p1, p2, p3] = [at(i - 2), at(i - 1), p, at(i + 1)]
      const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6]
      const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6]
      return `${d} C${c1[0].toFixed(1)},${c1[1].toFixed(1)} ${c2[0].toFixed(1)},${c2[1].toFixed(1)} ${p2[0]},${p2[1].toFixed(1)}`
    }, '')
  }
  const fmtDb = (db) => (db > 0 ? `+${db}` : String(db))

  const presets = (s) => [...Object.entries(M.EQ_PRESETS), ['custom', { name: 'Свой' }]].map(([id, p]) =>
    `<button class="chip${s.eqPreset === id ? ' on' : ''}" data-act="eq-preset" data-id="${id}"${id === 'custom' ? ' disabled' : ''}>${p.name}</button>`).join('')

  const band = (db, i) =>
    `<div class="eq-band" data-band="${i}" style="--db:${db}"><span class="eq-val">${fmtDb(db)}</span>` +
    `<div class="eq-rail" role="slider" aria-label="${M.EQ_BANDS[i]} Гц" aria-valuemin="-12" aria-valuemax="12" aria-valuenow="${db}"><span class="eq-zero"></span><span class="eq-fill"></span><span class="eq-knob"></span></div>` +
    `<span class="eq-hz">${M.EQ_BANDS[i]}</span></div>`

  const render = (s) => `
    <div class="eqp${s.eqOn ? '' : ' off'}" role="dialog" aria-label="Эквалайзер">
      <header class="eqp-head">
        <div><h2>Эквалайзер</h2><p>12 полос · применяется ко всем сервисам и файлам</p></div>
        <button class="tgl${s.eqOn ? ' on' : ''}" data-act="toggle" data-key="eqOn" role="switch" aria-checked="${s.eqOn}" aria-label="Включить эквалайзер"><i></i></button>
        <button class="icon-btn" data-act="close-overlay" aria-label="Закрыть">${icon('close')}</button>
      </header>
      <div class="eq-presets">${presets(s)}</div>
      <svg class="eq-curve" viewBox="0 0 ${CURVE_W} ${CURVE_H}" preserveAspectRatio="none" aria-hidden="true">
        <line x1="0" x2="${CURVE_W}" y1="${CURVE_H / 2}" y2="${CURVE_H / 2}" class="eq-mid"/>
        <path class="eq-area" d="${curvePath(s.eqBands)} L${CURVE_W},${CURVE_H} L0,${CURVE_H} Z"/>
        <path class="eq-line" d="${curvePath(s.eqBands)}"/>
      </svg>
      <div class="eq-bands">${s.eqBands.map(band).join('')}</div>
      <footer class="eqp-foot"><span>${icon('info')} Двойной клик по полосе — вернуть в 0</span>
        <button class="btn btn-soft sm" data-act="eq-preset" data-id="flat">${icon('refresh')}<span>Сбросить</span></button></footer>
    </div>`

  const update = (el, prev, next) => {
    if (!H.changed(prev, next, ['eqBands', 'eqOn', 'eqPreset'])) return
    el.querySelector('.eqp').classList.toggle('off', !next.eqOn)
    const tgl = el.querySelector('.tgl')
    tgl.classList.toggle('on', next.eqOn)
    tgl.setAttribute('aria-checked', String(next.eqOn))
    el.querySelector('.eq-presets').innerHTML = presets(next)
    const d = curvePath(next.eqBands)
    el.querySelector('.eq-line').setAttribute('d', d)
    el.querySelector('.eq-area').setAttribute('d', `${d} L${CURVE_W},${CURVE_H} L0,${CURVE_H} Z`)
    next.eqBands.forEach((db, i) => {
      const b = el.querySelector(`[data-band="${i}"]`)
      b.style.setProperty('--db', db)
      b.querySelector('.eq-val').textContent = fmtDb(db)
      b.querySelector('.eq-rail').setAttribute('aria-valuenow', db)
    })
  }

  const withBand = (bands, i, db) => F(bands.map((x, j) => (j === i ? db : x)))
  const dbAt = (rail, ev) => {
    const r = rail.getBoundingClientRect()
    const k = 1 - Math.min(1, Math.max(0, (ev.clientY - r.top) / r.height))
    return Math.round((k * 2 - 1) * DB_MAX)
  }

  // Перетаскивание: pointer capture на полосе, каждое движение — новое состояние
  const after = (el) => {
    el.querySelectorAll('.eq-band').forEach((b) => {
      const i = Number(b.dataset.band)
      const rail = b.querySelector('.eq-rail')
      const setDb = (ev) => {
        const s = S.app.state
        const db = dbAt(rail, ev)
        if (s.eqBands[i] !== db) S.app.set({ eqBands: withBand(s.eqBands, i, db), eqPreset: 'custom', eqOn: true })
      }
      rail.addEventListener('pointerdown', (ev) => {
        rail.setPointerCapture(ev.pointerId)
        b.classList.add('drag')
        setDb(ev)
      })
      rail.addEventListener('pointermove', (ev) => { if (rail.hasPointerCapture(ev.pointerId)) setDb(ev) })
      rail.addEventListener('pointerup', () => b.classList.remove('drag'))
      rail.addEventListener('dblclick', () => S.app.set({ eqBands: withBand(S.app.state.eqBands, i, 0), eqPreset: 'custom' }))
    })
  }

  S.use({
    defaults: { eqOn: true, eqPreset: 'bass', eqBands: M.EQ_PRESETS.bass.bands },
    actions: {
      'eq-preset': (s, el) => (M.EQ_PRESETS[el.dataset.id] ? { eqPreset: el.dataset.id, eqBands: M.EQ_PRESETS[el.dataset.id].bands, eqOn: true } : {}),
    },
    overlays: { eq: { render, update, after } },
  })
})(window.Sonar)
