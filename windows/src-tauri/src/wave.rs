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
/// `sad` / `fun` и `new` — незнакомое. Настроение угадываем по жанру, тегам и названию трека.
pub const MODES: [&str; 6] = ["own", "hard", "calm", "sad", "fun", "new"];

const MOODS: [(&str, &[&str]); 4] = [
  (
    "hard",
    &[
      "phonk", "drift", "hardstyle", "hardcore", "drill", "trap", "rage", "metal", "rock", "punk", "dubstep", "dnb",
      "drum & bass", "drum and bass", "breakcore", "jersey", "hard", "aggressive", "brazilian", "funk", "techno", "industrial",
      "rusrap", "hip-hop", "hiphop", "rap",
    ],
  ),
  (
    "calm",
    &[
      "lofi", "lo-fi", "chill", "ambient", "acoustic", "piano", "jazz", "sleep", "calm", "relax", "study", "classical",
      "instrumental", "soul", "r&b", "rnb", "downtempo", "bossa", "folk",
    ],
  ),
  (
    "sad",
    &[
      "sad", "emo", "depress", "melanchol", "slowed", "reverb", "heartbreak", "lonely", "cry", "alone", "grief", "tears",
      "cloud rap", "cloudrap", "dark", "грус", "одинок", "слёз", "слез",
    ],
  ),
  (
    "fun",
    &[
      "pop", "dance", "house", "disco", "party", "happy", "summer", "hyperpop", "electro", "edm", "club", "remix",
      "sped up", "nightcore", "funk", "k-pop", "kpop", "весел", "лето",
    ],
  ),
];

/// Насколько трек подходит настроению: совпал по жанру/тегам/названию — плюс, похож на другое
/// настроение — минус, ничего не известно — ноль.
pub fn mood_fit(mood: &str, t: &Track) -> f64 {
  let text = format!("{} {}", t.tags.as_deref().unwrap_or(""), t.title.to_lowercase());
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

/// Оценка кандидата: лайкнутый артист ×2, доля дослушанного минус доля пропусков,
/// бонус своей платформе (`general.platform`), время суток (кого слушаешь в эти часы),
/// настроение режима, немного случайности. «Незнакомое» — наоборот, знакомые артисты внизу.
fn score(t: &Track, taste: &Taste, prefer: Option<&str>, mode: &str, rng: &mut Rng) -> f64 {
  let a = artist_key(t);
  let plays = *taste.plays.get(&a).unwrap_or(&0) as f64;
  let skips = *taste.skips.get(&a).unwrap_or(&0) as f64;
  let total = plays + skips + 1.0;
  let liked = if taste.liked_artists.contains(&a) { 2.0 } else { 0.0 };
  let platform = match prefer {
    Some(p) if t.ref_.starts_with(&format!("{p}:")) => 0.6,
    _ => 0.0,
  };
  let hour = taste.hour_share.get(&a).copied().unwrap_or(0.0);
  let noise = rng.unit() * 0.5;
  match mode {
    "new" => {
      let known = liked > 0.0 || plays > 0.0;
      (if known { -2.5 } else { 1.0 }) - skips / total + platform * 0.5 + noise
    }
    "hard" | "calm" | "sad" | "fun" => mood_fit(mode, t) * 1.5 + liked * 0.5 + plays / total - skips / total + platform * 0.5 + hour * 0.4 + noise,
    _ => liked + plays / total - skips / total + platform + hour * 1.2 + noise,
  }
}

/// Порция из `n` треков: без дублей и фильтрованных, не два одинаковых артиста подряд,
/// не больше двух треков артиста. `relaxed` — разрешить недавно слушанное (когда кандидатов мало).
pub fn pick(cands: Vec<Track>, taste: &Taste, filter: &Filter, prefer: Option<&str>, mode: &str, n: usize, relaxed: bool, rng: &mut Rng) -> Vec<Track> {
  let mut seen = HashSet::new();
  let mut scored: Vec<(f64, Track)> = cands
    .into_iter()
    .filter(|t| t.available && seen.insert(t.ref_.clone()))
    .filter(|t| !filter.banned.contains(&t.ref_) && !filter.exclude.contains(&t.ref_))
    .filter(|t| relaxed || !filter.recent.contains(&t.ref_))
    .filter(|t| !filter.paused_artists.contains(&artist_key(t)))
    .map(|t| (score(&t, taste, prefer, mode, rng), t))
    .collect();
  scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));

  let mut out: Vec<Track> = Vec::with_capacity(n);
  let mut per_artist: HashMap<String, usize> = HashMap::new();
  // Кто сейчас не подходит (тот же артист, что предыдущий), ждёт следующего шанса — не теряется.
  let mut pending: Vec<Track> = Vec::new();
  for (_, t) in scored {
    pending.push(t);
    loop {
      let ok = |t: &Track| {
        let a = artist_key(t);
        !out.last().is_some_and(|l| artist_key(l) == a) && per_artist.get(&a).copied().unwrap_or(0) < 2
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
    let out = pick(cands, &taste, &f, None, "own", 10, false, &mut Rng::new(42));
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
    let out = pick(vec![t("sc:1", "x"), t("sc:2", "Fav")], &taste, &f, None, "own", 1, true, &mut Rng::new(7));
    assert_eq!(out[0].ref_, "sc:2");
    let out = pick(vec![t("sc:1", "x"), t("sc:2", "Fav")], &taste, &f, None, "own", 2, false, &mut Rng::new(7));
    assert_eq!(out.len(), 1);
  }

  #[test]
  fn sample_unique() {
    let mut r = Rng::new(1);
    let s = r.sample(&[1, 2, 3, 4, 5], 3);
    assert_eq!(s.len(), 3);
    assert_eq!(s.iter().collect::<HashSet<_>>().len(), 3);
  }
}
