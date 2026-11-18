//! Правила умного плейлиста и движок, который по ним отбирает треки. Чистая логика без базы:
//! на вход — кандидаты из источника и история прослушиваний, на выход — готовый список.
//! JSON правил общий для ПК и iPhone — описан в docs/PLATFORMS.md «Умные плейлисты».

use crate::providers::registry::{parse_ref, service_of, RefKind};
use crate::providers::Track;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

pub const DAY: i64 = 86_400_000;
/// Версия схемы правил: другая — плейлист показывается с ошибкой, а не считается наугад.
pub const RULES_VERSION: u32 = 1;
pub const MAX_DAYS: u32 = 3650;
pub const MAX_LIMIT: u32 = 1000;
pub const MAX_CONDITIONS: usize = 20;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Rules {
  pub v: u32,
  pub source: Source,
  #[serde(rename = "match", default)]
  pub match_: Match,
  #[serde(default)]
  pub conditions: Vec<Condition>,
  #[serde(default)]
  pub sort: Option<Sort>,
  #[serde(default)]
  pub limit: Option<u32>,
}

/// Откуда берутся треки: Любимые, свой плейлист или всё, что слушал.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum Source {
  Liked,
  Playlist { id: String },
  Played,
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Match {
  #[default]
  All,
  Any,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Cmp {
  Gte,
  Lte,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum When {
  Before,
  After,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Is {
  Is,
  Not,
}

/// Одно условие. `days` = 0 или нет — за всё время.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "field", rename_all = "snake_case")]
pub enum Condition {
  /// Прослушиваний за последние `days` дней больше/меньше `value` (включительно).
  Plays {
    #[serde(default)]
    days: Option<u32>,
    op: Cmp,
    value: u32,
  },
  /// Последнее прослушивание раньше/позже, чем `days` дней назад. Ни разу не слушал — «раньше».
  LastPlayed { op: When, days: u32 },
  /// Добавлен за последние `days` дней (в Любимые, в плейлист; для «всё прослушанное» — первое прослушивание).
  Added { days: u32 },
  /// Сервис трека по префиксу ref (`sc`, `ym`, …).
  Service { op: Is, value: String },
  /// Исполнитель: вхождение без учёта регистра в строку артиста или имя любого из артистов.
  Artist { op: Is, value: String },
  /// Длительность в секундах больше/меньше `value` (включительно).
  Duration { op: Cmp, value: u32 },
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum SortBy {
  Plays,
  LastPlayed,
  Added,
  Title,
  Artist,
  Duration,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Sort {
  pub by: SortBy,
  /// Для `plays`: окно в днях (0 или нет — за всё время).
  #[serde(default)]
  pub days: Option<u32>,
  #[serde(default = "yes")]
  pub desc: bool,
}

fn yes() -> bool {
  true
}

/// Трек-кандидат из источника: сам трек и когда он туда попал.
#[derive(Debug, Clone, PartialEq)]
pub struct Candidate {
  pub track: Track,
  pub added_at: i64,
}

/// История прослушиваний: ref → моменты прослушиваний (мс), по возрастанию.
#[derive(Debug, Default, Clone)]
pub struct History(HashMap<String, Vec<i64>>);

impl History {
  pub fn from_rows(rows: impl IntoIterator<Item = (String, i64)>) -> Self {
    let mut map: HashMap<String, Vec<i64>> = HashMap::new();
    for (r, at) in rows {
      map.entry(r).or_default().push(at);
    }
    for list in map.values_mut() {
      list.sort_unstable();
    }
    Self(map)
  }

  /// Прослушиваний с момента `since` (включительно); `None` — за всё время.
  pub fn count(&self, r: &str, since: Option<i64>) -> usize {
    let Some(list) = self.0.get(r) else { return 0 };
    match since {
      None => list.len(),
      Some(from) => list.len() - list.partition_point(|&t| t < from),
    }
  }

  pub fn last(&self, r: &str) -> Option<i64> {
    self.0.get(r).and_then(|l| l.last().copied())
  }

  /// Все прослушанные ref: (ref, первое, последнее прослушивание).
  pub fn refs(&self) -> impl Iterator<Item = (&str, i64, i64)> {
    self.0.iter().filter_map(|(r, l)| Some((r.as_str(), *l.first()?, *l.last()?)))
  }
}

impl Rules {
  /// Проверка перед сохранением: понятная причина вместо молча пустого плейлиста. Причина — ключ строки
  /// для `t()` на клиенте, те же, что у `rulesProblem` в lib/smart.ts.
  pub fn validate(&self) -> Result<(), String> {
    if self.v != RULES_VERSION {
      return Err("Правила из новой версии Sonar".into());
    }
    if let Source::Playlist { id } = &self.source {
      if id.trim().is_empty() {
        return Err("Выбери плейлист".into());
      }
    }
    if self.conditions.len() > MAX_CONDITIONS {
      return Err("Слишком много условий".into());
    }
    for c in &self.conditions {
      match c {
        Condition::Service { value, .. } if !is_service(value) => return Err("Выбери сервис".into()),
        Condition::Artist { value, .. } if value.trim().is_empty() => return Err("Впиши исполнителя".into()),
        _ => {}
      }
    }
    Ok(())
  }

  fn limit(&self) -> Option<usize> {
    self.limit.map(|l| l.clamp(1, MAX_LIMIT) as usize)
  }
}

/// Id сервиса из реестра (`sc`, `ym`, …) — это префикс его трека.
fn is_service(id: &str) -> bool {
  matches!(parse_ref(&format!("{}:x", id.trim())), Some((_, RefKind::Track)))
}

/// Начало окна в `days` дней от `now`; 0 или нет — без окна.
fn since(now: i64, days: Option<u32>) -> Option<i64> {
  days.filter(|d| *d > 0).map(|d| now - i64::from(d.min(MAX_DAYS)) * DAY)
}

fn service_str(r: &str) -> Option<&'static str> {
  service_of(r).map(|s| s.as_str())
}

fn artist_matches(t: &Track, needle: &str) -> bool {
  let needle = needle.trim().to_lowercase();
  t.artist.to_lowercase().contains(&needle) || t.artists.iter().any(|a| a.name.to_lowercase().contains(&needle))
}

fn compare(op: Cmp, left: u64, right: u64) -> bool {
  match op {
    Cmp::Gte => left >= right,
    Cmp::Lte => left <= right,
  }
}

fn check(c: &Condition, cand: &Candidate, history: &History, now: i64) -> bool {
  let r = cand.track.ref_.as_str();
  match c {
    Condition::Plays { days, op, value } => compare(*op, history.count(r, since(now, *days)) as u64, u64::from(*value)),
    Condition::LastPlayed { op, days } => {
      let edge = now - i64::from((*days).min(MAX_DAYS)) * DAY;
      match (op, history.last(r)) {
        (When::Before, None) => true,
        (When::Before, Some(at)) => at < edge,
        (When::After, None) => false,
        (When::After, Some(at)) => at >= edge,
      }
    }
    Condition::Added { days } => since(now, Some(*days)).is_none_or(|from| cand.added_at >= from),
    Condition::Service { op, value } => (service_str(r) == Some(value.trim())) == (*op == Is::Is),
    Condition::Artist { op, value } => artist_matches(&cand.track, value) == (*op == Is::Is),
    Condition::Duration { op, value } => compare(*op, cand.track.duration_ms / 1000, u64::from(*value)),
  }
}

fn passes(rules: &Rules, cand: &Candidate, history: &History, now: i64) -> bool {
  if rules.conditions.is_empty() {
    return true;
  }
  let mut results = rules.conditions.iter().map(|c| check(c, cand, history, now));
  match rules.match_ {
    Match::All => results.all(|ok| ok),
    Match::Any => results.any(|ok| ok),
  }
}

/// Ключ сортировки: число (счёт, время, длительность) или текст (название, артист).
fn sort_key(c: &Candidate, by: SortBy, history: &History, from: Option<i64>) -> (i64, String) {
  match by {
    SortBy::Plays => (history.count(&c.track.ref_, from) as i64, String::new()),
    SortBy::LastPlayed => (history.last(&c.track.ref_).unwrap_or(i64::MIN), String::new()),
    SortBy::Added => (c.added_at, String::new()),
    SortBy::Title => (0, c.track.title.to_lowercase()),
    SortBy::Artist => (0, c.track.artist.to_lowercase()),
    SortBy::Duration => (c.track.duration_ms as i64, String::new()),
  }
}

/// Устойчивая сортировка: при равенстве ключей остаётся порядок источника (и при убывании тоже).
fn sort_stable(list: Vec<Candidate>, sort: &Sort, history: &History, now: i64) -> Vec<Candidate> {
  let from = since(now, sort.days);
  let mut keyed: Vec<((i64, String), Candidate)> =
    list.into_iter().map(|c| (sort_key(&c, sort.by, history, from), c)).collect();
  keyed.sort_by(|a, b| if sort.desc { b.0.cmp(&a.0) } else { a.0.cmp(&b.0) });
  keyed.into_iter().map(|(_, c)| c).collect()
}

/// Отобрать треки по правилам: фильтр → сортировка → лимит. Повторы ref схлопываются (первый остаётся).
pub fn evaluate(rules: &Rules, candidates: Vec<Candidate>, history: &History, now: i64) -> Vec<Candidate> {
  let mut seen = std::collections::HashSet::new();
  let list: Vec<Candidate> = candidates
    .into_iter()
    .filter(|c| seen.insert(c.track.ref_.clone()))
    .filter(|c| passes(rules, c, history, now))
    .collect();
  let mut list = match &rules.sort {
    Some(s) => sort_stable(list, s, history, now),
    None => list,
  };
  if let Some(n) = rules.limit() {
    list.truncate(n);
  }
  list
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::providers::ArtistRef;

  const NOW: i64 = 1_000 * DAY;

  fn track(r: &str, artist: &str, secs: u64) -> Track {
    Track {
      ref_: r.into(),
      title: format!("T {r}"),
      artist: artist.into(),
      artists: vec![ArtistRef { ref_: format!("sca:{artist}"), name: artist.into(), avatar_url: None }],
      album: None,
      duration_ms: secs * 1000,
      cover_url: None,
      url: None,
      explicit: false,
      available: true,
      plays: None,
      tags: None,
    }
  }

  fn cand(r: &str, added_days_ago: i64) -> Candidate {
    Candidate { track: track(r, "Artist", 200), added_at: NOW - added_days_ago * DAY }
  }

  fn rules(json: &str) -> Rules {
    serde_json::from_str(json).expect("правила разбираются")
  }

  fn refs(list: &[Candidate]) -> Vec<&str> {
    list.iter().map(|c| c.track.ref_.as_str()).collect()
  }

  fn history(rows: &[(&str, i64)]) -> History {
    History::from_rows(rows.iter().map(|(r, days_ago)| (r.to_string(), NOW - days_ago * DAY)))
  }

  #[test]
  fn long_unplayed_takes_old_and_never_played() {
    let r = rules(r#"{"v":1,"source":{"kind":"liked"},"conditions":[{"field":"last_played","op":"before","days":60}]}"#);
    let h = history(&[("sc:1", 5), ("sc:2", 90), ("sc:2", 70)]);
    let out = evaluate(&r, vec![cand("sc:1", 1), cand("sc:2", 2), cand("sc:3", 3)], &h, NOW);
    assert_eq!(refs(&out), ["sc:2", "sc:3"]);
  }

  #[test]
  fn plays_window_counts_only_recent() {
    let r = rules(r#"{"v":1,"source":{"kind":"played"},"conditions":[{"field":"plays","days":30,"op":"gte","value":2}]}"#);
    let h = history(&[("sc:1", 1), ("sc:1", 2), ("sc:2", 1), ("sc:2", 40), ("sc:2", 50)]);
    let out = evaluate(&r, vec![cand("sc:1", 0), cand("sc:2", 0)], &h, NOW);
    assert_eq!(refs(&out), ["sc:1"]);
  }

  #[test]
  fn plays_all_time_lte() {
    let r = rules(r#"{"v":1,"source":{"kind":"liked"},"conditions":[{"field":"plays","op":"lte","value":2}]}"#);
    let h = history(&[("sc:1", 400), ("sc:1", 300), ("sc:1", 200), ("sc:2", 1)]);
    let out = evaluate(&r, vec![cand("sc:1", 0), cand("sc:2", 0), cand("sc:3", 0)], &h, NOW);
    assert_eq!(refs(&out), ["sc:2", "sc:3"]);
  }

  #[test]
  fn added_service_artist_duration() {
    let mut c = vec![cand("sc:1", 3), cand("ym:2", 3), cand("sc:3", 30)];
    c[1].track = track("ym:2", "Other Band", 100);
    let h = History::default();
    let added = rules(r#"{"v":1,"source":{"kind":"liked"},"conditions":[{"field":"added","days":14}]}"#);
    assert_eq!(refs(&evaluate(&added, c.clone(), &h, NOW)), ["sc:1", "ym:2"]);
    let svc = rules(r#"{"v":1,"source":{"kind":"liked"},"conditions":[{"field":"service","op":"is","value":"ym"}]}"#);
    assert_eq!(refs(&evaluate(&svc, c.clone(), &h, NOW)), ["ym:2"]);
    let not_artist = rules(r#"{"v":1,"source":{"kind":"liked"},"conditions":[{"field":"artist","op":"not","value":"other"}]}"#);
    assert_eq!(refs(&evaluate(&not_artist, c.clone(), &h, NOW)), ["sc:1", "sc:3"]);
    let short = rules(r#"{"v":1,"source":{"kind":"liked"},"conditions":[{"field":"duration","op":"lte","value":150}]}"#);
    assert_eq!(refs(&evaluate(&short, c, &h, NOW)), ["ym:2"]);
  }

  #[test]
  fn match_any_joins_conditions() {
    let r = rules(
      r#"{"v":1,"source":{"kind":"liked"},"match":"any","conditions":[
        {"field":"service","op":"is","value":"ym"},{"field":"added","days":7}]}"#,
    );
    let out = evaluate(&r, vec![cand("sc:1", 3), cand("ym:2", 30), cand("sc:3", 30)], &History::default(), NOW);
    assert_eq!(refs(&out), ["sc:1", "ym:2"]);
  }

  #[test]
  fn sort_desc_is_stable_and_limit_cuts() {
    let r = rules(r#"{"v":1,"source":{"kind":"played"},"sort":{"by":"plays","days":30,"desc":true},"limit":2}"#);
    let h = history(&[("sc:1", 1), ("sc:2", 1), ("sc:2", 2), ("sc:3", 1)]);
    let out = evaluate(&r, vec![cand("sc:1", 0), cand("sc:2", 0), cand("sc:3", 0)], &h, NOW);
    assert_eq!(refs(&out), ["sc:2", "sc:1"]);
  }

  #[test]
  fn sort_by_last_played_puts_never_played_first() {
    let r = rules(r#"{"v":1,"source":{"kind":"liked"},"sort":{"by":"last_played","desc":false}}"#);
    let h = history(&[("sc:1", 5), ("sc:2", 90)]);
    let out = evaluate(&r, vec![cand("sc:1", 0), cand("sc:2", 0), cand("sc:3", 0)], &h, NOW);
    assert_eq!(refs(&out), ["sc:3", "sc:2", "sc:1"]);
  }

  #[test]
  fn duplicates_collapse_to_first() {
    let r = rules(r#"{"v":1,"source":{"kind":"playlist","id":"pl_1"}}"#);
    let out = evaluate(&r, vec![cand("sc:1", 1), cand("sc:1", 9)], &History::default(), NOW);
    assert_eq!(out.len(), 1);
    assert_eq!(out[0].added_at, NOW - DAY);
  }

  #[test]
  fn validate_rejects_bad_rules() {
    assert!(rules(r#"{"v":1,"source":{"kind":"liked"}}"#).validate().is_ok());
    let err = |json: &str| rules(json).validate().unwrap_err();
    assert_eq!(err(r#"{"v":2,"source":{"kind":"liked"}}"#), "Правила из новой версии Sonar");
    assert_eq!(err(r#"{"v":1,"source":{"kind":"playlist","id":" "}}"#), "Выбери плейлист");
    for bad in ["zz", "sca", ""] {
      let svc = format!(r#"{{"v":1,"source":{{"kind":"liked"}},"conditions":[{{"field":"service","op":"is","value":"{bad}"}}]}}"#);
      assert_eq!(err(&svc), "Выбери сервис", "{bad}");
    }
    let artist = r#"{"v":1,"source":{"kind":"liked"},"conditions":[{"field":"artist","op":"is","value":""}]}"#;
    assert_eq!(err(artist), "Впиши исполнителя");
    let many = format!(
      r#"{{"v":1,"source":{{"kind":"liked"}},"conditions":[{}]}}"#,
      vec![r#"{"field":"added","days":1}"#; MAX_CONDITIONS + 1].join(",")
    );
    assert_eq!(err(&many), "Слишком много условий");
    let unknown = r#"{"v":1,"source":{"kind":"liked"},"conditions":[{"field":"mood","value":1}]}"#;
    assert!(serde_json::from_str::<Rules>(unknown).is_err());
  }

  #[test]
  fn limit_is_clamped() {
    let r = rules(r#"{"v":1,"source":{"kind":"liked"},"limit":0}"#);
    assert_eq!(evaluate(&r, vec![cand("sc:1", 0), cand("sc:2", 0)], &History::default(), NOW).len(), 1);
  }
}
