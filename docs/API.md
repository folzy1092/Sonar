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
| GET | `/me` | → `User` (Windows до сервера держит профиль в настройках `profile.name / username / avatar` — `SETTINGS.md`; с сервером берёт отсюда и шлёт правки `PATCH /me`) |
| PATCH | `/me` | `{username?, display_name?, avatar?}` → `User` |
| GET | `/me/devices` | → `[Device]` (это устройство — `current: true`) |
| PUT | `/me/device` | при **каждом запуске** клиента: `{device}` → `Device` — сервер обновляет имя, ОС, `app_version`, `build`, `last_seen_at` этого устройства |
| PATCH | `/me/devices/{id}` | переименовать: `{name}` (≤ 48 символов) → `Device` |
| DELETE | `/me/devices/{id}` | завершить сессию устройства → `204`. Своя сессия моложе **24 ч** → `403 session_too_new` «Вход был недавно — завершать другие сессии можно через 24 часа» (свою можно всегда — это `POST /auth/logout`) |
| PUT | `/me/avatar` | multipart `file` (JPEG/PNG ≤ 5 МБ, сервер режет до 512×512) → `{avatar_url}` |
| DELETE | `/me/avatar` | → `204` |
| PUT | `/me/background` | multipart `file` (картинка ≤ 5 МБ или видео ≤ 10 с, ≤ 15 МБ) → `{id, kind: "image"\|"video", url}` |
| DELETE | `/me/background` | → `204` |
| GET | `/public/users/{username}` (без авт., CORS для сайта) | → `{username, display_name, number, avatar_url, created_at}` |
| GET | `/notifications?since=` | → `[{id, title, text, created_at, read}]` |
| POST | `/notifications/read` | `{ids: [id]}` → `204` |

`device` = `{id, name, platform, os, app_version, build}`, например
`{"id": "6f1c…-uuid", "name": "iPhone 15 Pro", "platform": "ios", "os": "iOS 18.1", "app_version": "0.1.0", "build": 239}`:

- `id` (`device_id`) — **постоянный id устройства**, его придумывает клиент: iPhone — UUID, созданный один раз и
  сохранённый в Keychain (переживает переустановку, как в Shadow); ПК — HWID. Повторный вход с того же
  устройства заменяет его прежнюю сессию, а не добавляет строку в «Устройства». Тот же id — в `op_id` синка.
- `name` — человекочитаемо: iPhone — модель по `utsname.machine` («iPhone 15 Pro», таблица — `ios/Sonar/Core/Account/DeviceInfo.swift`);
  ПК — «Windows 10 (Folzy)» / «Windows 11 (Folzy)» (имя ПК в скобках). Пользователь может переименовать.
- `platform` — `ios` | `windows` | `android`. `os` — «iOS 18.1», «Windows 10 22H2».
- `app_version` + `build` — версия Sonar; приходят при входе и при каждом запуске (`PUT /me/device`), поэтому
  сервер знает последнюю версию каждого устройства.

```json
// Device
{"id": "6f1c…", "name": "iPhone 15 Pro", "platform": "ios", "os": "iOS 18.1", "app_version": "0.1.0",
 "build": 239, "created_at": 1794340534779, "last_seen_at": 1794340600000, "current": true}
```

`created_at` — когда на устройстве вошли (начало сессии; по нему правило 24 ч), `last_seen_at` — последний запрос.

Быстрая ссылка (`POST /auth/link`) отвечает `{code, url, bot_url, expires_at}`: `url` = `https://sonar.folzy.ru/auth/<code>`
(открыть там, где уже вошли; QR на новом устройстве), `bot_url` = `https://t.me/SonarMusicApp?start=link_<code>` —
«Войти через Telegram» на новом iPhone/ПК. `GET /auth/link/{code}` → `{for: {kind, name, platform?}, created_at, expires_at}`.

Клиенты держат аккаунт за флагом, пока сервера нет: iOS — `AccountStore.serverEnabled` (адрес из Info.plist
`SonarAPIBaseURL` или настройки `server.url` **и** `server.enabled = true`, по умолчанию false); Windows — `sync.server`
и сессия в keyring. Сессия — только в Keychain / keyring.

```json
// User
{"id": "u_01J...", "login": "folzy", "username": "folzy", "display_name": "Folzy",
 "number": 104633, "avatar_url": null, "created_at": 1791590400000,
 "telegram": {"id": 123, "username": "cocainemodel"}, "has_password": true,
 "services": {"soundcloud": {"connected": true, "name": "Folzy", "premium": null},
              "yandex": {"connected": false}},
 "lastfm": {"connected": true, "name": "wxnna_cry"}}
```

## 2. Сервисы

### Префиксы ref

Реестр сервисов — одна таблица на всех клиентах: Windows `windows/src-tauri/src/providers/registry.rs` и
`windows/src/lib/services.ts`, iOS `ios/Sonar/Core/Models/ServiceRegistry.swift`. Порядок строк — порядок показа
везде. У сервиса два имени: короткий **id** (корень префиксов ref, `src` поиска) и длинный **key** (Keychain/keyring,
`service_accounts.service`, `general.platform`, поля `services` у `GET /me`). Где сервис приходит параметром
(`{svc}` в путях ниже), принимаются оба: `sc` и `soundcloud` — одно и то же.

| id | key | Название | трек | альбом | артист | плейлист | работает |
|---|---|---|---|---|---|---|---|
| `sc` | `soundcloud` | SoundCloud | `sc:<id>` | `scalb:<id>` | `sca:<id>` | `scpl:<id>` | да |
| `ym` | `yandex` | Яндекс Музыка | `ym:<id>` | `ymalb:<id>` | `yma:<id>` | `ympl:<uid>:<kind>` | да |
| `yt` | `youtube` | YouTube Music | `yt:<videoId>` | `ytalb:<browseId>` | `yta:<channelId>` | `ytpl:<playlistId>` | нет |
| `vk` | `vk` | VK Музыка | `vk:<owner>_<id>` | `vkalb:<owner>_<id>` | `vka:<id>` | `vkpl:<owner>_<id>` | нет |
| `sp` | `spotify` | Spotify | `sp:<id>` | `spalb:<id>` | `spa:<id>` | `sppl:<id>` | нет |
| `local` | `local` | Локальные файлы | `local:<sha1 пути>` | — | — | — | нет |

Сервисы с «нет» пока только описаны: интерфейс их не показывает, сервер и клиенты отвечают
«`<Название>`: пока не поддерживается». Что каждый сервис умеет (`caps`) — в `GET /services`.

Особые ref: `scpl:likes` и `ympl:likes` — лайки аккаунта сервиса как плейлист; `ympl:<uid>:<kind>` — плейлист
пользователя Яндекса; `scpl:<id>` — плейлист SoundCloud. Формат ref не меняется.

Разбор ref (одинаково в Rust, TS и Swift):

```
prefix = текст до ПЕРВОГО ':'   (нет ':' или пустой префикс → не сервис)
сервис, вид = единственная пара (сервис, вид), у которой префикс == prefix   (точное равенство, не «начинается с»)
иначе → не сервис
```

| ref | сервис | вид |
|---|---|---|
| `sc:123` | sc | трек |
| `scalb:9` | sc | альбом |
| `sca:7` | sc | артист |
| `scpl:likes` | sc | плейлист |
| `ympl:42:1003` | ym | плейлист |
| `ymalb:5` | ym | альбом |
| `yma:1` | ym | артист |
| `yt:abc` | yt | трек |
| `local:abc` | local | трек |
| `pl_x` | — | — |
| `similar:sc:1` | — | — |
| `sc` | — | — |
| (пустая строка) | — | — |
| `:1` | — | — |

Все префиксы в таблице разные (это проверяют тесты на каждом клиенте).

Не сервисы: `pl_…`, `similar:<ref>`.

### Пути

`{svc}` — короткий id или key сервиса (`sc` / `soundcloud`). Ответ подключения — `{connected, name, avatar_url, premium}`:
`premium` — `true`/`false`, если сервис сообщает о подписке (Яндекс: Плюс, `plus.hasPlus`), иначе `null` (SoundCloud — всегда `null`).

| Метод | Путь | Тело → ответ |
|---|---|---|
| GET | `/services` | все сервисы реестра с состоянием → `[ServiceEntry]` (ПК: команда `services_list`) |
| PUT | `/services/{svc}/key` | `{fields: {…}}` → `{connected, name, avatar_url, premium}` — «Вставить ключ» (ПК: `connect_service_key {service, fields}`) |
| PUT | `/services/soundcloud` | `{client_id, oauth_token}` → `{connected, name, avatar_url, premium}` (по-прежнему работает) |
| PUT | `/services/yandex` | `{token}` → `{connected, name, avatar_url, premium}` (по-прежнему работает) |
| GET | `/services/yandex/oauth-url` | → `{url}` (для входа в один клик) |
| DELETE | `/services/{svc}` | → `204` |
| GET | `/services/{svc}/playlists` | фантомные плейлисты → `[ServicePlaylist]` |
| GET | `/services/{svc}/playlists/{id}/tracks` | → `[Track]` |
| POST | `/services/{svc}/playlists/{id}/import` | `{name?}` → `Playlist` (новый плейлист Sonar) |

Поля `PUT /services/{svc}/key` (незнакомые имена полей пропускаются):

| Сервис | Поля |
|---|---|
| `sc` / `soundcloud` | `client_id` — обязательно (32 символа); `oauth_token` — необязательно, `OAuth ` в начале срезается |
| `ym` / `yandex` | `token` — обязательно |

Ключ проверяется запросом аккаунта к сервису и сохраняется только в Keychain / keyring. Неизвестный сервис —
«Неизвестный сервис: `<svc>`», ещё не работающий — «`<Название>`: пока не поддерживается». Значения полей не
попадают ни в текст ошибки, ни в лог.

`ServiceEntry` — строка реестра плюс состояние; ключи именно такие (snake_case), все шесть сервисов в порядке реестра:

```json
[
  {"id": "sc", "key": "soundcloud", "name": "SoundCloud", "color": "#FF5500", "icon": "SoundCloud.svg", "icon_mono": "soundcloud-mono.svg",
   "prefixes": {"track": "sc", "album": "scalb", "artist": "sca", "playlist": "scpl"},
   "caps": {"search": true, "stream": true, "library": true, "playlists": true, "similar": true, "login": true, "key": true},
   "implemented": true, "connected": true, "account_name": "dj-anna", "avatar_url": "https://i1.sndcdn.com/…", "premium": null},
  {"id": "ym", "key": "yandex", "name": "Яндекс Музыка", "color": "#FFBC0D", "icon": "Yandex-Music.svg", "icon_mono": "yandex-music-mono.svg",
   "prefixes": {"track": "ym", "album": "ymalb", "artist": "yma", "playlist": "ympl"},
   "caps": {"search": true, "stream": true, "library": true, "playlists": true, "similar": true, "login": true, "key": true},
   "implemented": true, "connected": true, "account_name": "Анна", "avatar_url": null, "premium": true},
  {"id": "yt", "key": "youtube", "name": "YouTube Music", "color": "#FF0033", "icon": "youtube-music.svg", "icon_mono": "youtube-music-mono.svg",
   "prefixes": {"track": "yt", "album": "ytalb", "artist": "yta", "playlist": "ytpl"},
   "caps": {"search": true, "stream": true, "library": true, "playlists": true, "similar": true, "login": true, "key": false},
   "implemented": false, "connected": false, "account_name": null, "avatar_url": null, "premium": null},
  {"id": "vk", "…": "…"}, {"id": "sp", "…": "…"},
  {"id": "local", "key": "local", "name": "Локальные файлы", "color": "#8E8E93", "icon": null, "icon_mono": null,
   "prefixes": {"track": "local", "album": null, "artist": null, "playlist": null},
   "caps": {"search": false, "stream": true, "library": true, "playlists": false, "similar": false, "login": false, "key": false},
   "implemented": false, "connected": false, "account_name": null, "avatar_url": null, "premium": null}
]
```

`icon` / `icon_mono` — файлы знаков в `brand/icon/`; у неработающих сервисов `connected: false`, остальное `null`.

## 3. Каталог и поток

| Метод | Путь | Ответ |
|---|---|---|
| GET | `/search?q=&src=all\|sc\|ym&kind=track\|album\|artist\|playlist&limit=30` | `{tracks:[], albums:[], artists:[], playlists:[]}`; `src` — короткий id работающего сервиса (§2 «Префиксы ref») |
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
// необязательное "loudness": -8.1 — громкость EBU R128, LUFS (Яндекс `r128.i`), для нормализации; у SC нет


// StreamInfo
{"url": "https://cf-hls-media.sndcdn.com/...", "protocol": "hls", "codec": "aac",
 "bitrate": 160, "expires_at": 1794340594779, "gain_db": null}

// Album — префикс альбома сервиса (§2 «Префиксы ref»): scalb:<id плейлиста-альбома SC> | ymalb:<id>
{"ref": "ymalb:9", "title": "Come Over When You're Sober", "artist": "Lil Peep",
 "artists": [{"ref": "yma:7", "name": "Lil Peep", "avatar_url": null}],
 "cover_url": "https://avatars.yandex.net/.../400x400", "year": 2017, "track_count": 7,
 "url": "https://music.yandex.ru/album/9"}

// Artist — префикс артиста сервиса (§2 «Префиксы ref»): sca:<id пользователя SC> | yma:<id>
{"ref": "sca:5", "name": "extra", "avatar_url": "...", "followers": 9400, "url": "https://soundcloud.com/extra"}

// ServicePlaylist — префикс плейлиста сервиса (§2 «Префиксы ref»): scpl:<id> | ympl:<uid>:<kind>; лайки сервиса — scpl:likes, ympl:likes
{"ref": "ympl:42:1003", "title": "2016", "owner": "Folzy", "cover_url": "...", "track_count": 121}
```

Страницы: `/artists/{ref}` → `{artist: Artist, top: [Track], albums: [Album]}`,
`/albums/{ref}` → `{album: Album, tracks: [Track]}`,
`/services/{svc}/playlists/{id}/tracks` → `{playlist: ServicePlaylist, tracks: [Track]}`.

## 4. Медиатека

| Метод | Путь | Тело → ответ |
|---|---|---|
| GET | `/library/likes?kind=track\|album\|artist` | `{rev, items: [{item: Track\|Album\|Artist, added_at}]}` |
| PUT | `/library/likes/{ref}` | → `{rev}` (вид — по разбору ref из §2 «Префиксы ref»: трек, альбом или артист работающего сервиса, например `sc:`/`ym:` трек, `scalb:`/`ymalb:` альбом, `sca:`/`yma:` артист; плейлист сервиса — не лайк) |
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

### Экспорт плейлиста в файл (только клиент)

Сервер не участвует: файл собирает клиент из уже загруженных треков. Меню плейлиста и Любимых →
«Экспорт» → M3U8, CSV или JSON. Имя файла — название списка: запрещённые в Windows знаки
(`<>:"/\|?*`) и управляющие символы → пробел, пробелы схлопнуты, точки и пробелы по краям убраны,
до 100 символов, имена устройств (`CON`, `NUL`, `COM1`…) — с `_` в начале, пусто — `Sonar`.
Ссылка на трек — его `url` (только http/https), иначе по ref из реестра (§2 «Префиксы ref»):
`ym:` → `music.yandex.ru/track/<id>`, `yt:` → `music.youtube.com/watch?v=<id>`, `sp:` →
`open.spotify.com/track/<id>`, `vk:` → `vk.com/audio<id>`; у `sc:` без `url` и `local:` ссылки нет.

| Формат | Содержимое |
|---|---|
| M3U8 | UTF-8, `\n`: `#EXTM3U`, `#PLAYLIST:<имя>`, на трек — `#EXTINF:<сек>,<артист> - <название>` (длительность неизвестна — `-1`, без артиста — только название) и строка со ссылкой (нет — ref) |
| CSV | UTF-8 с BOM, CRLF, RFC 4180 (кавычки, если есть `,` `"` или перенос; `"` удваивается). Колонки `title,artist,album,duration,service,link,added`: `duration` — секунды, `service` — название сервиса на языке интерфейса, `added` — ISO 8601 UTC или пусто. Текст, начинающийся с `= + - @`, табуляции или `\r`, — с `'` в начале (не формула в Excel) |
| JSON | массив `Track` (§3, ровно поля API — без `plays`, `tags`, `loudness`) + `added_at` (мс или `null`), отступ 2 пробела |

ПК (Tauri): текст файла — `windows/src/lib/export.ts`, имя файла (`sanitize_file_name`) и запись — команда
`export_playlist {name, format: "m3u8"|"csv"|"json", title, contents}` → имя сохранённого файла или
`null` (окно «Сохранить как» закрыто без выбора). Окно сохранения (tauri-plugin-dialog) открывает и файл
пишет Rust (`src-tauri/src/export.rs`), поэтому у страницы нет прав `dialog:*` / `fs:*` в
`capabilities`. Ошибки: «Неизвестный формат экспорта», «Плейлист слишком большой для экспорта»
(больше 64 МБ), «Окно сохранения закрылось», «Не удалось сохранить файл» (путь в журнал не пишется),
«Файл с таким именем уже есть» (окно отдало путь без нужного расширения — Rust дописывает его и чужой
файл с получившимся именем не заменяет, ведь такого имени пользователь в окне не подтверждал).
iPhone: `Core/Export/PlaylistExport.swift` (те же правила; ключи JSON по алфавиту) → три файла во
временной папке → лист «Поделиться» (`Features/Library/ExportSheet.swift`); `added_at` там пока `null`.

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
остальное — последняя запись. Проигравшую по `client_ts` настройку сервер тоже подтверждает в `applied`, но
поднимает `rev` строки-победителя — она придёт отправившему в следующем `pull` (иначе у него осталось бы своё).
Изменения типа, который клиент не хранит (у iPhone пока нет плейлистов; настройки-объекты ПК), клиент не
применяет, держит в журнале и **не** шлёт обратно удалением. `wave_event`: строка с исходом (`reward`) важнее строки без него.
Образец логики сервера — `MemoryServer` в `windows/src-tauri/src/sync.rs` и `MemorySyncServer` в
`ios/Sonar/Core/Sync/SyncEngine.swift` (тесты двух устройств).
`player_state` клиент пока не шлёт (продолжение на другом устройстве — отдельной задачей).

**iOS** (`ios/Sonar/Core/Sync/`, готово 2026-11-17, за флагом `AccountStore.serverEnabled`): тот же протокол.
Данные телефона лежат в JSON хранилищ, поэтому рядом журнал `sync.json` — последнее значение и `rev` каждой
строки; правка в хранилище → сверка снимка → новый `rev`. Едут: `like` (Любимые; порядок перетаскиванием —
через `added_at` перенесённого трека, как сортирует ПК), `dislike`, `track_pref` (скорость «Запомнить» и
сдвиг текста), `setting` (по SETTINGS.md, плюс `server.*` / `account.*` — только устройство), `POST /plays`
из журнала «Статистики». Офлайн-файлы (`DownloadStore`) не синхронизируются. Плейлисты и `wave_event` —
когда они появятся на iPhone.

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
- `source`: key сервиса из §2 «Префиксы ref» (`soundcloud` / `yandex`; позже `youtube` / `vk` / `spotify`). `id` и `track_id` — id без префикса трека (`sc:`/`ym:`).
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
