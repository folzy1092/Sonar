# Уход с Last.fm (спека, решение владельца 2026-11-18)

С 1 декабря 2026 ключ API Last.fm работает только у владельца ключа с **Last.fm Pro**. Pro владелец брать
не будет. Решение: **Last.fm Sonar больше не нужен** — прослушивания и «сейчас играет» Sonar знает сам, а
после сервера отдаёт их своим API (`docs/API.md`: `POST /plays`, `GET /stats`, `GET /stats/recap`,
`GET /oauth/now` в формате Dotify). Селфбот читает оттуда же — его спека в репо `folzy1092/folzy-selfbot`,
`docs/superpowers/specs/2026-11-18-lastfm-exit-design.md`.

## 1. Сейчас, до 1 декабря — сохранить историю (владелец, один раз) — скрипт ✅ 2026-11-18

- **ListenBrainz** (аккаунт MusicBrainz `wxnna_cru` уже есть): listenbrainz.org → настройки → импорт из
  Last.fm, поле «Start Import From» пустое, недавние скробблы в профиле Last.fm не скрыты. Это резервная
  копия всей истории, бесплатно и навсегда.
- **Свой файл истории:** скрипт `server/tools/export_lastfm.py` (сделать в этой задаче) — пока ключ жив,
  выкачивает все скробблы `user.getRecentTracks` в `server/data/lastfm-export.jsonl`
  (`{ts, artist, title, album, mbid}` построчно; файл в `.gitignore`, в репо не класть). Его потом
  импортирует сервер (п. 4), чтобы итоги и статистика не начинались с нуля.

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
  `lastfm-export.jsonl` (или экспорт ListenBrainz), сопоставляет треки по исполнителю и названию с `sc:` /
  `ym:` / `yt:` (как резервный сервис, `track_alias`), не нашлось — сохраняет как `ext:` (только название и
  исполнитель, для статистики). Повторный импорт не дублирует (ключ — время + исполнитель + название).
  Описать в `docs/API.md` и `docs/DB.md`.

## 4. Документы ✅ сделано 2026-11-18

- CLAUDE.md: убрать Last.fm из списка «вход в браузере по умолчанию» и из статуса; записать решение.
- SPEC, TZ, BOT, SITE, PLATFORMS, SETTINGS — вычистить упоминания Last.fm как рабочей интеграции.

## Готово, когда

- В приложениях нет ни одной строки «Last.fm», тесты зелёные, сборки CI без секретов Last.fm.
- `server/tools/export_lastfm.py` выкачал историю владельца в файл **до 1 декабря**.
- После сервера: селфбот получает «сейчас играет» и итоги из API Sonar.
