//! Тот же трек на другом сервисе — для резервного сервиса (`Core::resolve_playable`), «SoundCloud
//! через Яндекс», импорта по ссылке (этап 5) и поиска дублей офлайн (этап 7). Правила строгие —
//! лучше не сыграть ничего, чем чужую версию: длительность ±3 с, исполнитель совпадает, название
//! почти одинаковое, а «версии» (remix, live, sped up, slowed…) должны совпадать с обеих сторон.
//!
//! Публичное API:
//! - `Wanted::new(artists, title, duration_ms)` — что ищем по названию / исполнителю / длительности;
//! - `Wanted::from_track(&Track)` — то же по треку из любого сервиса или из кэша;
//! - `Wanted::queries()` — запросы к поиску сервиса, `Wanted::best(&[Track])` — лучший доступный кандидат;
//! - `Wanted::score(&Track)` — оценка одного кандидата (None — другой трек), без сети;
//! - `same_track(&Track, &Track)` — один ли это трек (дубли по сохранённым метаданным);
//! - `artist_keys(&Track, &Wanted)` — имена исполнителей для отбора пар без сравнения всех со всеми.

use super::Track;
use crate::lyrics::title_split::reupload_variants;
use crate::lyrics::{clean_title, first_artist, keyword_title, norm, rules, similarity};
use regex::Regex;
use std::collections::HashSet;
use std::sync::LazyLock;

pub const MAX_DURATION_DIFF_MS: u64 = 3000;
const MIN_TITLE: f64 = 0.9;

/// Что ищем: исполнители-кандидаты (залившего, из метаданных, из «АРТИСТ - ТРЕК»), название, длительность.
#[derive(Debug, Clone)]
pub struct Wanted {
  pub artists: Vec<String>,
  pub titles: Vec<String>,
  pub duration_ms: u64,
  /// Слова «версий» в исходном названии — у найденного должны быть те же.
  versions: HashSet<&'static str>,
}

static VERSION_WORDS: &[&str] = &[
  "remix", "rmx", "live", "acoustic", "sped", "speed", "slowed", "reverb", "nightcore", "instrumental", "karaoke",
  "cover", "edit", "mix", "version", "demo", "ремикс", "акустика", "live",
];
static WORD: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[\p{L}\p{N}]+").unwrap());
static ARTIST_SPLIT: LazyLock<Regex> =
  LazyLock::new(|| Regex::new(r"(?i)\s*,\s*|\s+(?:&|feat\.?|ft\.?|x|\+|×|и|and|with|w/)\s+").unwrap());

fn versions(s: &str) -> HashSet<&'static str> {
  let lower = s.to_lowercase();
  let words: HashSet<&str> = WORD.find_iter(&lower).map(|m| m.as_str()).collect();
  VERSION_WORDS.iter().copied().filter(|v| words.contains(v)).collect()
}

fn artist_names(s: &str) -> impl Iterator<Item = String> + '_ {
  ARTIST_SPLIT.split(s).map(norm).filter(|n| !n.is_empty())
}

impl Wanted {
  /// Что ищем по исполнителям (`artists`, по порядку важности), названию и длительности
  /// (0 — неизвестна, тогда не сверяется). «АРТИСТ - ТРЕК» в названии (перезалив) тоже учитывается.
  pub fn new<S: AsRef<str>>(artists: impl IntoIterator<Item = S>, title: &str, duration_ms: u64) -> Self {
    let artists: Vec<S> = artists.into_iter().collect();
    let uploader = artists.iter().map(|a| a.as_ref().trim()).find(|a| !a.is_empty()).unwrap_or("");
    let mut names = Vec::new();
    let mut titles = Vec::new();
    // перезалив «АРТИСТ - ТРЕК»: первый вариант разбора (docs/TITLE_SPLIT.md)
    if let Some((a, t)) = reupload_variants(uploader, title, &rules::current().dash).into_iter().next() {
      names.push(a);
      titles.push(clean_title(&t));
    }
    for a in &artists {
      let a = a.as_ref().trim();
      if !a.is_empty() && !names.iter().any(|n: &String| n == a) {
        names.push(a.to_string());
      }
    }
    let (_, core, feats) = keyword_title(title);
    for t in [clean_title(title), core] {
      if !t.is_empty() && !titles.contains(&t) {
        titles.push(t);
      }
    }
    names.extend(feats);
    Self { artists: names, titles, duration_ms, versions: versions(title) }
  }

  /// `uploader` — ник залившего на SoundCloud, `meta_artist` — `publisher_metadata.artist`.
  pub fn soundcloud(uploader: &str, meta_artist: Option<&str>, title: &str, duration_ms: u64) -> Self {
    Self::new([meta_artist.unwrap_or(""), uploader], title, duration_ms)
  }

  /// Трек любого сервиса (или из кэша `tracks`): строка исполнителя и все исполнители по отдельности.
  pub fn from_track(t: &Track) -> Self {
    let names = std::iter::once(t.artist.as_str()).chain(t.artists.iter().map(|a| a.name.as_str()));
    Self::new(names, &t.title, t.duration_ms)
  }

  /// Запросы к поиску сервиса по порядку (не больше двух).
  pub fn queries(&self) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for a in self.artists.iter().take(2) {
      if let Some(t) = self.titles.first() {
        let q = format!("{} {t}", first_artist(a));
        if !out.contains(&q) {
          out.push(q);
        }
      }
    }
    out
  }

  /// Лучший доступный кандидат из выдачи или None.
  pub fn best<'a>(&self, cands: &'a [Track]) -> Option<&'a Track> {
    let mut best: Option<(&Track, f64)> = None;
    for c in cands.iter().filter(|c| c.available) {
      if let Some(score) = self.score(c) {
        if best.is_none_or(|b| score > b.1) {
          best = Some((c, score));
        }
      }
    }
    best.map(|b| b.0)
  }

  /// Похожесть названия (0.9…1.0), если кандидат — тот же трек; иначе None. Доступность не смотрит.
  pub fn score(&self, c: &Track) -> Option<f64> {
    if self.duration_ms > 0 && c.duration_ms > 0 && self.duration_ms.abs_diff(c.duration_ms) > MAX_DURATION_DIFF_MS {
      return None;
    }
    let wanted: HashSet<String> = self.artists.iter().flat_map(|a| artist_names(a).collect::<Vec<_>>()).collect();
    let theirs: HashSet<String> =
      c.artists.iter().map(|a| norm(&a.name)).chain(artist_names(&c.artist)).filter(|n| !n.is_empty()).collect();
    if theirs.is_disjoint(&wanted) || versions(&c.title) != self.versions {
      return None;
    }
    let found = norm(&clean_title(&c.title));
    let score = self.titles.iter().map(|t| similarity(&norm(t), &found)).fold(0.0, f64::max);
    (score >= MIN_TITLE).then_some(score)
  }
}

/// Один ли это трек (по сохранённым метаданным, без сети) — в любую сторону: перезалив
/// «АРТИСТ - ТРЕК» с SoundCloud совпадает с треком Яндекса и наоборот.
#[allow(dead_code)] // для импорта по ссылке (этап 5) и дублей (этап 7)
pub fn same_track(a: &Track, b: &Track) -> bool {
  a.ref_ == b.ref_ || Wanted::from_track(a).score(b).is_some() || Wanted::from_track(b).score(a).is_some()
}

/// Имена исполнителей, по которым `Wanted::score` может свести трек с другим (свои, из строки
/// исполнителя и из «АРТИСТ - ТРЕК»), нормализованные. Общее имя — необходимое условие совпадения:
/// по нему поиск дублей отбирает пары, не сравнивая всё со всем.
pub fn artist_keys(t: &Track, w: &Wanted) -> HashSet<String> {
  w.artists
    .iter()
    .flat_map(|a| artist_names(a).collect::<Vec<_>>())
    .chain(t.artists.iter().map(|a| norm(&a.name)))
    .chain(artist_names(&t.artist))
    .filter(|n| !n.is_empty())
    .collect()
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::providers::ArtistRef;

  fn ym(id: &str, artist: &str, title: &str, ms: u64) -> Track {
    Track {
      ref_: format!("ym:{id}"),
      title: title.into(),
      artist: artist.into(),
      artists: vec![ArtistRef { ref_: "yma:1".into(), name: artist.into(), avatar_url: None }],
      album: None,
      duration_ms: ms,
      cover_url: None,
      url: None,
      explicit: false,
      available: true,
      plays: None,
      tags: None,
    }
  }

  #[test]
  fn matches_same_track() {
    let w = Wanted::soundcloud("EsDeeKid", None, "4 Raws", 146_000);
    let c = vec![ym("1", "EsDeeKid", "4 Raws", 146_500)];
    assert_eq!(w.best(&c).map(|t| t.ref_.as_str()), Some("ym:1"));
  }

  #[test]
  fn rejects_other_duration_artist_and_versions() {
    let w = Wanted::soundcloud("EsDeeKid", None, "4 Raws", 146_000);
    let c = vec![
      ym("1", "EsDeeKid", "4 Raws", 160_000),
      ym("2", "Someone", "4 Raws", 146_000),
      ym("3", "EsDeeKid", "4 Raws (Sped Up)", 146_000),
    ];
    assert!(w.best(&c).is_none());
  }

  #[test]
  fn reupload_and_prod_tags() {
    let w = Wanted::soundcloud("random uploader", None, "Кизару - Дежавю (prod. x)", 180_000);
    assert!(w.queries()[0].starts_with("Кизару"));
    let c = vec![ym("7", "Kizaru, Другой", "Дежавю", 181_000), ym("8", "Кизару", "Дежавю", 181_000)];
    assert_eq!(w.best(&c).map(|t| t.ref_.as_str()), Some("ym:8"));
  }

  #[test]
  fn from_track_finds_twin_on_any_service() {
    let mut yt = ym("x", "EsDeeKid", "4 Raws", 146_000);
    yt.ref_ = "yt:abc".into();
    let w = Wanted::from_track(&yt);
    assert_eq!(w.queries(), vec!["EsDeeKid 4 Raws".to_string()]);
    let c = vec![ym("1", "EsDeeKid", "4 Raws (Live)", 146_000), ym("2", "EsDeeKid", "4 Raws", 147_000)];
    assert_eq!(w.best(&c).map(|t| t.ref_.as_str()), Some("ym:2"));
  }

  #[test]
  fn best_skips_unavailable_but_score_does_not() {
    let w = Wanted::new(["A"], "Song", 100_000);
    let mut gone = ym("1", "A", "Song", 100_000);
    gone.available = false;
    assert!(w.best(std::slice::from_ref(&gone)).is_none());
    assert!(w.score(&gone).is_some());
  }

  #[test]
  fn unknown_duration_is_not_checked() {
    let w = Wanted::new(["A"], "Song", 0);
    assert!(w.score(&ym("1", "A", "Song", 999_000)).is_some());
  }

  #[test]
  fn same_track_both_ways() {
    let mut sc = ym("1", "random uploader", "Кизару - Дежавю", 180_000);
    sc.ref_ = "sc:1".into();
    sc.artists = vec![];
    let y = ym("2", "Кизару", "Дежавю", 181_000);
    assert!(same_track(&sc, &y));
    assert!(same_track(&y, &sc));
    assert!(!same_track(&y, &ym("3", "Кизару", "Дежавю (Slowed)", 181_000)));
    assert!(!same_track(&y, &ym("4", "Кизару", "Дежавю", 200_000)));
  }

  #[test]
  fn keeps_remix_only_for_remix() {
    let w = Wanted::soundcloud("A", None, "Song (Remix)", 100_000);
    let c = vec![ym("1", "A", "Song", 100_000), ym("2", "A", "Song (Remix)", 100_000)];
    assert_eq!(w.best(&c).map(|t| t.ref_.as_str()), Some("ym:2"));
  }
}
