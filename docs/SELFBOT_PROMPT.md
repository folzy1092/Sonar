# Задание: selfbot переходит с Dotify на Sonar (2026-11-25)

Это задание для сессии в репо **folzy-selfbot** (`C:\Users\Folzy\Desktop\projects\selfbot`, код — `code/`).
Владелец уходит с Dotify на свой плеер Sonar: «сейчас играет» в bio/имени, карточка `/now`, пост канала и
«Топ недели» должны брать трек из Sonar, а не из Dotify. Перед началом прочитать `CLAUDE.md`, `AGENTS.md` и
`память_для_claude.md` selfbot. Коммиты — от Folzy, в `master`, без следов ИИ; после пуша — уведомление
владельцу (`notify.py`), в «Что сделать» — `/update` и что вписать в настройки.

## Когда начинать

Нужен метод `GET /api/oauth/now` на сервере Sonar — это **этап 5** задания `docs/SERVER_PROMPT.md` в репо Sonar.
Пока его нет, сделать всё, что можно, проверить на заглушке (ниже) и не выкатывать переключение по умолчанию.
Проверка, что метод уже есть: `curl -H "Authorization: Bearer sk_…" https://try-sonar.ru/api/oauth/now` → 200 и JSON.

## Что отдаёт Sonar (договор — `docs/API.md` §7 репо Sonar)

`GET https://try-sonar.ru/api/oauth/now` — ключ API пользователя Sonar (`sk_…`, берётся в боте
@SonarMusicApp → Профиль → Интеграция или в приложении): заголовок `Authorization: Bearer sk_…`; сервер
принимает и `?token=sk_…`, как Dotify. Ответ — **тот же JSON, что у Dotify**:

```json
{"is_playing": true, "position_ms": 41000, "state": "playing", "updated_at": 1794340534779,
 "track": {"id": "2296053116", "track_id": "2296053116", "source": "soundcloud", "title": "…", "artist": "…",
           "cover_art": "https://…", "duration": 123, "duration_ms": 123000, "context": "favorites",
           "is_playing": true, "position_ms": 41000, "updated_at": 1794340534779}}
```

- `state`: `playing` / `paused` / `stopped`; `track: null` — ничего ещё не играло.
- `source`: `soundcloud` / `yandex` / `youtube` / `spotify` (у Dotify были только первые два). `id` — без
  префикса сервиса. Для `youtube` и `spotify` ссылку на трек давать через song.link (правило владельца:
  ссылки только SoundCloud или song.link), обложку брать из `cover_art`.
- Профиль: `GET https://try-sonar.ru/api/oauth/profile` с тем же ключом → `{username, display_name, avatar_url}`.

## Что сделать

1. **Источник Sonar вместо Dotify.** `tracks.py`: `fetch_sonar_track(token)` по образцу `fetch_dotify_track`
   (тот же разбор — формат совпадает, `DotifyTrack` переименовать в общий класс ответа). Адрес — константа
   `SONAR_API = "https://try-sonar.ru/api"`, переопределяется переменной `SONAR_API_URL` в `.env` (на случай
   переезда сервера). Ключ — в заголовке `Authorization`, не в адресе (адрес попадает в журналы).
2. **Хранение ключа.** Колонка `users.sonar_token` (миграция в `core.py`, как `dotify_token`), в `db_backup.py` —
   в `SECRET_COLUMNS`. Команда, которой владелец вписывает ключ, — по образцу той, что сейчас для Dotify.
3. **Опрос.** `loops.py`: `_poll_sonar` вместо `_poll_dotify`, `health` — «Sonar». Правило «пока источник
   ответил треком, история SoundCloud — лишь эхо» (`_echo_sources`) переносится на Sonar как есть.
4. **Основной сервис.** `main_service`: значение `Sonar`; миграция `Dotify → Sonar` у всех, у кого стоял Dotify.
5. **`/get`** (админка, `admin.py`): отладочный GET к `SONAR_API` с ключом владельца вместо `api.dotify.fun`.
6. **Dotify убрать** — после того как владелец проверил Sonar вживую (п. «Проверка»): `fetch_dotify_track`,
   `dotify_token` (колонку оставить, но не читать), упоминания в текстах бота и README. До проверки — оставить
   Dotify запасным источником: Sonar не ответил (сеть, 5xx) — спросить Dotify.
7. Тексты, где написано «Dotify» (подсказки, `/help`, канал), — на «Sonar».

## Проверка

- Тесты selfbot (как в его `CLAUDE.md`), плюс тест разбора ответа Sonar на образце выше: `playing`, `paused`,
  `track: null`, источник `youtube` (ссылка — song.link).
- Заглушка, пока на сервере нет этапа 5: локальный `python -m http.server` с файлом ответа и `SONAR_API_URL`
  на него.
- Вживую: в Sonar на ПК играет трек → через один круг опроса bio и `/now` показывают его; пауза в Sonar → bio
  переходит в «не играет» по тем же правилам, что были с Dotify.
- Тестовые сообщения — только в тему «Tests» лог-группы (`-1002276939424`), не в канал.
