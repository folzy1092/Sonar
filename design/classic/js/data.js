// Выдуманные, но правдоподобные данные прототипа. Артисты и обложки — придуманы.
window.Sonar = window.Sonar || {}
;(function (S) {
  const SERVICES = Object.freeze({
    sc: { short: 'SC', name: 'SoundCloud' },
    ym: { short: 'Я', name: 'Яндекс Музыка' },
    yt: { short: 'YT', name: 'YouTube Music' },
    vk: { short: 'VK', name: 'VK Музыка' },
    sp: { short: 'Sp', name: 'Spotify' },
    file: { short: '', name: 'Файл с компьютера' },
  })

  // pattern — рисунок абстрактной обложки (covers.js), color — её основной цвет
  const TRACKS = Object.freeze([
    { id: 't1', title: 'ЛУННЫЙ ПАРК - Вдоль проводов (slowed + reverb)', artist: 'nightdrive edits', service: 'sc', color: '#ff2d95', pattern: 'orbit', dur: 214, bpm: 84 },
    { id: 't2', title: 'Lowlight', artist: 'Mira Holt', service: 'sp', color: '#2740b8', pattern: 'arcs', dur: 197, bpm: 96 },
    { id: 't3', title: 'Сквозняк', artist: 'Ветер Севера', service: 'ym', color: '#dccaa8', pattern: 'split', dur: 241, bpm: 72 },
    { id: 't4', title: 'Paper Satellites', artist: 'Owen Vale & Kasia Lind', service: 'yt', color: '#141416', pattern: 'grid', dur: 263, bpm: 110 },
    { id: 't5', title: 'Бетон и сирень', artist: 'Кира Ланская', service: 'vk', color: '#5f9b3a', pattern: 'bands', dur: 188, bpm: 124 },
    { id: 't6', title: 'demo_final_v3_НОЧЬ.flac', artist: 'Локальный файл', service: 'file', color: '#8c8c8c', pattern: 'wave', dur: 156, bpm: 90 },
    { id: 't7', title: 'Midnight Ferry (Sped Up)', artist: 'harborlights', service: 'sc', color: '#e8692b', pattern: 'arcs', dur: 131, bpm: 140 },
    { id: 't8', title: 'Не звони после двух', artist: 'Сонная Артемида', service: 'ym', color: '#7b4bd6', pattern: 'orbit', dur: 222, bpm: 78 },
  ])

  const SWATCHES = Object.freeze([
    { name: 'Почти чёрная', color: '#141416' },
    { name: 'Кислотно-розовая', color: '#ff2d95' },
    { name: 'Бежевая', color: '#dccaa8' },
    { name: 'Глубокая синяя', color: '#2740b8' },
    { name: 'Травяная', color: '#5f9b3a' },
    { name: 'Монохром', color: '#8c8c8c' },
  ])

  const MOODS = Object.freeze([
    { id: 'base', name: 'Обычное', line: 'Твой вкус, понемногу нового' },
    { id: 'happy', name: 'Весёлое', line: 'Светло, быстро, с улыбкой' },
    { id: 'calm', name: 'Спокойное', line: 'Тихо и тепло, без резких поворотов' },
    { id: 'sad', name: 'Грустное', line: 'Медленно, честно, под дождь' },
    { id: 'hard', name: 'Жёсткое', line: 'Плотный звук и тяжёлый бит' },
    { id: 'night', name: 'Ночное', line: 'Для дороги после полуночи' },
    { id: 'sleep', name: 'Сон', line: 'Почти без слов, всё тише к концу' },
    { id: 'top', name: 'Популярное', line: 'То, что сейчас слушают все' },
    { id: 'focus', name: 'Концентрация', line: 'Ровный фон, ничего не отвлекает' },
  ])

  const RECENT = Object.freeze([
    { title: 'Лето в бетоне', sub: 'Кира Ланская · альбом', color: '#5f9b3a', pattern: 'bands' },
    { title: 'Ночная смена', sub: 'Плейлист · 48 треков', color: '#2a2f45', pattern: 'grid' },
    { title: 'Lowlight — EP', sub: 'Mira Holt', color: '#2740b8', pattern: 'arcs' },
    { title: 'Любимые', sub: '1 284 трека', color: '#ff2d95', pattern: 'orbit' },
    { title: 'Polar Drift', sub: 'Owen Vale · альбом', color: '#9fb7c9', pattern: 'wave' },
    { title: 'Дорога домой', sub: 'Плейлист · смешанный', color: '#e8692b', pattern: 'split' },
    { title: 'Сквозняк', sub: 'Ветер Севера · сингл', color: '#dccaa8', pattern: 'split' },
  ])

  const MIXES = Object.freeze([
    { title: 'Ночное', sub: 'Sonar Mix · настроение', color: '#2b2350', pattern: 'orbit' },
    { title: 'Концентрация', sub: 'Sonar Mix · настроение', color: '#3a5a52', pattern: 'grid' },
    { title: 'Похоже на Mira Holt', sub: 'Волна по артисту', color: '#2740b8', pattern: 'arcs' },
    { title: 'Открытия недели', sub: 'Новое для тебя', color: '#c2483e', pattern: 'bands' },
  ])

  const PLAYLISTS = Object.freeze([
    { title: 'Ночная смена', color: '#2a2f45', pattern: 'grid' },
    { title: 'Дорога домой', color: '#e8692b', pattern: 'split' },
    { title: 'slowed / reverb', color: '#ff2d95', pattern: 'wave' },
    { title: 'Для зала — тяжёлое', color: '#141416', pattern: 'bands' },
    { title: 'Умный: 2019–2021, ♥', color: '#7b4bd6', pattern: 'orbit', smart: true },
  ])

  S.data = Object.freeze({ SERVICES, TRACKS, SWATCHES, MOODS, RECENT, MIXES, PLAYLISTS })
})(window.Sonar)
