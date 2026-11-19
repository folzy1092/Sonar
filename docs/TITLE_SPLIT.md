# Перезаливы: «АРТИСТ - ТРЕК» в названии — спецификация

Перенос логики из selfbot владельца (`folzy-selfbot/title_split.py`, `lyrics.py`, `admin_nolyrics.py`), чтобы
агенту Sonar **не нужен был доступ** к тому репо. Код selfbot — владельца, правила и регулярки ниже можно
переносить как есть (Python → Rust / Swift). Задание — `docs/POLISH_PROMPT.md` пункт 7.

## Зачем

На SoundCloud много перезаливов: «исполнитель» трека — тот, кто залил (`Kleyy`, `juchen`), а настоящий артист —
в названии: `cowboyclicker - doesnt matter (prod. gloro)`. lrclib и Genius по паре (`Kleyy`, `cowboyclicker -
doesnt matter (prod. gloro)`) ничего не находят, по (`cowboyclicker`, `doesnt matter`) — находят.

## Что делает модуль

Чистые функции, без сети:

- `reupload_variants(artist, title) -> [(artist, title)]` — до **4** запасных пар для поиска текста; исходная пара
  **никогда** не возвращается; без повторов (без учёта регистра); порядок детерминирован; нет разделителя — `[]`.
- `search_pair(artist, title) -> (artist, title)` — одна пара «настоящий артист + чистое название» для Genius и
  для показа. Не похоже на перезалив — исходная пара без изменений.
- `clean_title(title)`, `clean_artist(name)` — чистка (ниже).
- Словарь «артист-трек» (`dash_artists`) — редактируемый список (см. ниже).

## Константы

```
MAX_VARIANTS = 4
DASH = "-" U+2010 U+2011 U+2012 U+2013(–) U+2014(—) U+2015 U+2212(−)
SEPARATOR = \s+[DASH]\s+          # тире ТОЛЬКО с пробелами с двух сторон
DEFAULT_DASH_ARTISTS = ["cowboyclicker"]
DASH_NAME_MAX = 40

LEAD_TAGS = remix official new exclusive unreleased leak leaked snippet preview premiere free mashup full "tiktok remix"

MULTI_ARTIST (делит «A, B», «A & B», «A feat B»…) =
  \s*,\s* | \s+(?:&|feat\.?|ft\.?|x\+?|\+|×|и|and|with|w/)\s+          (без учёта регистра)
COLLAB (слева явно артисты) = ^[+@] | \s+(?:x\+?|\+|×|feat\.?|ft\.?)\s+ | ,\s     (без учёта регистра)

LEAD_MARKS = ^[\s+@~#*]+
TRAILING_GROUP = \s*(?:\([^()]*\)|\[[^\[\]]*\]|\{[^{}]*\}|\*\*[^*]*\*\*)\s*$
ANY_STARS = \s*\*\*[^*]*\*\*
```

Хвостовой мусор названия (`TITLE_TAILS`, все без учёта регистра, применяются по кругу):

```
\.(?:mp3|мп3|wav|flac|m4a)\s*$
\s+prod(?:uced)?\b.*$                       «prod kilolit», «prod. skorpy», «prod by. @x»  («Product Of Love» — НЕ режется: \b)
\s+p/\S.*$                                  «p/quazar»
\s+(?:feat|ft)\.?\s.*$
\s+\+.*$                                    «+mor+alyen», «+ 2 lines»
\s*#\S*(?:\s+#\S*)*\s*$                     «#2016», «#tag #tag»
\s+@\S+\s*$                                 «@beabadoobee»
\s+archive\s*$
\s+\d+\s*(?:й|-й|st|nd|rd|th)?\s*(?:парт|part)\w*\s*$      «1й парт»
\s+tiktok\s+remix\s*$
\s+(?:speed(?:ed)?|sped|slowed|nightcore)(?:\s+(?:up|down|x\s+mix|mix|\+\s*reverb|and\s+reverb))*\s*$
```

Слова-метки версии (`LABEL_WORDS`) — правая часть **только** из них — не название:

```
live edition remaster remastered remasters remix rmx edit edited radio acoustic version ver instrumental demo
slowed sped speed up down nightcore reverb reverbed mix extended original deluxe bonus mono stereo
explicit clean reprise unplugged session sessions cover official audio video lyric lyrics hq hd
and x mixed bass boosted
ремикс ремастер ремастеринг слоуд слоу замедленная замедленный ускоренная ускоренный версия акустика
акустическая живое лайв инструментал демо оригинал радио эдит спид ап найткор реверб микс и
```
плюс год `(?:19[5-9]|20[0-3])\d` и `v\d+`; плюс строка, начинающаяся с `feat|ft|featuring|prod|produced`
(перед ними допустимы пробелы, `(`, `[`).

## Функции-помощники

- `norm(s)` — casefold + схлопнуть пробелы.
- `letters(s)` — число букв.
- `is_label(text)`: `text` в нижнем регистре, `(ed)` → `ed`; начинается с feat/prod → да; иначе разбить на слова
  `[^\W_]+` — **все** слова из `LABEL_WORDS` или год/`vN` → да (пусто → нет).
  Не метки: `Live Forever`, `Original Sin`, `Product Of Love`, `Time`, `Remixed Feelings`. Метки: `2011 Remaster`, `speed up + reverb`.
- `strip_label_tail(text)`: если хвост после **последнего** разделителя — метка, срезать его (`Song - Slowed` → `Song`).
- `clean_title(title)` — до 8 кругов, пока что-то меняется: убрать `**…**`; убрать хвостовую скобку
  (`TRAILING_GROUP`); применить все `TITLE_TAILS`; `strip_label_tail`; обрезать висящие пробелы/тире по краям.
  На каждом шаге: если результат пустой — оставить как было. Итог пустой — исходное.
- `clean_artist(name)`: убрать `LEAD_MARKS`, хвостовую скобку; если есть `/` и **все** части ≥ 3 символов —
  взять первую («ШИПЫ/ONDA ANDAR» → «ШИПЫ», «AC/DC» — остаётся); снова убрать `LEAD_MARKS`.
- `first_artist(name)` — до первого `MULTI_ARTIST`.
- `looks_like_artist(name)`: не пусто, ≤ 60 знаков, ≤ 6 слов, есть буква или цифра.
- `is_uploader(name, uploader_norm)`: `norm(name) == uploader` или `norm(first_artist(name)) == uploader`.
- `usable(name, track)`: в `name` ≥ 2 букв, в `clean_title(track)` ≥ 2 букв, и ни `track`, ни
  `clean_title(track)` не метка.

## Подготовка названия

1. **Словарь «артист-трек»** (`dash_compact`): для каждого имени из словаря (длинные первыми), без учёта регистра,
   шаблон `^\s*(ИМЯ)\s*[DASH]\s*(?=\S)(.+)$` → `«ИМЯ - остальное»`. Только с начала названия; «cowboyclickers-трек»,
   «my cowboyclicker-трек», «cowboyclicker-», «cowboyclicker» — не трогаются.
   Нормализация имени словаря: без `@`, схлопнуть пробелы, нижний регистр; < 2 букв/цифр, > 40 знаков или с
   переводом строки — отбросить. Пустой список — это «пусто», а не «по умолчанию»; список не прочитался — по умолчанию.
2. **Список артистов через запятую** (`spaced_compact`), только если разделителя с пробелами нет вообще:
   `^([^DASH]*,[^DASH]*)[DASH](?=\S)(.+)$`, частей через запятую ≥ 2 и каждая ≥ 2 символов →
   «vzk1ll, cowboyclicker, jetcasse - много дел».
3. **Ведущие метки** (`drop_lead_tags`): пока разделителей ≥ 2 и текст до первого — из `LEAD_TAGS`, отрезать его
   («REMIX - A & B - TRACK» → «A & B - TRACK»).

## Сбор вариантов (`collect`)

```
artist, title = trim
work, spans = drop_lead_tags(spaced_compact(dash_compact(title)))
нет spans → []
uploader = norm(artist)
для index в {первый, последний} разделитель:
  left, right = части по этому разделителю (trim); пустые или is_label(left) → дальше
  who = artist если norm(left) == uploader, иначе clean_artist(left)
  если looks_like_artist(who) и usable(who, right):
      raw  += (who, right, split)
      если clean_title(right) != right: clean += (who, clean_title(right), split)
  ОБРАТНЫЙ ПОРЯДОК — только если разделитель один, слева не залившый и слева не COLLAB:
      who_right = clean_artist(clean_title(right))
      by_uploader = is_uploader(who_right, uploader)
      marked = clean_title(left) != left            # «(full)», «.mp3» слева
      если looks_like_artist(who_right), ≤ 40 знаков, ≤ 4 слов, (by_uploader или marked), не is_label(right):
          если by_uploader: who_right = artist; swapped_first = true
          если usable(who_right, clean_title(left)): swapped += (who_right, clean_title(left), swap)
порядок = swapped_first ? swapped+raw+clean : raw+clean+swapped
убрать повторы по (norm, norm) и исходную пару
reupload_variants = первые 4 пары (без вида)
search_pair: первый вариант; нет — исходная; если вид swap и это не залившый — исходная;
             иначе (artist, clean_title(track))
```

## Порядок поиска текста (как в selfbot `fetch_any`)

1. Обычная пара (как сейчас в Sonar: как есть → упрощённо → …).
2. Для треков SoundCloud — название и исполнитель со страницы SoundCloud (если отличаются).
3. **Только если не нашлось** — `reupload_variants` по очереди. Нашлось — в журнал «текст нашёлся по названию
   перезалива». Не нашлось ни по одному — запомнить промах на `VARIANT_RECHECK` (в selfbot — часы), чтобы не
   долбить lrclib десятком запросов каждый раз; сетевой сбой — **не** промах (повторим сразу). Ручная
   перепроверка трека сбрасывает промах.
4. Genius ищет по `search_pair`.
Правила с сервера (`docs/POLISH_PROMPT.md` п. 7): **перезаливщик** из списка — шаг 3 идёт **первым**; ручная пара
на трек — вместо всех шагов.

## Показ (как в selfbot `_show_real_artist`)

В selfbot карточка трека показывает **настоящего артиста и чистое название**, а залившего хранит отдельно
(`uploader`, ссылка на профиль залившего не меняется). В Sonar: настройка «Настоящий артист у перезаливов»
(`lyrics.reupload_display`, **по умолчанию вкл**, как у selfbot) — первая строка `doesnt matter`, вторая
`cowboyclicker`, под ней мелко «залил Kleyy» (ссылка на профиль залившего). Сам трек, ref, лайки, история — по
исходным данным, меняется только показ. Не похоже на перезалив — как было.

## Админка «Треки без текста» (как в selfbot)

- Сводка за **сутки / неделю**: треки без текста, которые играли за период (без игнорируемых), по 25 на страницу,
  «◀ 1/3 ▶»; у каждого — ссылка (трек SoundCloud или поиск), сколько раз играл, пометки.
- **Перепроверка** при открытии: не больше 10 треков за нажатие, пауза ~0,8 с между ними, недавно проверенные
  (30 мин) пропускаются; два «сервис не ответил» подряд — дальше не стучимся. Нашёлся текст — трек уходит из
  списка. Отчёт перепроверки: «искал исполнитель …, название …, пробовал и как перезалив: «A» — «B»; …».
- **Игнорировать** / **Игнорируемые** (по 10 на страницу) — снять трек из сводки и вернуть.
- **Словарь** «артист-трек»: показать, добавить (несколько через запятую или с новой строки), убрать.
- В Sonar добавить (чего нет в selfbot): у трека — «Это перезалив» (поля «артист» / «название», предпросмотр
  `reupload_variants`, «Найти текст», «Сохранить для всех»), список **перезаливщиков**.

## Тесты — перенести все

Формат: (исполнитель, название) → **начало** списка вариантов. Каждый случай также проверяет: исходной пары нет
и вариантов ≤ 4.

| исполнитель | название | начало результата |
|---|---|---|
| juchen | gothviolence – не могу уснуть | (gothviolence, не могу уснуть) |
| гниющая плесень | gothviolence — they wanna kill themselves when I hang up | (gothviolence, they wanna kill themselves when I hang up) |
| mereana mordegard⛧⸸ | cowboyclicker - RUSSIAN ROULETTE  archive | (cowboyclicker, RUSSIAN ROULETTE  archive), (cowboyclicker, RUSSIAN ROULETTE) |
| fleurnothappy | fleurnothappy - hermaeus mora prod @cl6udly | (fleurnothappy, hermaeus mora prod @cl6udly), (fleurnothappy, hermaeus mora) |
| BATO | BATO - Miura 2 | (BATO, Miura 2) — и **только** она |
| Bones | Bones - Sodium | (Bones, Sodium) |
| ШИПЫ | VZk1ll Turbo 2000, ШИПЫ - Mr.Bigbucks Cxsinoslayer 2016 | (VZk1ll Turbo 2000, ШИПЫ, Mr.Bigbucks Cxsinoslayer 2016) |
| ШИПЫ | cowboyclicker x ШИПЫ - fuck you | (cowboyclicker x ШИПЫ, fuck you) |
| playerwithoutheart | Russianmafiaextra X Cowboyclicker – Awake | (Russianmafiaextra X Cowboyclicker, Awake) |
| урал гайсин | bigpluggssd feat. фолли - сучка сосет достала.мп3 | (bigpluggssd feat. фолли, сучка сосет достала.мп3), (…, сучка сосет достала) |
| KUDOKUSHI, AQUAKEY | KUDOKUSHI, AQUKAEY - same problems | (KUDOKUSHI, AQUKAEY, same problems) |
| анатолий балансиага | анатолий балансиага, eliass - angelsnumber | (анатолий балансиага, eliass, angelsnumber) |
| @leilahimikat | + ONDA ANDAR - Нацеди мне | (ONDA ANDAR, Нацеди мне) |
| leilahimikat | +ШИПЫ/ONDA ANDAR - sоrты яdа | (ШИПЫ, sоrты яdа) |
| @extra | @russianmafiaextra + cowboyclicker - awake p/quazar | (russianmafiaextra + cowboyclicker, awake p/quazar), (…, awake) |
| ~ Slump Audios Radio ~ | cowboyclicker - fall (nepuhz) [slump audios exclusive + v8gve] | (cowboyclicker, fall (nepuhz) [slump audios exclusive + v8gve]), (cowboyclicker, fall) |
| щщщ | gothviolence - Не Найдёшь Меня +mor+alyen+sydniy | (gothviolence, Не Найдёшь Меня +mor+alyen+sydniy), (gothviolence, Не Найдёшь Меня) |
| justinhoward | ШИПЫ - ChainMail_{{Sp1keSpells77}}#2016 [prod hatred.exe] | (ШИПЫ, ChainMail_{{Sp1keSpells77}}#2016 [prod hatred.exe]), (ШИПЫ, ChainMail_{{Sp1keSpells77}}) |
| культ | gothviolence - theydonknowme prod kilolit | (gothviolence, theydonknowme prod kilolit), (gothviolence, theydonknowme) |
| 17.javelin | cowboyclicker - no tomorrow prod. skorpy | (…, no tomorrow prod. skorpy), (cowboyclicker, no tomorrow) |
| yaphula | jaydes - migraine @beabadoobee | (jaydes, migraine @beabadoobee), (jaydes, migraine) |
| мельников | gothviolence – i dontbelieve the words anymore... im takin yr sWAG.mp3 | (…, …sWAG.mp3), (gothviolence, i dontbelieve the words anymore... im takin yr sWAG) |
| eternalfearofgod | cowboyclicker - fishing ft. tarozan(slowed+reverb) | (…, fishing ft. tarozan(slowed+reverb)), (cowboyclicker, fishing) |
| ALIK SHAWARMA | cowboyclicker - idontwanna(without helios812) | (…, idontwanna(without helios812)), (cowboyclicker, idontwanna) |
| 1nv6l1d | Овсянкин - Red lipstick + 2 lines | (Овсянкин, Red lipstick + 2 lines), (Овсянкин, Red lipstick) |
| six | yuke - gone (edited) | (yuke, gone (edited)), (yuke, gone) |
| SEMATARY | SEMATARY FT. GHOST MOUNTAIN - BUNNY SUIT \*\*VIDEO IN DESCRIPTION\*\* | (SEMATARY FT. GHOST MOUNTAIN, BUNNY SUIT \*\*VIDEO IN DESCRIPTION\*\*), (…, BUNNY SUIT) |
| #некийй парень | BENJAMINGOTBENZ - MOONLIGHT ANGEL SPEED X MIX | (…, MOONLIGHT ANGEL SPEED X MIX), (BENJAMINGOTBENZ, MOONLIGHT ANGEL) |
| imurcurse | ONDA ANDAR – SHIPY DOWNHEAD RACING #2016 | (…, SHIPY DOWNHEAD RACING #2016), (ONDA ANDAR, SHIPY DOWNHEAD RACING) |
| mirror private club | ШИПЫ - Krovat' 1й парт | (ШИПЫ, Krovat' 1й парт), (ШИПЫ, Krovat') |
| 43 | REMIX - BIG BABY TAPE & KIZARU - BON VOYAGE (prod by. @threen1ne) | (BIG BABY TAPE & KIZARU, BON VOYAGE (prod by. @threen1ne)), (…, BON VOYAGE) |
| мадвей | сны не меняются(full) - onda andar | (сны не меняются, onda andar), (onda andar, сны не меняются) |
| Alex G | east coast - alex g | (Alex G, east coast), (east coast, alex g) |

Отдельные проверки:

- Обратная пара только с доказательством: `мадвей` / `сны не меняются(full) - onda andar` → **последняя**
  (onda andar, сны не меняются); `x` / `клип.mp3 - Some Artist` → последняя (Some Artist, клип);
  `Alex G` / `east coast - alex g` → **первая** (Alex G, east coast).
- Без доказательства — без обратной: `russianmafiaextra` / `russianmafiaextra - hello past` → ровно
  [(russianmafiaextra, hello past)]; `juchen` / `gothviolence – не могу уснуть` → ровно 1 пара;
  `blissful` / `Дарк Бриллиант Корсес - Anniversary` → ровно [(Дарк Бриллиант Корсес, Anniversary)].
- `Alex G` / `Alex G | east coast - alex g (full)` — без повторов, ровно одна пара с названием, начинающимся на «alex g |».
- Нет разделителя → `[]`: `Mr.Bigbucks`, `ONDA ANDAR`, ``, `   `, `a - `, ` - b`.
- Дефис без пробелов — не разделитель: `T-Shirt`, `Self-Obsession` → `[]`; `Self-Obsession - Track` → первая (Self-Obsession, Track).
- Исходная пара не возвращается; `A` / `a - A` — нет (A, a - A); `ab` / `AB - ab` → [(ab, ab)].
- `x` / `Aa - Bb - Cc - Dd` — ≥ 2 вариантов, без повторов, ≤ 4, повторный вызов — тот же результат;
  `x` / `Bones - Bones` → [(Bones, Bones)].
- Три части: `Artist - Middle - Track` содержит (Artist, Middle - Track) и (Artist - Middle, Track).
- `AC/DC - Hells Bells` → первая (AC/DC, Hells Bells). `clean_title('Product Of Love')` = `Product Of Love`.
- `search_pair`: (juchen, gothviolence – не могу уснуть) → (gothviolence, не могу уснуть);
  (x, cowboyclicker - fall (nepuhz)) → (cowboyclicker, fall); (x, no separator) → как есть.
- Правая часть — только метка → `[]` и `search_pair` как есть (исполнитель `Some Band`): `Creep - Live`,
  `Time - 2011 Remaster`, `Song - Radio Edit`, `Runaway - Radio Edit`, `X - Remix`, `Song - Acoustic Version`,
  `Song - Remastered 2009`, `Song - Remaster(ed)`, `Song - Sped Up`, `Song - Extended Mix`, `Song - Original Mix`,
  `Song - Instrumental`, `Song - Deluxe Edition`, `Song - Mono`, `Song - 1999`, `Song - Ремикс`, `Song - Слоуд`,
  `Song - Slowed + Reverb`, `Song - (Live)`, `Song - feat. Someone`, `Song - prod. Someone`.
- `clean_title`: `Song - Slowed`, `Song - Radio Edit`, `Song - slowed`, `Song —` → `Song`;
  `u` / `Artist - Song - Slowed` → [(Artist, Song - Slowed), (Artist, Song)], `search_pair` → (Artist, Song).
- `u` / `Kanye West - Power - Remix`: нет пары с названием `Remix`, есть (Kanye West, Power), `search_pair` → (Kanye West, Power).
- Шум вместо названия → `[]` и `search_pair` как есть: `Artist - prod`, `Artist - feat. X`, `Artist - ft. Y`,
  `Artist - #1`, `Artist - prod. beats`, `Artist - 7`, `A - Song`.
- Словарь (по умолчанию `cowboyclicker`): `автор` / `cowboyclicker-трек`, `CowboyClicker–Трек`, `cowboyclicker -трек`,
  `cowboyclicker- трек` → [(cowboyclicker/CowboyClicker, трек/Трек)]; `cowboyclicker-трек (prod. x)` → последняя
  (cowboyclicker, трек); `search_pair('автор', 'cowboyclicker-трек')` → (cowboyclicker, трек).
  Не трогает: `T-Shirt`, `Self-Obsession`, `Jay-Z`, `cowboyclickers-трек`, `cowboyclicker`, `cowboyclicker-`,
  `my cowboyclicker-трек`; `cowboyclicker x шипы - fuck you` → [(cowboyclicker x шипы, fuck you)].
- Словарь меняется: [`jay-z`, `wu tang`] → хранится как (`wu tang`, `jay-z`) (длинные первыми);
  `jay-z-99 problems` → [(jay-z, 99 problems)]; `Wu Tang-C.R.E.A.M.` → [(Wu Tang, C.R.E.A.M.)];
  `cowboyclicker-трек` → `[]` (убран); после удаления `jay-z` → `jay-z-99 problems` → `[]`.
- Нормализация имени: `  @CowboyClicker \n` → `cowboyclicker`; `a`, `--`, пусто → отбросить; 41 символ → отбросить;
  `Sad  Boy` → `sad boy`. Загрузчик словаря упал → по умолчанию; пустой список → пусто.
- Поиск текста: первая пара нашлась — варианты не пробуются; не нашлась — пробуется (gothviolence, не могу уснуть);
  вариантов нет — один запрос; сетевой сбой на варианте — дальше не идём и промах не записываем; промах
  запоминается (второй вызов — только обычный поиск) и истекает; ручная перепроверка сбрасывает его.
