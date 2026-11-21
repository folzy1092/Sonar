// ПК: карта исполнителей. Узлы — кнопки, связи «похожи» — SVG в поле 1000×640.
// Тяни фон — двигаешь карту, колесо или +/− — масштаб. Выбранный исполнитель гасит всех, кроме соседей.
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon, cover } = S
  const M = S.more
  const H = S.h
  const W = 1000
  const HGT = 640
  const K_MIN = 0.5
  const K_MAX = 2.4
  const K_STEP = 1.2
  const FIT_PAD = 0.92
  const NODE_BASE = 44
  const NODE_PER_EDGE = 5

  const neighbours = (id) => M.MAP.edges.flatMap(([a, b]) => (a === id ? [b] : b === id ? [a] : []))
  const degree = (id) => neighbours(id).length

  // Вид карты живёт в DOM, не в состоянии: двигать и масштабировать нужно 60 раз в секунду
  let view = { x: 0, y: 0, k: 1 }
  const world = () => H.pc.querySelector('.map-world')
  const apply = () => {
    const w = world()
    if (!w) return
    w.style.setProperty('--mx', `${view.x}px`)
    w.style.setProperty('--my', `${view.y}px`)
    w.style.setProperty('--mk', view.k.toFixed(3))
  }
  const fit = () => {
    const st = H.pc.querySelector('.map-stage')
    if (!st) return
    const k = Math.min(st.clientWidth / W, st.clientHeight / HGT) * FIT_PAD
    view = { k, x: (st.clientWidth - W * k) / 2, y: (st.clientHeight - HGT * k) / 2 }
    apply()
  }
  const zoomAt = (factor, cx, cy) => {
    const k = Math.min(K_MAX, Math.max(K_MIN, view.k * factor))
    const r = k / view.k
    view = { k, x: cx - (cx - view.x) * r, y: cy - (cy - view.y) * r }
    apply()
  }
  const stageCenter = () => {
    const st = H.pc.querySelector('.map-stage')
    return st ? [st.clientWidth / 2, st.clientHeight / 2] : [0, 0]
  }

  const node = (id) => {
    const a = H.artist(id)
    const [x, y] = M.MAP.nodes[id]
    const size = NODE_BASE + degree(id) * NODE_PER_EDGE
    return `<button class="mnode" data-act="map-sel" data-id="${id}" style="--x:${x}px;--y:${y}px;--d:${size}px" aria-label="${H.esc(a.name)}">` +
      `<span class="cv round">${cover(a.color, a.pattern)}</span><span class="mnode-name">${H.esc(a.name)}</span></button>`
  }
  const edges = () => `<svg class="map-edges" viewBox="0 0 ${W} ${HGT}" aria-hidden="true">${M.MAP.edges.map(([a, b]) => {
    const [x1, y1] = M.MAP.nodes[a]
    const [x2, y2] = M.MAP.nodes[b]
    return `<line class="medge" data-a="${a}" data-b="${b}" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"/>`
  }).join('')}</svg>`

  const card = (s) => {
    if (!s.mapSel) {
      return `<div class="map-card hint">${icon('graph')}<b>Кто на кого похож</b><p>Нажми на исполнителя — подсветим похожих. Тяни, чтобы двигать, колесо — масштаб.</p>` +
        `<p class="set-note">Связи — из того, что ты слушаешь подряд, и из «похожих» SoundCloud и Яндекса. Соседи подмешиваются в Sonar Mix.</p></div>`
    }
    const a = H.artist(s.mapSel)
    const near = neighbours(a.id).map(H.artist)
    return `<div class="map-card pane-in"><span class="cv round map-card-cv">${cover(a.color, a.pattern)}</span>` +
      `<b class="sel">${H.esc(a.name)}</b><span>${a.genre} · ${a.listeners} слушателей</span>` +
      `<div class="map-card-btns"><button class="btn btn-accent sm" data-act="play-coll" data-to="artist/${a.id}">${icon('play')}<span>Слушать</span></button>` +
      `<button class="btn btn-soft sm" data-act="go" data-to="artist/${a.id}">Открыть</button></div>` +
      `<h3>Похожие · ${near.length}</h3><div class="map-near">${near.map((n) =>
        `<button class="chip" data-act="map-sel" data-id="${n.id}">${H.esc(n.name)}</button>`).join('')}</div></div>`
  }

  const markSel = (el, sel) => {
    const near = sel ? new Set([sel, ...neighbours(sel)]) : null
    el.querySelector('.map-stage').classList.toggle('has-sel', Boolean(sel))
    el.querySelectorAll('.mnode').forEach((n) => {
      n.classList.toggle('sel', n.dataset.id === sel)
      n.classList.toggle('near', Boolean(near && near.has(n.dataset.id)))
    })
    el.querySelectorAll('.medge').forEach((e) => e.classList.toggle('on', Boolean(sel) && (e.dataset.a === sel || e.dataset.b === sel)))
  }

  const render = (s) => `
    <div class="map-page">
      <header class="page-head"><div><div class="eyebrow">${icon('graph')}<span>${Object.keys(M.MAP.nodes).length} исполнителей · ${M.MAP.edges.length} связей</span></div><h1>Карта исполнителей</h1></div>
        <div class="map-tools">
          <button class="icon-btn" data-act="map-zoom" data-dir="-1" aria-label="Отдалить">${icon('zoomOut')}</button>
          <button class="icon-btn" data-act="map-zoom" data-dir="1" aria-label="Приблизить">${icon('zoomIn')}</button>
          <button class="icon-btn" data-act="map-fit" aria-label="Показать всю карту">${icon('target')}</button>
        </div></header>
      <div class="map-wrap">
        <div class="map-stage"><div class="map-world">${edges()}${Object.keys(M.MAP.nodes).map(node).join('')}</div></div>
        <aside class="map-side" data-map-card>${card(s)}</aside>
      </div>
    </div>`

  const after = (el, s) => {
    const stage = el.querySelector('.map-stage')
    if (!stage) return
    fit()
    markSel(el, s.mapSel)
    let drag = null
    stage.addEventListener('pointerdown', (ev) => {
      if (ev.target.closest('.mnode')) return
      drag = { px: ev.clientX, py: ev.clientY, x: view.x, y: view.y }
      stage.setPointerCapture(ev.pointerId)
      stage.classList.add('grab')
    })
    stage.addEventListener('pointermove', (ev) => {
      if (!drag) return
      const sc = S.app.scale
      view = { ...view, x: drag.x + (ev.clientX - drag.px) / sc, y: drag.y + (ev.clientY - drag.py) / sc }
      apply()
    })
    const stop = () => { drag = null; stage.classList.remove('grab') }
    stage.addEventListener('pointerup', stop)
    stage.addEventListener('pointercancel', stop)
    stage.addEventListener('wheel', (ev) => {
      ev.preventDefault()
      const r = stage.getBoundingClientRect()
      const sc = S.app.scale
      zoomAt(ev.deltaY < 0 ? K_STEP : 1 / K_STEP, (ev.clientX - r.left) / sc, (ev.clientY - r.top) / sc)
    }, { passive: false })
  }

  const update = (host, prev, next) => {
    if (prev.mapSel === next.mapSel) return
    markSel(host, next.mapSel)
    host.querySelector('[data-map-card]').innerHTML = card(next)
  }

  S.use({
    defaults: { mapSel: null },
    actions: {
      'map-sel': (s, el) => ({ mapSel: s.mapSel === el.dataset.id ? null : el.dataset.id }),
      'map-zoom': (s, el) => { zoomAt(Number(el.dataset.dir) > 0 ? K_STEP : 1 / K_STEP, ...stageCenter()); return {} },
      'map-fit': () => { fit(); return { mapSel: null } },
    },
    pages: {
      map: {
        render, after, update,
        empty: () => ({ icon: 'graph', title: 'Карта пока пустая', line: 'Она появится, когда в прослушиваниях наберётся хотя бы 20 исполнителей.' }),
      },
    },
    hash: { sel: (v) => (M.MAP.nodes[v] ? { mapSel: v } : {}) },
  })
})(window.Sonar)
