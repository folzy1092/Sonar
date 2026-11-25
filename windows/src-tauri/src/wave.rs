//! Своя волна Sonar Mix (SPEC §3.7, PSEUDOCODE §11) в автономном клиенте: кандидаты — похожие треки
//! от сидов (последние лайки и дослушанные + немного «разведки» по старым лайкам), фильтры
//! (не играть прослушанное за 7 дней, дизлайки, артисты на паузе) и выбор порции с разнообразием.
//! Сессию (что уже выдано, кто на паузе) держит интерфейс и передаёт сюда — ядро без состояния.

use crate::providers::registry::{parse_ref, RefKind};
use crate::providers::{ArtistRef, Track};
use crate::store::Taste;
use serde::Serialize;
use std::collections::{HashMap, HashSet};

/// Порция волны.
pub const PORTION: usize = 10;

/// Простой генератор случайных чисел (xorshift) — без лишнего крейта.
pub struct Rng(u64);

impl Rng {
  /// Зерно перемешивается splitmix64: у голого xorshift с малым зерном первые числа почти нули.
  pub fn new(seed: u64) -> Self {
    let mut z = seed.wrapping_add(0x9E37_79B9_7F4A_7C15);
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    Self((z ^ (z >> 31)) | 1)
  }
  pub fn next(&mut self) -> u64 {
    let mut x = self.0;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    self.0 = x;
    x
  }
  /// 0.0 … 1.0
  pub fn unit(&mut self) -> f64 {
    (self.next() >> 11) as f64 / (1u64 << 53) as f64
  }
  /// `n` случайных элементов без повторов.
  pub fn sample<T: Clone>(&mut self, items: &[T], n: usize) -> Vec<T> {
    let mut v = items.to_vec();
    for i in (1..v.len()).rev() {
      let j = (self.next() % (i as u64 + 1)) as usize;
      v.swap(i, j);
    }
    v.truncate(n);
    v
  }
  /// `n` элементов без повторов, чаще — тяжёлые (вес ≤ 0 — не берётся). Выборка по одному:
  /// элемент с весом `w` выпадает с вероятностью `w / Σw` среди ещё не взятых.
  pub fn weighted_sample<T: Clone>(&mut self, items: &[(T, f64)], n: usize) -> Vec<T> {
    let mut left: Vec<(T, f64)> = items.iter().filter(|(_, w)| *w > 0.0 && w.is_finite()).cloned().collect();
    let mut out = Vec::with_capacity(n.min(left.len()));
    while out.len() < n && !left.is_empty() {
      let total: f64 = left.iter().map(|(_, w)| w).sum();
      let mut x = self.unit() * total;
      let mut i = left.len() - 1;
      for (j, (_, w)) in left.iter().enumerate() {
        if x < *w {
          i = j;
          break;
        }
        x -= w;
      }
      out.push(left.remove(i).0);
    }
    out
  }
}

/// Что нельзя ставить в порцию.
#[derive(Default, Clone)]
pub struct Filter {
  /// Слушали за 7 дней.
  pub recent: HashSet<String>,
  /// 👎.
  pub banned: HashSet<String>,
  /// Уже выданы в этой сессии волны.
  pub exclude: HashSet<String>,
  /// Артисты на паузе до конца сессии (два пропуска подряд), в нижнем регистре.
  pub paused_artists: HashSet<String>,
  /// Артисты «Никогда» (экран вкуса): ни их треков, ни их соавторских — в нижнем регистре.
  pub never_artists: HashSet<String>,
  /// Сколько треков **незнакомых** артистов (ни лайка, ни прослушиваний) пускать в порцию: «Обычное»
  /// волна — в основном знакомое, как у Яндекса. `None` — без лимита. См. [`familiarity`].
  pub max_unknown: Option<usize>,
  /// Трек SoundCloud незнакомого артиста с меньшим числом прослушиваний не берём: в «похожих»
  /// SoundCloud много случайных заливов. 0 — без порога.
  pub min_plays_unknown: u64,
}

impl Filter {
  /// Трек артиста из «Никогда» (любой из соавторов).
  pub fn is_never(&self, t: &Track) -> bool {
    !self.never_artists.is_empty() && artist_keys(t).iter().any(|k| self.never_artists.contains(k))
  }
}

/// Что вкус говорит об артистах (`wave.artist_prefs`, экран «Вкус»): «Больше» и «Меньше» — признак
/// оценки (`+1` / `−1`), «Никогда» — отдельный набор для фильтра. Ключ — имя артиста в нижнем регистре.
pub fn artist_prefs(v: Option<&serde_json::Value>) -> (HashMap<String, f64>, HashSet<String>) {
  let mut pref = HashMap::new();
  let mut never = HashSet::new();
  if let Some(map) = v.and_then(|v| v.as_object()) {
    for (k, e) in map {
      let key = k.trim().to_lowercase();
      match e.get("level").and_then(|l| l.as_str()) {
        Some("more") => drop(pref.insert(key, 1.0)),
        Some("less") => drop(pref.insert(key, -1.0)),
        Some("never") => drop(never.insert(key)),
        _ => {}
      }
    }
  }
  (pref, never)
}

/// Знакомое и новое по режиму: (сколько незнакомых артистов в порции из `n`, порог прослушиваний
/// для треков SoundCloud незнакомых). «Обычное» — до 30 %, настроения — до 40 %, волна по треку —
/// до 50 %, «Популярное» — до 60 % (хиты чужих артистов — его суть) и только заметные треки.
pub fn familiarity(mode: &str, by_seed: bool, n: usize) -> (Option<usize>, u64) {
  let share = |k: f64| Some(((n as f64) * k).round() as usize);
  match mode {
    _ if by_seed => (share(0.5), 300),
    "own" => (share(0.3), 1000),
    "popular" => (share(0.6), 50_000),
    _ => (share(0.4), 1000),
  }
}

/// Трек сервиса с коротким id `p` (`sc`, `ym`) — по префиксу ref из реестра.
fn is_track_of(r: &str, p: &str) -> bool {
  matches!(parse_ref(r), Some((s, RefKind::Track)) if s.id.as_str() == p)
}

/// Знакомый артист трека: лайкнут или его слушали (по любому из артистов трека).
pub fn is_known(t: &Track, taste: &Taste) -> bool {
  artist_keys(t).iter().any(|k| taste.liked_artists.contains(k) || taste.plays.get(k).is_some_and(|&p| p > 0.0))
}

/// Главный артист трека (первый из `artist_keys`) — по нему лимиты разнообразия, пауза, сессия.
pub fn artist_key(t: &Track) -> String {
  artist_keys(t).swap_remove(0)
}

/// Артисты трека: имена из `artists` (нижний регистр, без крайних пробелов), а если списка нет —
/// строка `artist` целиком. Первый — главный. Имена **не режутся** по запятым и `&`
/// («Tyler, The Creator», «Simon & Garfunkel»): совместный трек Яндекса и так приходит списком.
pub fn artist_keys(t: &Track) -> Vec<String> {
  artist_names(&t.artist, &t.artists)
}

/// То же по сохранённым полям (строка `artist` и список из `artists_json`).
pub fn artist_names(artist: &str, artists: &[ArtistRef]) -> Vec<String> {
  let mut out: Vec<String> = Vec::with_capacity(artists.len().max(1));
  for a in artists {
    let k = a.name.trim().to_lowercase();
    if !k.is_empty() && !out.contains(&k) {
      out.push(k);
    }
  }
  if out.is_empty() {
    out.push(artist.trim().to_lowercase());
  }
  out
}

/// Оценка исхода трека — одна шкала для всех сигналов волны (та же функция в
/// `src/player/reward.ts`, тесты на обе). `listened_ms` — сколько прослушано, `manual_skip` —
/// трек пропустили вручную (а не закончился сам или сменился иначе), `liked` — лайкнут во время
/// трека или уже в Любимых, `disliked` — 👎.
///
/// | исход | оценка |
/// |---|---|
/// | 👎 | −2 |
/// | лайк | +1.5 (отменяет минусы) |
/// | пропуск, `f < 0.25` или < 30 с — ранний | −1 |
/// | пропуск, `0.25 ≤ f < 0.5` | −0.4 |
/// | пропуск, `0.5 ≤ f < 0.8` | 0 |
/// | `f ≥ 0.8` | +1 |
/// | сменился не пропуском, `f < 0.8` | 0 |
///
/// Длительность неизвестна (0) — по секундам: < 30 с — ранний пропуск, ≥ 150 с — дослушан.
pub fn reward(listened_ms: u64, duration_ms: u64, manual_skip: bool, liked: bool, disliked: bool) -> f64 {
  if disliked {
    return -2.0;
  }
  if liked {
    return 1.5;
  }
  let early = listened_ms < 30_000;
  if duration_ms == 0 {
    return if listened_ms >= 150_000 {
      1.0
    } else if manual_skip && early {
      -1.0
    } else {
      0.0
    };
  }
  let f = listened_ms as f64 / duration_ms as f64;
  if f >= 0.8 {
    1.0
  } else if !manual_skip {
    0.0
  } else if f < 0.25 || early {
    -1.0
  } else if f < 0.5 {
    -0.4
  } else {
    0.0
  }
}

/// Ранний пропуск (оценка −1 без 👎) — два подряд ставят артиста на паузу.
#[cfg(test)]
pub fn is_early_skip(listened_ms: u64, duration_ms: u64, manual_skip: bool) -> bool {
  reward(listened_ms, duration_ms, manual_skip, false, false) <= -1.0
}

/// Режим Sonar Mix (настроение под «Sonar Mix» на главной): `own` — обычное, по лайкам; остальное —
/// настроения. Настроение угадываем по жанру, тегам и названию трека — группы тегов настроений
/// MIREX (Hu & Downie, теги слушателей) плюс жанры, которые обычно туда ложатся. «Популярное» вдобавок
/// тянет треки с большим числом прослушиваний (`popularity`). Старое `new` («Незнакомое») убрано —
/// незнакомый режим приходит как `own` (commands.rs берёт `own` для всего, чего нет в `MODES`).
pub const MODES: [&str; 9] = ["own", "fun", "calm", "sad", "hard", "night", "sleep", "popular", "focus"];

const MOODS: [(&str, &[&str]); 8] = [
  (
    "hard",
    &[
      "phonk", "drift", "hardstyle", "hardcore", "drill", "trap", "rage", "metal", "rock", "punk", "dubstep", "dnb",
      "drum & bass", "drum and bass", "breakcore", "jersey", "hard", "aggressive", "brazilian", "funk", "techno", "industrial",
      "rusrap", "hip-hop", "hiphop", "rap", "energetic", "workout", "gym", "intense", "angry", "энерг",
    ],
  ),
  (
    "calm",
    &[
      "lofi", "lo-fi", "chill", "ambient", "acoustic", "piano", "jazz", "calm", "relax", "classical", "instrumental",
      "soul", "r&b", "rnb", "downtempo", "bossa", "folk", "mellow", "soothing", "serene", "lounge", "спокой",
    ],
  ),
  (
    "sad",
    &[
      "sad", "emo", "depress", "melanchol", "slowed", "reverb", "heartbreak", "lonely", "cry", "alone", "grief", "tears",
      "cloud rap", "cloudrap", "dark", "gloomy", "sorrow", "sadcore", "грус", "одинок", "слёз", "слез", "печал", "тоск",
      "меланхол",
    ],
  ),
  (
    "fun",
    &[
      "pop", "dance", "house", "disco", "party", "happy", "summer", "hyperpop", "electro", "edm", "club", "remix",
      "sped up", "nightcore", "funk", "k-pop", "kpop", "upbeat", "feel good", "sunny", "cheerful", "latin", "весел",
      "радост", "лето",
    ],
  ),
  (
    "night",
    &[
      "night", "midnight", "nocturn", "darkwave", "synthwave", "retrowave", "outrun", "vaporwave", "witch house",
      "trip-hop", "trip hop", "triphop", "deep house", "after hours", "afterhours", "city pop", "noir", "neo-soul",
      "neo soul", "dark", "ночь", "ночн", "полноч",
    ],
  ),
  (
    "sleep",
    &[
      "sleep", "lullaby", "ambient", "drone", "meditat", "new age", "white noise", "rain sounds", "nature sounds",
      "dreamy", "dream pop", "healing", "432hz", "soft piano", "сон", "колыбел", "засып", "медитац",
    ],
  ),
  (
    "popular",
    &["hits", "chart", "top 40", "top 50", "top 100", "viral", "tiktok", "trending", "mainstream", "billboard", "хиты", "чарт", "тренд"],
  ),
  (
    "focus",
    &[
      "focus", "study", "concentrat", "instrumental", "lofi", "lo-fi", "chillhop", "jazzhop", "classical", "piano",
      "post-rock", "post rock", "minimal", "soundtrack", "score", "beats to", "coding", "фокус", "концентрац", "учёб",
      "учеб",
    ],
  ),
];

/// Режим — настроение (есть словарь в `MOODS`); `own` и всё незнакомое — нет.
pub fn is_mood(mode: &str) -> bool {
  MOODS.iter().any(|(m, _)| *m == mode)
}

/// «Функциональные» настроения — Сон и Концентрация: музыка под дело, а не под вкус. Подбор строже
/// (только подходящие словарю, если их хватает), вкус к артисту весит меньше.
fn is_functional(mode: &str) -> bool {
  matches!(mode, "sleep" | "focus")
}

/// Популярность трека по числу прослушиваний: 1 тыс. и меньше — 0, 10 млн и больше — 1 (логарифм).
/// Число неизвестно (у Яндекса его нет) — 0, а не «непопулярен».
pub fn popularity(t: &Track) -> f64 {
  t.plays.map_or(0.0, |p| (((p as f64) + 1.0).log10() - 3.0) / 4.0).clamp(0.0, 1.0)
}

/// Насколько трек подходит настроению: совпал по жанру/тегам/названию — плюс, похож на другое
/// настроение — минус, ничего не известно — ноль.
pub fn mood_fit(mood: &str, t: &Track) -> f64 {
  let text = format!("{} {}", t.tags.as_deref().unwrap_or("").to_lowercase(), t.title.to_lowercase());
  let hits = |words: &[&str]| words.iter().filter(|w| text.contains(**w)).count();
  let mut own = 0;
  let mut other = 0;
  for (m, words) in MOODS {
    let n = hits(words);
    if m == mood {
      own = n;
    } else {
      other = other.max(n);
    }
  }
  if own > 0 {
    1.6 + 0.3 * (own.min(3) as f64 - 1.0) - if other > own { 0.4 } else { 0.0 }
  } else if other > 0 {
    -0.8
  } else {
    0.0
  }
}

/// Склейка написаний одного тега: слева как пишут (слова через пробел, нижний регистр), справа — тег.
const TAG_ALIASES: &[(&str, &str)] = &[
  ("hip-hop", "hiphop"),
  ("hip hop", "hiphop"),
  ("lo-fi", "lofi"),
  ("lo fi", "lofi"),
  ("r&b", "rnb"),
  ("r & b", "rnb"),
  ("drum & bass", "dnb"),
  ("drum and bass", "dnb"),
  ("drum n bass", "dnb"),
  ("drumandbass", "dnb"),
  ("k-pop", "kpop"),
  ("k pop", "kpop"),
  ("cloud rap", "cloudrap"),
  ("hyper pop", "hyperpop"),
  ("hyper-pop", "hyperpop"),
];

/// Слова-пустышки: по ним ничего не понять ни о звуке, ни о сцене.
const JUNK_TAGS: &[&str] =
  &["music", "new", "free", "download", "soundcloud", "official", "audio", "song", "track", "beat", "beats", "prod", "remix"];

/// Больше тегов с одного трека не берём — дальше обычно спам ключевыми словами.
const MAX_TAGS: usize = 8;

fn is_year(t: &str) -> bool {
  t.len() == 4 && t.parse::<u16>().is_ok_and(|y| (1960..=2039).contains(&y))
}

/// Теги трека из строки «жанр + теги SoundCloud / жанр Яндекса» (docs/WAVE.md 2.4, нижний регистр).
/// - фраза в кавычках — один тег (`"drift phonk"`, `"lil peep"`), остальное режется по пробелам, запятым и «/»;
/// - разные написания склеиваются (`hip-hop` / `hip hop` / `hiphop`, `lo-fi` / `lofi`, `drum & bass` / `dnb`…);
/// - **годы остаются** (`2016` — метка эпохи и сцены), остальные числа, слова короче трёх знаков и
///   пустышки (`music`, `free`, `beat`…) выбрасываются;
/// - имя собственного артиста трека (`own_artists`) выбрасывается, а на чужом треке — остаётся:
///   тег `lil peep` у другого исполнителя говорит о сцене;
/// - не больше восьми тегов, порядок как в строке, повторы убираются.
pub fn parse_tags(tags: &str, own_artists: &[String]) -> Vec<String> {
  // 1. куски: (текст, был ли в кавычках)
  let mut parts: Vec<(String, bool)> = Vec::new();
  let mut cur = String::new();
  let mut quoted = false;
  let flush = |cur: &mut String, quoted: bool, parts: &mut Vec<(String, bool)>| {
    let text = cur.split_whitespace().collect::<Vec<_>>().join(" ");
    if !text.is_empty() {
      parts.push((text, quoted));
    }
    cur.clear();
  };
  for ch in tags.to_lowercase().chars() {
    match ch {
      '"' => {
        flush(&mut cur, quoted, &mut parts);
        quoted = !quoted;
      }
      ',' | ';' | '/' if !quoted => flush(&mut cur, false, &mut parts),
      c if c.is_whitespace() && !quoted => flush(&mut cur, false, &mut parts),
      c => cur.push(c),
    }
  }
  flush(&mut cur, quoted, &mut parts);

  // 2. склейка написаний: фраза в кавычках — целиком, слова без кавычек — до трёх подряд
  let alias = |key: &str| TAG_ALIASES.iter().find(|(k, _)| *k == key).map(|(_, v)| (*v).to_owned());
  let mut raw: Vec<String> = Vec::new();
  let mut i = 0;
  while i < parts.len() {
    let (text, q) = &parts[i];
    if *q {
      raw.push(alias(text).unwrap_or_else(|| text.clone()));
      i += 1;
      continue;
    }
    let mut taken = 1;
    let mut tag = text.clone();
    for len in (2..=3).rev() {
      if i + len <= parts.len() && parts[i..i + len].iter().all(|(_, q)| !q) {
        let key = parts[i..i + len].iter().map(|(t, _)| t.as_str()).collect::<Vec<_>>().join(" ");
        if let Some(a) = alias(&key) {
          tag = a;
          taken = len;
          break;
        }
      }
    }
    if taken == 1 {
      tag = alias(&tag).unwrap_or(tag);
    }
    raw.push(tag);
    i += taken;
  }

  // 3. чистка
  let mut out: Vec<String> = Vec::new();
  for tag in raw {
    let tag = tag.trim_matches(|c: char| matches!(c, '#' | '.' | ',' | '!' | '?' | ':' | ';' | '\'' | '-' | ' ')).to_owned();
    let digits = !tag.is_empty() && tag.chars().all(|c| c.is_ascii_digit());
    let drop = tag.chars().count() < 3
      || !tag.chars().any(char::is_alphanumeric)
      || (digits && !is_year(&tag))
      || JUNK_TAGS.contains(&tag.as_str())
      || own_artists.iter().any(|a| *a == tag);
    if !drop && !out.contains(&tag) {
      out.push(tag);
      if out.len() == MAX_TAGS {
        break;
      }
    }
  }
  out
}

/// Теги трека (`parse_tags`): свои артисты из тегов выбрасываются.
pub fn tag_set(t: &Track) -> Vec<String> {
  parse_tags(t.tags.as_deref().unwrap_or(""), &artist_keys(t))
}

/// Откуда кандидат: сколько сидов его предложили («голоса» — совпадение графов похожих, главный
/// сигнал радио по похожим) и насколько высоко он стоял в их списках.
#[derive(Default)]
pub struct Origin {
  pub votes: HashMap<String, u32>,
  /// Лучшее место в списке похожих, 1.0 — первый, 0.0 — последний.
  pub rank: HashMap<String, f64>,
  /// Предложен треком, который зашёл в этой сессии.
  pub from_session: HashSet<String>,
  /// Сид, в чьём списке трек стоял выше всего, — «от кого пришёл» (для `wave_events` и лимита
  /// «не больше 4 треков порции от одного сида»).
  pub seed_of: HashMap<String, String>,
  /// Пришли только вторым шагом — от похожих на похожие (разведка, docs/WAVE.md 4.2).
  pub hop2: HashSet<String>,
  /// Популярные треки любимых / слушаемых артистов (у волны по треку — артиста трека): знакомое
  /// в котле, чтобы волна не состояла из одних чужих «похожих».
  pub artist_top: HashSet<String>,
}

impl Origin {
  /// Учесть список похожих от одного сида (`seed` — его ref).
  pub fn add(&mut self, seed: &str, list: &[Track], session: bool) {
    self.add_scaled(seed, list, session, 1.0);
  }

  /// Популярные треки артиста (`seed` — ref артиста): место в списке весит `× 0.5`, голосом не
  /// считаются (это не «похожие»). Треки, которых в похожих не было, помечаются как `artist`.
  pub fn add_artist(&mut self, artist: &str, list: &[Track]) {
    let len = list.len().max(1) as f64;
    for (i, t) in list.iter().enumerate() {
      if !self.votes.contains_key(&t.ref_) {
        self.artist_top.insert(t.ref_.clone());
        self.votes.insert(t.ref_.clone(), 1);
        self.rank.insert(t.ref_.clone(), 0.5 * (1.0 - i as f64 / len));
        self.seed_of.insert(t.ref_.clone(), artist.to_owned());
      }
    }
  }

  /// Второй шаг разведки: список похожих от кандидата первого круга, место в нём весит `× 0.6`.
  /// Треки, которых в первом круге не было, помечаются как `hop2`.
  pub fn add_hop(&mut self, seed: &str, list: &[Track]) {
    for t in list {
      if !self.votes.contains_key(&t.ref_) {
        self.hop2.insert(t.ref_.clone());
      }
    }
    self.add_scaled(seed, list, false, 0.6);
  }

  fn add_scaled(&mut self, seed: &str, list: &[Track], session: bool, scale: f64) {
    let len = list.len().max(1) as f64;
    let mut seen = HashSet::new();
    for (i, t) in list.iter().enumerate() {
      if !seen.insert(&t.ref_) {
        continue;
      }
      *self.votes.entry(t.ref_.clone()).or_insert(0) += 1;
      let r = scale * (1.0 - i as f64 / len);
      if self.rank.get(&t.ref_).is_none_or(|best| r > *best) {
        self.rank.insert(t.ref_.clone(), r);
        self.seed_of.insert(t.ref_.clone(), seed.to_owned());
      }
      if session {
        self.from_session.insert(t.ref_.clone());
      }
    }
  }
}

/// Что волна узнала за эту сессию (держит интерфейс, ядро без состояния).
#[derive(Default)]
pub struct Session {
  /// Пропущенные хотя бы раз артисты — мягкий минус.
  pub skipped_artists: HashSet<String>,
  /// Сколько раз артист уже звучал в сессии.
  pub served: HashMap<String, usize>,
  /// Последние выданные артисты (новые в конце) — не ставить их в начало новой порции.
  pub recent_artists: Vec<String>,
  /// Теги сессии с весом: треков, что зашли (дослушаны / лайкнуты), — плюс; пропущенных — минус.
  pub tags: HashMap<String, f64>,
}

/// Артист не чаще стольких раз за сессию.
const SESSION_ARTIST_CAP: usize = 4;

/// Выборка из Beta(a, b) для целых a, b ≥ 1: a-я порядковая статистика из a+b−1 равномерных.
/// Счётчики больше 40 масштабируются (форма та же, разброс чуть шире) — дёшево и без крейтов.
pub fn beta(a: u32, b: u32, rng: &mut Rng) -> f64 {
  let (mut a, mut b) = (a.max(1) as f64, b.max(1) as f64);
  let s = a + b;
  if s > 40.0 {
    a = (a * 40.0 / s).round().max(1.0);
    b = (b * 40.0 / s).round().max(1.0);
  }
  let n = (a + b - 1.0) as usize;
  let mut u: Vec<f64> = (0..n).map(|_| rng.unit()).collect();
  u.sort_by(|x, y| x.partial_cmp(y).unwrap_or(std::cmp::Ordering::Equal));
  u[a as usize - 1]
}

/// Признаки кандидата на момент выдачи (docs/WAVE.md, этап 3). Оценка = Σ признак × вес режима +
/// шум; признаки пишутся в `wave_events.features_json` — по ним потом можно подбирать веса по цифрам.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Features {
  /// Вкус к артисту — выборка Томпсона, −1 … 1.
  pub affinity: f64,
  /// Артист среди лайкнутых, 0 / 1.
  pub liked_artist: f64,
  /// Артист лайкнутый или слушанный, 0 / 1.
  pub known: f64,
  /// Артист совсем новый (1 − `known`), 0 / 1.
  pub fresh: f64,
  /// `min(голоса − 1, 3)`: сколько сидов предложили трек.
  pub votes: f64,
  /// Место в списке похожих, 0 … 1.
  pub rank: f64,
  /// Предложен треком, который зашёл в этой сессии, 0 / 1.
  pub from_session: f64,
  /// Артист пропущен в этой сессии, 0 / 1.
  pub session_skipped: f64,
  /// Теги как у зашедших (плюс) и как у пропущенных (минус) в этой сессии, −0.9 … 0.9.
  pub session_tags: f64,
  /// Долгий профиль тегов: чем кончались треки с такими тегами за всё время (лайки, прослушивания,
  /// пропуски, 👎), −1 … 1; нет известных тегов — 0.
  pub profile_fit: f64,
  /// Профиль тегов **этого режима**: чем кончались треки с такими тегами именно в «Грустной» /
  /// «Жёсткой» / … волне (`wave_events`), −1 … 1. Учит режим тому, что в нём заходит тебе.
  pub mode_profile: f64,
  /// Штраф самому треку за пропуски (`min(Σ вес · |оценка|, 2)`, затухание 30 дней): пропущенный
  /// трек не возвращается через неделю как ни в чём не бывало.
  pub track_skips: f64,
  /// Трек с платформы, которую выбрал пользователь, 0 / 1.
  pub platform: f64,
  /// Доля прослушиваний артиста в это время суток, 0 … 1.
  pub hour: f64,
  /// `mood_fit` режима, −0.8 … 2.2.
  pub mood: f64,
  /// Доля пропусков артиста.
  pub skip_rate: f64,
  /// `popularity` трека, 0 … 1 (весит только в «Популярном»).
  pub popularity: f64,
  /// Сосед твоих любимых по карте исполнителей (фиты, подписки, общие соавторы), 0 … 1 —
  /// лучший из артистов трека (`artist_graph::scene_for`); карты нет — 0.
  pub scene: f64,
  /// «Больше» (+1) / «Меньше» (−1) этого артиста на экране вкуса; лучший из соавторов, 0 — не задано.
  pub pref: f64,
}

/// Веса признаков режима. Стартовые значения — ровно те числа, что были в `score` до разбиения на
/// признаки, поведение волны не менялось (тест `score_matches_legacy_formula`).
#[derive(Debug, Clone, Copy, Default)]
pub struct Weights {
  pub affinity: f64,
  pub liked_artist: f64,
  pub known: f64,
  pub fresh: f64,
  pub votes: f64,
  pub rank: f64,
  pub from_session: f64,
  pub session_skipped: f64,
  pub session_tags: f64,
  pub profile_fit: f64,
  pub mode_profile: f64,
  pub track_skips: f64,
  pub platform: f64,
  pub hour: f64,
  pub mood: f64,
  pub skip_rate: f64,
  pub popularity: f64,
  pub scene: f64,
  pub pref: f64,
}

impl Weights {
  pub fn dot(&self, f: &Features) -> f64 {
    self.affinity * f.affinity
      + self.liked_artist * f.liked_artist
      + self.known * f.known
      + self.fresh * f.fresh
      + self.votes * f.votes
      + self.rank * f.rank
      + self.from_session * f.from_session
      + self.session_skipped * f.session_skipped
      + self.session_tags * f.session_tags
      + self.profile_fit * f.profile_fit
      + self.mode_profile * f.mode_profile
      + self.track_skips * f.track_skips
      + self.platform * f.platform
      + self.hour * f.hour
      + self.mood * f.mood
      + self.skip_rate * f.skip_rate
      + self.popularity * f.popularity
      + self.scene * f.scene
      + self.pref * f.pref
  }
}

/// Вес «Больше» / «Меньше» по артисту (признак ±1): как лайкнутый артист в «Обычном».
pub const PREF_WEIGHT: f64 = 2.0;

/// Вес соседства по карте исполнителей: заметно меньше лайка, чтобы не вытеснять вкус.
pub const SCENE_WEIGHT: f64 = 0.4;

/// Веса режима: настроения — `mood_fit` плюс вкус (Ночное — сильнее время суток, Сон и Концентрация —
/// словарь важнее вкуса, Популярное — число прослушиваний), остальное («Обычное») — лайки, вкус и время
/// суток. Общее для всех — «похожесть» и то, что зашло или не зашло в сессии.
pub fn weights(mode: &str) -> Weights {
  let common = Weights {
    votes: 0.6,
    rank: 0.5,
    from_session: 0.7,
    session_skipped: -0.9,
    session_tags: 1.0,
    track_skips: -1.2,
    // соседи по карте исполнителей — небольшой плюс во всех режимах: «свои» по сцене, а не случайные похожие
    scene: SCENE_WEIGHT,
    // «Больше» / «Меньше» — сильнее любого вкусового признака: слово владельца важнее статистики
    pref: PREF_WEIGHT,
    ..Default::default()
  };
  match mode {
    "popular" => Weights {
      mood: 0.8,
      popularity: 2.2,
      liked_artist: 0.8,
      known: 0.3,
      affinity: 0.4,
      platform: 0.3,
      hour: 0.2,
      profile_fit: 0.8,
      mode_profile: 1.2,
      ..common
    },
    m if is_functional(m) => Weights {
      mood: 2.2,
      liked_artist: 0.5,
      known: 0.2,
      affinity: 0.3,
      platform: 0.3,
      hour: 0.2,
      profile_fit: 0.5,
      mode_profile: 1.5,
      ..common
    },
    "night" => Weights {
      mood: 1.5,
      liked_artist: 1.0,
      known: 0.4,
      affinity: 0.6,
      platform: 0.3,
      hour: 1.2,
      profile_fit: 0.8,
      mode_profile: 1.5,
      ..common
    },
    // настроение: словарь `mood_fit` — подсказка на старте, профиль режима — то, чему он научился у тебя
    m if is_mood(m) => Weights {
      mood: 1.5,
      liked_artist: 1.0,
      // знакомый артист — плюс: волна должна звучать твоей, а не чужими «похожими»
      known: 0.4,
      affinity: 0.6,
      platform: 0.3,
      hour: 0.4,
      profile_fit: 0.8,
      mode_profile: 1.5,
      ..common
    },
    _ => Weights { liked_artist: 2.0, known: 0.8, affinity: 1.0, platform: 0.6, hour: 1.2, profile_fit: 1.2, ..common },
  }
}

/// Признаки кандидата. Вкус к артисту — выборка Томпсона из Beta(1+дослушано, 1+пропущено): у
/// знакомых и любимых она стабильно высокая, у малознакомых — разбросана, поэтому волна иногда
/// пробует новых, а не крутит одних и тех же. Плюс: лайкнутый артист, голоса и место в похожих,
/// «зашло в сессии», теги как у зашедших, своя платформа, время суток, настроение режима.
fn features(t: &Track, taste: &Taste, origin: &Origin, session: &Session, prefer: Option<&str>, mode: &str, rng: &mut Rng) -> Features {
  let keys = artist_keys(t);
  let a = keys[0].clone();
  // вкус — по лучшему из артистов трека (совместный трек любимого артиста — тоже «свой»)
  // «за» и «против» артиста — суммы с затуханием (store `taste`, docs/WAVE.md 2.2)
  let (plays, skips) = keys
    .iter()
    .map(|k| (taste.plays.get(k).copied().unwrap_or(0.0), taste.skips.get(k).copied().unwrap_or(0.0)))
    .max_by(|x, y| {
      let m = |(p, s): &(f64, f64)| (1.0 + p) / (2.0 + p + s);
      m(x).partial_cmp(&m(y)).unwrap_or(std::cmp::Ordering::Equal).then(x.0.partial_cmp(&y.0).unwrap_or(std::cmp::Ordering::Equal))
    })
    .unwrap_or((0.0, 0.0));
  let affinity = 2.0 * beta(1 + plays.round() as u32, 1 + skips.round() as u32, rng) - 1.0;
  let liked = keys.iter().any(|k| taste.liked_artists.contains(k));
  let known = liked || plays > 0.0;
  let platform = matches!(prefer, Some(p) if is_track_of(&t.ref_, p));
  let tags = tag_set(t);
  let session_tags = if session.tags.is_empty() {
    0.0
  } else {
    let fit: f64 = tags.iter().filter_map(|w| session.tags.get(w)).sum();
    (0.3 * fit).clamp(-0.9, 0.9)
  };
  Features {
    affinity,
    liked_artist: liked as u8 as f64,
    known: known as u8 as f64,
    fresh: !known as u8 as f64,
    votes: (*origin.votes.get(&t.ref_).unwrap_or(&1) as f64 - 1.0).min(3.0),
    rank: origin.rank.get(&t.ref_).copied().unwrap_or(0.0),
    from_session: origin.from_session.contains(&t.ref_) as u8 as f64,
    session_skipped: session.skipped_artists.contains(&a) as u8 as f64,
    session_tags,
    profile_fit: tags_fit(&taste.tag_profile, &tags),
    mode_profile: tags_fit(&taste.mode_tag_profile, &tags),
    track_skips: taste.track_skips.get(&t.ref_).copied().unwrap_or(0.0).min(2.0),
    platform: platform as u8 as f64,
    hour: keys.iter().filter_map(|k| taste.hour_share.get(k).copied()).fold(0.0, f64::max),
    mood: if is_mood(mode) { mood_fit(mode, t) } else { 0.0 },
    skip_rate: skips / (plays + skips + 1.0),
    popularity: popularity(t),
    scene: scene_fit(&taste.scene, &keys),
    pref: pref_of(&taste.artist_pref, &keys),
  }
}

/// «Больше» любого из артистов трека перебивает «Меньше» (соавторство с любимым не наказываем).
fn pref_of(pref: &HashMap<String, f64>, keys: &[String]) -> f64 {
  let all: Vec<f64> = keys.iter().filter_map(|k| pref.get(k).copied()).collect();
  if all.iter().any(|&v| v > 0.0) {
    1.0
  } else if all.iter().any(|&v| v < 0.0) {
    -1.0
  } else {
    0.0
  }
}

/// Близость трека к твоей сцене: лучший из его артистов по карте (ключи карты — `parse::key`).
fn scene_fit(scene: &HashMap<String, f64>, keys: &[String]) -> f64 {
  if scene.is_empty() {
    return 0.0;
  }
  keys.iter().filter_map(|k| scene.get(&crate::artist_graph::parse::key(k)).copied()).fold(0.0, f64::max).clamp(0.0, 1.0)
}

/// Насколько теги трека нравятся по профилю (`tag → оценка −1…1`): среднее по известным тегам × 2,
/// обрезанное до −1…1. Ни один тег не известен — 0 (профиль ничего не знает, а не «не нравится»).
pub fn tags_fit(profile: &HashMap<String, f64>, tags: &[String]) -> f64 {
  let known: Vec<f64> = tags.iter().filter_map(|t| profile.get(t).copied()).collect();
  if known.is_empty() {
    return 0.0;
  }
  (2.0 * known.iter().sum::<f64>() / known.len() as f64).clamp(-1.0, 1.0)
}

/// Кандидат с признаками, с которыми он выбран.
pub struct Picked {
  pub track: Track,
  pub features: Features,
  /// Откуда кандидат (`wave_events.source`): `similar`, `hop2` (разведка) или `liked` (свой лайк).
  pub source: &'static str,
}

/// Не больше стольких треков порции от одного сида — чтобы порция не была «вся про один трек».
const SEED_CAP: usize = 4;

/// Порция из `n` треков: без дублей и фильтрованных, не два одинаковых артиста подряд (и не те,
/// что звучали только что), не больше двух треков артиста в порции и четырёх за сессию.
/// В режиме настроения, если подходящих хватает, неподходящие отбрасываются совсем.
/// `relaxed` — разрешить недавно слушанное (когда кандидатов мало).
/// Без признаков — для тестов; приложение зовёт [`pick_with`].
#[cfg(test)]
#[allow(clippy::too_many_arguments)]
pub fn pick(
  cands: Vec<Track>,
  taste: &Taste,
  origin: &Origin,
  session: &Session,
  filter: &Filter,
  prefer: Option<&str>,
  mode: &str,
  n: usize,
  relaxed: bool,
  rng: &mut Rng,
) -> Vec<Track> {
  pick_with(cands, taste, origin, session, filter, prefer, mode, n, relaxed, rng).into_iter().map(|p| p.track).collect()
}

/// То же, что [`pick`], но с признаками каждого выбранного трека (для `wave_events`).
#[allow(clippy::too_many_arguments)]
pub fn pick_with(
  cands: Vec<Track>,
  taste: &Taste,
  origin: &Origin,
  session: &Session,
  filter: &Filter,
  prefer: Option<&str>,
  mode: &str,
  n: usize,
  relaxed: bool,
  rng: &mut Rng,
) -> Vec<Picked> {
  let mut seen = HashSet::new();
  let mut pool: Vec<Track> = cands
    .into_iter()
    .filter(|t| t.available && seen.insert(t.ref_.clone()))
    .filter(|t| !filter.banned.contains(&t.ref_) && !filter.exclude.contains(&t.ref_))
    .filter(|t| relaxed || !filter.recent.contains(&t.ref_))
    .filter(|t| !filter.paused_artists.contains(&artist_key(t)))
    .filter(|t| !filter.is_never(t))
    .filter(|t| session.served.get(&artist_key(t)).copied().unwrap_or(0) < SESSION_ARTIST_CAP)
    // случайные заливы незнакомых авторов SoundCloud (мало прослушиваний) — мимо
    .filter(|t| filter.min_plays_unknown == 0 || is_known(t, taste) || t.plays.is_none_or(|p| p >= filter.min_plays_unknown))
    .collect();
  if is_mood(mode) {
    let fits = pool.iter().filter(|t| mood_fit(mode, t) > 0.0).count();
    // Сон и Концентрация строже: хватает подходящих словарю на порцию с запасом — только они
    if is_functional(mode) && fits >= n * 2 {
      pool.retain(|t| mood_fit(mode, t) > 0.0);
    } else if fits >= n * 3 {
      pool.retain(|t| mood_fit(mode, t) >= 0.0);
    }
  }
  let w = weights(mode);
  let mut scored: Vec<(f64, Picked)> = pool
    .into_iter()
    .map(|track| {
      let features = features(&track, taste, origin, session, prefer, mode, rng);
      let source = if origin.hop2.contains(&track.ref_) {
        "hop2"
      } else if origin.artist_top.contains(&track.ref_) {
        "artist"
      } else {
        "similar"
      };
      (w.dot(&features) + rng.unit() * 0.3, Picked { track, features, source })
    })
    .collect();
  scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));

  let mut out: Vec<Picked> = Vec::with_capacity(n);
  let mut per_artist: HashMap<String, usize> = HashMap::new();
  let mut per_seed: HashMap<String, usize> = HashMap::new();
  let seed_of = |p: &Picked| origin.seed_of.get(&p.track.ref_).cloned();
  let max_unknown = filter.max_unknown.unwrap_or(usize::MAX);
  let mut unknown = 0usize;
  // только что звучавшие артисты (хвост прошлой порции) — не первым треком новой
  let tail: Vec<&String> = session.recent_artists.iter().rev().take(3).collect();
  // Кто сейчас не подходит (тот же артист, что предыдущий), ждёт следующего шанса — не теряется.
  let mut pending: Vec<Picked> = Vec::new();
  // Первый проход — с лимитом на сид; не хватило (один-два сида, волна по треку) — второй проход
  // добирает порцию из отложенных уже без него.
  let mut queue: Vec<Picked> = scored.into_iter().map(|x| x.1).collect();
  for seed_cap in [true, false] {
    for p in std::mem::take(&mut queue) {
      pending.push(p);
      loop {
        let ok = |p: &Picked| {
          let a = artist_key(&p.track);
          let just_played = out.is_empty() && tail.iter().any(|x| **x == a);
          !just_played
            && (unknown < max_unknown || p.features.known > 0.0)
            && !out.last().is_some_and(|l| artist_key(&l.track) == a)
            && per_artist.get(&a).copied().unwrap_or(0) < 2
            && per_artist.get(&a).copied().unwrap_or(0) + session.served.get(&a).copied().unwrap_or(0) < SESSION_ARTIST_CAP
            && (!seed_cap || seed_of(p).is_none_or(|s| per_seed.get(&s).copied().unwrap_or(0) < SEED_CAP))
        };
        let Some(i) = pending.iter().position(ok) else { break };
        let p = pending.remove(i);
        if p.features.known == 0.0 {
          unknown += 1;
        }
        *per_artist.entry(artist_key(&p.track)).or_insert(0) += 1;
        if let Some(s) = seed_of(&p) {
          *per_seed.entry(s).or_insert(0) += 1;
        }
        out.push(p);
        if out.len() == n {
          return out;
        }
      }
    }
    queue = std::mem::take(&mut pending);
  }
  out
}

/// Сколько своих лайков в порции из 10 (docs/WAVE.md 4.1): «Обычное» — 3, настроение — до 2,
/// волна по треку — 0.
pub fn liked_share(mode: &str, by_seed: bool) -> usize {
  if by_seed {
    return 0;
  }
  match mode {
    "own" => 3,
    m if is_mood(m) => 2,
    _ => 0,
  }
}

/// «Забытые любимые»: из своих лайков, что давно не играли, — до `k` лучших по вкусу к артисту,
/// профилю тегов, тегам сессии и времени суток. В настроении — только подходящие ему (`mood_fit > 0`).
/// Фильтры те же, что у новых; артисты не повторяются.
#[allow(clippy::too_many_arguments)]
pub fn pick_liked(cands: Vec<Track>, taste: &Taste, session: &Session, filter: &Filter, mode: &str, k: usize, rng: &mut Rng) -> Vec<Picked> {
  if k == 0 {
    return Vec::new();
  }
  let origin = Origin::default();
  let mood = is_mood(mode);
  let mut scored: Vec<(f64, Picked)> = cands
    .into_iter()
    .filter(|t| t.available && !filter.banned.contains(&t.ref_) && !filter.exclude.contains(&t.ref_))
    .filter(|t| !filter.paused_artists.contains(&artist_key(t)))
    .filter(|t| !filter.is_never(t))
    .filter(|t| session.served.get(&artist_key(t)).copied().unwrap_or(0) < SESSION_ARTIST_CAP)
    .filter(|t| !mood || mood_fit(mode, t) > 0.0)
    .map(|track| {
      let f = features(&track, taste, &origin, session, None, mode, rng);
      let score = f.affinity + f.profile_fit + f.session_tags + f.hour - 0.6 * f.track_skips + rng.unit() * 0.3;
      (score, Picked { track, features: f, source: "liked" })
    })
    .collect();
  scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
  let mut artists = HashSet::new();
  scored.into_iter().map(|x| x.1).filter(|p| artists.insert(artist_key(&p.track))).take(k).collect()
}

/// Вставить свои лайки в порцию новых на места 2, 5, 8 (с нуля): первым всегда идёт новый трек.
/// Место, где рядом тот же артист, сдвигается дальше; не нашлось — трек не ставится. Порция
/// обрезается до `n` — недостающие свои добираются новыми.
pub fn insert_liked(mut out: Vec<Picked>, liked: Vec<Picked>, n: usize) -> Vec<Picked> {
  let taken: HashSet<String> = out.iter().map(|p| p.track.ref_.clone()).collect();
  for (slot, p) in [2usize, 5, 8].into_iter().zip(liked.into_iter().filter(|p| !taken.contains(&p.track.ref_))) {
    let a = artist_key(&p.track);
    let fits = |out: &Vec<Picked>, i: usize| {
      i <= out.len()
        && !out.get(i.wrapping_sub(1)).is_some_and(|x| artist_key(&x.track) == a)
        && !out.get(i).is_some_and(|x| artist_key(&x.track) == a)
        && out.iter().filter(|x| artist_key(&x.track) == a).count() < 2
    };
    if let Some(i) = (slot.min(out.len())..=out.len()).find(|&i| i > 0 && fits(&out, i)) {
      out.insert(i, p);
    }
  }
  out.truncate(n);
  out
}

/// «Почему этот трек» — строка под названием в плеере для треков волны: откуда трек пришёл в
/// порцию. `kind`: `liked` (свой забытый лайк), `artist` (популярное у любимого артиста), `explore`
/// (разведка — похожие на похожие), `session` (похож на то, что зашло сейчас), `seed` (волна по
/// треку), `similar` (похож на твой лайк / дослушанный). Второе — ref сида, от которого пришёл.
pub fn why(p: &Picked, origin: &Origin, by_seed: Option<&str>) -> (&'static str, Option<String>) {
  let seed = origin.seed_of.get(&p.track.ref_).cloned();
  match p.source {
    "liked" => ("liked", None),
    "artist" => ("artist", seed),
    "hop2" => ("explore", None),
    _ if seed.is_some() && seed.as_deref() == by_seed => ("seed", seed),
    _ if origin.from_session.contains(&p.track.ref_) => ("session", seed),
    _ => ("similar", seed),
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn t(r: &str, artist: &str) -> Track {
    Track {
      ref_: r.into(),
      title: r.into(),
      artist: artist.into(),
      artists: vec![],
      album: None,
      duration_ms: 180_000,
      cover_url: None,
      url: None,
      explicit: false,
      available: true,
      plays: None,
      tags: None,
    }
  }

  #[test]
  fn mood_by_tags_and_title() {
    let mut a = t("sc:1", "A");
    a.tags = Some("phonk drift".into());
    let mut b = t("sc:2", "B");
    b.title = "sad song (slowed)".into();
    assert!(mood_fit("hard", &a) > 1.0);
    assert!(mood_fit("sad", &a) < 0.0);
    assert!(mood_fit("sad", &b) > 1.0);
    assert_eq!(mood_fit("calm", &t("sc:3", "C")), 0.0);
  }

  #[test]
  fn filters_and_diversity() {
    let cands = vec![
      t("sc:1", "A"),
      t("sc:2", "A"),
      t("sc:3", "A"),
      t("sc:4", "B"),
      t("sc:5", "C"),
      t("sc:6", "D"),
      t("sc:1", "A"),
      t("sc:7", "Banned"),
      t("sc:8", "Paused"),
    ];
    let mut f = Filter::default();
    f.banned.insert("sc:7".into());
    f.paused_artists.insert("paused".into());
    f.recent.insert("sc:6".into());
    let taste = Taste::default();
    let out = pick(cands, &taste, &Origin::default(), &Session::default(), &f, None, "own", 10, false, &mut Rng::new(42));
    let refs: Vec<&str> = out.iter().map(|x| x.ref_.as_str()).collect();
    assert!(!refs.contains(&"sc:7") && !refs.contains(&"sc:8") && !refs.contains(&"sc:6"));
    let a_count = refs.iter().filter(|r| ["sc:1", "sc:2", "sc:3"].contains(r)).count();
    assert!((1..=2).contains(&a_count), "не больше 2 треков артиста");
    for w in out.windows(2) {
      assert_ne!(artist_key(&w[0]), artist_key(&w[1]), "один артист два раза подряд");
    }
    let uniq: HashSet<_> = refs.iter().collect();
    assert_eq!(uniq.len(), refs.len());
  }

  #[test]
  fn liked_artist_first_and_relaxed() {
    let mut taste = Taste::default();
    taste.liked_artists.insert("fav".into());
    let mut f = Filter::default();
    f.recent.insert("sc:2".into());
    let out = pick(vec![t("sc:1", "x"), t("sc:2", "Fav")], &taste, &Origin::default(), &Session::default(), &f, None, "own", 1, true, &mut Rng::new(7));
    assert_eq!(out[0].ref_, "sc:2");
    let out = pick(vec![t("sc:1", "x"), t("sc:2", "Fav")], &taste, &Origin::default(), &Session::default(), &f, None, "own", 2, false, &mut Rng::new(7));
    assert_eq!(out.len(), 1);
  }

  #[test]
  fn artist_prefs_parse_levels_and_ignore_junk() {
    let v = serde_json::json!({
      "Markul": { "name": "Markul", "level": "more" },
      " oxxxymiron ": { "name": "Oxxxymiron", "level": "less" },
      "x": { "name": "X", "level": "never" },
      "bad": { "name": "Bad", "level": "lots" },
      "broken": 5
    });
    let (pref, never) = artist_prefs(Some(&v));
    assert_eq!(pref.get("markul"), Some(&1.0));
    assert_eq!(pref.get("oxxxymiron"), Some(&-1.0));
    assert_eq!(pref.len(), 2);
    assert_eq!(never.iter().collect::<Vec<_>>(), vec!["x"]);
    let (p, n) = artist_prefs(None);
    assert!(p.is_empty() && n.is_empty());
  }

  #[test]
  fn never_artist_is_never_picked_even_as_co_author() {
    let taste = Taste::default();
    let mut f = Filter::default();
    f.never_artists.insert("bad".into());
    let mut co = t("sc:2", "good");
    let a = |n: &str| crate::providers::ArtistRef { ref_: format!("sc:a:{n}"), name: n.into(), avatar_url: None };
    co.artists = vec![a("Good"), a("Bad")];
    let out = pick(vec![t("sc:1", "Bad"), co, t("sc:3", "ok")], &taste, &Origin::default(), &Session::default(), &f, None, "own", 3, true, &mut Rng::new(5));
    assert_eq!(out.iter().map(|p| p.ref_.as_str()).collect::<Vec<_>>(), vec!["sc:3"]);
    let liked = pick_liked(vec![t("sc:1", "Bad"), t("sc:3", "ok")], &taste, &Session::default(), &f, "own", 3, &mut Rng::new(5));
    assert_eq!(liked.len(), 1);
  }

  #[test]
  fn all_never_pool_gives_empty_portion_not_a_hang() {
    // «Никогда» не ослабляется даже в ослабленном проходе: пул из одних таких — пустая порция
    let mut f = Filter::default();
    f.never_artists.insert("bad".into());
    let pool = || vec![t("sc:1", "Bad"), t("sc:2", " BAD ")];
    for relaxed in [false, true] {
      assert!(pick(pool(), &Taste::default(), &Origin::default(), &Session::default(), &f, None, "own", 5, relaxed, &mut Rng::new(3)).is_empty());
    }
    assert!(pick_liked(pool(), &Taste::default(), &Session::default(), &f, "own", 5, &mut Rng::new(3)).is_empty());
  }

  #[test]
  fn more_and_less_move_the_score() {
    let mut taste = Taste::default();
    taste.artist_pref.insert("loved".into(), 1.0);
    taste.artist_pref.insert("tired".into(), -1.0);
    let w = weights("own");
    let mut rng = Rng::new(1);
    let score = |name: &str, taste: &Taste, rng: &mut Rng| w.dot(&features(&t("sc:1", name), taste, &Origin::default(), &Session::default(), None, "own", rng));
    // шум Томпсона у всех троих один и тот же вид, поэтому берём среднее по многим выборкам
    let mean = |name: &str, taste: &Taste, rng: &mut Rng| (0..400).map(|_| score(name, taste, rng)).sum::<f64>() / 400.0;
    let (more, none, less) = (mean("loved", &taste, &mut rng), mean("other", &taste, &mut rng), mean("tired", &taste, &mut rng));
    assert!(more > none + 1.5, "{more} vs {none}");
    assert!(less < none - 1.5, "{less} vs {none}");
  }

  #[test]
  fn votes_and_session_lift() {
    let taste = Taste::default();
    let f = Filter::default();
    let mut origin = Origin::default();
    // sc:2 предложили три сида, sc:1 — один
    origin.add("seed1", &[t("sc:1", "a"), t("sc:2", "b")], false);
    origin.add("seed2", &[t("sc:2", "b")], false);
    origin.add("seed3", &[t("sc:2", "b")], false);
    let out = pick(vec![t("sc:1", "a"), t("sc:2", "b")], &taste, &origin, &Session::default(), &f, None, "own", 1, false, &mut Rng::new(3));
    assert_eq!(out[0].ref_, "sc:2");
    // пропущенный в сессии артист уступает
    let mut s = Session::default();
    s.skipped_artists.insert("b".into());
    let mut o2 = Origin::default();
    o2.add("seed1", &[t("sc:2", "b"), t("sc:1", "a")], false);
    // в «Обычном» есть случайная проба вкуса (affinity), поэтому — большинство из многих прогонов
    let wins = (1..=40)
      .filter(|seed| pick(vec![t("sc:1", "a"), t("sc:2", "b")], &taste, &o2, &s, &f, None, "own", 1, false, &mut Rng::new(*seed))[0].ref_ == "sc:1")
      .count();
    assert!(wins >= 28, "пропущенный артист уступает в большинстве прогонов: {wins}/40");
  }

  #[test]
  fn session_artist_cap_and_tail() {
    let taste = Taste::default();
    let f = Filter::default();
    let mut s = Session::default();
    s.served.insert("a".into(), SESSION_ARTIST_CAP);
    s.recent_artists = vec!["b".into()];
    let out = pick(vec![t("sc:1", "A"), t("sc:2", "B"), t("sc:3", "C")], &taste, &Origin::default(), &s, &f, None, "own", 3, false, &mut Rng::new(5));
    let refs: Vec<&str> = out.iter().map(|x| x.ref_.as_str()).collect();
    assert!(!refs.contains(&"sc:1"), "артист исчерпал лимит сессии");
    assert_eq!(refs.first(), Some(&"sc:3"), "только что звучавший артист — не первым");
    assert_eq!(refs.len(), 2);
  }

  #[test]
  fn mood_filter_when_enough() {
    let taste = Taste::default();
    let f = Filter::default();
    let mut cands: Vec<Track> = (0..6)
      .map(|i| {
        let mut x = t(&format!("sc:{i}"), &format!("s{i}"));
        x.tags = Some("sad emo".into());
        x
      })
      .collect();
    let mut loud = t("sc:99", "loud");
    loud.tags = Some("phonk".into());
    cands.push(loud);
    let out = pick(cands, &taste, &Origin::default(), &Session::default(), &f, None, "sad", 2, false, &mut Rng::new(9));
    assert!(out.iter().all(|x| x.ref_ != "sc:99"));
  }

  #[test]
  fn beta_range_and_mean() {
    let mut r = Rng::new(11);
    let hi: f64 = (0..400).map(|_| beta(30, 2, &mut r)).sum::<f64>() / 400.0;
    let lo: f64 = (0..400).map(|_| beta(2, 30, &mut r)).sum::<f64>() / 400.0;
    assert!(hi > 0.8 && lo < 0.2, "{hi} {lo}");
    assert!((0.0..=1.0).contains(&beta(500, 500, &mut r)));
  }

  fn with_artists(mut x: Track, names: &[&str]) -> Track {
    x.artists = names.iter().map(|n| ArtistRef { ref_: format!("yma:{n}"), name: (*n).into(), avatar_url: None }).collect();
    x
  }

  #[test]
  fn artist_keys_joint_and_empty() {
    // совместный трек Яндекса: «A, B» строкой, артисты списком — два ключа, главный первый
    let joint = with_artists(t("ym:1", "Oxxxymiron, Markul"), &["Oxxxymiron", " Markul "]);
    assert_eq!(artist_keys(&joint), vec!["oxxxymiron".to_owned(), "markul".to_owned()]);
    assert_eq!(artist_key(&joint), "oxxxymiron");
    // списка нет — строка целиком, по запятым и & не режем
    assert_eq!(artist_keys(&t("sc:1", "Tyler, The Creator")), vec!["tyler, the creator".to_owned()]);
    assert_eq!(artist_keys(&t("sc:2", "Simon & Garfunkel")), vec!["simon & garfunkel".to_owned()]);
    // повтор имени в списке — один ключ
    assert_eq!(artist_keys(&with_artists(t("ym:2", "A"), &["A", "a"])).len(), 1);
  }

  #[test]
  fn taste_by_best_artist_and_diversity_by_main() {
    let mut taste = Taste::default();
    taste.liked_artists.insert("markul".into());
    let f = Filter::default();
    // совместный трек с любимым вторым артистом обходит чужой трек
    let joint = with_artists(t("ym:1", "X, Markul"), &["X", "Markul"]);
    let out = pick(vec![t("sc:9", "Other"), joint], &taste, &Origin::default(), &Session::default(), &f, None, "own", 1, false, &mut Rng::new(4));
    assert_eq!(out[0].ref_, "ym:1");
    // пауза — по главному артисту
    let mut f = Filter::default();
    f.paused_artists.insert("x".into());
    let joint = with_artists(t("ym:1", "X, Markul"), &["X", "Markul"]);
    let out = pick(vec![joint], &taste, &Origin::default(), &Session::default(), &f, None, "own", 1, false, &mut Rng::new(4));
    assert!(out.is_empty());
  }

  #[test]
  fn reward_table() {
    const MIN: u64 = 60_000;
    let d = 4 * MIN;
    assert_eq!(reward(d, d, false, false, true), -2.0, "👎");
    assert_eq!(reward(10_000, d, true, true, false), 1.5, "лайк отменяет минусы");
    assert_eq!(reward(10_000, d, true, false, false), -1.0, "ранний пропуск по секундам");
    assert_eq!(reward(50_000, d, true, false, false), -1.0, "f < 0.25");
    assert_eq!(reward(35_000, 100_000, true, false, false), -0.4, "0.25 ≤ f < 0.5, но ≥ 30 с");
    assert_eq!(reward(25_000, 100_000, true, false, false), -1.0, "f ≥ 0.25, но < 30 с — ранний");
    assert_eq!(reward(2 * MIN, d, true, false, false), 0.0, "0.5 ≤ f < 0.8");
    assert_eq!(reward(d * 8 / 10, d, true, false, false), 1.0, "f ≥ 0.8 даже пропуском");
    assert_eq!(reward(d, d, false, false, false), 1.0, "дослушан");
    assert_eq!(reward(10_000, d, false, false, false), 0.0, "сменился не пропуском");
    // длительность неизвестна
    assert_eq!(reward(10_000, 0, true, false, false), -1.0);
    assert_eq!(reward(60_000, 0, true, false, false), 0.0);
    assert_eq!(reward(150_000, 0, false, false, false), 1.0);
    assert!(is_early_skip(10_000, d, true) && !is_early_skip(10_000, d, false));
  }

  /// Разбор тегов до `parse_tags` (по пробелам и кавычкам) — для сверки со старой оценкой.
  fn legacy_tag_words(t: &Track) -> Vec<String> {
    t.tags
      .as_deref()
      .unwrap_or("")
      .to_lowercase()
      .split(|c: char| c == ',' || c == '"' || c.is_whitespace())
      .filter(|w| w.chars().count() >= 3)
      .map(str::to_owned)
      .collect()
  }

  /// Оценка до разбиения на признаки и веса — для сверки, что поведение волны не поменялось.
  fn legacy_score(t: &Track, taste: &Taste, origin: &Origin, session: &Session, prefer: Option<&str>, mode: &str, rng: &mut Rng) -> f64 {
    let keys = artist_keys(t);
    let a = keys[0].clone();
    let (plays, skips) = keys
      .iter()
      .map(|k| (taste.plays.get(k).copied().unwrap_or(0.0), taste.skips.get(k).copied().unwrap_or(0.0)))
      .max_by(|x, y| {
        let m = |(p, s): &(f64, f64)| (1.0 + p) / (2.0 + p + s);
        m(x).partial_cmp(&m(y)).unwrap_or(std::cmp::Ordering::Equal).then(x.0.partial_cmp(&y.0).unwrap_or(std::cmp::Ordering::Equal))
      })
      .unwrap_or((0.0, 0.0));
    let affinity = 2.0 * beta(1 + plays.round() as u32, 1 + skips.round() as u32, rng) - 1.0;
    let liked = if keys.iter().any(|k| taste.liked_artists.contains(k)) { 2.0 } else { 0.0 };
    let platform = match prefer {
      Some(p) if t.ref_.starts_with(&format!("{p}:")) => 0.6,
      _ => 0.0,
    };
    let hour = keys.iter().filter_map(|k| taste.hour_share.get(k).copied()).fold(0.0, f64::max);
    let votes = *origin.votes.get(&t.ref_).unwrap_or(&1) as f64;
    let sim = 0.6 * (votes - 1.0).min(3.0) + 0.5 * origin.rank.get(&t.ref_).copied().unwrap_or(0.0);
    let mut live = if origin.from_session.contains(&t.ref_) { 0.7 } else { 0.0 };
    if session.skipped_artists.contains(&a) {
      live -= 0.9;
    }
    if !session.tags.is_empty() {
      let fit: f64 = legacy_tag_words(t).iter().filter_map(|w| session.tags.get(w)).sum();
      live += (0.3 * fit).min(0.9);
    }
    let noise = rng.unit() * 0.3;
    let base = sim + live + noise;
    match mode {
      "hard" | "calm" | "sad" | "fun" => base + mood_fit(mode, t) * 1.5 + liked * 0.5 + affinity * 0.6 + platform * 0.5 + hour * 0.4,
      _ => base + liked + affinity + platform + hour * 1.2,
    }
  }

  #[test]
  fn score_matches_legacy_formula() {
    let mut taste = Taste::default();
    taste.liked_artists.insert("fav".into());
    taste.plays.insert("fav".into(), 12.0);
    taste.skips.insert("fav".into(), 1.0);
    taste.plays.insert("meh".into(), 2.0);
    taste.skips.insert("meh".into(), 9.0);
    taste.plays.insert("heard".into(), 3.0);
    taste.hour_share.insert("fav".into(), 0.8);
    taste.hour_share.insert("heard".into(), 0.3);
    let mut origin = Origin::default();
    origin.add("s1", &[t("sc:1", "fav"), t("sc:2", "meh"), t("ym:3", "heard"), t("sc:4", "stranger")], true);
    origin.add("s2", &[t("sc:4", "stranger"), t("sc:1", "fav")], false);
    let mut session = Session::default();
    session.skipped_artists.insert("meh".into());
    session.tags.insert("phonk".into(), 2.0);
    let mut cands = vec![t("sc:1", "fav"), t("sc:2", "meh"), t("ym:3", "heard"), t("sc:4", "stranger"), t("sc:5", "new one")];
    cands[2].tags = Some("sad emo".into());
    cands[3].tags = Some("phonk drift".into());
    cands[4].tags = Some("pop dance".into());
    for mode in ["own", "hard", "calm", "sad", "fun"] {
      for prefer in [None, Some("sc"), Some("ym")] {
        for (i, c) in cands.iter().enumerate() {
          for session in [&session, &Session::default()] {
            let seed = 100 + i as u64;
            let (mut r1, mut r2) = (Rng::new(seed), Rng::new(seed));
            let old = legacy_score(c, &taste, &origin, session, prefer, mode, &mut r1);
            let f = features(c, &taste, &origin, session, prefer, mode, &mut r2);
            // «знакомый артист» в «Своей» и настроениях добавлен после (меньше незнакомых) — без него формула прежняя
            let mut w = weights(mode);
            w.known = 0.0;
            let new = w.dot(&f) + r2.unit() * 0.3;
            assert!((old - new).abs() < 1e-9, "{mode} {prefer:?} {}: {old} ≠ {new}", c.ref_);
          }
        }
      }
    }
  }

  #[test]
  fn own_wave_mostly_familiar() {
    let mut taste = Taste::default();
    for i in 1..=7 {
      taste.plays.insert(format!("k{i}"), 3.0);
    }
    let mut cands: Vec<Track> = (0..20).map(|i| t(&format!("sc:u{i}"), &format!("u{i}"))).collect();
    cands.extend((1..=7).map(|i| t(&format!("sc:k{i}"), &format!("k{i}"))));
    let (max_unknown, min_plays_unknown) = familiarity("own", false, 10);
    let f = Filter { max_unknown, min_plays_unknown, ..Default::default() };
    let out = pick(cands, &taste, &Origin::default(), &Session::default(), &f, None, "own", 10, false, &mut Rng::new(1));
    assert_eq!(out.len(), 10);
    let unknown = out.iter().filter(|x| !is_known(x, &taste)).count();
    assert!(unknown <= 3, "незнакомых {unknown}");
  }

  #[test]
  fn obscure_unknown_uploads_dropped() {
    let mut taste = Taste::default();
    taste.plays.insert("fav".into(), 1.0);
    let mut obscure = t("sc:1", "nobody");
    obscure.plays = Some(40);
    let mut popular = t("sc:2", "stranger");
    popular.plays = Some(50_000);
    let mut mine = t("sc:3", "fav");
    mine.plays = Some(10);
    let f = Filter { min_plays_unknown: 1000, ..Default::default() };
    let out = pick(vec![obscure, popular, mine], &taste, &Origin::default(), &Session::default(), &f, None, "own", 10, false, &mut Rng::new(2));
    let refs: Vec<&str> = out.iter().map(|x| x.ref_.as_str()).collect();
    assert!(!refs.contains(&"sc:1") && refs.contains(&"sc:2") && refs.contains(&"sc:3"));
    assert_eq!(familiarity("popular", false, 10), (Some(6), 50_000));
    assert_eq!(familiarity("own", false, 10), (Some(3), 1000));
  }

  #[test]
  fn artist_top_marked_and_not_counted_as_vote() {
    let mut o = Origin::default();
    o.add("s1", &[t("sc:1", "a")], false);
    o.add_artist("sca:9", &[t("sc:1", "a"), t("sc:2", "fav")]);
    assert!(o.artist_top.contains("sc:2") && !o.artist_top.contains("sc:1"));
    assert_eq!(o.votes["sc:1"], 1);
    assert!(o.rank["sc:2"] <= 0.5);
  }

  #[test]
  fn origin_remembers_best_seed_and_pick_returns_features() {
    let mut o = Origin::default();
    // sc:2 у первого сида — на втором месте из трёх, у второго — первым: «пришёл» от второго
    o.add("seedA", &[t("sc:1", "a"), t("sc:2", "b"), t("sc:3", "c")], false);
    o.add("seedB", &[t("sc:2", "b")], false);
    assert_eq!(o.seed_of.get("sc:1").map(String::as_str), Some("seedA"));
    assert_eq!(o.seed_of.get("sc:2").map(String::as_str), Some("seedB"));
    assert_eq!(o.votes["sc:2"], 2);
    // равное место — остаётся первый сид
    o.add("seedC", &[t("sc:1", "a")], false);
    assert_eq!(o.seed_of.get("sc:1").map(String::as_str), Some("seedA"));

    let out = pick_with(
      vec![t("sc:1", "a"), t("sc:2", "b")],
      &Taste::default(),
      &o,
      &Session::default(),
      &Filter::default(),
      Some("sc"),
      "own",
      2,
      false,
      &mut Rng::new(1),
    );
    let two = out.iter().find(|p| p.track.ref_ == "sc:2").unwrap();
    assert_eq!(two.features.votes, 1.0, "два голоса — на один больше базового");
    assert_eq!(two.features.platform, 1.0);
    assert_eq!(two.features.known, 0.0);
    assert_eq!(two.features.fresh, 1.0);
    // признаки сериализуются целиком — их читает wave_events.features_json
    let json = serde_json::to_string(&two.features).unwrap();
    assert!(json.contains("\"affinity\"") && json.contains("\"session_tags\""));
  }

  fn names(v: &[&str]) -> Vec<String> {
    v.iter().map(|s| (*s).to_owned()).collect()
  }

  #[test]
  fn parse_tags_phrases_junk_and_years() {
    // фраза в кавычках — один тег; пустышки и «#» уходят; год остаётся — это метка эпохи
    assert_eq!(parse_tags("trap \"drift phonk\" 2016 music #new free", &[]), names(&["trap", "drift phonk", "2016"]));
    // остальные числа, слишком новые «годы» и короткие слова — мусор
    assert_eq!(parse_tags("2016 808 123 1999 2077 ab", &[]), names(&["2016", "1999"]));
    // жанр + теги через запятую и разный регистр
    assert_eq!(parse_tags("Hip-hop & Rap, Cloud Rap", &[]), names(&["hiphop", "rap", "cloudrap"]));
    // жанр через «/» делится на два тега, написания склеиваются
    assert_eq!(parse_tags("R&B/Soul", &[]), names(&["rnb", "soul"]));
    // кириллица
    assert_eq!(parse_tags("русский рэп \"грустный рэп\"", &[]), names(&["русский", "рэп", "грустный рэп"]));
    assert!(parse_tags("", &[]).is_empty());
    assert!(parse_tags("\"\" \" \"", &[]).is_empty());
  }

  #[test]
  fn parse_tags_merges_spellings() {
    for s in ["hip-hop", "hip hop", "hiphop", "\"hip hop\"", "Hip-Hop"] {
      assert_eq!(parse_tags(s, &[]), names(&["hiphop"]), "{s}");
    }
    for s in ["lo-fi", "lofi", "lo fi"] {
      assert_eq!(parse_tags(s, &[]), names(&["lofi"]), "{s}");
    }
    for s in ["r&b", "rnb", "r & b"] {
      assert_eq!(parse_tags(s, &[]), names(&["rnb"]), "{s}");
    }
    for s in ["drum & bass", "drum and bass", "dnb", "\"drum & bass\"", "drumandbass"] {
      assert_eq!(parse_tags(s, &[]), names(&["dnb"]), "{s}");
    }
    for s in ["k-pop", "kpop", "k pop"] {
      assert_eq!(parse_tags(s, &[]), names(&["kpop"]), "{s}");
    }
    // разные написания одного — один тег, соседние теги не склеиваются
    assert_eq!(parse_tags("hip-hop hiphop lofi trap", &[]), names(&["hiphop", "lofi", "trap"]));
    assert_eq!(parse_tags("drum trap bass", &[]), names(&["drum", "trap", "bass"]));
  }

  #[test]
  fn parse_tags_own_artist_only() {
    // тег с именем артиста на его же треке — шум; на чужом треке — метка сцены
    let tags = "\"lil peep\" gothboiclique 2016";
    assert_eq!(parse_tags(tags, &names(&["lil peep"])), names(&["gothboiclique", "2016"]));
    assert_eq!(parse_tags(tags, &names(&["lil tracy"])), names(&["lil peep", "gothboiclique", "2016"]));
    // через трек: артисты берутся из `artists`
    let mut x = with_artists(t("sc:1", "Lil Peep"), &["Lil Peep"]);
    x.tags = Some(tags.into());
    assert_eq!(tag_set(&x), names(&["gothboiclique", "2016"]));
  }

  #[test]
  fn parse_tags_cap_and_dedup() {
    let many = "aaa bbb ccc ddd eee fff ggg hhh iii jjj aaa";
    let out = parse_tags(many, &[]);
    assert_eq!(out.len(), 8);
    assert_eq!(out[0], "aaa");
    assert_eq!(parse_tags("aaa aaa AAA", &[]), names(&["aaa"]));
  }

  #[test]
  fn tags_fit_averages_known_tags_only() {
    let mut p = HashMap::new();
    p.insert("a".to_owned(), 0.4);
    p.insert("b".to_owned(), -0.2);
    assert_eq!(tags_fit(&p, &names(&["x", "y"])), 0.0, "ничего не известно — ноль, не минус");
    assert!((tags_fit(&p, &names(&["a", "x"])) - 0.8).abs() < 1e-9, "неизвестные не разбавляют");
    assert!((tags_fit(&p, &names(&["a", "b"])) - 0.2).abs() < 1e-9);
    p.insert("c".to_owned(), 0.9);
    assert_eq!(tags_fit(&p, &names(&["c"])), 1.0, "обрезается по 1");
    assert_eq!(tags_fit(&p, &[]), 0.0);
  }

  #[test]
  fn session_tags_go_both_ways() {
    let taste = Taste::default();
    let o = Origin::default();
    let mut s = Session::default();
    s.tags.insert("emo".into(), 1.0);
    s.tags.insert("polka".into(), -2.0);
    let mut like = t("sc:1", "a");
    like.tags = Some("emo".into());
    let mut dislike = t("sc:2", "b");
    dislike.tags = Some("polka".into());
    let f = |x: &Track| features(x, &taste, &o, &s, None, "own", &mut Rng::new(1)).session_tags;
    assert!((f(&like) - 0.3).abs() < 1e-9);
    assert!((f(&dislike) + 0.6).abs() < 1e-9);
    s.tags.insert("polka".into(), -50.0);
    let f = |x: &Track| features(x, &taste, &o, &s, None, "own", &mut Rng::new(1)).session_tags;
    assert_eq!(f(&dislike), -0.9, "минус тоже обрезается");
  }

  #[test]
  fn profile_moves_ranking_and_mode_profile_teaches_mood() {
    let mut taste = Taste::default();
    taste.tag_profile.insert("gothboiclique".into(), 0.4);
    taste.tag_profile.insert("polka".into(), -0.4);
    let mut a = t("sc:1", "a");
    a.tags = Some("gothboiclique".into());
    let mut b = t("sc:2", "b");
    b.tags = Some("polka".into());
    let o = Origin::default();
    let s = Session::default();
    // незнакомые артисты: вкус к артисту одинаковый, поэтому порядок определяет профиль
    for seed in 1..20 {
      let out = pick(vec![b.clone(), a.clone()], &taste, &o, &s, &Filter::default(), None, "own", 2, false, &mut Rng::new(seed));
      assert_eq!(out[0].ref_, "sc:1", "seed {seed}");
    }
    // режим научился: gothboiclique в «Грустной» заходит, но слова «sad» в тегах нет — словарь молчит
    taste.mode_tag_profile.insert("gothboiclique".into(), 0.5);
    let f = features(&a, &taste, &o, &s, None, "sad", &mut Rng::new(3));
    assert_eq!(f.mood, 0.0, "словарь не знает этот тег");
    assert!((f.mode_profile - 1.0).abs() < 1e-9);
    assert!((f.profile_fit - 0.8).abs() < 1e-9);
    let w = weights("sad");
    assert!(w.mode_profile > 0.0 && weights("own").mode_profile == 0.0, "профиль режима — только у настроений");
    // и признаки целиком попадают в журнал
    let json = serde_json::to_string(&f).unwrap();
    assert!(json.contains("\"profile_fit\"") && json.contains("\"mode_profile\""));
  }

  #[test]
  fn scene_bonus_for_map_neighbours() {
    let o = Origin::default();
    let s = Session::default();
    let mut taste = Taste::default();
    let near = t("sc:1", "Lil Peep");
    let far = t("sc:2", "Stranger");
    // карты нет — признак нулевой, оценка как раньше
    assert_eq!(features(&near, &taste, &o, &s, None, "own", &mut Rng::new(1)).scene, 0.0);
    // ключ карты — только буквы и цифры: «Lil Peep» → «lilpeep»
    taste.scene.insert("lilpeep".into(), 0.8);
    let (fa, fb) = (
      features(&near, &taste, &o, &s, None, "own", &mut Rng::new(1)),
      features(&far, &taste, &o, &s, None, "own", &mut Rng::new(1)),
    );
    assert!((fa.scene - 0.8).abs() < 1e-9);
    assert_eq!(fb.scene, 0.0);
    // при прочих равных сосед по карте выше — на вес × близость
    for mode in ["own", "sad", "night", "popular", "sleep"] {
      let w = weights(mode);
      let gap = w.dot(&fa) - w.dot(&Features { scene: 0.0, ..fa.clone() });
      assert!((gap - SCENE_WEIGHT * 0.8).abs() < 1e-9, "{mode}");
    }
    // у совместного трека — лучший из артистов
    let mut joint = t("sc:3", "Stranger");
    joint.artists = vec![
      ArtistRef { ref_: "sc:a".into(), name: "Stranger".into(), avatar_url: None },
      ArtistRef { ref_: "sc:b".into(), name: "LIL PEEP".into(), avatar_url: None },
    ];
    assert!((features(&joint, &taste, &o, &s, None, "own", &mut Rng::new(1)).scene - 0.8).abs() < 1e-9);
    let json = serde_json::to_string(&fa).unwrap();
    assert!(json.contains("\"scene\""));
  }

  #[test]
  fn sample_unique() {
    let mut r = Rng::new(1);
    let s = r.sample(&[1, 2, 3, 4, 5], 3);
    assert_eq!(s.len(), 3);
    assert_eq!(s.iter().collect::<HashSet<_>>().len(), 3);
  }

  #[test]
  fn weighted_sample_unique_and_prefers_heavy() {
    let items: Vec<(u32, f64)> = vec![(1, 10.0), (2, 1.0), (3, 0.0), (4, 1.0)];
    let mut rng = Rng::new(7);
    let mut first_heavy = 0;
    for _ in 0..400 {
      let got = rng.weighted_sample(&items, 3);
      let uniq: HashSet<_> = got.iter().collect();
      assert_eq!(uniq.len(), got.len(), "без повторов");
      assert!(!got.contains(&3), "вес 0 не берётся");
      if got[0] == 1 {
        first_heavy += 1;
      }
    }
    assert!(first_heavy > 280, "тяжёлый первым в ~83 % случаев: {first_heavy}");
  }

  #[test]
  fn skipped_track_loses_to_same_without_skips() {
    let mut taste = Taste::default();
    taste.track_skips.insert("sc:1".into(), 3.0);
    let o = Origin::default();
    let mut wins = 0;
    for seed in 0..50 {
      let out = pick(vec![t("sc:1", "a"), t("sc:2", "b")], &taste, &o, &Session::default(), &Filter::default(), None, "own", 1, false, &mut Rng::new(seed));
      if out[0].ref_ == "sc:2" {
        wins += 1;
      }
    }
    assert_eq!(wins, 50, "пропущенный трек уступает такому же без пропусков");
  }

  #[test]
  fn no_more_than_four_from_one_seed() {
    let mut o = Origin::default();
    let one: Vec<Track> = (0..8).map(|i| t(&format!("sc:{i}"), &format!("a{i}"))).collect();
    o.add("big", &one, false);
    let other: Vec<Track> = (10..16).map(|i| t(&format!("sc:{i}"), &format!("b{i}"))).collect();
    o.add("small", &other, false);
    let cands: Vec<Track> = one.iter().chain(other.iter()).cloned().collect();
    let out = pick_with(cands, &Taste::default(), &o, &Session::default(), &Filter::default(), None, "own", 10, false, &mut Rng::new(3));
    assert_eq!(out.len(), 10, "лимит мягкий: не хватает других сидов — порция добирается");
    // хватает других сидов — лимит держится
    let mut o3 = Origin::default();
    o3.add("big", &one, false);
    let many: Vec<Track> = (20..30).map(|i| t(&format!("sc:{i}"), &format!("c{i}"))).collect();
    for (i, x) in many.iter().enumerate() {
      o3.add(&format!("s{i}"), std::slice::from_ref(x), false);
    }
    let cands: Vec<Track> = one.iter().chain(many.iter()).cloned().collect();
    let out = pick_with(cands, &Taste::default(), &o3, &Session::default(), &Filter::default(), None, "own", 10, false, &mut Rng::new(3));
    assert!(out.iter().filter(|p| o3.seed_of[&p.track.ref_] == "big").count() <= 4);
  }

  #[test]
  fn hop2_scaled_and_marked() {
    let mut o = Origin::default();
    o.add("s", &[t("sc:1", "a")], false);
    o.add_hop("sc:1", &[t("sc:1", "a"), t("sc:9", "z")]);
    assert!(o.hop2.contains("sc:9") && !o.hop2.contains("sc:1"));
    assert!(o.rank["sc:9"] <= 0.3 + 1e-9, "второй шаг весит × 0.6: {}", o.rank["sc:9"]);
    let out = pick_with(vec![t("sc:9", "z")], &Taste::default(), &o, &Session::default(), &Filter::default(), None, "own", 1, false, &mut Rng::new(1));
    assert_eq!(out[0].source, "hop2");
  }

  fn picked(r: &str, artist: &str, source: &'static str) -> Picked {
    Picked { track: t(r, artist), features: Features::default(), source }
  }

  #[test]
  fn liked_go_to_slots_2_5_8_never_first() {
    let out: Vec<Picked> = (0..10).map(|i| picked(&format!("sc:{i}"), &format!("n{i}"), "similar")).collect();
    let liked = vec![picked("sc:a", "la", "liked"), picked("sc:b", "lb", "liked"), picked("sc:c", "lc", "liked")];
    let got = insert_liked(out, liked, 10);
    assert_eq!(got.len(), 10);
    let at: Vec<usize> = got.iter().enumerate().filter(|(_, p)| p.source == "liked").map(|(i, _)| i).collect();
    assert_eq!(at, vec![2, 5, 8]);
    assert_eq!(got[0].source, "similar");
  }

  #[test]
  fn liked_slot_shifts_away_from_same_artist() {
    let out: Vec<Picked> = (0..10).map(|i| picked(&format!("sc:{i}"), if i == 2 { "same" } else { "x" }, "similar")).collect();
    // у новых «x» стоят подряд не по правилам — проверяем только сдвиг своего трека от «same»
    let got = insert_liked(out, vec![picked("sc:l", "same", "liked")], 10);
    let i = got.iter().position(|p| p.source == "liked").unwrap();
    assert!(i > 3, "место 2 и 3 — рядом с тем же артистом: {i}");
  }

  #[test]
  fn liked_share_by_mode_and_mood_filter() {
    assert_eq!(liked_share("own", false), 3);
    assert_eq!(liked_share("sad", false), 2);
    assert_eq!(liked_share("night", false), 2);
    assert_eq!(liked_share("legacy", false), 0);
    assert_eq!(liked_share("own", true), 0);
    let mut sad = t("sc:1", "a");
    sad.tags = Some("sad emo".into());
    let fun = t("sc:2", "b");
    let got = pick_liked(vec![sad, fun], &Taste::default(), &Session::default(), &Filter::default(), "sad", 2, &mut Rng::new(1));
    assert_eq!(got.iter().map(|p| p.track.ref_.as_str()).collect::<Vec<_>>(), vec!["sc:1"]);
    assert!(got.iter().all(|p| p.source == "liked"));
  }

  #[test]
  fn why_names_the_source() {
    let mut origin = Origin::default();
    origin.add("sc:seed", &[t("sc:1", "a")], false);
    origin.add("sc:live", &[t("sc:2", "b")], true);
    origin.add_artist("sca:9", &[t("sc:3", "c")]);
    let picked = |r: &str, source: &'static str| Picked { track: t(r, "x"), features: Features::default(), source };
    assert_eq!(why(&picked("sc:1", "similar"), &origin, None), ("similar", Some("sc:seed".into())));
    assert_eq!(why(&picked("sc:1", "similar"), &origin, Some("sc:seed")), ("seed", Some("sc:seed".into())));
    assert_eq!(why(&picked("sc:2", "similar"), &origin, None), ("session", Some("sc:live".into())));
    assert_eq!(why(&picked("sc:3", "artist"), &origin, None), ("artist", Some("sca:9".into())));
    assert_eq!(why(&picked("sc:4", "liked"), &origin, None).0, "liked");
    assert_eq!(why(&picked("sc:5", "hop2"), &origin, None).0, "explore");
  }

  #[test]
  fn nine_moods_without_discover() {
    assert_eq!(MODES.len(), 9);
    assert!(!MODES.contains(&"new"), "«Незнакомое» убрано");
    assert!(!is_mood("own") && !is_mood("new"));
    for m in MODES.iter().filter(|m| **m != "own") {
      assert!(is_mood(m), "{m} — настроение со своим словарём");
      assert!(weights(m).mood > 0.0 && weights(m).mode_profile > 0.0, "{m}");
    }
  }

  #[test]
  fn new_moods_have_own_profiles() {
    let tagged = |r: &str, tags: &str| {
      let mut x = t(r, "a");
      x.tags = Some(tags.into());
      x
    };
    assert!(mood_fit("night", &tagged("sc:1", "synthwave midnight")) > 1.0);
    assert!(mood_fit("sleep", &tagged("sc:2", "sleep ambient drone")) > 1.0);
    assert!(mood_fit("focus", &tagged("sc:3", "study instrumental chillhop")) > 1.0);
    assert!(mood_fit("popular", &tagged("sc:4", "viral tiktok hits")) > 1.0);
    // фонк — не сон и не концентрация
    assert!(mood_fit("sleep", &tagged("sc:5", "phonk drift")) < 0.0);
    assert!(mood_fit("focus", &tagged("sc:5", "phonk drift")) < 0.0);
    // профили разные: один и тот же трек по-разному подходит разным настроениям
    let lofi = tagged("sc:6", "lofi study beats to relax");
    assert!(mood_fit("focus", &lofi) > mood_fit("sleep", &lofi));
  }

  #[test]
  fn popular_prefers_many_plays() {
    assert_eq!(popularity(&t("ym:1", "a")), 0.0, "нет числа — не штраф");
    let mut big = t("sc:1", "a");
    big.plays = Some(10_000_000);
    let mut small = t("sc:2", "b");
    small.plays = Some(2_000);
    assert!((popularity(&big) - 1.0).abs() < 1e-9);
    assert!(popularity(&small) < 0.1);
    for seed in 1..15 {
      let out = pick(vec![small.clone(), big.clone()], &Taste::default(), &Origin::default(), &Session::default(), &Filter::default(), None, "popular", 2, false, &mut Rng::new(seed));
      assert_eq!(out[0].ref_, "sc:1", "seed {seed}");
    }
    assert_eq!(weights("own").popularity, 0.0, "популярность весит только в «Популярном»");
  }

  #[test]
  fn sleep_and_focus_keep_only_fitting_when_enough() {
    let mut cands: Vec<Track> = (0..6)
      .map(|i| {
        let mut x = t(&format!("sc:{i}"), &format!("a{i}"));
        x.tags = Some("sleep ambient".into());
        x
      })
      .collect();
    cands.push(t("sc:99", "zz"));
    let out = pick(cands, &Taste::default(), &Origin::default(), &Session::default(), &Filter::default(), None, "sleep", 3, false, &mut Rng::new(1));
    assert!(out.iter().all(|x| x.ref_ != "sc:99"), "трек без признаков сна не попадает, когда подходящих хватает");
  }
}
