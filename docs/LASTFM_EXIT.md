# Уход с Last.fm (спека, решение владельца 2026-11-18)

С 1 декабря 2026 ключ API Last.fm работает только у владельца ключа с **Last.fm Pro**. Pro владелец брать
не будет. Решение: **Last.fm Sonar больше не нужен** — прослушивания и «сейчас играет» Sonar знает сам, а
после сервера отдаёт их своим API (`docs/API.md`: `POST /plays`, `GET /stats`, `GET /stats/recap`,
`GET /oauth/now` в формате Dotify). Селфбот читает оттуда же — его спека в репо `folzy1092/folzy-selfbot`,
`docs/superpowers/specs/2026-11-18-lastfm-exit-design.md`.

## 1. Сейчас, до 1 декабря — сохранить историю (владелец, один раз) — скрипт ✅ 2026-11-18

- **ListenBrainz** (аккаунт MusicBrainz `wxnna_cru` уже есть): listenbrainz.org → настройки → импорт из
  Last.fm, поле «Start Import From» пустое, недавние скробблы в профиле Last.fm не скрыты. Это резервная
  копия всей истории, бесплатно и навсегда, **ключ Last.fm не нужен** — импорт идёт по нику.
- **Свой файл истории** (`{ts, artist, title, album, mbid}` построчно, от новых к старым; файлы в `.gitignore`,
  в репо не класть). Его потом импортирует сервер (п. 3), чтобы итоги и статистика не начинались с нуля.
  Два скрипта, формат один (общее — `server/tools/history_file.py`), оба продолжают с места обрыва:
  - **основной, без ключа:** `server/tools/export_listenbrainz.py` — после импорта на ListenBrainz выкачивает
    историю из открытого API ListenBrainz (`/1/user/<ник>/listens`, по 1000) в
    `server/data/listenbrainz-export.jsonl`; спрашивает только ник ListenBrainz (скрытым вводом). Работает и
    после 1 декабря — важно лишь успеть импорт на ListenBrainz, пока Last.fm отдаёт историю;
  - **если есть ключ API Last.fm:** `server/tools/export_lastfm.py` — `user.getRecentTracks` напрямую в
    `server/data/lastfm-export.jsonl` (ключ и ник — скрытым вводом). У владельца ключа нет — этот путь запасной.

## 2. Windows и iPhone — убрать Last.fm ✅ сделано 2026-11-18

- **Убрать** интеграцию: `windows/src-tauri/src/lastfm.rs`, вход в Last.fm (`login.rs`), команды, раздел в
  Интеграциях, ключи `integrations.lastfm.*` (`lib/settings.svelte.ts`, `docs/SETTINGS.md`), переводы;
  iPhone — `ios/Sonar/Core/Integrations/Lastfm*.swift`, `SettingsDefaults+System.swift`, экран интеграции.
  Секреты CI `SONAR_LASTFM_KEY` / `SONAR_LASTFM_SECRET` — из `windows.yml` и `ios.yml` (сами секреты в GitHub
  владелец может удалить).
- Сохранённую сессию Last.fm (keyring / Keychain) при запуске один раз стереть — мусор не копить.
- **Ничего не терять:** каждое прослушивание и так пишется в локальную `plays` (ПК — SQLite, iPhone — свой
  журнал); с сервером уходит `POST /plays` (синк уже готов на клиенте — `store/sync.rs`).
- ListenBrainz в Sonar **не делаем**, пока владелец не попросит: с сервером он не нужен.

## 3. Сервер (`server/`, когда будет Velt) — в ROADMAP

- Убрать `LASTFM_API_KEY` из `config.py`, `status.py` (пункт Last.fm на странице статуса), экрана бота
  (`bot/screens.py`), `env.example`, тестов. Пункт «Last.fm» в `GET /status`, `/status` бота и на сайте
  (`docs/SITE.md`, SPEC §3.11) — убрать.
- `GET /oauth/now` — «сейчас играет» по последнему `player_state` пользователя (формат Dotify, API.md) —
  главный источник для селфбота.
- `GET /stats`, `GET /stats/recap` — уже в API.md; для селфбота нужен **ключ API пользователя** (бот:
  «Ключ API», BOT.md) — селфбот ходит с ним.
- **Импорт истории:** `POST /plays/import` (только владелец аккаунта, свой ключ) — принимает
  `listenbrainz-export.jsonl` или `lastfm-export.jsonl` (формат один), сопоставляет треки по исполнителю и названию с `sc:` /
  `ym:` / `yt:` (как резервный сервис, `track_alias`), не нашлось — сохраняет как `ext:` (только название и
  исполнитель, для статистики). Повторный импорт не дублирует (ключ — время + исполнитель + название).
  Описать в `docs/API.md` и `docs/DB.md`.

## 4. Документы ✅ сделано 2026-11-18

- CLAUDE.md: убрать Last.fm из списка «вход в браузере по умолчанию» и из статуса; записать решение.
- SPEC, TZ, BOT, SITE, PLATFORMS, SETTINGS — вычистить упоминания Last.fm как рабочей интеграции.

## Готово, когда

- В приложениях нет ни одной строки «Last.fm», тесты зелёные, сборки CI без секретов Last.fm.
- История владельца импортирована на ListenBrainz **до 1 декабря** и выкачана в файл
  (`export_listenbrainz.py`; с ключом Last.fm — `export_lastfm.py`).
- После сервера: селфбот получает «сейчас играет» и итоги из API Sonar.
