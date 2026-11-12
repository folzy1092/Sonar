# Sonar — каталог настроек

Каждая настройка — ключ `раздел.имя`, хранится как JSON-значение. **sync** — уходит на сервер
и одинакова на всех устройствах. Ключи общие для iOS и Windows, если смысл совпадает.
Референс — файл в `reference/` (только локально).

## Меню настроек iOS (`mobile/photo_1..3`)

```
[Шапка профиля: аватар, имя, @username, #номер, дата регистрации] [Поделиться] [✎]
Профиль:     Статистика · Безопасность · Приватность 🔒
Приложение:  Основные · Аудио · Кэш · Язык
Интерфейс:   Вид · Плеер · Жесты
Интеграции:  Сервисы (SoundCloud, Яндекс) · Last.fm · Ключ API
Прочее:      Сбросить настройки · Выйти · Версия 1.0.0 (сборка N) · Автообновление
О приложении: Телеграм · Сайт
```
Убрано: Подписка, Прокси, Кастомизация, Мастерская, Discord.

## Основные — `general.*` (`photo_11`, `pc/16`)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `general.platform` | `soundcloud` / `yandex` | `soundcloud` | да |
| `general.restore` | `none` / `track` / `queue` | `queue` | да |
| `general.similar_autoplay` | bool | `true` | да |
| `general.add_position` | `start` / `end` | `start` | да |
| `general.language` | `system` / `ru` / `en` | `system` | нет |

Кнопки «Отправить на сервер» / «Получить с сервера» — действия, не настройки.
`general.platform` — откуда главная берёт волну и рекомендации.

## Аудио — `audio.*` (`photo_12`, `pc/4,5`)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `audio.quality` | `low`(192) / `medium`(256) / `high`(320) / `max`(1411+) | `high` | нет |
| `audio.gapless` | bool | `true` | да |
| `audio.normalize` | bool | `false` | да |
| `audio.on_interruption` | `duck` / `pause` / `none` | `duck` | да |
| `audio.crossfade` (PC) | bool | `false` | да |
| `audio.output_device` (PC) | id устройства | системное | нет |

Качество — пожелание: сервер выбирает ближайшее доступное (SC выше 256 не даёт).

## Вид — `appearance.*` (`photo_13..15`, `pc/1..3`)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `appearance.mode` | `system` / `dark` / `light` | `dark` | да |
| `appearance.cover_theme` | bool — тема под обложку | `true` | да |
| `appearance.preset` | `neutral`, `amoled`, `crimson`, `nord`, `sky`, `mint`, `violet`, `blossom`, `sakura`, `terminal`, `aqua`, `sunset`, `slate` | `neutral` | да |
| `appearance.tab_style` | `standard` / `rounded` / `floating` | `floating` | да |
| `appearance.mini_player` | `capsule` / `standard` / `minimal` | `capsule` | да |
| `appearance.background` | `cover_color` / `theme` / `image` | `cover_color` | да |
| `appearance.progress_indicator` | `ring_on_cover` / `line` / `background` | `ring_on_cover` | да |
| `appearance.cover_shape` | `circle` / `square` | `circle` | да |
| `appearance.corner_radius` | `none` / `small` / `medium` / `pill` | `pill` | да |
| `appearance.glass` | bool — прозрачность | `true` | да |
| `appearance.glass_type` | `thin` / `regular` / `ultra` | `ultra` | да |
| `appearance.opacity` | 0–100 % | `100` | да |
| `appearance.glass_blur` | 0–40 px | `0` | да |
| `appearance.bg_blur` | 0–40 px | `0` | да |
| `appearance.bg_dim` | 0–90 % | `0` | да |
| `appearance.bg_image` | id картинки на сервере / null | `null` | да |
| `appearance.font` | `system`, `inter`, `sf_rounded`, `serif`, `mono`, … | `system` | да |
| `appearance.font_size` | 12 / 14 / 16 / 18 / 20 | `16` | да |
| `appearance.font_weight` (PC) | `auto` / 400 / 500 / 600 / 700 | `auto` | да |
| `appearance.scale_window` (PC) | 75–125 % | `90` | нет |
| `appearance.scale_fullscreen` (PC) | 75–125 % | `90` | нет |

## Плеер — `player.*` (`photo_16, 17`, `pc/6, 7`)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `player.style` | `standard` / `vinyl` / `large` | `large` | да |
| `player.queue_view` | `normal` / `extended` | `extended` | да |
| `player.background` | `none` / `cover_blur` / `cover_color` | `none` | да |
| `player.title_align` | `left` / `center` / `right` | `center` | да |
| `player.slider` | `normal` / `thin` / `smooth` / `wave_bars` / `wavy` | `normal` | да |
| `player.play_button` | `circle` / `square` / `clean` | `circle` | да |
| `player.artist_avatars` | bool | `true` | да |
| `player.visualizer` (PC) | `off` / `bar` / `cover` / `slider` | `bar` | да |
| `player.visualizer_style` (PC) | `wave` / `bars` | `wave` | да |
| `player.cover_position` (PC) | `left` / `right` | `left` | да |
| `player.cover_in_cover` (PC) | bool | `false` | да |

## Очередь — `queue.*` (PC `pc/7`; на iOS — часть «Плеера»)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `queue.show` (PC) | bool | `true` | да |
| `queue.next_preview` | bool — «Далее: …» в плеере | `true` | да |
| `queue.position` (PC) | `bottom` / `left` / `right` | `bottom` | да |
| `queue.add_following` | bool — тап по треку ставит и следующие за ним | `true` | да |

## Жесты — `gestures.*` (`photo_18..20`)

Действия: `off`, `like`, `enqueue`, `play_next`, `next`, `previous`, `delete`.

| Ключ | По умолч. |
|---|---|
| `gestures.library.left` | `play_next` |
| `gestures.library.right` | `play_next` |
| `gestures.queue.left` | `delete` |
| `gestures.queue.right` | `delete` |
| `gestures.mini.left` | `next` |
| `gestures.mini.right` | `previous` |
| `gestures.player.left` | `next` |
| `gestures.player.right` | `previous` |
| `gestures.cover.double_tap` | `like` |
| `gestures.cover.triple_tap` | `next` |

Все — sync. `delete` в Медиатеке = убрать из плейлиста/лайков (с «Отменить» 4 с).

## Мини-плеер PC — `mini.*` (`pc/8, 9`)

| Ключ | Значения | По умолч. |
|---|---|---|
| `mini.style` | `off` / `full` / `rounded` / `hybrid` / `deck` | `rounded` |
| `mini.position` | `top` / `bottom` / `bottom_inset` / `floating` | `bottom` |
| `mini.background` | `theme` / `cover` / `cover_color` | `cover_color` |
| `mini.progress` | `line` / `background` / `around_cover` | `background` |
| `mini.cover_shape` | `default` / `circle` | `circle` |
| `mini.shape` | `default` / `capsule` | `capsule` |

## Оверлей PC — `overlay.*` (`pc/10, 11`) — после MVP

`overlay.mode` (`off` / `fullscreen` / `island` / `card` / `sticky`), `overlay.shape`
(`square` / `rounded`), `overlay.position`, `overlay.opacity` (90), `overlay.scale` (100),
`overlay.width` (340), `overlay.height` (58).

## Интеграции — `integrations.*` (`photo_3`, `pc/14, 15`)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `integrations.lastfm.scrobble` | bool | `true` | сервер |
| `integrations.lastfm.now_playing` | bool | `true` | сервер |
| `integrations.discord.enabled` (PC) | bool | `true` | да |
| `integrations.discord.cover` (PC) | bool | `true` | да |
| `integrations.discord.progress` (PC) | bool | `true` | да |

Ключ API (для selfbot и `GET /oauth/now`) — создать / перевыпустить / удалить, показывается
один раз. OBS-плашка (`pc/15`) — после MVP, тем же ключом.

## Система PC — `system.*` (`pc/16`)

`system.autostart` (true), `system.tray` (true), `system.power_saving`
(`off` / `minimized` / `background`, по умолч. `background`). Горячие клавиши (`pc/17`) —
**не делаем**.

## Кэш / Хранилище — `storage.*` (`pc/18`, iOS «Кэш»)

| Ключ | Значения | По умолч. | sync |
|---|---|---|---|
| `storage.cache_tracks` | bool | `false` | нет |
| `storage.cache_limit_mb` | 500 / 1000 / 2000 / 5000 | `1000` | нет |

Экран: занято всего (полоса по типам), «Треки N, X МБ», «Обложки», «Тексты» — «Очистить» у
каждого и «Очистить всё»; «История поиска — Очистить»; «Настройки треков — Сбросить»
(сдвиг текста по треку). Скачанные вручную треки — отдельной строкой, «Очистить» с
подтверждением.

## Автообновление — `update.*` (iOS)

`update.auto_check` (true), `update.channel` (`stable`). Сертификат (`.p12`, пароль,
`.mobileprovision`) — только Keychain/файлы устройства, не sync.
