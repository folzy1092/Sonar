// Данные экранов посложнее: тексты с таймингом и пояснениями, статистика, итоги, карта исполнителей,
// поиск, эквалайзер, тарифы Sonar Deep, обновление. Всё выдумано.
window.Sonar = window.Sonar || {}
;(function (S) {
  const F = Object.freeze

  // Строка текста: t — начало (с), text — строка, ann — пояснение к строке (кнопка «i» справа).
  // Пустой text — проигрыш. Тайминги слов считаются в full.js пропорционально длине слова.
  const LYRICS = F({
    t1: F([
      { t: 8, text: 'Вдоль проводов идёт тихий ток' },
      { t: 13, text: 'Город уснул, а я не смог' },
      { t: 18.5, text: 'Фонари считают мои шаги' },
      { t: 24, text: 'Ты сказала: «просто беги»', ann: 'Эта же фраза — в припеве первого сингла ЛУННОГО ПАРКА. Эдит возвращает её в два раза медленнее.' },
      { t: 30, text: '' },
      { t: 36, text: 'Вдоль проводов — до самой зари' },
      { t: 41.5, text: 'Всё, что болит, держи внутри' },
      { t: 47, text: 'Красный, зелёный, снова красный' },
      { t: 52.5, text: 'Мы на мосту, и вечер ясный', ann: 'Мост — тот же, что на обложке. Его снимали с телефона в четыре утра.' },
      { t: 58, text: 'Вдоль проводов идёт тихий ток' },
      { t: 63.5, text: 'Город уснул, а я не смог' },
      { t: 69, text: 'Если услышишь — не отвечай' },
      { t: 74.5, text: 'Просто включи и не выключай' },
      { t: 80, text: '' },
      { t: 88, text: 'Вдоль проводов…' },
      { t: 94, end: true },
    ]),
    t2: F([
      { t: 6, text: 'Low light on the kitchen floor' },
      { t: 11, text: 'Every word we had before' },
      { t: 16, text: 'Folded up and put away' },
      { t: 21, text: 'Still I hear you anyway', ann: 'Mira дописала эту строку в ночь, когда EP уже сдали на сведение. Демо без неё лежит у неё на SoundCloud.' },
      { t: 27, text: '' },
      { t: 33, text: 'Keep it low, keep it slow' },
      { t: 38, text: 'Only the radio knows' },
      { t: 43, text: 'How we left the porch light on' },
      { t: 48.5, text: 'Long after the night was gone', ann: '«Свет на крыльце» — сквозной образ всего Lowlight — EP: он есть в трёх песнях из пяти.' },
      { t: 54, text: 'Low light, low light' },
      { t: 58, text: 'Stay with me tonight' },
      { t: 63, end: true },
    ]),
  })

  // Детерминированная «волна» значений для графиков
  const series = (n, base, amp, seed) =>
    F(Array.from({ length: n }, (_, i) => Math.round(base + amp * Math.sin(i * 1.7 + seed) + amp * 0.5 * Math.cos(i * 0.6 + seed * 2))))

  const STATS = F({
    week: F({
      label: 'Неделя', minutes: 1284, tracks: 312, artists: 87, fresh: 23,
      bars: F([142, 96, 210, 188, 164, 276, 208]), labels: F(['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс']),
      top: F([['a1', 64], ['a2', 51], ['a7', 38], ['a5', 27], ['a4', 19]]),
      tracks5: F([['t1', 22], ['t2', 17], ['t8', 14], ['t11', 11], ['t5', 9]]),
      services: F([['sc', 41], ['ym', 24], ['sp', 15], ['yt', 11], ['vk', 7], ['file', 2]]),
    }),
    month: F({
      label: 'Месяц', minutes: 5410, tracks: 1290, artists: 214, fresh: 96,
      bars: series(30, 180, 70, 1), labels: F(Array.from({ length: 30 }, (_, i) => String(i + 1))),
      top: F([['a2', 212], ['a1', 198], ['a7', 140], ['a3', 96], ['a14', 71]]),
      tracks5: F([['t2', 74], ['t1', 69], ['t3', 41], ['t8', 40], ['t10', 33]]),
      services: F([['sc', 38], ['ym', 27], ['sp', 16], ['yt', 10], ['vk', 7], ['file', 2]]),
    }),
    year: F({
      label: 'Год', minutes: 61240, tracks: 14820, artists: 1312, fresh: 708,
      bars: series(12, 5100, 1400, 3), labels: F(['янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек']),
      top: F([['a2', 1204], ['a1', 1011], ['a7', 760], ['a5', 512], ['a3', 498]]),
      tracks5: F([['t2', 318], ['t1', 290], ['t8', 201], ['t5', 177], ['t3', 160]]),
      services: F([['sc', 41], ['ym', 27], ['sp', 14], ['yt', 10], ['vk', 6], ['file', 2]]),
    }),
  })

  // Итоги года — «истории»: каждая 5 с, клик слева — назад, справа — вперёд
  const RECAP = F([
    { kind: 'intro', color: '#2740b8', pattern: 'arcs', eyebrow: 'Итоги 2026', big: '61 240', unit: 'минут музыки', line: 'Это 42 дня без перерыва. Спасибо, что слушал с Sonar.' },
    { kind: 'artist', color: '#2740b8', pattern: 'arcs', eyebrow: 'Артист года', aid: 'a2', big: 'Mira Holt', unit: '1 204 прослушивания', line: 'Чаще всего — по вечерам в будни, после 22:00.' },
    { kind: 'track', color: '#ff2d95', pattern: 'orbit', eyebrow: 'Трек года', tid: 't2', big: 'Lowlight', unit: '318 раз', line: 'Ты включал его 4 раза подряд 14 марта.' },
    { kind: 'mood', color: '#2b2350', pattern: 'orbit', eyebrow: 'Настроение года', big: 'Ночное', unit: '38 % всего Sonar Mix', line: 'А «Концентрация» выручала по понедельникам.' },
    { kind: 'svc', color: '#3a5a52', pattern: 'grid', eyebrow: 'Откуда музыка', big: '5 сервисов', unit: 'в одной медиатеке', line: 'SoundCloud — 41 %, Яндекс — 27 %, Spotify — 14 %, YouTube — 10 %, VK — 6 %.' },
  ])

  // Карта исполнителей: координаты в поле 1000×640, рёбра — «похожи»
  const MAP = F({
    nodes: F({
      a1: [500, 300], a2: [640, 230], a3: [330, 210], a4: [700, 420], a5: [380, 400], a6: [560, 470],
      a7: [430, 120], a8: [820, 330], a9: [800, 160], a10: [200, 320], a11: [640, 90], a12: [240, 470],
      a13: [900, 470], a14: [520, 580], a15: [140, 160], a16: [340, 560],
    }),
    edges: F([
      ['a1', 'a2'], ['a1', 'a6'], ['a1', 'a5'], ['a1', 'a7'], ['a1', 'a3'], ['a2', 'a9'], ['a2', 'a11'], ['a2', 'a4'],
      ['a2', 'a7'], ['a3', 'a7'], ['a3', 'a10'], ['a3', 'a15'], ['a4', 'a8'], ['a4', 'a6'], ['a4', 'a13'], ['a5', 'a12'],
      ['a5', 'a16'], ['a5', 'a14'], ['a6', 'a14'], ['a8', 'a13'], ['a8', 'a9'], ['a9', 'a11'], ['a10', 'a12'], ['a10', 'a15'],
      ['a12', 'a16'], ['a14', 'a16'], ['a7', 'a11'],
    ]),
  })

  const SEARCH_RECENT = F(['Mira Holt', 'сквозняк', 'slowed reverb', 'https://open.spotify.com/playlist/37i9dQZF1DX4sWSpwq3LiO'])
  const SEARCH_FILTERS = F([['all', 'Все'], ['sc', 'SoundCloud'], ['ym', 'Яндекс'], ['yt', 'YouTube'], ['vk', 'VK'], ['sp', 'Spotify'], ['file', 'Файлы']])

  const EQ_BANDS = F(['32', '64', '125', '250', '500', '1к', '2к', '4к', '8к', '12к', '16к', '20к'])
  const EQ_PRESETS = F({
    flat: F({ name: 'Ровно', bands: F([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) }),
    bass: F({ name: 'Больше баса', bands: F([7, 6, 5, 3, 1, 0, 0, 0, 0, 0, 0, 0]) }),
    vocal: F({ name: 'Голос', bands: F([-2, -2, -1, 0, 2, 4, 5, 4, 2, 0, -1, -1]) }),
    night: F({ name: 'Ночью тише', bands: F([-3, -2, -1, 0, 0, 0, -1, -2, -3, -4, -5, -6]) }),
    bright: F({ name: 'Ярче', bands: F([0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 5, 4]) }),
  })

  // Sonar Deep: цены — зеркало windows/src/lib/subscription.ts (черновик)
  const PLANS = F([
    { id: 'ping', name: 'Ping', seats: 1, price: 100 },
    { id: 'echo', name: 'Echo', seats: 2, price: 190 },
    { id: 'pod', name: 'Pod', seats: 3, price: 285 },
    { id: 'fleet', name: 'Fleet', seats: 4, price: 380 },
  ])
  const PERIODS = F([[1, 0], [3, 10], [6, 15], [12, 25]])
  const DEEP_FEATURES = F(['Эффекты 3D, 8D, 12D и 16D', 'Реверб и «зал»', 'Расширенный пульт с iPhone', 'Свой фон плеера — видео до 10 с'])

  const UPDATE = F({
    version: '0.2.0', size: '14,2 МБ',
    notes: F(['Карта исполнителей стала быстрее', 'Караоке в тексте — по словам', 'Исправлен вход в SoundCloud после сна ПК']),
  })

  const SERVICE_STATE = F([
    { id: 'sc', state: 'error', who: 'folzy', line: 'Вход устарел — SoundCloud вернул 401' },
    { id: 'ym', state: 'on', who: 'Folzy', line: 'Плюс · качество до FLAC' },
    { id: 'yt', state: 'on', who: 'folzy.music', line: 'Подключён 12 ноября' },
    { id: 'vk', state: 'off', who: '', line: 'Не подключён' },
    { id: 'sp', state: 'on', who: 'folzy', line: 'Только поиск и импорт' },
    { id: 'file', state: 'on', who: '', line: '2 папки · 148 файлов' },
  ])

  S.more = F({
    LYRICS, STATS, RECAP, MAP, SEARCH_RECENT, SEARCH_FILTERS, EQ_BANDS, EQ_PRESETS,
    PLANS, PERIODS, DEEP_FEATURES, UPDATE, SERVICE_STATE,
  })
})(window.Sonar)
