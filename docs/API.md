# Sonar — API сервера

База: `<API>` = `SONAR_PUBLIC_URL` = `https://sonar-api.folzy.ru` (Cloudflare Tunnel, SPEC §3.2). JSON, UTF-8. Время — миллисекунды Unix (`*_at`).
Авторизация: `Authorization: Bearer <session>` (кроме помеченных «без авторизации»).

Ошибка — всегда так:
```json
{"error": {"code": "login_taken", "message": "Логин уже занят"}}
```
Коды HTTP: 400 неверные данные, 401 нет/неверная сессия, 403 нельзя, 404 нет,
409 конфликт, 429 лимит, 502 сервис (SC/Яндекс) ответил ошибкой, 503 сервис недоступен.

## 1. Аккаунт

| Метод | Путь | Тело → ответ |
|---|---|---|
| POST | `/auth/register` (без авт.) | `{login, password, device}` → `{session, user}` |
| POST | `/auth/login` (без авт.) | `{login, password, device}` → `{session, user}` |
| POST | `/auth/logout` | — → `204` |
| POST | `/auth/telegram/start` | `{purpose: "login"\|"link", device?}` → `{request_id, link, expires_at}` (для `login` — без авт.) |
| GET | `/auth/telegram/poll/{request_id}` | → `{status: "pending"\|"approved"\|"rejected"\|"expired", session?, user?}` |
| POST | `/auth/link` (без авт.) | быстрая ссылка (5 мин): `{device}` или `{telegram}` → `{code, url, expires_at}` — BOT.md §3, §6 |
| GET | `/auth/link/{code}/poll` (без авт.) | → `{status, session?, user?}` |
| GET | `/auth/link/{code}` | (вошедший) кто просит доступ → `{for, created_at, expires_at}` |
| POST | `/auth/link/{code}/approve` · `/reject` | (вошедший) → `204` |
| POST | `/reports` | баг / идея из приложения → `{id}` (BOT.md §2.10) |
| DELETE | `/auth/telegram` | отвязать (только если есть пароль) → `204` |
| PUT | `/me/password` | `{old_password?, new_password}` → `204` (`old` не нужен, если пароля не было) |
| GET | `/me` | → `User` |
| PATCH | `/me` | `{username?, display_name?, avatar?}` → `User` |
| GET | `/me/devices` | → `[Device]` |
| DELETE | `/me/devices/{id}` | завершить сессию → `204` |
| PUT | `/me/avatar` | multipart `file` (JPEG/PNG ≤ 5 МБ, сервер режет до 512×512) → `{avatar_url}` |
| DELETE | `/me/avatar` | → `204` |
| PUT | `/me/background` | multipart `file` (картинка ≤ 5 МБ или видео ≤ 10 с, ≤ 15 МБ) → `{id, kind: "image"\|"video", url}` |
| DELETE | `/me/background` | → `204` |
| GET | `/public/users/{username}` (без авт., CORS для сайта) | → `{username, display_name, number, avatar_url, created_at}` |
| GET | `/notifications?since=` | → `[{id, title, text, created_at, read}]` |
| POST | `/notifications/read` | `{ids: [id]}` → `204` |

`device` = `{name: "iPhone 15 Pro", platform: "ios", app_version: "1.0.0", build: 12}`.

```json
// User
{"id": "u_01J...", "login": "folzy", "username": "folzy", "display_name": "Folzy",
 "number": 104633, "avatar_url": null, "created_at": 1791590400000,
 "telegram": {"id": 123, "username": "cocainemodel"}, "has_password": true,
 "services": {"soundcloud": {"connected": true, "name": "Folzy"},
              "yandex": {"connected": false}},
 "lastfm": {"connected": true, "name": "wxnna_cry"}}
```

## 2. Сервисы

| Метод | Путь | Тело → ответ |
|---|---|---|
| PUT | `/services/soundcloud` | `{client_id, oauth_token}` → `{connected, name, avatar_url}` |
| PUT | `/services/yandex` | `{token}` → `{connected, name, avatar_url}` |
| GET | `/services/yandex/oauth-url` | → `{url}` (для входа в один клик) |
| DELETE | `/services/{svc}` | → `204` |
| GET | `/services/{svc}/playlists` | фантомные плейлисты → `[ServicePlaylist]` |
| GET | `/services/{svc}/playlists/{id}/tracks` | → `[Track]` |
| POST | `/services/{svc}/playlists/{id}/import` | `{name?}` → `Playlist` (новый плейлист Sonar) |

## 3. Каталог и поток

| Метод | Путь | Ответ |
|---|---|---|
| GET | `/search?q=&src=all\|sc\|ym&kind=track\|album\|artist\|playlist&limit=30` | `{tracks:[], albums:[], artists:[], playlists:[]}` |
| GET | `/tracks/{ref}` | `Track` |
| GET | `/tracks/{ref}/stream?quality=low\|medium\|high\|max` | `StreamInfo` |
| GET | `/tracks/{ref}/related` | `[Track]` |
| GET | `/albums/{ref}` · `/artists/{ref}` | альбом с треками · артист с топом |
| GET | `/home` | `{greeting, blocks: [Block]}` |
| POST | `/wave/start` | — → `{session_id, tracks: [Track]}` (своя волна, SPEC §3.7) |
| POST | `/wave/{session_id}/feedback` | `{event: "started"\|"finished"\|"skip"\|"like"\|"dislike", ref, played_ms}` → `{tracks: [Track]}` (догрузка, если пора) |

```json
// Track
{"ref": "sc:2296053116", "title": "море стало моим домом.", "artist": "одиссея",
 "artists": [{"ref": "sca:123", "name": "одиссея", "avatar_url": "..."}],
 "album": null, "duration_ms": 123000,
 "cover_url": "https://i1.sndcdn.com/artworks-...-t500x500.png",
 "url": "https://soundcloud.com/odisseya/more", "explicit": false, "available": true}

// StreamInfo
{"url": "https://cf-hls-media.sndcdn.com/...", "protocol": "hls", "codec": "aac",
 "bitrate": 160, "expires_at": 1794340594779, "gain_db": null}

// Album — scalb:<id плейлиста-альбома SC> | ymalb:<id>
{"ref": "ymalb:9", "title": "Come Over When You're Sober", "artist": "Lil Peep",
 "artists": [{"ref": "yma:7", "name": "Lil Peep", "avatar_url": null}],
 "cover_url": "https://avatars.yandex.net/.../400x400", "year": 2017, "track_count": 7,
 "url": "https://music.yandex.ru/album/9"}

// Artist — sca:<id пользователя SC> | yma:<id>
{"ref": "sca:5", "name": "extra", "avatar_url": "...", "followers": 9400, "url": "https://soundcloud.com/extra"}

// ServicePlaylist — scpl:<id> | ympl:<uid>:<kind>; лайки сервиса — scpl:likes, ympl:likes
{"ref": "ympl:42:1003", "title": "2016", "owner": "Folzy", "cover_url": "...", "track_count": 121}
```

Страницы: `/artists/{ref}` → `{artist: Artist, top: [Track], albums: [Album]}`,
`/albums/{ref}` → `{album: Album, tracks: [Track]}`,
`/services/{svc}/playlists/{id}/tracks` → `{playlist: ServicePlaylist, tracks: [Track]}`.

## 4. Медиатека

| Метод | Путь | Тело → ответ |
|---|---|---|
| GET | `/library/likes?kind=track\|album\|artist` | `{rev, items: [{item: Track\|Album\|Artist, added_at}]}` |
| PUT | `/library/likes/{ref}` | → `{rev}` (вид по префиксу: `sc:`/`ym:` трек, `scalb:`/`ymalb:` альбом, `sca:`/`yma:` артист) |
| DELETE | `/library/likes/{ref}` | → `{rev}` |
| PUT | `/library/track-prefs/{ref}` | `{speed?: 0.5…2.0, lyrics_offset_ms?, eq?: number[12]}` → `{rev}` («Запомнить») |
| DELETE | `/library/track-prefs` | сбросить все → `{rev}` |
| GET | `/playlists` | `[Playlist]` (без треков) |
| POST | `/playlists` | `{name, tracks?: [ref]}` → `Playlist` |
| GET | `/playlists/{id}` | `Playlist` с `tracks` |
| PATCH | `/playlists/{id}` | `{name?, hidden?, cover?}` → `Playlist` |
| DELETE | `/playlists/{id}` | → `{rev}` |
| POST | `/playlists/{id}/tracks` | `{refs: [ref], position: "start"\|"end"\|int}` → `{rev}` |
| DELETE | `/playlists/{id}/tracks` | `{item_ids: [id]}` → `{rev}` |
| PUT | `/playlists/{id}/order` | `{item_ids: [id]}` (полный порядок) → `{rev}` |

```json
// Playlist (в списке tracks = null; covers — до 4 обложек первых треков для коллажа)
{"id": "pl_01JD3...", "name": "Микс", "hidden": false, "source_ref": "scpl:77",
 "created_at": 1794340594779, "updated_at": 1794340594779, "track_count": 2, "duration_ms": 312000,
 "covers": ["https://..."], "tracks": [{"item_id": "pi_01JD3...", "added_at": 1794340594779, "ref": "sc:1", "...": "поля Track"}]}
```

Импорт плейлиста сервиса повторно не создаёт копию: уже перенесённый (`source_ref`) дополняется
треками, которых в нём ещё нет. Windows-клиент сейчас делает всё это локально (команды
`src-tauri/src/commands.rs`, те же формы).

## 5. Плеер, прослушивания, статистика

| Метод | Путь | Тело → ответ |
|---|---|---|
| PUT | `/player/state` | `PlayerState` → `204` |
| GET | `/player/state` | `PlayerState` (для восстановления на другом устройстве) |
| POST | `/plays` | `{plays: [{ref, played_at, listened_ms, context}]}` → `{accepted: n}` |
| GET | `/stats?period=day\|week\|month\|half_year\|year\|all&metric=time\|tracks` | `Stats` |

```json
// PlayerState
{"device_id": "d_...", "ref": "sc:2296053116", "context": "favorites",
 "is_playing": true, "position_ms": 41000, "queue": ["sc:1", "ym:2"], "queue_index": 0,
 "shuffle": false, "repeat": "off", "client_ts": 1794340534779}

// Stats (Windows-клиент считает так же из локальной plays — store/stats.rs)
{"period": "week", "total_ms": 140520000, "delta_pct": 20,
 "buckets": [{"label": "пт", "value_ms": 21000000}],
 "top_artist": {"name": "ONDA ANDAR", "avatar_url": "...", "ref": "sca:1", "ms": 184320000, "plays": 1753},
 "top_context": {"title": "park music", "owner": "type_0", "tracks": 71},
 "more_artists": [{"name": "cowboyclicker", "avatar_url": null, "ref": null, "ms": 71520000, "plays": 863}],
 "top_tracks": [{"ref": "sc:1", "title": "zombie", "artist": "cowboyclicker", "cover_url": "...", "plays": 52, "ms": 9360000}],
 "plays": 6701, "tracks": 450, "artists": 10, "streak_days": 36, "peak_hour": 14, "per_day": 192,
 "fav_weekday": 5}
// buckets: day — 24 часа, week — 7 дней, month — 30 дней, half_year/year — месяцы, all — до 24 месяцев.
// peak_hour и fav_weekday (0 = пн) — в часовом поясе клиента.
```

## 5а. Главная: тренды, плейлисты пользователей, чарты (SPEC §4.7)

Всё считается на сервере по `plays` и сохранениям **всех пользователей Sonar**. Клиент Windows до
появления сервера показывает на главной заготовку этих рядов; подборка «под время суток» и «Релизы
недели» считаются на устройстве (`daypart_mix`, `home_releases` в `src-tauri/src/commands.rs`).

| Метод | Путь | Ответ |
|---|---|---|
| GET | `/home/trends?limit=24` | `{tracks: [Track & {plays, delta_pct}]}` — что слушают в приложении за 7 дней, `delta_pct` к прошлой неделе |
| GET | `/home/playlists?sort=popular\|saved\|new&period=week\|month\|all&limit=24` | `{playlists: [PublicPlaylist]}` |
| GET | `/charts?kind=tracks\|artists\|albums\|playlists&period=week\|month\|all&limit=50` | `{kind, period, updated_at, items: [ChartItem]}` |

```json
// PublicPlaylist — чужой открытый плейлист Sonar
{"id": "pl_...", "name": "ночной вайб", "owner": {"username": "type_0", "display_name": "type_0", "avatar_url": "..."},
 "track_count": 71, "duration_ms": 14520000, "covers": ["...", "...", "...", "..."], "plays": 340, "saves": 12}

// ChartItem: место, сдвиг к прошлому периоду (null — новый), прослушивания и сам объект по kind
{"pos": 1, "prev_pos": 3, "plays": 1753, "listeners": 9,
 "track": {"ref": "sc:1", "title": "zombie", "artist": "cowboyclicker", "cover_url": "..."}}
// для kind=artists — "artist": Artist, albums — "album": Album, playlists — "playlist": PublicPlaylist
```

## 6. Синхронизация и настройки

| Метод | Путь | Тело → ответ |
|---|---|---|
| GET | `/sync/pull?since=<rev>` | `{rev, changes: [{type, key, value\|null, rev}]}` |
| POST | `/sync/push` | `{ops: [{op_id, type, key, value\|null, client_ts}]}` → `{rev, applied: [op_id]}` |
| — | тип `wave_event` | события журнала волны едут в `sync/push` / `sync/pull` без `features_json` (WAVE.md §3а); профили тегов не синхронизируются — считаются из событий |
| GET | `/sync/snapshot` | полный снимок: лайки, плейлисты, настройки, состояние плеера |
| POST | `/sync/replace` | полный снимок с клиента → `{rev}` |

`type`: `like`, `playlist`, `playlist_item`, `setting`, `player_state`, `track_pref`, `dislike`, `wave_event`.
Настройки: `type: "setting"`, `key: "appearance.cover_theme"`, `value: true`.

**Что шлёт клиент** (Windows, `store/sync.rs`, готово 2026-11-16; `value: null` — удалено):

| `type` | `key` | `value` |
|---|---|---|
| `like` | ref (`sc:1`, `ymalb:9`, `sca:3`) | `{kind, added_at, track?}` — `track` (Track) у треков, чтобы на другом устройстве была карточка |
| `playlist` | `pl_…` | `{name, hidden, source_ref, created_at, updated_at}` |
| `playlist_item` | id элемента | `{playlist_id, ref, position, added_at, track?}` |
| `setting` | ключ | значение; только `sync: да` из SETTINGS.md — громкость, масштаб, качество, `system.*`, `update.*`, `storage.*` остаются на устройстве |
| `dislike` | ref | `{artist, added_at}` |
| `track_pref` | ref | `{speed, lyrics_offset_ms}` |
| `wave_event` | `we_…` | `{device_id, session_id, ref, artist, mode, source, seed_ref, served_at, reward, listened_ms, ended_at}` — без `features_json` |

`op_id` = `<device_id>:<type>:<key>:<локальный rev>` — повтор после сбоя сети сервер узнаёт по нему и
не применяет дважды, но в `applied` возвращает. Настройки — «побеждает позднее» по `client_ts`,
остальное — последняя запись. `wave_event`: строка с исходом (`reward`) важнее строки без него.
Образец логики сервера — `MemoryServer` в `windows/src-tauri/src/sync.rs` (тесты двух устройств).
`player_state` клиент пока не шлёт (продолжение на другом устройстве — отдельной задачей).

## 7. Интеграции

| Метод | Путь | Тело → ответ |
|---|---|---|
| GET | `/integrations/lastfm/auth-url` | → `{url}` |
| GET | `/integrations/lastfm/callback?token=` (без авт.) | Last.fm возвращает сюда |
| PATCH | `/integrations/lastfm` | `{scrobble?, now_playing?}` |
| DELETE | `/integrations/lastfm` | → `204` |
| POST | `/integrations/api-key` | создать/перевыпустить → `{key: "sk_...", created_at}` (показывается **один раз**) |
| DELETE | `/integrations/api-key` | → `204` |
| GET | `/me/integration` | → `{key: "sk_…" \| null, created_at}` — тот же токен, что в боте (BOT.md §2.6а); клиенты подставляют его в ссылку плашки OBS. Изменение токена в боте или приложении приходит остальным синком (`type: "integration_key"`) |
| GET | `/obs?token=sk_…` (без авт., токен в адресе) | страница плашки OBS с сервера — та же, что локальная в Windows (`obs.html`) |
| GET | `/config` (без авт.) | → `{discord_app_id, site_url, telegram_url}` — общие настройки клиентов: ID приложения Discord для RPC пользователь не вводит, клиент берёт отсюда (до сервера — вшит в сборку) |
| GET | `/oauth/profile?token=sk_…` (ключ API) | → `{username, display_name, avatar_url}` — для selfbot и «Интеграции» в боте (BOT.md §2.6а) |

### `GET /oauth/now` — формат Dotify

Авторизация: `Authorization: Bearer sk_...` (ключ API). Тот же JSON, что у Dotify, чтобы
selfbot переключился сменой адреса:

```json
{
  "is_playing": false,
  "position_ms": 0,
  "state": "paused",
  "track": {
    "artist": "одиссея",
    "context": "favorites",
    "cover_art": "https://i1.sndcdn.com/artworks-m48chaKIzyvbEVpS-V42PYA-t500x500.png",
    "duration": 123,
    "duration_ms": 123000,
    "id": "2296053116",
    "is_playing": false,
    "position_ms": 0,
    "source": "soundcloud",
    "title": "море стало моим домом.",
    "track_id": "2296053116",
    "updated_at": 1794340534779
  },
  "updated_at": 1794340534779
}
```

- `state`: `playing` / `paused` / `stopped` (`track: null`, если ничего ещё не играло).
- `source`: `soundcloud` / `yandex`. `id` и `track_id` — id без префикса `sc:`/`ym:`.
- `duration` — секунды (целое), `duration_ms` — миллисекунды.

## 9. Статус (SPEC §3.11)

Без авторизации, кэш 30 с.

| Метод | Путь | Ответ |
|---|---|---|
| GET | `/status` | текущее состояние (ниже) |
| GET | `/status/history?days=90` | `{days: [{date: "2026-11-15", items: {api: 100.0, bot: 99.3, …}}]}` — % успешных проверок по дням |

```json
{
  "state": "degraded",                 // ok | degraded | down
  "title": "Некоторые сервисы работают с перебоями",
  "uptime_30d": 99.99,
  "checked_at": 1794700000000,
  "infra": [
    {"id": "api", "name": "Основной", "icon": "🖥️", "state": "ok", "ms": 12},
    {"id": "bot", "name": "Бот", "icon": "🤖", "state": "ok", "ms": null},
    {"id": "storage", "name": "Хранилище", "icon": "📦", "state": "ok", "ms": 3},
    {"id": "site", "name": "Сайт", "icon": "🌐", "state": "ok", "ms": 210}
  ],
  "platforms": [
    {"id": "soundcloud", "name": "SoundCloud", "icon": "🌐", "state": "ok", "ms": 340},
    {"id": "yandex", "name": "Яндекс Музыка", "icon": "🌐", "state": "degraded", "ms": 2900},
    {"id": "lrclib", "name": "lrclib", "icon": "📝", "state": "ok", "ms": 410},
    {"id": "genius", "name": "Genius", "icon": "📝", "state": "ok", "ms": 520},
    {"id": "lastfm", "name": "Last.fm", "icon": "🎧", "state": "ok", "ms": 190},
    {"id": "telegram", "name": "Telegram", "icon": "✈️", "state": "ok", "ms": 95}
  ]
}
```

## 8. Обновления

| Метод | Путь | Ответ |
|---|---|---|
| GET | `/updates/manifest.plist?ipa=<url>&build=<n>` (без авт.) | `manifest.plist` для `itms-services` |

Сами `update.json` / `changelog.json` клиент читает с
`https://raw.githubusercontent.com/folzy1092/Sonar/main/updates/`:

```json
// update.json
{"enabled": true, "build": 42, "version": "1.2.0", "minimum_build": 30,
 "title": "Sonar 1.2.0", "notes": "Тексты песен, жесты в очереди",
 "api_url": null,  // если не null — приложение переключается на новый адрес API
 "url": "https://github.com/folzy1092/Sonar/releases/download/build-42/Sonar.ipa"}
```
