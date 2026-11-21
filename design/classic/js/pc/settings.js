// ПК: настройки. Окно Sonar уезжает вправо с 3D-наклоном (~15°), справа выезжает панель.
// Разделы: Вид, Звук, Сервисы, Профиль, Sonar Deep, Система. Переключатели и сегменты — общие:
// .tgl[data-key] и [data-act=set][data-key][data-val]; их «включённость» сверяет syncControls.
// Куски, которые считаются из состояния (тарифы, сервисы, хранилище), помечены data-part.
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon, badge, cover } = S
  const D = S.data
  const M = S.more
  const H = S.h
  const F = Object.freeze
  const CACHE_GB = 1.8
  const CACHE_LIMIT_GB = 5

  const SECTIONS = F([
    ['look', 'palette', 'Вид'], ['sound', 'sound', 'Звук'], ['services', 'plug', 'Сервисы'],
    ['profile', 'user', 'Профиль'], ['deep', 'deep', 'Sonar Deep'], ['system', 'monitor', 'Система'],
  ])
  const STYLES = F([
    ['classic', 'Классика', 'Мягкие углы, спокойная плотность'],
    ['round', 'Круглый', 'Больше воздуха и скруглений'],
    ['sharp', 'Строгий', 'Острые углы, плотные списки'],
  ])
  const FONTS = F([['manrope', 'Manrope'], ['golos', 'Golos Text'], ['onest', 'Onest']])
  const HOTKEYS = F([['Пауза / играть', 'Ctrl Alt P'], ['Следующий', 'Ctrl Alt →'], ['Предыдущий', 'Ctrl Alt ←'], ['Нравится', 'Ctrl Alt L']])

  // ── Контролы ──────────────────────────────────────────
  const tgl = (key, label) =>
    `<button class="tgl" data-act="toggle" data-key="${key}" role="switch" aria-label="${label}"><i></i></button>`
  const seg = (key, opts, type = '') =>
    `<div class="seg" role="radiogroup">${opts.map(([v, l]) =>
      `<button class="seg-b" data-act="set" data-key="${key}" data-val="${v}"${type ? ` data-type="${type}"` : ''} role="radio">${l}</button>`).join('')}</div>`
  const row = (title, line, ctl, cls = '') =>
    `<div class="set-row ${cls}"><div class="set-txt"><b>${title}</b>${line ? `<span>${line}</span>` : ''}</div><div class="set-ctl">${ctl}</div></div>`
  const group = (title, rows) => `<section class="set-group">${title ? `<h3>${title}</h3>` : ''}<div class="set-card">${rows}</div></section>`
  const part = (name, s) => `<div data-part="${name}">${PARTS[name].html(s)}</div>`

  const valOf = (el) => (el.dataset.type === 'num' ? Number(el.dataset.val) : el.dataset.val)
  const syncControls = (scope, s) => {
    scope.querySelectorAll('.tgl[data-key]').forEach((b) => {
      b.classList.toggle('on', Boolean(s[b.dataset.key]))
      b.setAttribute('aria-checked', String(Boolean(s[b.dataset.key])))
    })
    scope.querySelectorAll('[data-act="set"][data-key]').forEach((b) => {
      const on = s[b.dataset.key] === valOf(b)
      b.classList.toggle('on', on)
      if (b.getAttribute('role') === 'radio') b.setAttribute('aria-checked', String(on))
    })
  }

  // ── Вычисляемые куски ─────────────────────────────────
  const priceOf = (plan, months) => {
    const off = (M.PERIODS.find(([m]) => m === months) || [1, 0])[1]
    const perMonth = Math.round(plan.price * (1 - off / 100))
    return { perMonth, total: perMonth * months, saved: (plan.price - perMonth) * months, off }
  }
  const planCard = (p, s) => {
    const pr = priceOf(p, s.period)
    return `<button class="plan" data-act="set" data-key="plan" data-val="${p.id}">` +
      `<span class="plan-name">${p.name}</span><span class="plan-seats">${H.tn(p.seats, ['слот', 'слота', 'слотов'])}</span>` +
      `<span class="plan-price"><b data-count="${pr.perMonth}">${pr.perMonth}</b> ₽<small>/мес</small></span>` +
      `<span class="plan-total">${s.period === 1 ? 'Каждый месяц' : `${pr.total.toLocaleString('ru-RU')} ₽ за ${s.period} мес`}</span>` +
      `<span class="plan-save${pr.saved ? '' : ' none'}">${pr.saved ? `Экономия ${pr.saved.toLocaleString('ru-RU')} ₽` : 'Без скидки'}</span></button>`
  }

  const svcRow = (x, s) => {
    const st = x.id === 'sc' && s.svcFixed ? 'on' : x.id === 'vk' && s.vkLinked ? 'on' : x.state
    const line = st === x.state ? x.line : x.id === 'vk' ? 'Подключён только что' : 'Вход обновлён · всё играет'
    const who = x.id === 'vk' && s.vkLinked ? 'folzy' : x.who
    const btn = st === 'error'
      ? `<button class="btn btn-accent sm" data-act="svc-fix">${icon('refresh')}<span>Войти заново</span></button>`
      : st === 'off'
        ? `<button class="btn btn-soft sm" data-act="svc-link">${icon('plus')}<span>Подключить</span></button>`
        : `<button class="btn btn-soft sm" data-act="noop">Отключить</button>`
    return `<div class="svc-row st-${st}">${badge(x.id)}<div class="svc-txt"><b>${D.SERVICES[x.id].name}${who ? ` <span>· ${H.esc(who)}</span>` : ''}</b>` +
      `<span class="svc-line">${st === 'error' ? icon('info') : ''}${line}</span></div><span class="pill pill-${st}">${{ on: 'Подключён', off: 'Нет', error: 'Ошибка' }[st]}</span>${btn}</div>`
  }

  const PARTS = {
    plans: { deps: ['period'], html: (s) => `<div class="plans">${M.PLANS.map((p) => planCard(p, s)).join('')}</div>` },
    services: { deps: ['svcFixed', 'vkLinked'], html: (s) => M.SERVICE_STATE.map((x) => svcRow(x, s)).join('') },
    storage: {
      deps: ['cacheCleared'],
      html: (s) => {
        const used = s.cacheCleared ? 0 : CACHE_GB
        return `<div class="store"><div class="store-bar"><i style="--k:${(used / CACHE_LIMIT_GB).toFixed(3)}"></i></div>` +
          `<div class="store-txt"><b>${used.toLocaleString('ru-RU')} ГБ</b> из ${CACHE_LIMIT_GB} ГБ · ${s.cacheCleared ? 'кэш пуст' : '412 треков в кэше'}</div>` +
          `<button class="btn btn-soft sm" data-act="cache-clear"${s.cacheCleared ? ' disabled' : ''}>${icon('trash')}<span>Очистить</span></button></div>`
      },
    },
    hotkeys: {
      deps: ['hotkeys'],
      html: (s) => `<div class="keys${s.hotkeys ? '' : ' off'}">${HOTKEYS.map(([a, k]) => `<span>${a}</span><kbd>${k}</kbd>`).join('')}</div>`,
    },
  }

  // ── Разделы ───────────────────────────────────────────
  const styleCard = ([id, name, line]) =>
    `<button class="style-card st-${id}" data-act="set" data-key="style" data-val="${id}">` +
    `<span class="style-prev"><i></i><i></i><i></i></span><b>${name}</b><span>${line}</span></button>`

  const look = () =>
    group('Тема', row('Оформление', 'Тёмная — основная, светлая — днём', seg('theme', [['dark', 'Тёмная'], ['light', 'Светлая']])) +
      row('Цвет под обложку', 'Весь интерфейс перекрашивается в цвет текущего трека', tgl('coverTheme', 'Цвет под обложку'))) +
    group('Стиль', `<div class="styles">${STYLES.map(styleCard).join('')}</div>`) +
    group('Текст и значки',
      row('Шрифт', 'Все шрифты бесплатные, с кириллицей', seg('font', FONTS)) +
      row('Толщина значков', '', seg('iconStroke', [['1.5', 'Тонкие'], ['1.75', 'Обычные'], ['2.1', 'Жирные']], 'num'))) +
    group('Движение', row('Меньше движения', 'Только плавная прозрачность — без сдвигов и размытия', seg('motion', [['full', 'Всё'], ['reduced', 'Меньше']])))

  const fx = (name) => `<button class="fx" data-act="deep-lock">${icon('lock')}<span>${name}</span></button>`
  const sound = () =>
    group('Качество',
      row('Качество звука', 'FLAC — только у Яндекса с Плюсом', seg('quality', [['auto', 'Авто'], ['high', 'Высокое'], ['flac', 'FLAC']])) +
      row('Выравнивать громкость', 'Треки разных сервисов звучат одинаково громко', tgl('normalize', 'Выравнивать громкость')) +
      row('Плавный переход', 'Конец трека перетекает в начало следующего', seg('crossfade', [['0', 'Нет'], ['3', '3 с'], ['6', '6 с'], ['12', '12 с']], 'num'))) +
    group('Эквалайзер', row('12 полос', 'Пресеты и своя кривая', `<button class="btn btn-soft sm" data-act="overlay" data-id="eq">${icon('eq')}<span>Открыть</span></button>`)) +
    group('Эффекты · Sonar Deep', `<div class="fxs">${['3D', '8D', '12D', '16D', 'Реверб'].map(fx).join('')}</div>` +
      `<p class="set-note">${icon('deep')} Эффекты — единственное платное в Sonar. Сама музыка и скачивание — бесплатно.</p>`)

  const services = (s) =>
    group('Подключённые сервисы', part('services', s)) +
    group('Если трек недоступен', row('Резерв из другого сервиса', 'Найдём тот же трек в другом подключённом сервисе и сыграем оттуда', tgl('fallback', 'Резерв из другого сервиса')))

  const showcase = () => ['t2', 't8', 't3'].map(H.track).map((t) =>
    `<div class="show"><span class="cv">${cover(t.color, t.pattern)}</span><b class="ellipsis">${H.esc(t.title)}</b><span class="ellipsis">${H.esc(t.artist)}</span></div>`).join('')
  const PRIVACY = F([['privProfile', 'Профиль'], ['privStats', 'Статистика'], ['privNow', 'Что слушаю сейчас']])
  const profile = () =>
    `<div class="prof"><div class="prof-banner">${cover('#2740b8', 'arcs')}</div>` +
    `<div class="prof-row"><span class="avatar xl">F</span><div class="prof-who"><b class="sel">Folzy</b><span class="sel">@folzy</span></div>` +
    `<button class="btn btn-soft sm" data-act="noop">${icon('palette')}<span>Баннер и фон</span></button></div></div>` +
    group('Аккаунт', row('Логин', 'Не меняется — его меняет только админ', '<code>folzy</code>') +
      row('Имя пользователя', 'Ссылка на профиль — sonar.folzy.ru/@folzy', '<button class="btn btn-soft sm" data-act="noop">Изменить</button>')) +
    group('Витрина', `<div class="shows">${showcase()}</div>`) +
    group('Приватность', PRIVACY.map(([k, l]) => row(l, '', seg(k, [['all', 'Все'], ['friends', 'Друзья'], ['none', 'Никто']]))).join(''))

  const deep = (s) =>
    `<div class="deep-hero"><span class="deep-mark">${icon('deep')}</span><div><h3>Sonar Deep</h3>` +
    `<p>Платно — только эффекты Sonar. Музыка, лайки, плейлисты и скачивание остаются бесплатными.</p></div></div>` +
    group('Срок', seg('period', M.PERIODS.map(([m, off]) => [String(m), `${m} мес${off ? ` <em>−${off}%</em>` : ''}`]), 'num')) +
    group('Тариф', part('plans', s)) +
    group('Что внутри', `<ul class="feats">${M.DEEP_FEATURES.map((f) => `<li>${icon('check')}${f}</li>`).join('')}</ul>`) +
    `<div class="deep-pay"><button class="btn btn-accent" data-act="deep-pay">${icon('external')}<span>Оплатить на сайте</span></button><span>sonar.folzy.ru/pay</span></div>`

  const system = (s) =>
    group('Запуск', row('Запускать вместе с Windows', 'Свёрнутым в трей', tgl('autostart', 'Автозапуск')) +
      row('Крестик прячет в трей', 'Музыка продолжает играть, «Выход» — в меню трея', tgl('closeToTray', 'Крестик прячет в трей'))) +
    group('Горячие клавиши', row('По всей системе', 'Работают, даже когда Sonar свёрнут', tgl('hotkeys', 'Горячие клавиши')) + part('hotkeys', s)) +
    group('Обновления', row('Автообновление', 'Скачивать тихо и ставить при перезапуске', tgl('autoUpdate', 'Автообновление')) +
      row('Версия 0.1.0', 'Последняя проверка — сегодня в 09:12', `<button class="btn btn-soft sm" data-act="scene" data-id="update">${icon('refresh')}<span>Проверить</span></button>`)) +
    group('Хранилище', part('storage', s)) +
    `<div class="about">${S.logo()}<div><b>Sonar 0.1.0</b><span>Windows · канал обновлений @SonarUpdates</span></div></div>`

  const PANES = F({ look, sound, services, profile, deep, system })

  // ── Окно настроек ─────────────────────────────────────
  const pane = (s) => `<div class="set-pane" data-sec="${s.settingsSec}"><h2>${SECTIONS.find(([id]) => id === s.settingsSec)[2]}</h2>${PANES[s.settingsSec](s)}</div>`
  const render = (s) => `
    <div class="set" role="dialog" aria-label="Настройки">
      <nav class="set-nav">
        <div class="set-nav-head"><b>Настройки</b><button class="icon-btn sm" data-act="close-overlay" aria-label="Закрыть">${icon('close')}</button></div>
        ${SECTIONS.map(([id, ic, label]) => `<button class="set-tab" data-act="set" data-key="settingsSec" data-val="${id}">${icon(ic)}<span>${label}</span>${id === 'deep' ? '<span class="tag">Deep</span>' : ''}</button>`).join('')}
      </nav>
      <div class="set-scroll" data-set-pane>${pane(s)}</div>
    </div>`

  const after = (el, s) => { syncControls(el, s); H.countUp(el) }
  const PART_DEPS = Object.values(PARTS).flatMap((p) => p.deps)
  const update = (el, prev, next) => {
    if (prev.settingsSec !== next.settingsSec) {
      const host = el.querySelector('[data-set-pane]')
      host.innerHTML = pane(next)
      host.scrollTop = 0
      host.firstElementChild.classList.add('pane-in')
      H.countUp(host)
    } else if (H.changed(prev, next, PART_DEPS)) {
      el.querySelectorAll('[data-part]').forEach((p) => {
        const def = PARTS[p.dataset.part]
        if (!H.changed(prev, next, def.deps)) return
        p.innerHTML = def.html(next)
        H.countUp(p)
      })
    }
    syncControls(el, next)
  }

  // Те же разделы и контролы собирает экран «Профиль» на iPhone
  S.settingsView = Object.freeze({ SECTIONS, PANES, PARTS, PART_DEPS, syncControls, group, row, tgl, seg, part })

  // Вид применяется ко всему прототипу (ПК и iPhone)
  const renderLookPrefs = (prev, next) => {
    if (!H.changed(prev, next, ['style', 'font', 'iconStroke', 'coverTheme'])) return
    H.roots.forEach((r) => {
      r.dataset.style = next.style
      r.dataset.font = next.font
      r.dataset.cover = next.coverTheme ? 'on' : 'off'
      r.style.setProperty('--stroke', next.iconStroke)
    })
  }

  S.use({
    defaults: {
      settingsSec: 'look', coverTheme: true, style: 'classic', font: 'manrope', iconStroke: 1.75,
      quality: 'flac', normalize: true, crossfade: 6, fallback: true, svcFixed: false, vkLinked: false,
      privProfile: 'all', privStats: 'friends', privNow: 'friends', plan: 'echo', period: 3,
      autostart: true, closeToTray: true, hotkeys: false, autoUpdate: true, cacheCleared: false,
    },
    actions: {
      settings: (s, el) => ({ overlay: 'settings', settingsSec: PANES[el.dataset.sec || el.dataset.to] ? (el.dataset.sec || el.dataset.to) : s.settingsSec, menu: null, ann: null }),
      'deep-lock': () => ({ settingsSec: 'deep', ...S.app.toast('3D, 8D, 12D, 16D и реверб — в Sonar Deep') }),
      'deep-pay': (s) => S.app.toast(`Откроется sonar.folzy.ru/pay — тариф ${M.PLANS.find((p) => p.id === s.plan).name}, ${s.period} мес`),
      'svc-fix': () => ({ svcFixed: true, ...S.app.toast('SoundCloud снова подключён') }),
      'svc-link': () => ({ vkLinked: true, ...S.app.toast('VK Музыка подключена') }),
      'cache-clear': () => ({ cacheCleared: true, ...S.app.toast('Кэш очищен — 1,8 ГБ', { cacheCleared: false }) }),
    },
    renderers: [renderLookPrefs],
    overlays: { settings: { render, update, after, scrim: false } },
    hash: { sec: (v) => (PANES[v] ? { settingsSec: v } : {}) },
  })
})(window.Sonar)
