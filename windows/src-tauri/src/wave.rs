//! Своя «Моя волна» (SPEC §3.7, PSEUDOCODE §11) в автономном клиенте: кандидаты — похожие треки
//! от сидов (последние лайки и дослушанные + немного «разведки» по старым лайкам), фильтры
//! (не играть прослушанное за 7 дней, дизлайки, артисты на паузе) и выбор порции с разнообразием.
//! Сессию (что уже выдано, кто на паузе) держит интерфейс и передаёт сюда — ядро без состояния.

use crate::providers::Track;
use crate::store::Taste;
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

pub fn artist_key(t: &Track) -> String {
  t.artist.to_lowercase()
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
}

impl Origin {
  /// Учесть список похожих от одного сида.
  pub fn add(&mut self, list: &[Track], session: bool) {
    let len = list.len().max(1) as f64;
    let mut seen = HashSet::new();
    for (i, t) in list.iter().enumerate() {
      if !seen.insert(&t.ref_) {
        continue;
      }
      *self.votes.entry(t.ref_.clone()).or_insert(0) += 1;
      let r = 1.0 - i as f64 / len;
      let e = self.rank.entry(t.ref_.clone()).or_insert(0.0);
      *e = e.max(r);
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

/// Оценка кандидата. Вкус к артисту — выборка Томпсона из Beta(1+дослушано, 1+пропущено): у
/// знакомых и любимых она стабильно высокая, у малознакомых — разбросана, поэтому волна иногда
/// пробует новых, а не крутит одних и тех же. Плюс: лайкнутый артист, голоса и место в похожих,
/// «зашло в сессии», теги как у зашедших, своя платформа, время суток, настроение режима.
fn score(t: &Track, taste: &Taste, origin: &Origin, session: &Session, prefer: Option<&str>, mode: &str, rng: &mut Rng) -> f64 {
  let a = artist_key(t);
  let plays = *taste.plays.get(&a).unwrap_or(&0);
  let skips = *taste.skips.get(&a).unwrap_or(&0);
  let affinity = 2.0 * beta(1 + plays, 1 + skips, rng) - 1.0; // −1 … 1
  let liked = if taste.liked_artists.contains(&a) { 2.0 } else { 0.0 };
  let platform = match prefer {
    Some(p) if t.ref_.starts_with(&format!("{p}:")) => 0.6,
    _ => 0.0,
  };
  let hour = taste.hour_share.get(&a).copied().unwrap_or(0.0);
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

/// Порция из `n` треков: без дублей и фильтрованных, не два одинаковых артиста подряд (и не те,
/// что звучали только что), не больше двух треков артиста в порции и четырёх за сессию.
/// В режиме настроения, если подходящих хватает, неподходящие отбрасываются совсем.
/// `relaxed` — разрешить недавно слушанное (когда кандидатов мало).
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
  let mut scored: Vec<(f64, Track)> = pool.into_iter().map(|t| (score(&t, taste, origin, session, prefer, mode, rng), t)).collect();
  scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));

  let mut out: Vec<Track> = Vec::with_capacity(n);
  let mut per_artist: HashMap<String, usize> = HashMap::new();
  // только что звучавшие артисты (хвост прошлой порции) — не первым треком новой
  let tail: Vec<&String> = session.recent_artists.iter().rev().take(3).collect();
  // Кто сейчас не подходит (тот же артист, что предыдущий), ждёт следующего шанса — не теряется.
  let mut pending: Vec<Track> = Vec::new();
  for (_, t) in scored {
    pending.push(t);
    loop {
      let ok = |t: &Track| {
        let a = artist_key(t);
        let just_played = out.is_empty() && tail.iter().any(|x| **x == a);
        !just_played
          && !out.last().is_some_and(|l| artist_key(l) == a)
          && per_artist.get(&a).copied().unwrap_or(0) < 2
          && per_artist.get(&a).copied().unwrap_or(0) + session.served.get(&a).copied().unwrap_or(0) < SESSION_ARTIST_CAP
      };
      let Some(i) = pending.iter().position(ok) else { break };
      let t = pending.remove(i);
      *per_artist.entry(artist_key(&t)).or_insert(0) += 1;
      out.push(t);
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
    origin.add(&[t("sc:1", "a"), t("sc:2", "b")], false);
    origin.add(&[t("sc:2", "b")], false);
    origin.add(&[t("sc:2", "b")], false);
    let out = pick(vec![t("sc:1", "a"), t("sc:2", "b")], &taste, &origin, &Session::default(), &f, None, "new", 1, false, &mut Rng::new(3));
    assert_eq!(out[0].ref_, "sc:2");
    // пропущенный в сессии артист уступает
    let mut s = Session::default();
    s.skipped_artists.insert("b".into());
    let mut o2 = Origin::default();
    o2.add(&[t("sc:2", "b"), t("sc:1", "a")], false);
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

  #[test]
  fn sample_unique() {
    let mut r = Rng::new(1);
    let s = r.sample(&[1, 2, 3, 4, 5], 3);
    assert_eq!(s.len(), 3);
    assert_eq!(s.iter().collect::<HashSet<_>>().len(), 3);
  }
}
