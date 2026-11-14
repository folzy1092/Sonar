//! lrclib.net — открытая база LRC без ключа. Порт `fetch` / `_pick` из selfbot.

use super::clean_title;
use anyhow::{bail, Result};
use serde::Deserialize;
use std::time::Duration;

const API_URL: &str = "https://lrclib.net/api";
const USER_AGENT: &str = "Sonar (https://github.com/folzy1092/Sonar)";
/// Насколько длительность в lrclib может отличаться от трека, секунд.
const DURATION_SLACK: f64 = 4.0;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Record {
  track_name: Option<String>,
  duration: Option<f64>,
  #[serde(default)]
  instrumental: bool,
  synced_lyrics: Option<String>,
  plain_lyrics: Option<String>,
}

#[derive(Debug, Default)]
pub struct Found {
  pub synced: Option<String>,
  pub plain: Option<String>,
}

fn fits(r: &Record, duration: f64) -> bool {
  duration <= 0.0 || r.duration.is_none_or(|d| (d - duration).abs() <= DURATION_SLACK)
}

/// Лучший результат: сначала с тем же названием (без «(prod. …)»), потом любой подходящий.
fn pick(results: &[Record], duration: f64, title: &str) -> Found {
  let wanted = clean_title(title).to_lowercase();
  let fitting: Vec<&Record> = results.iter().filter(|r| !r.instrumental && fits(r, duration)).collect();
  let same = |r: &&&Record| !wanted.is_empty() && clean_title(r.track_name.as_deref().unwrap_or("")).to_lowercase() == wanted;
  let has = |s: &Option<String>| s.as_deref().is_some_and(|t| !t.trim().is_empty());
  let synced = fitting
    .iter()
    .filter(|r| has(&r.synced_lyrics))
    .find(same)
    .or_else(|| fitting.iter().find(|r| has(&r.synced_lyrics)))
    .and_then(|r| r.synced_lyrics.clone());
  let plain = fitting
    .iter()
    .filter(|r| has(&r.plain_lyrics))
    .find(same)
    .or_else(|| fitting.iter().find(|r| has(&r.plain_lyrics)))
    .and_then(|r| r.plain_lyrics.clone());
  Found { synced, plain }
}

async fn get_json<T: for<'de> Deserialize<'de>>(http: &reqwest::Client, path: &str, query: &[(&str, String)]) -> Result<Option<T>> {
  let r = http
    .get(format!("{API_URL}/{path}"))
    .query(query)
    .header("User-Agent", USER_AGENT)
    .timeout(Duration::from_secs(10))
    .send()
    .await?;
  let status = r.status();
  if status.as_u16() == 404 {
    return Ok(None);
  }
  if !status.is_success() {
    bail!("lrclib {path}: HTTP {status}");
  }
  Ok(Some(r.json().await?))
}

/// Поиск по исполнителю и названию: `/get` (точно, с длительностью), потом `/search`.
/// Синхронный текст важнее: plain запоминается, но поиск synced идёт дальше.
pub async fn fetch(http: &reqwest::Client, artist: &str, title: &str, duration: f64) -> Result<Found> {
  let mut best = Found::default();
  for name in super::artist_variants(artist) {
    let mut q = vec![("artist_name", name.clone()), ("track_name", title.to_string())];
    if duration > 0.0 {
      q.push(("duration", (duration.round() as i64).to_string()));
    }
    // 5xx на /get — не сбой: lrclib не дождался внешних источников. Дальше спрашиваем /search.
    if let Ok(Some(r)) = get_json::<Record>(http, "get", &q).await {
      let f = pick(std::slice::from_ref(&r), duration, title);
      if f.synced.is_some() {
        return Ok(f);
      }
      best.plain = best.plain.or(f.plain);
    }
    let mut titles = vec![title.to_string()];
    let clean = clean_title(title);
    if !clean.is_empty() && clean != title {
      titles.push(clean);
    }
    for t in titles {
      let found = get_json::<Vec<Record>>(http, "search", &[("artist_name", name.clone()), ("track_name", t)]).await?;
      let f = pick(&found.unwrap_or_default(), duration, title);
      if f.synced.is_some() {
        return Ok(f);
      }
      best.plain = best.plain.or(f.plain);
    }
  }
  Ok(best)
}

#[cfg(test)]
mod tests {
  use super::*;

  fn rec(name: &str, d: f64, synced: Option<&str>, plain: Option<&str>) -> Record {
    Record { track_name: Some(name.into()), duration: Some(d), instrumental: false, synced_lyrics: synced.map(Into::into), plain_lyrics: plain.map(Into::into) }
  }

  #[test]
  fn pick_prefers_same_title_and_duration() {
    let rs = vec![
      rec("gates (altered)", 120.0, Some("[00:01.00]alt"), None),
      rec("gates", 121.0, Some("[00:01.00]orig"), None),
      rec("gates", 200.0, Some("[00:01.00]long"), None),
    ];
    let f = pick(&rs, 120.0, "gates (prod. x)");
    assert_eq!(f.synced.as_deref(), Some("[00:01.00]orig"));
  }

  #[test]
  fn pick_keeps_plain_when_no_synced() {
    let rs = vec![rec("a", 100.0, None, Some("слова"))];
    let f = pick(&rs, 100.0, "a");
    assert!(f.synced.is_none());
    assert_eq!(f.plain.as_deref(), Some("слова"));
  }

  #[tokio::test]
  #[ignore = "живой запрос к lrclib"]
  async fn live_lrclib() {
    let http = reqwest::Client::new();
    let f = fetch(&http, "Coldplay", "Yellow", 269.0).await.unwrap();
    assert!(f.synced.is_some());
  }
}
