// ПК: статистика за неделю, месяц и год (из своих прослушиваний) и итоги года — «истории».
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon, cover, badge } = S
  const P = S.parts
  const D = S.data
  const M = S.more
  const H = S.h
  const F = Object.freeze
  const STORY_MS = 5000
  const MONTH_LABEL_EVERY = 5

  const RANGES = F([['week', 'Неделя'], ['month', 'Месяц'], ['year', 'Год']])
  const KPIS = F([
    ['minutes', 'минут музыки', 'clock'], ['tracks', 'прослушиваний', 'note'],
    ['artists', 'исполнителей', 'artist'], ['fresh', 'новых для тебя', 'flame'],
  ])
  const PLAYS = ['прослушивание', 'прослушивания', 'прослушиваний']

  const rangeSeg = () => `<div class="seg" role="radiogroup">${RANGES.map(([v, l]) =>
    `<button class="seg-b" data-act="set" data-key="statsRange" data-val="${v}" role="radio">${l}</button>`).join('')}</div>`
  const markRange = (scope, v) => scope.querySelectorAll('[data-key="statsRange"]').forEach((b) => b.classList.toggle('on', b.dataset.val === v))

  const kpi = (st) => `<div class="kpis">${KPIS.map(([k, label, ic], i) =>
    `<div class="kpi" style="--i:${i}">${icon(ic)}<b data-count="${st[k]}">${st[k].toLocaleString('ru-RU')}</b><span>${label}</span></div>`).join('')}</div>`

  const bars = (st, range) => {
    const max = Math.max(...st.bars)
    const label = (l, i) => (range !== 'month' || i % MONTH_LABEL_EVERY === 0 ? l : '')
    return `<div class="bars bars-${range}" role="img" aria-label="Минуты по дням">${st.bars.map((v, i) =>
      `<div class="bar" style="--k:${(v / max).toFixed(3)};--i:${i}" title="${st.labels[i]} — ${v.toLocaleString('ru-RU')} мин"><i></i><span>${label(st.labels[i], i)}</span></div>`).join('')}</div>`
  }

  const topArtists = (st) => {
    const max = st.top[0][1]
    return st.top.map(([id, n], i) => {
      const a = H.artist(id)
      return `<button class="top-row" data-act="go" data-to="artist/${id}" style="--i:${i}"><span class="top-n">${i + 1}</span>` +
        `<span class="cv round top-cv">${cover(a.color, a.pattern)}</span><span class="top-meta"><b class="ellipsis">${H.esc(a.name)}</b>` +
        `<span class="top-bar"><i style="--k:${(n / max).toFixed(3)}"></i></span></span><span class="top-c">${H.tn(n, PLAYS)}</span></button>`
    }).join('')
  }

  const topTracks = (st) => st.tracks5.map(([id, n], i) => {
    const t = H.track(id)
    return `<div class="top-row trow" data-act="track" data-id="${id}" data-tid="${id}" role="button" tabindex="0" style="--i:${i}"><span class="top-n">${i + 1}</span>` +
      `<span class="cv top-cv">${cover(t.color, t.pattern)}</span><span class="top-meta"><b class="ellipsis">${H.esc(t.title)}</b>` +
      `<span class="trow-artist">${badge(t.service)}<span class="ellipsis">${H.esc(t.artist)}</span></span></span><span class="top-c">${n}×</span></div>`
  }).join('')

  const services = (st) =>
    `<div class="svc-bar">${st.services.map(([id, p], i) => `<i style="--w:${p};--i:${i}" title="${D.SERVICES[id].name} — ${p} %"></i>`).join('')}</div>` +
    `<ul class="svc-legend">${st.services.map(([id, p], i) => `<li style="--i:${i}"><i></i>${badge(id)}<span>${D.SERVICES[id].name}</span><b>${p} %</b></li>`).join('')}</ul>`

  const body = (s) => {
    const st = M.STATS[s.statsRange]
    return `<div class="stats-body">${kpi(st)}
      <section class="panel panel-wide"><div class="panel-head"><h2>Сколько слушал</h2><span>${H.dur(st.minutes * 60)} за ${st.label.toLowerCase()}</span></div>${bars(st, s.statsRange)}</section>
      <section class="panel"><div class="panel-head"><h2>Исполнители</h2></div>${topArtists(st)}</section>
      <section class="panel"><div class="panel-head"><h2>Треки</h2></div>${topTracks(st)}</section>
      <section class="panel panel-wide"><div class="panel-head"><h2>Откуда музыка</h2><span>Все сервисы в одной медиатеке</span></div>${services(st)}</section></div>`
  }

  const recapBanner = () => {
    const r = M.RECAP[0]
    return `<button class="recap-banner" data-act="recap"><span class="recap-bg">${cover(r.color, r.pattern)}</span>` +
      `<span class="recap-txt"><span class="eyebrow">${icon('flame')}<span>Готово</span></span><b>Итоги 2026</b><span>Артист, трек и настроение года — пять историй</span></span>` +
      `<span class="recap-go">${icon('play')}</span></button>`
  }

  const statsPage = (s) => `
    <header class="page-head"><div><div class="eyebrow">${icon('stats')}<span>Из твоих прослушиваний в Sonar</span></div><h1>Статистика</h1></div>${rangeSeg()}</header>
    ${recapBanner()}
    <div data-stats>${body(s)}</div>`

  const statsUpdate = (host, prev, next) => {
    if (prev.statsRange === next.statsRange) return
    const el = host.querySelector('[data-stats]')
    if (!el) return
    el.innerHTML = body(next)
    el.firstElementChild.classList.add('pane-in')
    markRange(host, next.statsRange)
    S.app.hydrate()
    H.countUp(el)
  }

  // ── Итоги: истории ────────────────────────────────────
  let storyTimer = 0
  const arm = (i) => {
    clearTimeout(storyTimer)
    storyTimer = setTimeout(() => {
      const s = S.app.state
      if (s.overlay !== 'recap' || s.recapI !== i) return
      S.app.set(i + 1 < M.RECAP.length ? { recapI: i + 1 } : { overlay: null })
    }, STORY_MS)
  }

  const storyArt = (r) => {
    if (r.kind === 'artist') { const a = H.artist(r.aid); return `<span class="cv round rc-art">${cover(a.color, a.pattern)}</span>` }
    if (r.kind === 'track') { const t = H.track(r.tid); return `<span class="cv rc-art">${cover(t.color, t.pattern)}</span>` }
    if (r.kind === 'svc') return `<span class="rc-svcs">${['sc', 'ym', 'sp', 'yt', 'vk'].map(badge).join('')}</span>`
    return `<span class="rc-logo">${S.logo()}</span>`
  }

  const recap = (s) => {
    const r = M.RECAP[s.recapI]
    return `<div class="recap" role="dialog" aria-label="Итоги 2026" style="--story:${r.color}">
      <div class="rc-bg">${cover(r.color, r.pattern)}</div>
      <div class="rc-segs">${M.RECAP.map((_, i) => `<i class="${i < s.recapI ? 'done' : i === s.recapI ? 'now' : ''}"><b></b></i>`).join('')}</div>
      <button class="icon-btn rc-close" data-act="close-overlay" aria-label="Закрыть">${icon('close')}</button>
      <div class="rc-story" data-kind="${r.kind}">${storyArt(r)}
        <span class="rc-eyebrow">${r.eyebrow}</span><b class="rc-big sel">${H.esc(r.big)}</b><span class="rc-unit">${r.unit}</span><p class="rc-line">${r.line}</p></div>
      <button class="rc-zone rc-prev" data-act="recap-step" data-dir="-1" aria-label="Назад"></button>
      <button class="rc-zone rc-next" data-act="recap-step" data-dir="1" aria-label="Дальше"></button>
      <div class="rc-foot"><span>${s.recapI + 1} из ${M.RECAP.length}</span>${s.recapI === M.RECAP.length - 1 ? `<button class="btn btn-accent sm" data-act="toast-share">${icon('external')}<span>Поделиться</span></button>` : '<span>Клик справа — дальше</span>'}</div>
    </div>`
  }

  S.use({
    defaults: { statsRange: 'week', recapI: 0 },
    actions: {
      recap: () => ({ overlay: 'recap', recapI: 0, menu: null }),
      'recap-step': (s, el) => {
        const i = s.recapI + Number(el.dataset.dir)
        if (i < 0) return { recapI: 0 }
        return i >= M.RECAP.length ? { overlay: null } : { recapI: i }
      },
      'toast-share': () => ({ overlay: null, ...S.app.toast('Картинка итогов сохранена — можно отправить друзьям') }),
    },
    pages: {
      stats: {
        render: statsPage,
        update: statsUpdate,
        after: (el, s) => markRange(el, s.statsRange),
        empty: () => ({ icon: 'stats', title: 'Пока нечего считать', line: 'Послушай что-нибудь — статистика появится после первых треков.', action: { act: 'go', to: 'home', label: 'На главную' } }),
      },
    },
    overlays: {
      recap: { render: recap, deps: ['recapI'], after: (el, s) => arm(s.recapI), leave: () => clearTimeout(storyTimer) },
    },
    hash: {
      range: (v) => (M.STATS[v] ? { statsRange: v } : {}),
      story: (v) => (M.RECAP[Number(v)] ? { recapI: Number(v) } : {}),
    },
  })
})(window.Sonar)
