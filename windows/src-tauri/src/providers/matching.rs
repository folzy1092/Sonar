//! Тот же трек на другом сервисе: трек SoundCloud → Яндекс Музыка, чтобы играть его в FLAC / 320
//! (без Go+ SoundCloud отдаёт максимум AAC 160). Правила строгие — лучше сыграть SoundCloud, чем
//! чужую версию: длительность ±3 с, исполнитель совпадает, название почти одинаковое, а «версии»
//! (remix, live, sped up, slowed…) должны совпадать с обеих сторон.

use super::Track;
use crate::lyrics::{clean_title, first_artist, keyword_title, norm, reupload_variant, similarity};
use regex::Regex;
use std::collections::HashSet;
use std::sync::LazyLock;

const MAX_DURATION_DIFF_MS: u64 = 3000;
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
  /// `uploader` — ник залившего на SoundCloud, `meta_artist` — `publisher_metadata.artist`.
  pub fn soundcloud(uploader: &str, meta_artist: Option<&str>, title: &str, duration_ms: u64) -> Self {
    let mut artists = Vec::new();
    let mut titles = Vec::new();
    if let Some((a, t)) = reupload_variant(title) {
      artists.push(a);
      titles.push(clean_title(&t));
    }
    for a in [meta_artist.unwrap_or(""), uploader] {
      if !a.trim().is_empty() {
        artists.push(a.to_string());
      }
    }
    let (_, core, feats) = keyword_title(title);
    for t in [clean_title(title), core] {
      if !t.is_empty() && !titles.contains(&t) {
        titles.push(t);
      }
    }
    artists.extend(feats);
    Self { artists, titles, duration_ms, versions: versions(title) }
  }

  /// Запросы к поиску Яндекса по порядку.
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

  /// Лучший кандидат из выдачи или None. Возвращает ref (`ym:<id>`).
  pub fn best<'a>(&self, cands: &'a [Track]) -> Option<&'a Track> {
    let wanted_artists: HashSet<String> = self.artists.iter().flat_map(|a| artist_names(a).collect::<Vec<_>>()).collect();
    let mut best: Option<(&Track, f64)> = None;
    for c in cands {
      if !c.available {
        continue;
      }
      if self.duration_ms > 0 && c.duration_ms > 0 && self.duration_ms.abs_diff(c.duration_ms) > MAX_DURATION_DIFF_MS {
        continue;
      }
      let theirs: HashSet<String> =
        c.artists.iter().map(|a| norm(&a.name)).chain(artist_names(&c.artist)).filter(|n| !n.is_empty()).collect();
      if theirs.is_disjoint(&wanted_artists) {
        continue;
      }
      if versions(&c.title) != self.versions {
        continue;
      }
      let found = norm(&clean_title(&c.title));
      let score = self.titles.iter().map(|t| similarity(&norm(t), &found)).fold(0.0, f64::max);
      if score >= MIN_TITLE && best.is_none_or(|b| score > b.1) {
        best = Some((c, score));
      }
    }
    best.map(|b| b.0)
  }
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
  fn keeps_remix_only_for_remix() {
    let w = Wanted::soundcloud("A", None, "Song (Remix)", 100_000);
    let c = vec![ym("1", "A", "Song", 100_000), ym("2", "A", "Song (Remix)", 100_000)];
    assert_eq!(w.best(&c).map(|t| t.ref_.as_str()), Some("ym:2"));
  }
}
