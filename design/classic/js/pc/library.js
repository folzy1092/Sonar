// ПК: медиатека — Любимые, плейлисты (свои и «фантомные» из сервисов), исполнители, альбомы, файлы —
// и страницы коллекций: плейлист, альбом, исполнитель.
window.Sonar = window.Sonar || {}
;(function (S) {
  const { icon, badge } = S
  const P = S.parts
  const D = S.data
  const H = S.h
  const F = Object.freeze

  const head = (title, sub = '', extra = '') =>
    `<div class="page-head"><h1>${title}</h1>${sub ? `<span class="date">${sub}</span>` : ''}<div class="head-extra">${extra}</div></div>`
  const grid = (cards) => `<div class="grid">${cards}</div>`
  const totalDur = (ids) => H.dur(H.sum(ids.map((id) => H.track(id)?.dur || 0)))
  const tracksLine = (ids) => `${P.services(ids)}<span>${H.tn(ids.length, ['трек', 'трека', 'треков'])} · ${totalDur(ids)}</span>`
  const neighbours = (aid) => S.more.MAP.edges.filter((e) => e.includes(aid)).map((e) => (e[0] === aid ? e[1] : e[0]))

  const albumCard = (al) => P.card({ to: `album/${al.id}`, title: al.title, sub: `${H.artist(al.aid).name} · ${al.year}`, color: al.color, pattern: al.pattern })
  const artistCard = (a) => P.card({ to: `artist/${a.id}`, title: a.name, sub: a.genre, color: a.color, pattern: a.pattern }, true)
  const plCard = (p) => P.card({ to: `playlist/${p.id}`, title: p.title, sub: p.smart ? 'Умный плейлист' : H.tn(p.tracks.length, ['трек', 'трека', 'треков']), color: p.color, pattern: p.pattern })

  // ── Любимые ───────────────────────────────────────────
  const liked = (s) => {
    const c = H.collection('liked', s)
    return P.collHead(c, 'liked', { kindLabel: 'Свои лайки Sonar', sub: tracksLine(s.liked) }) +
      `<p class="coll-note">Лайки живут в Sonar, а не в сервисах — треки SoundCloud, Яндекса и Spotify лежат в одном списке.</p>` +
      P.ttable(s.liked, { src: 'liked' })
  }

  // ── Плейлисты ─────────────────────────────────────────
  const phantom = (p, s) => {
    const moved = s.moved.includes(p.id)
    return `<div class="phantom${moved ? ' moved' : ''}">` +
      `<div class="cv phantom-cv">${S.cover(p.color, p.pattern)}</div>` +
      `<div class="phantom-meta"><b class="ellipsis">${H.esc(p.title)}</b><span>${badge(p.service)}${D.SERVICES[p.service].name} · ${H.tn(p.count, ['трек', 'трека', 'треков'])}</span></div>` +
      (moved
        ? `<span class="phantom-done">${icon('check')}В Sonar</span>`
        : `<button class="btn btn-soft sm" data-act="transfer" data-id="${p.id}">${icon('transfer')}<span>Перенести</span></button>`) +
      `</div>`
  }
  const playlists = (s) =>
    head('Плейлисты', 'Свои — смешанные из любых сервисов', `<button class="btn btn-accent" data-act="new-playlist">${icon('plus')}<span>Новый плейлист</span></button>`) +
    grid(D.PLAYLISTS.map(plCard).join('')) +
    `<section class="shelf"><div class="shelf-head"><h2>Из сервисов</h2><span class="shelf-sub">Видны, но не твои — перенеси в Sonar, чтобы править</span></div>` +
    `<div class="phantoms">${D.PHANTOMS.map((p) => phantom(p, s)).join('')}</div></section>`

  // ── Исполнители, альбомы, файлы ───────────────────────
  const artists = () => head('Исполнители', 'Подписки и те, кого ты лайкал') + grid(D.ARTISTS.map(artistCard).join(''))
  const albums = () => head('Альбомы', 'Сохранённые') + grid(D.ALBUMS.map(albumCard).join(''))
  const files = () =>
    head('Файлы', 'Музыка с этого компьютера', `<button class="btn btn-soft" data-act="add-folder">${icon('folder')}<span>Добавить папку</span></button>`) +
    `<div class="folders">${D.LOCAL_FILES.folders.map((f) => `<div class="folder">${icon('folder')}<span class="ellipsis">${H.esc(f)}</span><span class="folder-n">следит за изменениями</span></div>`).join('')}</div>` +
    P.ttable(D.LOCAL_FILES.tracks, { src: '', album: false })

  // ── Коллекции ─────────────────────────────────────────
  const playlist = (s, id) => {
    const c = H.collection(`playlist/${id}`, s)
    if (!c) return P.empty({ icon: 'playlist', title: 'Плейлист не найден' })
    const rules = c.smart ? `<div class="rules">${c.note.split(' · ').map((r) => `<span class="rule">${H.esc(r)}</span>`).join('')}</div>` : ''
    const sub = `${tracksLine(c.tracks)}${c.note && !c.smart ? `<span>· ${H.esc(c.note)}</span>` : ''}`
    const extra = `<button class="icon-btn ghost" data-act="noop" aria-label="Изменить">${icon('settings')}</button>` +
      `<button class="icon-btn ghost" data-act="toast" data-text="Ссылка на плейлист скопирована" aria-label="Поделиться">${icon('link')}</button>`
    return P.collHead(c, `playlist/${id}`, { kindLabel: c.smart ? 'Умный плейлист' : 'Плейлист · смешанный', sub, extra }) + rules +
      P.ttable(c.tracks, { src: `playlist/${id}` })
  }

  const album = (s, id) => {
    const c = H.collection(`album/${id}`, s)
    if (!c) return P.empty({ icon: 'album', title: 'Альбом не найден' })
    const a = H.artist(c.aid)
    const saved = s.savedAlbums.includes(id)
    const sub = `<button class="tlink" data-act="go" data-to="artist/${a.id}">${H.esc(a.name)}</button><span>· ${c.year} · ${H.tn(c.tracks.length, ['трек', 'трека', 'треков'])} · ${totalDur(c.tracks)}</span>`
    const extra = `<button class="btn btn-soft${saved ? ' on' : ''}" data-act="save-album" data-id="${id}">${icon(saved ? 'check' : 'plus')}<span>${saved ? 'В медиатеке' : 'В медиатеку'}</span></button>`
    const more = D.ALBUMS.filter((x) => x.aid === c.aid && x.id !== id)
    return P.collHead(c, `album/${id}`, { kindLabel: c.kind, sub, extra }) +
      P.ttable(c.tracks, { src: `album/${id}`, album: false, added: false }) +
      `<p class="coll-note">© ${c.year} ${H.esc(a.name)}</p>` +
      (more.length ? `<section class="shelf"><div class="shelf-head"><h2>Ещё у ${H.esc(a.name)}</h2></div><div class="row">${more.map(albumCard).join('')}</div></section>` : '')
  }

  const artist = (s, id) => {
    const c = H.collection(`artist/${id}`, s)
    if (!c) return P.empty({ icon: 'artist', title: 'Исполнитель не найден' })
    const follows = s.follows.includes(id)
    const sub = `<span>${c.listeners} слушателей · ${H.esc(c.genre)}</span>`
    const extra = `<button class="btn btn-soft${follows ? ' on' : ''}" data-act="follow" data-id="${id}">${icon(follows ? 'check' : 'plus')}<span>${follows ? 'Вы подписаны' : 'Подписаться'}</span></button>` +
      `<button class="icon-btn ghost" data-act="go" data-to="map" aria-label="На карте исполнителей" title="На карте исполнителей">${icon('graph')}</button>`
    const als = D.ALBUMS.filter((x) => x.aid === id)
    const near = neighbours(id).map(H.artist)
    return P.collHead(c, `artist/${id}`, { kindLabel: 'Исполнитель', sub, extra }) +
      `<section class="shelf"><div class="shelf-head"><h2>Популярные треки</h2></div>${c.tracks.length ? P.ttable(c.tracks, { src: `artist/${id}`, added: false }) : '<p class="coll-note">Треков в медиатеке пока нет.</p>'}</section>` +
      (als.length ? `<section class="shelf"><div class="shelf-head"><h2>Альбомы</h2></div><div class="row">${als.map(albumCard).join('')}</div></section>` : '') +
      `<section class="shelf"><div class="shelf-head"><h2>Похожие</h2><button class="link" data-act="go" data-to="map">На карте</button></div><div class="row">${near.map(artistCard).join('')}</div></section>`
  }

  const toggleIn = (list, id) => F(list.includes(id) ? list.filter((x) => x !== id) : [...list, id])

  S.use({
    defaults: { moved: F([]), savedAlbums: F(['al1', 'al2', 'al3']), follows: F(['a2', 'a7']) },
    actions: {
      transfer: (s, el) => {
        const p = D.PHANTOMS.find((x) => x.id === el.dataset.id)
        return { moved: F([...s.moved, p.id]), ...S.app.toast(`«${p.title}» перенесён в Sonar — ${H.tn(p.count, ['трек', 'трека', 'треков'])}`) }
      },
      'save-album': (s, el) => ({ savedAlbums: toggleIn(s.savedAlbums, el.dataset.id) }),
      follow: (s, el) => ({ follows: toggleIn(s.follows, el.dataset.id) }),
      'add-folder': () => S.app.toast('Папка добавлена — Sonar следит за новыми файлами'),
      toast: (s, el) => S.app.toast(el.dataset.text),
    },
    pages: {
      liked: { render: liked, deps: ['liked'], skeleton: 'coll', empty: () => ({ icon: 'heart', title: 'Пока ни одного лайка', line: 'Жми сердце у трека — он появится здесь, из какого бы сервиса ни был.', action: { act: 'go', to: 'mix', label: 'Включить Sonar Mix' } }) },
      playlists: { render: playlists, deps: ['moved'], empty: () => ({ icon: 'playlist', title: 'Плейлистов нет', line: 'Собери свой — из треков любых сервисов вперемешку.', action: { act: 'new-playlist', label: 'Новый плейлист' } }) },
      artists: { render: artists, empty: () => ({ icon: 'artist', title: 'Исполнителей пока нет', line: 'Подпишись на кого-нибудь — или просто лайкай треки.' }) },
      albums: { render: albums, empty: () => ({ icon: 'album', title: 'Сохранённых альбомов нет', line: 'Нажми «В медиатеку» на странице альбома.' }) },
      files: { render: files, empty: () => ({ icon: 'folder', title: 'Файлов нет', line: 'Укажи папку с музыкой — Sonar подхватит mp3, flac и m4a.', action: { act: 'add-folder', label: 'Добавить папку' } }) },
      playlist: { render: playlist, skeleton: 'coll', empty: () => ({ icon: 'playlist', title: 'В плейлисте пусто', line: 'Добавь треки через меню трека → «В плейлист».', action: { act: 'go', to: 'search', label: 'Найти треки' } }) },
      album: { render: album, deps: ['savedAlbums'], skeleton: 'coll', empty: () => ({ icon: 'album', title: 'Альбом недоступен', line: 'Сервис не отдал треки — попробуй резерв из другого сервиса.' }) },
      artist: { render: artist, deps: ['follows'], skeleton: 'coll', empty: () => ({ icon: 'artist', title: 'Здесь пока ничего', line: 'У исполнителя нет треков ни в одном подключённом сервисе.' }) },
    },
  })
})(window.Sonar)
