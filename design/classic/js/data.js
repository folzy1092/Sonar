// Выдуманные, но правдоподобные данные прототипа. Артисты, тексты и обложки — придуманы.
window.Sonar = window.Sonar || {}
;(function (S) {
  const F = Object.freeze
  const SERVICES = F({
    sc: { short: 'SC', name: 'SoundCloud' },
    ym: { short: 'Я', name: 'Яндекс Музыка' },
    yt: { short: 'YT', name: 'YouTube Music' },
    vk: { short: 'VK', name: 'VK Музыка' },
    sp: { short: 'Sp', name: 'Spotify' },
    file: { short: '', name: 'Файл с компьютера' },
  })

  const ARTISTS = F([
    { id: 'a1', name: 'nightdrive edits', color: '#ff2d95', pattern: 'orbit', listeners: '48 тыс.', genre: 'slowed / edits' },
    { id: 'a2', name: 'Mira Holt', color: '#2740b8', pattern: 'arcs', listeners: '1,2 млн', genre: 'dream pop' },
    { id: 'a3', name: 'Ветер Севера', color: '#dccaa8', pattern: 'split', listeners: '312 тыс.', genre: 'инди' },
    { id: 'a4', name: 'Owen Vale', color: '#141416', pattern: 'grid', listeners: '640 тыс.', genre: 'электроника' },
    { id: 'a5', name: 'Кира Ланская', color: '#5f9b3a', pattern: 'bands', listeners: '890 тыс.', genre: 'поп' },
    { id: 'a6', name: 'harborlights', color: '#e8692b', pattern: 'arcs', listeners: '95 тыс.', genre: 'sped up' },
    { id: 'a7', name: 'Сонная Артемида', color: '#7b4bd6', pattern: 'orbit', listeners: '204 тыс.', genre: 'лоу-фай' },
    { id: 'a8', name: 'Lena Brandt', color: '#c2483e', pattern: 'split', listeners: '77 тыс.', genre: 'synth' },
    { id: 'a9', name: 'Kasia Lind', color: '#9fb7c9', pattern: 'wave', listeners: '150 тыс.', genre: 'ambient' },
    { id: 'a10', name: 'Полярная Ночь', color: '#2a2f45', pattern: 'grid', listeners: '58 тыс.', genre: 'пост-рок' },
    { id: 'a11', name: 'Tidewater', color: '#3a5a52', pattern: 'wave', listeners: '410 тыс.', genre: 'chillwave' },
    { id: 'a12', name: 'Северный Мост', color: '#8a6f4e', pattern: 'bands', listeners: '120 тыс.', genre: 'инди' },
    { id: 'a13', name: 'Ivo Marr', color: '#b8b0a2', pattern: 'split', listeners: '33 тыс.', genre: 'darkwave' },
    { id: 'a14', name: 'Кассета 84', color: '#d9a03b', pattern: 'arcs', listeners: '260 тыс.', genre: 'синти-поп' },
    { id: 'a15', name: 'Saltmarsh', color: '#4f6f8f', pattern: 'orbit', listeners: '22 тыс.', genre: 'shoegaze' },
    { id: 'a16', name: 'Daria Fen', color: '#a23d6d', pattern: 'wave', listeners: '510 тыс.', genre: 'r&b' },
  ])

  const ALBUMS = F([
    { id: 'al1', title: 'Лето в бетоне', aid: 'a5', year: 2025, kind: 'Альбом', color: '#5f9b3a', pattern: 'bands' },
    { id: 'al2', title: 'Lowlight — EP', aid: 'a2', year: 2024, kind: 'EP', color: '#2740b8', pattern: 'arcs' },
    { id: 'al3', title: 'Polar Drift', aid: 'a4', year: 2023, kind: 'Альбом', color: '#9fb7c9', pattern: 'wave' },
    { id: 'al4', title: 'Сквозняк', aid: 'a3', year: 2026, kind: 'Сингл', color: '#dccaa8', pattern: 'split' },
    { id: 'al5', title: 'Ночные эдиты, том 2', aid: 'a1', year: 2026, kind: 'Сборник', color: '#ff2d95', pattern: 'orbit' },
    { id: 'al6', title: 'Тише воды', aid: 'a7', year: 2025, kind: 'Альбом', color: '#7b4bd6', pattern: 'orbit' },
    { id: 'al7', title: 'Glasshouse', aid: 'a2', year: 2026, kind: 'Альбом', color: '#5a74d6', pattern: 'grid' },
    { id: 'al8', title: 'Freundschaft', aid: 'a8', year: 2025, kind: 'EP', color: '#c2483e', pattern: 'split' },
  ])

  // pattern — рисунок абстрактной обложки (art.js), color — её основной цвет
  const TRACKS = F([
    { id: 't1', title: 'ЛУННЫЙ ПАРК - Вдоль проводов (slowed + reverb)', artist: 'nightdrive edits', aid: 'a1', al: 'al5', service: 'sc', color: '#ff2d95', pattern: 'orbit', dur: 214, bpm: 84, added: 'сегодня' },
    { id: 't2', title: 'Lowlight', artist: 'Mira Holt', aid: 'a2', al: 'al2', service: 'sp', color: '#2740b8', pattern: 'arcs', dur: 197, bpm: 96, added: 'вчера' },
    { id: 't3', title: 'Сквозняк', artist: 'Ветер Севера', aid: 'a3', al: 'al4', service: 'ym', color: '#dccaa8', pattern: 'split', dur: 241, bpm: 72, added: '2 дня назад' },
    { id: 't4', title: 'Paper Satellites', artist: 'Owen Vale & Kasia Lind', aid: 'a4', al: 'al3', service: 'yt', color: '#141416', pattern: 'grid', dur: 263, bpm: 110, added: '18 ноя' },
    { id: 't5', title: 'Бетон и сирень', artist: 'Кира Ланская', aid: 'a5', al: 'al1', service: 'vk', color: '#5f9b3a', pattern: 'bands', dur: 188, bpm: 124, added: '16 ноя' },
    { id: 't6', title: 'demo_final_v3_НОЧЬ.flac', artist: 'Локальный файл', aid: null, al: null, service: 'file', color: '#8c8c8c', pattern: 'wave', dur: 156, bpm: 90, added: '12 ноя' },
    { id: 't7', title: 'Midnight Ferry (Sped Up)', artist: 'harborlights', aid: 'a6', al: null, service: 'sc', color: '#e8692b', pattern: 'arcs', dur: 131, bpm: 140, added: '9 ноя' },
    { id: 't8', title: 'Не звони после двух', artist: 'Сонная Артемида', aid: 'a7', al: 'al6', service: 'ym', color: '#7b4bd6', pattern: 'orbit', dur: 222, bpm: 78, added: '3 ноя' },
    { id: 't9', title: 'Nachtschwärmerfreundschaftsgeschichten', artist: 'Lena Brandt', aid: 'a8', al: 'al8', service: 'sp', color: '#c2483e', pattern: 'split', dur: 249, bpm: 104, added: '28 окт' },
    { id: 't10', title: 'Glasshouse', artist: 'Mira Holt', aid: 'a2', al: 'al7', service: 'yt', color: '#5a74d6', pattern: 'grid', dur: 205, bpm: 92, added: '21 окт' },
    { id: 't11', title: 'ПОСЛЕДНИЙ ТРАМВАЙ - Огни (sped up)', artist: 'nightdrive edits', aid: 'a1', al: 'al5', service: 'sc', color: '#f04a7a', pattern: 'wave', dur: 142, bpm: 132, added: '14 окт' },
    { id: 't12', title: 'Холодный чай', artist: 'Сонная Артемида', aid: 'a7', al: 'al6', service: 'vk', color: '#6a5acd', pattern: 'bands', dur: 176, bpm: 82, added: '2 окт' },
  ])

  const SWATCHES = F([
    { name: 'Почти чёрная', color: '#141416' },
    { name: 'Кислотно-розовая', color: '#ff2d95' },
    { name: 'Бежевая', color: '#dccaa8' },
    { name: 'Глубокая синяя', color: '#2740b8' },
    { name: 'Травяная', color: '#5f9b3a' },
    { name: 'Монохром', color: '#8c8c8c' },
  ])

  const MOODS = F([
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

  // Плейлисты Sonar — свои, смешанные (треки разных сервисов вместе)
  const PLAYLISTS = F([
    { id: 'pl0', title: 'Ночная смена', color: '#2a2f45', pattern: 'grid', note: 'Когда все уже спят, а ты ещё нет', tracks: ['t1', 't8', 't4', 't12', 't9', 't3', 't11'] },
    { id: 'pl1', title: 'Дорога домой', color: '#e8692b', pattern: 'split', note: 'Сорок минут от офиса до подъезда', tracks: ['t5', 't2', 't7', 't10', 't3'] },
    { id: 'pl2', title: 'slowed / reverb', color: '#ff2d95', pattern: 'wave', note: 'Всё медленнее и глубже', tracks: ['t1', 't11', 't7', 't6'] },
    { id: 'pl3', title: 'Для зала — тяжёлое', color: '#141416', pattern: 'bands', note: '', tracks: ['t7', 't11', 't5', 't4'] },
    { id: 'pl4', title: 'Умный: 2019–2021, ♥', color: '#7b4bd6', pattern: 'orbit', smart: true, note: 'Лайкнуто · вышло в 2019–2021 · обновляется сам', tracks: ['t2', 't8', 't12', 't9'] },
  ])

  // Плейлисты сервисов видны «фантомно» — их можно перенести в Sonar
  const PHANTOMS = F([
    { id: 'ph1', title: 'Мне нравится', service: 'ym', count: 1024, color: '#e9c46a', pattern: 'orbit' },
    { id: 'ph2', title: 'Likes', service: 'sc', count: 612, color: '#f26b38', pattern: 'wave' },
    { id: 'ph3', title: 'Discover Weekly', service: 'sp', count: 30, color: '#3f8f5a', pattern: 'grid' },
    { id: 'ph4', title: 'Мои треки', service: 'vk', count: 341, color: '#4a76a8', pattern: 'bands' },
  ])

  const RECENT = F([
    { to: 'album/al1', title: 'Лето в бетоне', sub: 'Кира Ланская · альбом', color: '#5f9b3a', pattern: 'bands' },
    { to: 'playlist/pl0', title: 'Ночная смена', sub: 'Плейлист · 7 треков', color: '#2a2f45', pattern: 'grid' },
    { to: 'album/al2', title: 'Lowlight — EP', sub: 'Mira Holt', color: '#2740b8', pattern: 'arcs' },
    { to: 'liked', title: 'Любимые', sub: '1 284 трека', color: '#ff2d95', pattern: 'orbit' },
    { to: 'album/al3', title: 'Polar Drift', sub: 'Owen Vale · альбом', color: '#9fb7c9', pattern: 'wave' },
    { to: 'playlist/pl1', title: 'Дорога домой', sub: 'Плейлист · смешанный', color: '#e8692b', pattern: 'split' },
    { to: 'album/al4', title: 'Сквозняк', sub: 'Ветер Севера · сингл', color: '#dccaa8', pattern: 'split' },
  ])

  const MIXES = F([
    { mood: 'night', title: 'Ночное', sub: 'Sonar Mix · настроение', color: '#2b2350', pattern: 'orbit' },
    { mood: 'focus', title: 'Концентрация', sub: 'Sonar Mix · настроение', color: '#3a5a52', pattern: 'grid' },
    { mood: 'base', title: 'Похоже на Mira Holt', sub: 'Волна по артисту', color: '#2740b8', pattern: 'arcs' },
    { mood: 'top', title: 'Открытия недели', sub: 'Новое для тебя', color: '#c2483e', pattern: 'bands' },
  ])

  const LOCAL_FILES = F({ folders: ['D:\\Музыка\\Демки', 'C:\\Users\\Folzy\\Music'], tracks: ['t6'] })

  S.data = F({ SERVICES, ARTISTS, ALBUMS, TRACKS, SWATCHES, MOODS, PLAYLISTS, PHANTOMS, RECENT, MIXES, LOCAL_FILES })
})(window.Sonar)
