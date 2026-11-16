//! Своя «Моя волна» (SPEC §3.7, PSEUDOCODE §11) в автономном клиенте: кандидаты — похожие треки
//! от сидов (последние лайки и дослушанные + немного «разведки» по старым лайкам), фильтры
//! (не играть прослушанное за 7 дней, дизлайки, артисты на паузе) и выбор порции с разнообразием.
//! Сессию (что уже выдано, кто на паузе) держит интерфейс и передаёт сюда — ядро без состояния.

use crate::providers::{ArtistRef, Track};
use crate::store::Taste;
use serde::Serialize;
use std::collections::{HashMap, HashSet};

/// Порция волны.
pub const PORTION: usize = 10;

/// Простой генератор случайных чисел (xorshift) — без лишнего крейта.
pub struct Rng(u64);

impl Rng {
  pub fn new(seed: u64) -> Self {
    Self(seed | 1)
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
}

/// Что нельзя ставить в порцию.
#[derive(Default)]
pub struct Filter {
  /// Слушали за 7 дней.
  pub recent: HashSet<String>,
  /// 👎.
  pub banned: HashSet<String>,
  /// Уже выданы в этой сессии волны.
  pub exclude: HashSet<String>,
  /// Артисты на паузе до конца сессии (два пропуска подряд), в нижнем регистре.
  pub paused_artists: HashSet<String>,
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
#[allow(dead_code)] // вкус по оценкам — этап 2 (docs/WAVE.md)
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
#[allow(dead_code)] // интерфейс считает то же в `reward.ts`; в Rust — с этапа 2
pub fn is_early_skip(listened_ms: u64, duration_ms: u64, manual_skip: bool) -> bool {
  reward(listened_ms, duration_ms, manual_skip, false, false) <= -1.0
}

/// Режим волны (кнопка под «Моя волна»): `own` — своя по лайкам, настроения `hard` / `calm` /
/// `sad` / `fun` и `new` — незнакомое. Настроение угадываем по жанру, тегам и названию трека —
/// группы тегов настроений Last.fm / MIREX (Hu & Downie) плюс жанры, которые обычно туда ложатся.
pub const MODES: [&str; 6] = ["own", "hard", "calm", "sad", "fun", "new"];

const MOODS: [(&str, &[&str]); 4] = [
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
      "lofi", "lo-fi", "chill", "ambient", "acoustic", "piano", "jazz", "sleep", "calm", "relax", "study", "classical",
      "instrumental", "soul", "r&b", "rnb", "downtempo", "bossa", "folk", "mellow", "soothing", "serene", "meditat",
      "lounge", "new age", "спокой",
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
];

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

/// Теги трека словами (жанр + теги SoundCloud / жанры Яндекса), в нижнем регистре.
pub fn tag_words(t: &Track) -> Vec<String> {
  t.tags
    .as_deref()
    .unwrap_or("")
    .to_lowercase()
    .split(|c: char| c == ',' || c == '"' || c.is_whitespace())
    .filter(|w| w.chars().count() >= 3)
    .map(str::to_owned)
    .collect()
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
  /// Сид, в чьём списке трек стоял выше всего, — «от кого пришёл» (для `wave_events`).
  pub seed_of: HashMap<String, String>,
}

impl Origin {
  /// Учесть список похожих от одного сида (`seed` — его ref).
  pub fn add(&mut self, seed: &str, list: &[Track], session: bool) {
    let len = list.len().max(1) as f64;
    let mut seen = HashSet::new();
    for (i, t) in list.iter().enumerate() {
      if !seen.insert(&t.ref_) {
        continue;
      }
      *self.votes.entry(t.ref_.clone()).or_insert(0) += 1;
      let r = 1.0 - i as f64 / len;
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
  /// Теги треков, которые зашли в сессии (дослушаны / лайкнуты), с весом.
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
  /// Теги как у зашедших (плюс) и как у пропущенных (минус) в этой сессии.
  pub session_tags: f64,
  /// Трек с платформы, которую выбрал пользователь, 0 / 1.
  pub platform: f64,
  /// Доля прослушиваний артиста в это время суток, 0 … 1.
  pub hour: f64,
  /// `mood_fit` режима, −0.8 … 2.2.
  pub mood: f64,
  /// Доля пропусков артиста.
  pub skip_rate: f64,
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
  pub platform: f64,
  pub hour: f64,
  pub mood: f64,
  pub skip_rate: f64,
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
      + self.platform * f.platform
      + self.hour * f.hour
      + self.mood * f.mood
      + self.skip_rate * f.skip_rate
  }
}

/// Веса режима: «Незнакомое» — чужие артисты, настроения — `mood_fit` плюс вкус, остальное («Своя») —
/// лайки, вкус и время суток. Общее для всех — «похожесть» и то, что зашло или не зашло в сессии.
pub fn weights(mode: &str) -> Weights {
  let common = Weights {
    votes: 0.6,
    rank: 0.5,
    from_session: 0.7,
    session_skipped: -0.9,
    session_tags: 1.0,
    ..Default::default()
  };
  match mode {
    "new" => Weights { known: -2.5, fresh: 1.0, skip_rate: -1.0, platform: 0.3, ..common },
    "hard" | "calm" | "sad" | "fun" => Weights { mood: 1.5, liked_artist: 1.0, affinity: 0.6, platform: 0.3, hour: 0.4, ..common },
    _ => Weights { liked_artist: 2.0, affinity: 1.0, platform: 0.6, hour: 1.2, ..common },
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
  let (plays, skips) = keys
    .iter()
    .map(|k| (*taste.plays.get(k).unwrap_or(&0), *taste.skips.get(k).unwrap_or(&0)))
    .max_by(|x, y| {
      let m = |(p, s): &(u32, u32)| (1.0 + *p as f64) / (2.0 + (*p + *s) as f64);
      m(x).partial_cmp(&m(y)).unwrap_or(std::cmp::Ordering::Equal).then(x.0.cmp(&y.0))
    })
    .unwrap_or((0, 0));
  let affinity = 2.0 * beta(1 + plays, 1 + skips, rng) - 1.0;
  let liked = keys.iter().any(|k| taste.liked_artists.contains(k));
  let known = liked || plays > 0;
  let platform = matches!(prefer, Some(p) if t.ref_.starts_with(&format!("{p}:")));
  let session_tags = if session.tags.is_empty() {
    0.0
  } else {
    let fit: f64 = tag_words(t).iter().filter_map(|w| session.tags.get(w)).sum();
    (0.3 * fit).min(0.9)
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
    platform: platform as u8 as f64,
    hour: keys.iter().filter_map(|k| taste.hour_share.get(k).copied()).fold(0.0, f64::max),
    mood: if matches!(mode, "hard" | "calm" | "sad" | "fun") { mood_fit(mode, t) } else { 0.0 },
    skip_rate: skips as f64 / (plays + skips + 1) as f64,
  }
}

/// Кандидат с признаками, с которыми он выбран.
pub struct Picked {
  pub track: Track,
  pub features: Features,
}

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
    .filter(|t| session.served.get(&artist_key(t)).copied().unwrap_or(0) < SESSION_ARTIST_CAP)
    .collect();
  if matches!(mode, "hard" | "calm" | "sad" | "fun") {
    let fits = pool.iter().filter(|t| mood_fit(mode, t) > 0.0).count();
    if fits >= n * 3 {
      pool.retain(|t| mood_fit(mode, t) >= 0.0);
    }
  }
  let w = weights(mode);
  let mut scored: Vec<(f64, Picked)> = pool
    .into_iter()
    .map(|track| {
      let features = features(&track, taste, origin, session, prefer, mode, rng);
      (w.dot(&features) + rng.unit() * 0.3, Picked { track, features })
    })
    .collect();
  scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));

  let mut out: Vec<Picked> = Vec::with_capacity(n);
  let mut per_artist: HashMap<String, usize> = HashMap::new();
  // только что звучавшие артисты (хвост прошлой порции) — не первым треком новой
  let tail: Vec<&String> = session.recent_artists.iter().rev().take(3).collect();
  // Кто сейчас не подходит (тот же артист, что предыдущий), ждёт следующего шанса — не теряется.
  let mut pending: Vec<Picked> = Vec::new();
  for (_, p) in scored {
    pending.push(p);
    loop {
      let ok = |p: &Picked| {
        let a = artist_key(&p.track);
        let just_played = out.is_empty() && tail.iter().any(|x| **x == a);
        !just_played
          && !out.last().is_some_and(|l| artist_key(&l.track) == a)
          && per_artist.get(&a).copied().unwrap_or(0) < 2
          && per_artist.get(&a).copied().unwrap_or(0) + session.served.get(&a).copied().unwrap_or(0) < SESSION_ARTIST_CAP
      };
      let Some(i) = pending.iter().position(ok) else { break };
      let p = pending.remove(i);
      *per_artist.entry(artist_key(&p.track)).or_insert(0) += 1;
      out.push(p);
      if out.len() == n {
        return out;
      }
    }
  }
  out
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
  fn votes_and_session_lift() {
    let taste = Taste::default();
    let f = Filter::default();
    let mut origin = Origin::default();
    // sc:2 предложили три сида, sc:1 — один
    origin.add("seed1", &[t("sc:1", "a"), t("sc:2", "b")], false);
    origin.add("seed2", &[t("sc:2", "b")], false);
    origin.add("seed3", &[t("sc:2", "b")], false);
    let out = pick(vec![t("sc:1", "a"), t("sc:2", "b")], &taste, &origin, &Session::default(), &f, None, "new", 1, false, &mut Rng::new(3));
    assert_eq!(out[0].ref_, "sc:2");
    // пропущенный в сессии артист уступает
    let mut s = Session::default();
    s.skipped_artists.insert("b".into());
    let mut o2 = Origin::default();
    o2.add("seed1", &[t("sc:2", "b"), t("sc:1", "a")], false);
    let out = pick(vec![t("sc:1", "a"), t("sc:2", "b")], &taste, &o2, &s, &f, None, "new", 1, false, &mut Rng::new(3));
    assert_eq!(out[0].ref_, "sc:1");
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

  /// Оценка до разбиения на признаки и веса — для сверки, что поведение волны не поменялось.
  fn legacy_score(t: &Track, taste: &Taste, origin: &Origin, session: &Session, prefer: Option<&str>, mode: &str, rng: &mut Rng) -> f64 {
    let keys = artist_keys(t);
    let a = keys[0].clone();
    let (plays, skips) = keys
      .iter()
      .map(|k| (*taste.plays.get(k).unwrap_or(&0), *taste.skips.get(k).unwrap_or(&0)))
      .max_by(|x, y| {
        let m = |(p, s): &(u32, u32)| (1.0 + *p as f64) / (2.0 + (*p + *s) as f64);
        m(x).partial_cmp(&m(y)).unwrap_or(std::cmp::Ordering::Equal).then(x.0.cmp(&y.0))
      })
      .unwrap_or((0, 0));
    let affinity = 2.0 * beta(1 + plays, 1 + skips, rng) - 1.0;
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
      let fit: f64 = tag_words(t).iter().filter_map(|w| session.tags.get(w)).sum();
      live += (0.3 * fit).min(0.9);
    }
    let noise = rng.unit() * 0.3;
    let base = sim + live + noise;
    match mode {
      "new" => {
        let known = liked > 0.0 || plays > 0;
        base + (if known { -2.5 } else { 1.0 }) - skips as f64 / (plays + skips + 1) as f64 + platform * 0.5
      }
      "hard" | "calm" | "sad" | "fun" => base + mood_fit(mode, t) * 1.5 + liked * 0.5 + affinity * 0.6 + platform * 0.5 + hour * 0.4,
      _ => base + liked + affinity + platform + hour * 1.2,
    }
  }

  #[test]
  fn score_matches_legacy_formula() {
    let mut taste = Taste::default();
    taste.liked_artists.insert("fav".into());
    taste.plays.insert("fav".into(), 12);
    taste.skips.insert("fav".into(), 1);
    taste.plays.insert("meh".into(), 2);
    taste.skips.insert("meh".into(), 9);
    taste.plays.insert("heard".into(), 3);
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
    for mode in MODES {
      for prefer in [None, Some("sc"), Some("ym")] {
        for (i, c) in cands.iter().enumerate() {
          for session in [&session, &Session::default()] {
            let seed = 100 + i as u64;
            let (mut r1, mut r2) = (Rng::new(seed), Rng::new(seed));
            let old = legacy_score(c, &taste, &origin, session, prefer, mode, &mut r1);
            let f = features(c, &taste, &origin, session, prefer, mode, &mut r2);
            let new = weights(mode).dot(&f) + r2.unit() * 0.3;
            assert!((old - new).abs() < 1e-9, "{mode} {prefer:?} {}: {old} ≠ {new}", c.ref_);
          }
        }
      }
    }
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

  #[test]
  fn sample_unique() {
    let mut r = Rng::new(1);
    let s = r.sample(&[1, 2, 3, 4, 5], 3);
    assert_eq!(s.len(), 3);
    assert_eq!(s.iter().collect::<HashSet<_>>().len(), 3);
  }
}
