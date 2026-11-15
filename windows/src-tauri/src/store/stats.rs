//! Статистика из локальной таблицы `plays` (SPEC §3.8, pc/Screenshot_32). Формат — `Stats` из
//! docs/API.md §5 (`GET /stats`) плюс поля экрана «Статистика»: на сервере считается так же.

use super::{now_ms, Store, LOCAL_USER};
use anyhow::Result;
use rusqlite::params;
use serde::Serialize;
use std::collections::{HashMap, HashSet};

const HOUR: i64 = 3600 * 1000;
const DAY: i64 = 24 * HOUR;
const WEEKDAYS: [&str; 7] = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"];
const MONTHS: [&str; 12] = ["янв", "фев", "мар", "апр", "май", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"];

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Bucket {
  pub label: String,
  pub value_ms: i64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ArtistStat {
  pub name: String,
  pub avatar_url: Option<String>,
  #[serde(rename = "ref")]
  pub ref_: Option<String>,
  pub ms: i64,
  pub plays: i64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct TrackStat {
  #[serde(rename = "ref")]
  pub ref_: String,
  pub title: String,
  pub artist: String,
  pub cover_url: Option<String>,
  pub plays: i64,
  pub ms: i64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Stats {
  pub period: String,
  pub total_ms: i64,
  /// Изменение времени к прошлому такому же периоду, % (None — сравнивать не с чем).
  pub delta_pct: Option<i64>,
  pub buckets: Vec<Bucket>,
  pub top_artist: Option<ArtistStat>,
  pub more_artists: Vec<ArtistStat>,
  pub top_tracks: Vec<TrackStat>,
  /// Прослушиваний, разных треков, разных артистов.
  pub plays: i64,
  pub tracks: i64,
  pub artists: i64,
  /// Дней подряд со слушанием (по сегодня или вчера) — за всё время.
  pub streak_days: i64,
  /// Час, когда слушаешь больше всего (0–23, местное время).
  pub peak_hour: Option<u32>,
  /// Треков в день (в среднем по дням, когда слушал).
  pub per_day: i64,
  /// Любимый день недели: 0 — пн … 6 — вс.
  pub fav_weekday: Option<u32>,
}

struct Row {
  ref_: String,
  artist: String,
  played_at: i64,
  listened_ms: i64,
}

/// Начало периода (мс) и шаг корзин графика.
fn period_start(period: &str, now: i64) -> Option<i64> {
  match period {
    "day" => Some(now - DAY),
    "week" => Some(now - 7 * DAY),
    "month" => Some(now - 30 * DAY),
    "half_year" => Some(now - 182 * DAY),
    "year" => Some(now - 365 * DAY),
    _ => None,
  }
}

/// Дни от эпохи в местном времени (смещение — минуты к UTC, как `-getTimezoneOffset()`).
fn local_day(ts: i64, tz_min: i64) -> i64 {
  (ts + tz_min * 60_000).div_euclid(DAY)
}

/// 1970-01-01 — четверг; 0 = пн.
fn weekday(day: i64) -> u32 {
  ((day + 3).rem_euclid(7)) as u32
}

/// Гражданская дата по дню от эпохи (алгоритм Howard Hinnant) — нужен только месяц и год.
fn year_month(day: i64) -> (i64, u32) {
  let z = day + 719_468;
  let era = z.div_euclid(146_097);
  let doe = z - era * 146_097;
  let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  let mp = (5 * doy + 2) / 153;
  let m = (if mp < 10 { mp + 3 } else { mp - 9 }) as u32;
  let y = yoe + era * 400 + if m <= 2 { 1 } else { 0 };
  (y, m)
}

fn buckets(period: &str, rows: &[Row], now: i64, tz: i64) -> Vec<Bucket> {
  let today = local_day(now, tz);
  match period {
    "day" => {
      let mut v = vec![0i64; 24];
      for r in rows {
        let h = ((r.played_at + tz * 60_000).rem_euclid(DAY) / HOUR) as usize;
        v[h] += r.listened_ms;
      }
      v.into_iter().enumerate().map(|(h, ms)| Bucket { label: format!("{h}"), value_ms: ms }).collect()
    }
    "week" | "month" => {
      let n = if period == "week" { 7 } else { 30 };
      let mut v = vec![0i64; n];
      for r in rows {
        let back = today - local_day(r.played_at, tz);
        if (0..n as i64).contains(&back) {
          v[n - 1 - back as usize] += r.listened_ms;
        }
      }
      v.into_iter()
        .enumerate()
        .map(|(i, ms)| {
          let d = today - (n as i64 - 1 - i as i64);
          let label = if period == "week" { WEEKDAYS[weekday(d) as usize].to_owned() } else { format!("{}", d - today) };
          Bucket { label, value_ms: ms }
        })
        .collect()
    }
    _ => {
      // по месяцам: полгода — 6, год — 12, всё время — до 24 последних
      let n = match period {
        "half_year" => 6,
        "year" => 12,
        _ => 24,
      };
      let (cy, cm) = year_month(today);
      let idx = |y: i64, m: u32| y * 12 + m as i64 - 1;
      let cur = idx(cy, cm);
      let mut v = vec![0i64; n];
      for r in rows {
        let (y, m) = year_month(local_day(r.played_at, tz));
        let back = cur - idx(y, m);
        if (0..n as i64).contains(&back) {
          v[n - 1 - back as usize] += r.listened_ms;
        }
      }
      let mut out: Vec<Bucket> = v
        .into_iter()
        .enumerate()
        .map(|(i, ms)| {
          let k = cur - (n as i64 - 1 - i as i64);
          Bucket { label: MONTHS[k.rem_euclid(12) as usize].to_owned(), value_ms: ms }
        })
        .collect();
      if period == "all" {
        // всё время: без пустых месяцев в начале
        // всё время: без пустых месяцев в начале, но не меньше полугода — график читается
        let first = out.iter().position(|b| b.value_ms > 0).unwrap_or(out.len()).min(out.len().saturating_sub(6));
        out.drain(..first);
      }
      out
    }
  }
}

/// Дни подряд со слушанием, заканчивая сегодня (или вчера — сегодня ещё не слушал).
fn streak(days: &HashSet<i64>, today: i64) -> i64 {
  let mut d = if days.contains(&today) { today } else { today - 1 };
  let mut n = 0;
  while days.contains(&d) {
    n += 1;
    d -= 1;
  }
  n
}

impl Store {
  fn play_rows(&self, from: Option<i64>, to: i64) -> Result<Vec<Row>> {
    let mut st = self.db.prepare(
      "SELECT ref, artist, played_at, listened_ms FROM plays
       WHERE user_id = ?1 AND played_at >= ?2 AND played_at < ?3 ORDER BY played_at",
    )?;
    let rows = st.query_map(params![LOCAL_USER, from.unwrap_or(0), to], |r| {
      Ok(Row { ref_: r.get(0)?, artist: r.get(1)?, played_at: r.get(2)?, listened_ms: r.get(3)? })
    })?;
    Ok(rows.collect::<rusqlite::Result<_>>()?)
  }

  /// Статистика за период (`day` / `week` / `month` / `half_year` / `year` / `all`).
  pub fn stats(&self, period: &str, tz_min: i64) -> Result<Stats> {
    let now = now_ms();
    let from = period_start(period, now);
    let rows = self.play_rows(from, now + 1)?;
    let total_ms: i64 = rows.iter().map(|r| r.listened_ms).sum();

    let delta_pct = match from {
      Some(f) => {
        let prev: i64 = self.play_rows(Some(f - (now - f)), f)?.iter().map(|r| r.listened_ms).sum();
        (prev > 0).then(|| ((total_ms - prev) as f64 / prev as f64 * 100.0).round() as i64)
      }
      None => None,
    };

    // артисты и треки
    let mut by_artist: HashMap<String, (String, i64, i64)> = HashMap::new();
    let mut by_track: HashMap<String, (i64, i64)> = HashMap::new();
    let mut hours = [0i64; 24];
    let mut weekdays = [0i64; 7];
    let mut days = HashSet::new();
    for r in &rows {
      let e = by_artist.entry(r.artist.to_lowercase()).or_insert_with(|| (r.artist.clone(), 0, 0));
      e.1 += r.listened_ms;
      e.2 += 1;
      let t = by_track.entry(r.ref_.clone()).or_insert((0, 0));
      t.0 += 1;
      t.1 += r.listened_ms;
      hours[((r.played_at + tz_min * 60_000).rem_euclid(DAY) / HOUR) as usize] += 1;
      let d = local_day(r.played_at, tz_min);
      weekdays[weekday(d) as usize] += 1;
      days.insert(d);
    }

    let mut artists: Vec<(String, i64, i64)> = by_artist.into_values().collect();
    artists.sort_by(|a, b| b.1.cmp(&a.1).then(b.2.cmp(&a.2)));
    let mut tracks: Vec<(String, i64, i64)> = by_track.into_iter().map(|(r, (n, ms))| (r, n, ms)).collect();
    tracks.sort_by(|a, b| b.1.cmp(&a.1).then(b.2.cmp(&a.2)));
    tracks.truncate(10);

    let cached = self.tracks(&tracks.iter().map(|t| t.0.clone()).collect::<Vec<_>>())?;
    let by_ref: HashMap<&str, &crate::providers::Track> = cached.iter().map(|t| (t.ref_.as_str(), t)).collect();
    let top_tracks = tracks
      .iter()
      .filter_map(|(r, n, ms)| {
        let t = by_ref.get(r.as_str())?;
        Some(TrackStat { ref_: r.clone(), title: t.title.clone(), artist: t.artist.clone(), cover_url: t.cover_url.clone(), plays: *n, ms: *ms })
      })
      .collect();

    let mut artist_stats: Vec<ArtistStat> = artists
      .iter()
      .take(9)
      .map(|(name, ms, n)| {
        let (r, avatar) = self.artist_face(name).unwrap_or((None, None));
        ArtistStat { name: name.clone(), avatar_url: avatar, ref_: r, ms: *ms, plays: *n }
      })
      .collect();
    let top_artist = if artist_stats.is_empty() { None } else { Some(artist_stats.remove(0)) };

    // за всё время — для серии дней
    let all_days: HashSet<i64> = if from.is_none() {
      days.clone()
    } else {
      self.play_rows(None, now + 1)?.iter().map(|r| local_day(r.played_at, tz_min)).collect()
    };
    let peak_hour = hours.iter().enumerate().max_by_key(|(_, n)| **n).filter(|(_, n)| **n > 0).map(|(h, _)| h as u32);
    let fav_weekday = weekdays.iter().enumerate().max_by_key(|(_, n)| **n).filter(|(_, n)| **n > 0).map(|(d, _)| d as u32);

    Ok(Stats {
      period: period.to_owned(),
      total_ms,
      delta_pct,
      buckets: buckets(period, &rows, now, tz_min),
      top_artist,
      more_artists: artist_stats,
      top_tracks,
      plays: rows.len() as i64,
      tracks: rows.iter().map(|r| &r.ref_).collect::<HashSet<_>>().len() as i64,
      artists: artists.len() as i64,
      streak_days: streak(&all_days, local_day(now, tz_min)),
      peak_hour,
      per_day: if days.is_empty() { 0 } else { (rows.len() as f64 / days.len() as f64).round() as i64 },
      fav_weekday,
    })
  }

  /// ref и аватар артиста по имени — из кэша треков (artists_json).
  fn artist_face(&self, name: &str) -> Result<(Option<String>, Option<String>)> {
    let mut st = self.db.prepare("SELECT artists_json FROM tracks WHERE artist = ?1 COLLATE NOCASE AND artists_json IS NOT NULL LIMIT 20")?;
    let rows = st.query_map([name], |r| r.get::<_, String>(0))?;
    let mut found: (Option<String>, Option<String>) = (None, None);
    for json in rows.flatten() {
      let Ok(list) = serde_json::from_str::<Vec<crate::providers::ArtistRef>>(&json) else { continue };
      if let Some(a) = list.iter().find(|a| a.name.eq_ignore_ascii_case(name)).or(list.first()) {
        found.0.get_or_insert_with(|| a.ref_.clone());
        if a.avatar_url.is_some() {
          return Ok((found.0, a.avatar_url.clone()));
        }
      }
    }
    Ok(found)
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::store::Play;

  #[test]
  fn calendar() {
    assert_eq!(weekday(0), 3); // 1970-01-01 — четверг
    assert_eq!(year_month(0), (1970, 1));
    assert_eq!(year_month(20_454), (2026, 1)); // 2026-01-01
    assert_eq!(year_month(20_772), (2026, 11)); // 2026-11-15
  }

  #[test]
  fn streak_counts_back_from_today() {
    let days: HashSet<i64> = [10, 9, 8, 6].into_iter().collect();
    assert_eq!(streak(&days, 10), 3);
    assert_eq!(streak(&days, 11), 3);
    assert_eq!(streak(&days, 12), 0);
  }

  #[test]
  fn stats_from_plays() {
    let mut s = Store::memory().unwrap();
    let now = now_ms();
    let t = |r: &str, a: &str| crate::providers::Track {
      ref_: r.into(),
      title: format!("T{r}"),
      artist: a.into(),
      artists: vec![],
      album: None,
      duration_ms: 200_000,
      cover_url: None,
      url: None,
      explicit: false,
      available: true,
      plays: None,
      tags: None,
    };
    s.upsert_tracks(&[t("sc:1", "A"), t("sc:2", "B")]).unwrap();
    for (i, (r, a)) in [("sc:1", "A"), ("sc:1", "A"), ("sc:2", "B")].iter().enumerate() {
      s.add_play(&Play { ref_: (*r).into(), artist: (*a).into(), context: None, played_at: now - i as i64 * 1000, listened_ms: 60_000 })
        .unwrap();
    }
    let st = s.stats("week", 0).unwrap();
    assert_eq!(st.plays, 3);
    assert_eq!(st.tracks, 2);
    assert_eq!(st.artists, 2);
    assert_eq!(st.total_ms, 180_000);
    assert_eq!(st.top_artist.as_ref().map(|a| a.name.as_str()), Some("A"));
    assert_eq!(st.top_tracks[0].ref_, "sc:1");
    assert_eq!(st.top_tracks[0].plays, 2);
    assert_eq!(st.buckets.len(), 7);
    assert_eq!(st.buckets.iter().map(|b| b.value_ms).sum::<i64>(), 180_000);
    assert_eq!(st.streak_days, 1);
    assert_eq!(st.per_day, 3);
  }
}
