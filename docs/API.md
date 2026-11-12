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
| GET | `/tracks/{ref}/lyrics` | `{synced: bool, source: "lrclib"\|"genius", lines: [{t_ms, text}], plain?}` или `404` (SPEC §3.7б) |
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
```

## 4. Медиатека

| Метод | Путь | Тело → ответ |
|---|---|---|
| GET | `/library/likes?kind=track\|album\|artist` | `{rev, items: [{item: Track\|Album\|Artist, added_at}]}` |
| PUT | `/library/likes/{ref}` | → `{rev}` (вид по префиксу: `sc:`/`ym:` трек, `scalb:`/`ymalb:` альбом, `sca:`/`yma:` артист) |
| DELETE | `/library/likes/{ref}` | → `{rev}` |
| PUT | `/library/track-prefs/{ref}` | `{speed?: 0.5…2.0, lyrics_offset_ms?}` → `{rev}` («Запомнить») |
| DELETE | `/library/track-prefs` | сбросить все → `{rev}` |
| GET | `/playlists` | `[Playlist]` (без треков) |
| POST | `/playlists` | `{name, tracks?: [ref]}` → `Playlist` |
| GET | `/playlists/{id}` | `Playlist` с `tracks` |
| PATCH | `/playlists/{id}` | `{name?, hidden?, cover?}` → `Playlist` |
| DELETE | `/playlists/{id}` | → `{rev}` |
| POST | `/playlists/{id}/tracks` | `{refs: [ref], position: "start"\|"end"\|int}` → `{rev}` |
| DELETE | `/playlists/{id}/tracks` | `{item_ids: [id]}` → `{rev}` |
| PUT | `/playlists/{id}/order` | `{item_ids: [id]}` (полный порядок) → `{rev}` |

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

// Stats
{"period": "week", "total_ms": 140520000, "delta_pct": 20,
 "buckets": [{"label": "пт", "value_ms": 21000000}],
 "top_artist": {"name": "ONDA ANDAR", "avatar_url": "...", "ms": 184320000},
 "top_context": {"title": "park music", "owner": "type_0", "tracks": 71},
 "more_artists": [{"name": "cowboyclicker", "ms": 71520000}]}
```

## 6. Синхронизация и настройки

| Метод | Путь | Тело → ответ |
|---|---|---|
| GET | `/sync/pull?since=<rev>` | `{rev, changes: [{type, key, value\|null, rev}]}` |
| POST | `/sync/push` | `{ops: [{op_id, type, key, value\|null, client_ts}]}` → `{rev, applied: [op_id]}` |
| GET | `/sync/snapshot` | полный снимок: лайки, плейлисты, настройки, состояние плеера |
| POST | `/sync/replace` | полный снимок с клиента → `{rev}` |

`type`: `like`, `playlist`, `playlist_item`, `setting`, `player_state`, `track_pref`.
Настройки: `type: "setting"`, `key: "appearance.cover_theme"`, `value: true`.

## 7. Интеграции

| Метод | Путь | Тело → ответ |
|---|---|---|
| GET | `/integrations/lastfm/auth-url` | → `{url}` |
| GET | `/integrations/lastfm/callback?token=` (без авт.) | Last.fm возвращает сюда |
| PATCH | `/integrations/lastfm` | `{scrobble?, now_playing?}` |
| DELETE | `/integrations/lastfm` | → `204` |
| POST | `/integrations/api-key` | создать/перевыпустить → `{key: "sk_...", created_at}` (показывается **один раз**) |
| DELETE | `/integrations/api-key` | → `204` |

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
