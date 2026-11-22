// Макет бота @SonarMusicApp по docs/BOT.md. Без сервера: всё состояние — в этом файле.
'use strict';

const $ = (s) => document.querySelector(s);
const feed = $('#feed');
const input = $('#input');
const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

// ---------- состояние ----------
const S = {
  who: 'user',          // guest | user | owner
  health: 'ok',         // ok | partial | down
  expect: null,         // ждём ввод: login | password | reg_login | reg_pass | reg_pass2 | report
  reg: {},
  report: null,         // { kind, platform } пока пишут первое сообщение
  ticket: null,         // открытое обращение { id, kind, platform }
  token: 'on',          // on | none — токен виден всегда (решение владельца 2026-11-15)
  tokenValue: 'snr_8f2c41d07a9b4e1f',
  period: 'week',
  online: 3,
};
const linked = () => S.who !== 'guest';
const name = () => 'Folzy';
const newToken = () => `snr_${Math.random().toString(16).slice(2, 10)}${Math.random().toString(16).slice(2, 10)}`;

// ---------- разметка ----------
const E = (k) => `<img class="e${k.startsWith('logo_') ? ' logo' : ''}" src="emoji/${k}.png" alt="">`;
const Q = (html, head) => `<blockquote>${head ? `<span class="qh">${head}</span>\n` : ''}${html}</blockquote>`;
const C = (t) => `<code>${t}</code>`;
const now = (plusMin = 0) => {
  const d = new Date(Date.now() + plusMin * 60000);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
};
const BANNERS = {
  main: `<img class="logo" src="logo.svg" alt="">Sonar`,
  profile: `<img src="emoji/profile.png" alt="">Профиль`,
  login: `<img src="emoji/login.png" alt="">Вход`,
  register: `<img src="emoji/register.png" alt="">Регистрация`,
  stats: `<img src="emoji/stats.png" alt="">Статистика`,
  support: `<img src="emoji/support.png" alt="">Поддержка`,
};
const B = (t, i, fn, extra = {}) => ({ t, i, fn, ...extra });
const back = (fn) => B('Назад', 'back', fn);

// ---------- сообщения ----------
function scrollDown() { requestAnimationFrame(() => { feed.scrollTop = feed.scrollHeight; }); }

function bubbleHTML(s) {
  const banner = s.banner ? `<div class="banner"><div class="banner-in">${BANNERS[s.banner]}</div></div>` : '';
  return `${banner}<div class="body">${s.html}<span class="time">${now()}</span></div>`;
}

function kbEl(msg, rows) {
  const kb = document.createElement('div');
  kb.className = 'kb';
  for (const row of rows || []) {
    const r = document.createElement('div');
    r.className = 'kb-row';
    for (const b of row) {
      const el = document.createElement('button');
      if (b.sel) el.classList.add('sel');
      if (b.soon) el.classList.add('soon');
      el.innerHTML = `${b.i ? `<img src="emoji/${b.i}.png" class="${b.i.startsWith('logo_') ? 'logo' : ''}" alt="">` : ''}<span>${b.t}</span>${b.url ? '<span class="arrow">↗</span>' : ''}`;
      el.addEventListener('click', (ev) => {
        ripple(el, ev);
        if (b.url) return toast(`Откроется ${b.url}`);
        b.fn && b.fn(msg);
      });
      r.append(el);
    }
    kb.append(r);
  }
  return kb;
}

function ripple(el, ev) {
  if (reduce) return;
  const r = el.getBoundingClientRect();
  const s = Math.max(r.width, r.height);
  const dot = document.createElement('span');
  dot.className = 'ripple';
  Object.assign(dot.style, { width: `${s}px`, height: `${s}px`, left: `${ev.clientX - r.left - s / 2}px`, top: `${ev.clientY - r.top - s / 2}px` });
  el.append(dot);
  setTimeout(() => dot.remove(), 550);
}

/** Новое сообщение бота. */
function send(s) {
  const row = document.createElement('div');
  row.className = 'row enter';
  const wrap = document.createElement('div');
  wrap.className = s.banner || s.kb ? 'msg' : 'msg small';
  const bubble = document.createElement('div');
  bubble.className = 'bubble sizer';
  const content = document.createElement('div');
  content.className = 'content';
  content.innerHTML = bubbleHTML(s);
  bubble.append(content);
  wrap.append(bubble);
  row.append(wrap);
  const msg = { row, wrap, bubble, content, kb: null, screen: s };
  msg.kb = kbEl(msg, s.kb);
  wrap.append(msg.kb);
  feed.append(row);
  hook(msg);
  scrollDown();
  return msg;
}

/** Правка того же сообщения: содержимое плавно меняется, высота едет. */
function edit(msg, s) {
  msg.screen = s;
  const { bubble, content } = msg;
  if (reduce) {
    content.innerHTML = bubbleHTML(s);
    const kb = kbEl(msg, s.kb); msg.kb.replaceWith(kb); msg.kb = kb; hook(msg);
    return;
  }
  const h0 = bubble.offsetHeight;
  bubble.style.height = `${h0}px`;
  content.classList.add('swap');
  msg.kb.style.transition = 'opacity .18s'; msg.kb.style.opacity = '0';
  setTimeout(() => {
    content.innerHTML = bubbleHTML(s);
    const kb = kbEl(msg, s.kb);
    kb.style.opacity = '0'; kb.style.transition = 'opacity .25s';
    msg.kb.replaceWith(kb); msg.kb = kb;
    hook(msg);
    bubble.style.height = 'auto';
    const h1 = bubble.offsetHeight;
    bubble.style.height = `${h0}px`;
    void bubble.offsetHeight;
    bubble.style.height = `${h1}px`;
    content.classList.remove('swap');
    requestAnimationFrame(() => { kb.style.opacity = '1'; });
    setTimeout(() => { bubble.style.height = 'auto'; scrollDown(); }, 340);
  }, 170);
}

function hook(msg) {
  msg.content.querySelectorAll('.spoiler').forEach((sp) => sp.addEventListener('click', () => sp.classList.toggle('open')));
  msg.content.querySelectorAll('.link').forEach((a) => a.addEventListener('click', () => toast(`Откроется ${a.dataset.href || a.textContent}`)));
}

/** Сообщение пользователя. */
function mine(html) {
  const row = document.createElement('div');
  row.className = 'row out enter';
  row.innerHTML = `<div class="msg"><div class="bubble"><div class="body">${html}<span class="time">${now()} ✓✓</span></div></div></div>`;
  feed.append(row);
  scrollDown();
  return row;
}
function minePhoto() {
  const row = document.createElement('div');
  row.className = 'row out enter';
  row.innerHTML = `<div class="msg"><div class="bubble"><div class="photo">скриншот.png</div><div class="body"><span class="time">${now()} ✓✓</span></div></div></div>`;
  feed.append(row);
  scrollDown();
}
function remove(row, delay = 650) {
  setTimeout(() => { row.style.maxHeight = `${row.offsetHeight}px`; row.classList.add('leave'); setTimeout(() => row.remove(), 320); }, delay);
}
const later = (ms, fn) => setTimeout(fn, ms);

/** Всплывашка answerCallbackQuery(show_alert) — окно по центру с кнопкой OK. */
function alertBox(text) {
  const box = document.createElement('div');
  box.className = 'alert';
  box.innerHTML = `<div class="alert-card"><p>${text}</p><button>OK</button></div>`;
  const close = () => { box.classList.add('closing'); setTimeout(() => box.remove(), 160); };
  box.querySelector('button').onclick = close;
  document.body.append(box);
}

let toastTimer;
function toast(text) {
  const t = $('#toast');
  t.textContent = text; t.hidden = false;
  t.style.animation = 'none'; void t.offsetWidth; t.style.animation = '';
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { t.hidden = true; }, 1800);
}

// ---------- экраны ----------
const scr = {
  guest: () => ({
    banner: 'main',
    html: `Привет! Это <b>Sonar</b> — твой музыкальный плеер.\n${Q('Аккаунт не привязан к Sonar\nВойди или зарегистрируйся, чтобы продолжить')}`,
    kb: [[B('Войти', 'login', (m) => go.login(m)), B('Регистрация', 'register', (m) => go.register(m))]],
  }),

  login: () => ({
    banner: 'login',
    html: `<b>Вход</b> ${E('login')}\n${Q('Введи свой <b>логин</b>:')}`,
    kb: [[B('Быстрая ссылка', 'quick_link', (m) => { S.expect = null; edit(m, scr.quick()); })],
      [B('Отмена', 'cancel', (m) => go.cancel(m))]],
  }),

  quick: () => ({
    banner: 'login',
    html: `${E('quick_link')} <b>Быстрая ссылка</b>\n${Q(`Открой на устройстве, где ты уже вошёл в Sonar. ${E('wait')} Действует до <b>${now(5)}</b>`)}`,
    kb: [[B('Открыть в Sonar', 'logo_sonar', (m) => openAuth(m))],
      [back((m) => go.login(m))]],
  }),

  quickExpired: () => ({
    banner: 'login',
    html: `${E('wait')} <b>Ссылка истекла</b>\n${Q('Ссылка живёт 5 минут. Сделай новую.')}`,
    kb: [[B('Новая ссылка', 'refresh', (m) => edit(m, scr.quick()))], [back((m) => go.login(m))]],
  }),

  register: () => ({
    banner: 'register',
    html: `<b>Регистрация</b> ${E('register')}\n${Q('Придумай <b>логин</b>:\n3–24 символа: a-z, 0-9, _ и точка')}`,
    kb: [[B('Отмена', 'cancel', (m) => go.cancel(m))]],
  }),

  main: () => ({
    banner: 'main',
    html: `Привет, <b>${name()}</b>! ${E('profile')}\n\nЧем я могу помочь?\n${Q(`Поддержка — кнопка ${E('bug')} Баг / Идея ниже`)}`,
    kb: [[B('Профиль', 'profile', (m) => edit(m, scr.profile())), B('Статистика', 'stats', (m) => edit(m, scr.stats()))],
      [B('Сервисы', 'services', (m) => edit(m, scr.services())), B('Баг / Идея', 'bug', (m) => edit(m, scr.reportKind()))],
      [B('Скачать Sonar', 'download', null, { url: 'try-sonar.ru' })]],
  }),

  profile: () => ({
    banner: 'profile',
    html: `${E('profile')} <b>Твой профиль</b>\n`
      + Q(`Имя: <b>Folzy</b>\nЛогин: ${C('@folzy')} · ${C('#104633')}\n${E('date')} с 14 ноября 2026`, 'Аккаунт')
      + Q(`${E('logo_soundcloud')} SoundCloud ${E('ok')}\n${E('logo_yandex_music')} Яндекс Музыка ${E('ok')}\n${E('logo_lastfm')} Last.fm ${E('down')}`, 'Сервисы')
      + Q(`${E('time')} 412 мин · ${E('track')} 96 треков`, 'Неделя')
      + `\n${E('web')} <span class="link">try-sonar.ru/@folzy</span>`,
    kb: [[B('Рефералка', 'referral', (m) => edit(m, scr.referral())), B('Интеграция', 'integration', (m) => edit(m, scr.integration()))],
      [B('Выйти', 'logout', (m) => edit(m, scr.logoutAsk()))],
      [B('Версии', 'versions', (m) => edit(m, scr.versions()))],
      [back((m) => edit(m, scr.main()))]],
  }),

  integration: () => {
    const head = `${E('integration')} <b>Интеграция</b>\n\n`;
    if (S.token === 'none') {
      return {
        html: `${head}${Q('Токена нет. Он нужен selfbot и своим сервисам: «сейчас играет», профиль.')}`,
        kb: [[B('Создать токен', 'success', (m) => { S.token = 'on'; S.tokenValue = newToken(); edit(m, scr.integration()); })], [back((m) => edit(m, scr.profile()))]],
      };
    }
    return {
      html: head
        + `Сейчас играет ${E('listening')}\n${Q('GET https://sonar-api.folzy.ru/oauth/now?token=...\nТекущий трек, обложка, тайминги')}\n`
        + `Профиль ${E('profile')}\n${Q('GET https://sonar-api.folzy.ru/oauth/profile?token=...\nНикнейм и аватарка')}\n`
        + `${E('key')} Токен: <span class="spoiler">${S.tokenValue}</span>`,
      kb: [
        [B('Скопировать токен', 'copy', () => toast('Токен скопирован'))],
        [B('Обновить токен', 'refresh', (m) => edit(m, scr.ask('Старый токен перестанет работать. Обновить?', () => { S.tokenValue = newToken(); edit(m, scr.integration()); }, () => edit(m, scr.integration()))))],
        [B('Отозвать токен', 'revoke', (m) => edit(m, scr.ask('Отозвать токен? Всё, что им пользуется, перестанет работать.', () => { S.token = 'none'; edit(m, scr.integration()); }, () => edit(m, scr.integration()))))],
        [back((m) => edit(m, scr.profile()))],
      ],
    };
  },

  ask: (text, yes, no) => ({
    html: `${E('warning')} <b>Точно?</b>\n${Q(text)}`,
    kb: [[B('Да', 'confirm', yes), B('Назад', 'back', no)]],
  }),

  referral: () => ({
    html: `${E('referral')} <b>Рефералка</b>\n`
      + Q(`${E('key')} Код: ${C('ZTRMC6')}\n${E('integration')} <span class="link" data-href="t.me/SonarMusicApp?start=ref_ZTRMC6">Открыть ссылку</span>\n${E('users')} Приглашено: <b>2</b>`)
      + Q(`${E('info')} Приглашай друзей в Sonar — они зарегистрируются по твоей ссылке.`),
    kb: [[B('Поделиться', 'share', () => toast('Выбор чата для отправки ссылки'))], [back((m) => edit(m, scr.profile()))]],
  }),

  versions: () => ({
    html: `${E('versions')} <b>Тестирование</b>\n`
      + Q('Скачивай свежие сборки. Выбери файл для установки:')
      + Q(`${E('new')} <b>Что нового (v0.2.0):</b>\nТексты песен, полноэкранный плеер, эквалайзер`),
    kb: [[B('Windows (v0.2.0)', 'logo_windows', null, { url: 'github.com/folzy1092/Sonar/releases' })],
      [B('iOS Beta (v1.0.0)', 'logo_apple', null, { url: 'github.com/folzy1092/Sonar/releases' })],
      [back((m) => edit(m, scr.profile()))]],
  }),

  logoutAsk: () => ({
    html: `${E('logout')} <b>Выход</b>\n${Q('Ты уверен, что хочешь выйти? Придётся авторизоваться заново.')}`,
    kb: [[B('Подтвердить', 'confirm', (m) => { setWho('guest'); edit(m, scr.guest()); })], [back((m) => edit(m, scr.profile()))]],
  }),

  stats: () => {
    const P = {
      day: ['День', '1 ч 48 мин', '+23%', 27], week: ['Неделя', '6 ч 52 мин', '+12%', 96],
      month: ['Месяц', '31 ч 10 мин', '−4%', 412], half: ['Полгода', '164 ч', '+31%', 2210], year: ['Год', '298 ч', '+57%', 4018],
    }[S.period];
    const per = (k, t) => B(t, null, (m) => { S.period = k; edit(m, scr.stats()); }, { sel: S.period === k });
    return {
      banner: 'stats',
      html: `${E('stats')} <b>Статистика · ${P[0]}</b>\n`
        + Q(`${E('time')} ${P[1]} · <b>${P[2]}</b> к прошлому периоду\n${E('track')} ${P[3]} треков`)
        + Q('1. Mareux\n2. Скриптонит\n3. Crystal Castles', 'Топ артистов')
        + Q('1. Mareux — The Perfect Girl\n2. Скриптонит — Привычка\n3. Crystal Castles — Kerosene', 'Топ треков')
        + Q(`${E('date')} Самый активный день: <b>пятница</b>\n${E('time')} Самый активный час: <b>23:00</b>`),
      kb: [[per('day', 'День'), per('week', 'Неделя'), per('month', 'Месяц')], [per('half', 'Полгода'), per('year', 'Год')],
        [B('Полная статистика в приложении', 'stats', null, { url: 'sonar://stats' })],
        [back((m) => edit(m, scr.main()))]],
    };
  },

  services: (tab) => {
    const tabs = [B('Яндекс Музыка', 'logo_yandex_music', (m) => edit(m, scr.services('ym')), { sel: tab === 'ym' }),
      B('SoundCloud', 'logo_soundcloud', (m) => edit(m, scr.services('sc')), { sel: tab === 'sc' })];
    const tail = `\n${Q(`${E('info')} Токены вставляй в приложении, не сюда — бот такие сообщения удаляет.`)}`;
    if (tab === 'ym') {
      return {
        banner: 'main',
        html: `${E('logo_yandex_music')} <b>Яндекс Музыка</b>\n`
          + Q('1. Открой ссылку кнопкой ниже.\n2. Войди в Яндекс и нажми «Разрешить».\n3. Адрес станет вида music.yandex.ru/#access_token=…\n   Не успел — возьми его из истории (Ctrl+H).\n4. Токен — между access_token= и &token_type.\n   Вставь в Sonar → Настройки → Сервисы.')
          + Q(`${E('warning')} Никому не отправляй токен. В приложении есть вход в один клик — он делает то же самое сам.`)
          + tail,
        kb: [[B('Открыть ссылку Яндекса', 'integration', null, { url: 'oauth.yandex.ru' })], tabs, [back((m) => edit(m, scr.services()))]],
      };
    }
    if (tab === 'sc') {
      return {
        banner: 'main',
        html: `${E('logo_soundcloud')} <b>SoundCloud</b> (с компьютера)\n`
          + Q('1. Открой soundcloud.com и войди.\n2. OAuth-токен: F12 → Application → Cookies → oauth_token.\n3. client_id: F12 → Network → F5 → фильтр client_id → значение после client_id=.\n4. Вставь оба в Sonar → Настройки → Сервисы.')
          + Q(`${E('warning')} Никому не отправляй oauth_token — это доступ к твоему аккаунту.`)
          + tail,
        kb: [tabs, [back((m) => edit(m, scr.services()))]],
      };
    }
    return {
      banner: 'main',
      html: `${E('services')} <b>Сервисы</b>\n\nКак подключить музыку к Sonar. Выбери сервис:${tail}`,
      kb: [tabs, [back((m) => edit(m, scr.main()))]],
    };
  },

  reportKind: () => ({
    banner: 'main',
    html: `<b>Баг или идея?</b> ${E('bug')}`,
    kb: [[B('Баг', 'bug', (m) => edit(m, scr.reportPlatform('bug'))), B('Идея', 'idea', (m) => edit(m, scr.reportPlatform('idea')))],
      [back((m) => edit(m, linked() ? scr.main() : scr.guest()))]],
  }),

  reportPlatform: (kind) => ({
    banner: 'main',
    html: kind === 'bug' ? `<b>Где произошёл баг?</b>` : `<b>В какое приложение добавить?</b>`,
    kb: [[B('Windows', 'logo_windows', (m) => go.reportPrompt(m, kind, 'windows')),
      B('iOS', 'logo_apple', (m) => go.reportPrompt(m, kind, 'ios'))],
    [B('Android · в разработке', 'logo_android', () => alertBox('Android-версия Sonar в разработке'), { soon: true })],
    [back((m) => edit(m, scr.reportKind()))]],
  }),

  reportPrompt: (kind) => ({
    banner: 'main',
    html: kind === 'bug' ? `<b>Что случилось?</b>\nМожно приложить скриншот или видео.` : `<b>Расскажи идею</b>\nМожно приложить картинку.`,
    kb: [[B('Отмена', 'cancel', (m) => go.cancel(m))]],
  }),

  status: () => {
    const owner = S.who === 'owner';
    const st = (x, extra = '') => x === 'ok' ? `${E('ok')} Работает${extra}` : x === 'partial' ? `${E('partial')} С перебоями${extra}` : `${E('down')} Недоступен`;
    const h = S.health;
    const head = h === 'ok' ? `${E('status_ok')} <b>Все системы работают штатно</b>`
      : h === 'partial' ? `${E('status_partial')} <b>Некоторые сервисы работают с перебоями</b>`
        : `${E('status_down')} <b>Сбой: Основной</b>`;
    const main = h === 'down' ? 'down' : 'ok';
    const ms = (v) => owner ? ` · ${v}` : '';
    const infra = owner
      ? [`${E('desktop')} Основной: ${st(main, ms('12 мс'))}`, `${E('track')} Медиа: ${st('ok', ms('340 мс'))}`, `${E('proxy')} Прокси: ${st('ok', ms('95 мс'))}`,
        `${E('bot')} Бот: ${st('ok')}`, `${E('web')} Сайт: ${st('ok')}`, `${E('storage')} Хранилище: ${st('ok', ms('1.2 ГБ свободно'))}`]
      : [`${E('desktop')} Основной: ${st(main)}`, `${E('storage')} Хранилище: ${st('ok')}`];
    const tree = (items) => items.map((x, i) => `${i === items.length - 1 ? '└' : '├'} ${x}`).join('\n');
    const ym = h === 'partial' ? `${E('partial')} 2.9 с` : E('ok');
    let html = `${head}\n\n${E('listening')} Слушают онлайн: <b>${S.online}</b>\n${E('users')} Пользователей: <b>12</b>\n${E('time')} Аптайм: <b>${h === 'down' ? '99.71' : '99.98'}%</b>\n\n`
      + `<b>Инфраструктура:</b>\n${tree(infra)}\n\n<b>Музыкальные платформы:</b>\n${tree([`${E('logo_soundcloud')} SoundCloud: ${E('ok')}`, `${E('logo_yandex_music')} Яндекс Музыка: ${ym}`])}`;
    if (owner) html += `\n\n<b>Тексты и прочее:</b>\n${tree([`${E('lyrics')} lrclib: ${E('ok')} · Genius: ${E('ok')}`, `${E('logo_lastfm')} Last.fm: ${E('ok')} · ${E('logo_telegram')} Telegram: ${E('ok')}`])}`;
    return {
      html,
      kb: [[B('Обновить', 'refresh', (m) => { S.online = 1 + Math.floor(Math.random() * 6); edit(m, scr.status()); toast('Обновлено'); }),
        B('Страница статуса', 'web', null, { url: 'try-sonar.ru/status' })]],
    };
  },
};

// ---------- переходы и шаги ввода ----------
const go = {
  login(m) { S.expect = 'login'; edit(m, scr.login()); },
  register(m) { S.expect = 'reg_login'; S.reg = {}; edit(m, scr.register()); },
  cancel(m) {
    S.expect = null; S.report = null;
    edit(m, { html: `Ок, в другой раз ${E('bye')}` });
    later(900, () => send(linked() ? scr.main() : scr.guest()));
  },
  reportPrompt(m, kind, platform) { S.report = { kind, platform }; S.expect = 'report'; edit(m, scr.reportPrompt(kind)); },
};

function short(html) { return send({ html }); }

function onText(text) {
  const t = text.trim();
  if (!t) return;
  if (t === '/start' || t === '/status') {
    mine(t);
    S.expect = null;
    later(350, () => send(t === '/status' ? scr.status() : linked() ? scr.main() : scr.guest()));
    return;
  }
  const row = mine(['password', 'reg_pass', 'reg_pass2'].includes(S.expect) ? '•'.repeat(Math.min(t.length, 16)) : escapeHtml(t));

  switch (S.expect) {
    case 'login':
      S.reg.login = t;
      S.expect = 'password';
      return later(400, () => short(`<b>Вход</b> ${E('key')}\n${Q('Теперь введи <b>пароль</b>:')}`));
    case 'password':
      remove(row);
      if (t === '0000') return later(500, () => short(`${E('cancel')} Неверный пароль`));
      S.expect = null;
      return later(700, () => { short(`<b>Успешно!</b> ${E('success')}\n${Q(`Аккаунт ${C(escapeHtml((S.reg.login || 'folzy').toLowerCase()))} теперь привязан к Telegram`)}`); setWho('user'); later(1500, () => send(scr.main())); });
    case 'reg_login':
      if (!/^[a-z0-9_.]{3,24}$/.test(t)) return later(400, () => short(`${E('cancel')} Логин — 3–24 символа: ${C('a-z 0-9 _ .')}`));
      S.reg.login = t; S.expect = 'reg_pass';
      return later(400, () => short(`<b>Регистрация</b> ${E('key')}\n${Q(`Логин ${C(t)} свободен. Придумай <b>пароль</b> (от 8 символов):`)}`));
    case 'reg_pass':
      remove(row);
      if (t.length < 8) return later(500, () => short(`${E('cancel')} Пароль — от 8 символов`));
      S.reg.pass = t; S.expect = 'reg_pass2';
      return later(500, () => short(`<b>Регистрация</b> ${E('key')}\n${Q('Введи пароль <b>ещё раз</b>:')}`));
    case 'reg_pass2':
      remove(row);
      if (t !== S.reg.pass) { S.expect = 'reg_pass'; return later(500, () => short(`${E('cancel')} Пароли не совпадают. Придумай пароль заново:`)); }
      S.expect = null;
      return later(700, () => {
        send({ html: `<b>Успешно!</b> ${E('success')}\n${Q(`Аккаунт ${C(S.reg.login)} создан и привязан к Telegram`)}`, kb: [[B('Скачать Sonar', 'download', null, { url: 'try-sonar.ru' })]] });
        setWho('user');
      });
    case 'report':
      return later(450, openTicket);
    default:
      if (S.ticket) return later(300, () => short(`${E('sent')} Отправлено`));
      if (/^(y0_|AQAAAA|2-\d)/.test(t) || /^[A-Za-z0-9_-]{30,}$/.test(t)) {
        remove(row, 300);
        return later(500, () => short(`${E('warning')} Токены вставляй в приложении, не сюда. Сообщение удалил.`));
      }
      return later(400, () => short(`Не понял тебя ${E('info')} Нажми /start — там всё кнопками.`));
  }
}

function onPhoto() {
  minePhoto();
  if (S.expect === 'report') return later(450, () => { openTicket(); later(500, () => short(`${E('attached')} Прикреплено`)); });
  if (S.ticket) return later(300, () => short(`${E('attached')} Прикреплено`));
  later(400, () => short(`${E('info')} Файлы уходят в поддержку. Сначала открой обращение: ${E('bug')} Баг / Идея`));
}

function openTicket() {
  const id = Math.random().toString(16).slice(2, 10);
  S.ticket = { id, ...S.report };
  S.expect = null; S.report = null;
  $('#support-tools').hidden = false;
  send({
    html: `<b>Отправлено!</b> ${E('success')}\n${Q(`Обращение ${C(`#${id}`)} создано. Пиши сюда — всё уйдёт в поддержку.`)}`,
    kb: [[B('Закрыть обращение', 'cancel', () => closeTicket())]],
  });
}

function closeTicket() {
  if (!S.ticket) return;
  short(`${E('closed')} Обращение ${C(`#${S.ticket.id}`)} закрыто.\n${Q(`Если вопрос не решён — открой новое: ${E('bug')} Баг / Идея`)}`);
  S.ticket = null;
  $('#support-tools').hidden = true;
}

function supportAction(kind) {
  const tk = S.ticket;
  if (!tk) return toast('Открытого обращения нет');
  const what = tk.kind === 'idea' ? 'Твоя идея' : 'Твой баг-репорт';
  const done = tk.kind === 'idea' ? 'принята' : 'принят';
  const no = tk.kind === 'idea' ? 'отклонена' : 'отклонён';
  if (kind === 'reply') short(`${E('support')} <b>Поддержка:</b>\nСпасибо! Посмотрим и вернёмся с ответом.`);
  if (kind === 'accept') short(`${E('success')} ${what} ${C(`#${tk.id}`)} ${E('confirm')} ${done}`);
  if (kind === 'reject') short(`${E('cancel')} ${what} ${C(`#${tk.id}`)} ${no}\n${Q('Причина: уже есть в планах')}`);
  if (kind === 'fixed') short(`${E('fixed')} Исправлено в версии <b>0.2.0</b> · ${C(`#${tk.id}`)}`);
  if (kind === 'close') closeTicket();
}

// ---------- окно подтверждения входа (приложение) ----------
let authTimer;
function openAuth(m) {
  const box = $('#auth');
  const yes = $('#auth-yes');
  const lbl = yes.querySelector('.lbl');
  box.hidden = false; box.classList.remove('closing');
  yes.disabled = true; yes.classList.remove('run'); void yes.offsetWidth; yes.classList.add('run');
  let n = 3; lbl.textContent = `Разрешить · ${n}`;
  clearInterval(authTimer);
  authTimer = setInterval(() => {
    n -= 1;
    if (n > 0) lbl.textContent = `Разрешить · ${n}`;
    else { clearInterval(authTimer); lbl.textContent = 'Разрешить'; yes.disabled = false; }
  }, 1000);
  const close = () => { box.classList.add('closing'); setTimeout(() => { box.hidden = true; }, 160); clearInterval(authTimer); };
  yes.onclick = () => {
    close();
    edit(m, { html: `<b>Успешно!</b> ${E('success')}\n${Q(`Аккаунт ${C('folzy')} теперь привязан к Telegram`)}` });
    setWho('user');
    later(1500, () => send(scr.main()));
  };
  $('#auth-no').onclick = () => { close(); edit(m, { html: `${E('cancel')} <b>Вход отклонён</b>\n${Q('Запрос закрыт на устройстве, где ты уже вошёл.')}`, kb: [[B('Попробовать снова', 'refresh', (mm) => go.login(mm))]] }); };
}

// ---------- боковая панель ----------
function setWho(v) {
  S.who = v;
  document.querySelectorAll('#who button').forEach((b) => b.classList.toggle('on', b.dataset.v === v));
}

const JUMPS = [
  ['/start без аккаунта', 'login', () => { setWho('guest'); send(scr.guest()); }],
  ['Вход логином', 'key', () => { setWho('guest'); const m = send(scr.guest()); later(450, () => go.login(m)); }],
  ['Быстрая ссылка', 'quick_link', () => { setWho('guest'); S.expect = null; send(scr.quick()); }],
  ['Регистрация', 'register', () => { setWho('guest'); const m = send(scr.guest()); later(450, () => go.register(m)); }],
  ['Главное меню', 'menu', () => { if (!linked()) setWho('user'); send(scr.main()); }],
  ['Профиль', 'profile', () => { if (!linked()) setWho('user'); send(scr.profile()); }],
  ['Интеграция', 'integration', () => { if (!linked()) setWho('user'); send(scr.integration()); }],
  ['Рефералка', 'referral', () => { if (!linked()) setWho('user'); send(scr.referral()); }],
  ['Версии', 'versions', () => { if (!linked()) setWho('user'); send(scr.versions()); }],
  ['Статистика', 'stats', () => { if (!linked()) setWho('user'); send(scr.stats()); }],
  ['Сервисы', 'services', () => { if (!linked()) setWho('user'); send(scr.services()); }],
  ['Баг / Идея', 'bug', () => { if (!linked()) setWho('user'); send(scr.reportKind()); }],
  ['/status', 'status_ok', () => { mine('/status'); later(350, () => send(scr.status())); }],
];

function initSide() {
  const jump = $('#jump');
  for (const [label, icon, fn] of JUMPS) {
    const b = document.createElement('button');
    b.className = 'side-btn';
    b.innerHTML = `<img src="emoji/${icon}.png" alt="">${label}`;
    b.onclick = () => { S.expect = null; fn(); };
    jump.append(b);
  }
  $('#who').addEventListener('click', (e) => {
    const v = e.target.closest('button')?.dataset.v; if (!v) return;
    setWho(v); S.expect = null;
    send(v === 'guest' ? scr.guest() : scr.main());
  });
  $('#health').addEventListener('click', (e) => {
    const v = e.target.closest('button')?.dataset.v; if (!v) return;
    S.health = v;
    document.querySelectorAll('#health button').forEach((b) => b.classList.toggle('on', b.dataset.v === v));
    toast('Состояние сменится при следующем /status или «Обновить»');
  });
  document.querySelectorAll('[data-sup]').forEach((b) => { b.onclick = () => supportAction(b.dataset.sup); });
}

function escapeHtml(s) { return s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }

// ---------- поле ввода ----------
$('#composer').addEventListener('submit', (e) => { e.preventDefault(); const v = input.value; input.value = ''; onText(v); });
$('#clip').addEventListener('click', onPhoto);
$('#cmd-btn').addEventListener('click', () => { const p = $('#cmd-pop'); p.hidden = !p.hidden; });
document.querySelectorAll('#cmd-pop button').forEach((b) => { b.onclick = () => { $('#cmd-pop').hidden = true; onText(b.dataset.cmd); }; });
$('#clear').addEventListener('click', () => { feed.innerHTML = ''; S.expect = null; });

initSide();
mine('/start');
later(300, () => send(scr.main()));
