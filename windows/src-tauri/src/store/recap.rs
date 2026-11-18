//! Итоги месяца и года (NEXT_PROMPT «Этап 11»): карточки «минуты, топ-5 треков и артистов,
//! новый артист, любимый час, самый длинный день, трек на повторе, доли сервисов» — из той же
//! таблицы `plays`, что и статистика. Границы периода — по местному времени (`tz_min`).

use super::stats::{local_day, year_month, ArtistStat, Row, TrackStat, DAY, HOUR};
use super::{now_ms, Store, LOCAL_USER};
use crate::providers::registry::service_of;
use anyhow::{bail, Result};
use rusqlite::params;
use serde::Serialize;
use std::collections::{HashMap, HashSet};

/// Сколько позиций в топах карточек.
const TOP_N: usize = 5;
/// Кандидатов в топ треков берём с запасом: трек без записи в кэше пропускается.
const TOP_CANDIDATES: usize = 10;
/// «Трек на повторе» — не меньше стольких прослушиваний за один день.
const MIN_REPEAT: i64 = 3;
const MIN_YEAR: i64 = 2000;
const MAX_YEAR: i64 = 2100;

/// Период, за который есть прослушивания: месяц (`month` 1–12) или год (`month` = None).
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct RecapPeriod {
  pub kind: String,
  pub year: i64,
  pub month: Option<u32>,
  pub total_ms: i64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct RecapPeriods {
  /// Новые сверху.
  pub months: Vec<RecapPeriod>,
  pub years: Vec<RecapPeriod>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct NewArtist {
  pub artist: ArtistStat,
  /// Первое прослушивание, `YYYY-MM-DD` по местному времени.
  pub first_played: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct LongestDay {
  pub date: String,
  pub ms: i64,
  pub plays: i64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Repeat {
  pub track: TrackStat,
  /// Сколько раз за день.
  pub count: i64,
  pub date: String,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ServiceShare {
  /// Короткий id сервиса из реестра (`sc`, `ym`, …).
  pub service: String,
  pub ms: i64,
  /// Целые проценты, в сумме ровно 100.
  pub pct: i64,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Recap {
  pub kind: String,
  pub year: i64,
  pub month: Option<u32>,
  pub total_ms: i64,
  pub plays: i64,
  pub tracks: i64,
  pub artists: i64,
  /// Дней, когда слушал.
  pub active_days: i64,
  /// К прошлому такому же периоду, % (None — сравнивать не с чем).
  pub delta_pct: Option<i64>,
  pub top_tracks: Vec<TrackStat>,
  pub top_artists: Vec<ArtistStat>,
  pub new_artist: Option<NewArtist>,
  /// Время по часам суток (24 значения, мс).
  pub hours: Vec<i64>,
  pub peak_hour: Option<u32>,
  pub longest_day: Option<LongestDay>,
  pub repeat: Option<Repeat>,
  pub services: Vec<ServiceShare>,
}

/// Месяц или год, проверенный на входе команды.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum RecapSpan {
  Month(i64, u32),
  Year(i64),
}

impl RecapSpan {
  pub fn parse(kind: &str, year: i64, month: Option<u32>) -> Result<Self> {
    if !(MIN_YEAR..=MAX_YEAR).contains(&year) {
      bail!("неверный год");
    }
    match (kind, month) {
      ("month", Some(m)) if (1..=12).contains(&m) => Ok(RecapSpan::Month(year, m)),
      ("year", None) => Ok(RecapSpan::Year(year)),
      _ => bail!("неверный период итогов"),
    }
  }

  fn previous(self) -> Self {
    match self {
      RecapSpan::Month(y, 1) => RecapSpan::Month(y - 1, 12),
      RecapSpan::Month(y, m) => RecapSpan::Month(y, m - 1),
      RecapSpan::Year(y) => RecapSpan::Year(y - 1),
    }
  }

  /// Первый и следующий за последним день периода (дни от эпохи).
  fn days(self) -> (i64, i64) {
    match self {
      RecapSpan::Month(y, 12) => (days_from_civil(y, 12, 1), days_from_civil(y + 1, 1, 1)),
      RecapSpan::Month(y, m) => (days_from_civil(y, m, 1), days_from_civil(y, m + 1, 1)),
      RecapSpan::Year(y) => (days_from_civil(y, 1, 1), days_from_civil(y + 1, 1, 1)),
    }
  }

  /// Границы периода в мс UTC: с местной полуночи первого дня до местной полуночи после последнего.
  fn bounds(self, tz_min: i64) -> (i64, i64) {
    let (a, b) = self.days();
    let shift = tz_min * 60_000;
    (a * DAY - shift, b * DAY - shift)
  }
}

/// День от эпохи по гражданской дате (Howard Hinnant, обратно к `civil`).
pub(super) fn days_from_civil(y: i64, m: u32, d: u32) -> i64 {
  let y = if m <= 2 { y - 1 } else { y };
  let era = y.div_euclid(400);
  let yoe = y - era * 400;
  let mp = (m as i64 + 9) % 12;
  let doy = (153 * mp + 2) / 5 + d as i64 - 1;
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  era * 146_097 + doe - 719_468
}

/// `YYYY-MM-DD` дня от эпохи.
fn iso_date(day: i64) -> String {
  let (y, m) = year_month(day);
  let d = day - days_from_civil(y, m, 1) + 1;
  format!("{y:04}-{m:02}-{d:02}")
}

fn hour_of(ts: i64, tz_min: i64) -> usize {
  ((ts + tz_min * 60_000).rem_euclid(DAY) / HOUR) as usize
}

fn delta(total: i64, prev: i64) -> Option<i64> {
  (prev > 0).then(|| ((total - prev) as f64 / prev as f64 * 100.0).round() as i64)
}

/// Проценты методом наибольшего остатка: целые, в сумме ровно 100.
pub(super) fn percents(values: &[i64]) -> Vec<i64> {
  let total: i64 = values.iter().sum();
  if total <= 0 {
    return vec![0; values.len()];
  }
  let mut out: Vec<i64> = values.iter().map(|v| v * 100 / total).collect();
  let mut rest = 100 - out.iter().sum::<i64>();
  let mut order: Vec<usize> = (0..values.len()).collect();
  order.sort_by(|&a, &b| (values[b] * 100 % total).cmp(&(values[a] * 100 % total)).then(a.cmp(&b)));
  for i in order {
    if rest <= 0 {
      break;
    }
    out[i] += 1;
    rest -= 1;
  }
  out
}

/// Доли сервисов по времени — id из реестра; ref без сервиса не считаем.
fn service_shares(rows: &[Row]) -> Vec<ServiceShare> {
  let mut by: HashMap<&'static str, i64> = HashMap::new();
  for r in rows {
    if let Some(id) = service_of(&r.ref_) {
      *by.entry(id.as_str()).or_default() += r.listened_ms;
    }
  }
  let mut list: Vec<(&str, i64)> = by.into_iter().filter(|(_, ms)| *ms > 0).collect();
  list.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
  let pct = percents(&list.iter().map(|(_, ms)| *ms).collect::<Vec<_>>());
  list.into_iter().zip(pct).map(|((s, ms), pct)| ServiceShare { service: s.to_owned(), ms, pct }).collect()
}

/// Самый длинный день по времени (при равенстве — более ранний).
fn longest_day(rows: &[Row], tz_min: i64) -> Option<LongestDay> {
  let mut by: HashMap<i64, (i64, i64)> = HashMap::new();
  for r in rows {
    let e = by.entry(local_day(r.played_at, tz_min)).or_default();
    e.0 += r.listened_ms;
    e.1 += 1;
  }
  by.into_iter()
    .filter(|(_, (ms, _))| *ms > 0)
    .max_by(|a, b| a.1 .0.cmp(&b.1 .0).then(b.0.cmp(&a.0)))
    .map(|(day, (ms, plays))| LongestDay { date: iso_date(day), ms, plays })
}

/// Кандидаты «трек на повторе»: (ref, день, раз, мс), лучшие первыми, не меньше `MIN_REPEAT`.
fn repeat_candidates(rows: &[Row], tz_min: i64) -> Vec<(String, i64, i64, i64)> {
  let mut by: HashMap<(&str, i64), (i64, i64)> = HashMap::new();
  for r in rows {
    let e = by.entry((r.ref_.as_str(), local_day(r.played_at, tz_min))).or_default();
    e.0 += 1;
    e.1 += r.listened_ms;
  }
  let mut list: Vec<(String, i64, i64, i64)> = by
    .into_iter()
    .filter(|(_, (n, _))| *n >= MIN_REPEAT)
    .map(|((r, d), (n, ms))| (r.to_owned(), d, n, ms))
    .collect();
  list.sort_by(|a, b| b.2.cmp(&a.2).then(b.3.cmp(&a.3)).then(a.1.cmp(&b.1)).then(a.0.cmp(&b.0)));
  list
}

/// Треки периода: (ref, прослушиваний, мс), по числу прослушиваний.
fn track_totals(rows: &[Row]) -> Vec<(String, i64, i64)> {
  let mut by: HashMap<&str, (i64, i64)> = HashMap::new();
  for r in rows {
    let e = by.entry(r.ref_.as_str()).or_default();
    e.0 += 1;
    e.1 += r.listened_ms;
  }
  let mut list: Vec<(String, i64, i64)> = by.into_iter().map(|(r, (n, ms))| (r.to_owned(), n, ms)).collect();
  list.sort_by(|a, b| b.1.cmp(&a.1).then(b.2.cmp(&a.2)).then(a.0.cmp(&b.0)));
  list
}

/// Артисты периода: (имя как в первой записи, мс, прослушиваний), по времени; без учёта регистра.
fn artist_totals(rows: &[Row]) -> Vec<(String, i64, i64)> {
  let mut by: HashMap<String, (String, i64, i64)> = HashMap::new();
  for r in rows.iter().filter(|r| !r.artist.trim().is_empty()) {
    let e = by.entry(r.artist.to_lowercase()).or_insert_with(|| (r.artist.clone(), 0, 0));
    e.1 += r.listened_ms;
    e.2 += 1;
  }
  let mut list: Vec<(String, i64, i64)> = by.into_values().collect();
  list.sort_by(|a, b| b.1.cmp(&a.1).then(b.2.cmp(&a.2)).then(a.0.cmp(&b.0)));
  list
}

fn peak_hour(hours: &[i64]) -> Option<u32> {
  hours.iter().enumerate().filter(|(_, ms)| **ms > 0).max_by(|a, b| a.1.cmp(b.1).then(b.0.cmp(&a.0))).map(|(h, _)| h as u32)
}

impl Store {
  /// Итоги месяца или года по местному времени.
  pub fn recap(&self, span: RecapSpan, tz_min: i64) -> Result<Recap> {
    let (from, to) = span.bounds(tz_min);
    let rows = self.play_rows(Some(from), to)?;
    let total_ms: i64 = rows.iter().map(|r| r.listened_ms).sum();
    let (pf, pt) = span.previous().bounds(tz_min);
    let prev: i64 = self.play_rows(Some(pf), pt)?.iter().map(|r| r.listened_ms).sum();

    let mut hours = vec![0i64; 24];
    for r in &rows {
      hours[hour_of(r.played_at, tz_min)] += r.listened_ms;
    }
    let tracks = track_totals(&rows);
    let artists = artist_totals(&rows);
    let (kind, year, month) = match span {
      RecapSpan::Month(y, m) => ("month", y, Some(m)),
      RecapSpan::Year(y) => ("year", y, None),
    };
    Ok(Recap {
      kind: kind.to_owned(),
      year,
      month,
      total_ms,
      plays: rows.len() as i64,
      tracks: tracks.len() as i64,
      artists: artists.len() as i64,
      active_days: rows.iter().map(|r| local_day(r.played_at, tz_min)).collect::<HashSet<_>>().len() as i64,
      delta_pct: delta(total_ms, prev),
      top_tracks: self.recap_tracks(&tracks)?,
      top_artists: artists.iter().take(TOP_N).map(|a| self.artist_stat(a)).collect(),
      new_artist: self.new_artist(&rows, &artists, from, tz_min)?,
      peak_hour: peak_hour(&hours),
      hours,
      longest_day: longest_day(&rows, tz_min),
      repeat: self.repeat(&rows, tz_min)?,
      services: service_shares(&rows),
    })
  }

  /// Месяцы и годы, за которые есть прослушивания, — для списка итогов и приглашения на Главной.
  pub fn recap_periods(&self, tz_min: i64) -> Result<RecapPeriods> {
    let rows = self.play_rows(None, now_ms() + 1)?;
    let mut months: HashMap<(i64, u32), i64> = HashMap::new();
    let mut years: HashMap<i64, i64> = HashMap::new();
    for r in &rows {
      let (y, m) = year_month(local_day(r.played_at, tz_min));
      *months.entry((y, m)).or_default() += r.listened_ms;
      *years.entry(y).or_default() += r.listened_ms;
    }
    let mut months: Vec<RecapPeriod> = months
      .into_iter()
      .map(|((year, m), total_ms)| RecapPeriod { kind: "month".into(), year, month: Some(m), total_ms })
      .collect();
    months.sort_by(|a, b| (b.year, b.month).cmp(&(a.year, a.month)));
    let mut years: Vec<RecapPeriod> =
      years.into_iter().map(|(year, total_ms)| RecapPeriod { kind: "year".into(), year, month: None, total_ms }).collect();
    years.sort_by(|a, b| b.year.cmp(&a.year));
    Ok(RecapPeriods { months, years })
  }

  fn artist_stat(&self, (name, ms, plays): &(String, i64, i64)) -> ArtistStat {
    let (r, avatar) = self.artist_face(name).unwrap_or((None, None));
    ArtistStat { name: name.clone(), avatar_url: avatar, ref_: r, ms: *ms, plays: *plays }
  }

  /// Топ треков с названием и обложкой из кэша; трек без записи в кэше пропускается.
  fn recap_tracks(&self, totals: &[(String, i64, i64)]) -> Result<Vec<TrackStat>> {
    let picked = &totals[..totals.len().min(TOP_CANDIDATES)];
    let mut out: Vec<TrackStat> = picked.iter().filter_map(|(r, n, ms)| self.track_stat(r, *n, *ms)).collect();
    out.truncate(TOP_N);
    Ok(out)
  }

  fn track_stat(&self, r: &str, plays: i64, ms: i64) -> Option<TrackStat> {
    let t = self.tracks(&[r.to_owned()]).ok()?.into_iter().next()?;
    Some(TrackStat { ref_: r.to_owned(), title: t.title, artist: t.artist, cover_url: t.cover_url, plays, ms })
  }

  fn repeat(&self, rows: &[Row], tz_min: i64) -> Result<Option<Repeat>> {
    Ok(repeat_candidates(rows, tz_min).into_iter().find_map(|(r, day, count, ms)| {
      let track = self.track_stat(&r, count, ms)?;
      Some(Repeat { track, count, date: iso_date(day) })
    }))
  }

  /// Артисты, которых слушал до `before` (имена в нижнем регистре: SQLite `lower()` — только ASCII).
  fn artists_before(&self, before: i64) -> Result<HashSet<String>> {
    let mut st = self.db.prepare("SELECT DISTINCT artist FROM plays WHERE user_id = ?1 AND played_at < ?2")?;
    let rows = st.query_map(params![LOCAL_USER, before], |r| r.get::<_, String>(0))?;
    Ok(rows.collect::<rusqlite::Result<Vec<_>>>()?.into_iter().map(|a| a.to_lowercase()).collect())
  }

  /// Новый артист периода: больше всего времени среди тех, кого раньше не слушал. Без истории до
  /// периода — None (иначе «новыми» были бы все).
  fn new_artist(&self, rows: &[Row], artists: &[(String, i64, i64)], from: i64, tz_min: i64) -> Result<Option<NewArtist>> {
    let known = self.artists_before(from)?;
    if known.is_empty() {
      return Ok(None);
    }
    let Some(found) = artists.iter().find(|(name, _, _)| !known.contains(&name.to_lowercase())) else { return Ok(None) };
    let key = found.0.to_lowercase();
    let first = rows.iter().find(|r| r.artist.to_lowercase() == key).map(|r| local_day(r.played_at, tz_min));
    Ok(first.map(|day| NewArtist { artist: self.artist_stat(found), first_played: iso_date(day) }))
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::store::Play;

  fn track(r: &str, a: &str) -> crate::providers::Track {
    crate::providers::Track {
      ref_: r.into(),
      title: format!("T{r}"),
      artist: a.into(),
      artists: vec![],
      album: None,
      duration_ms: 200_000,
      cover_url: Some(format!("https://img/{r}.jpg")),
      url: None,
      explicit: false,
      available: true,
      plays: None,
      tags: None,
    }
  }

  /// Мс UTC для местной даты и часа при смещении `tz`.
  fn at(y: i64, m: u32, d: u32, h: i64, tz: i64) -> i64 {
    days_from_civil(y, m, d) * DAY + h * HOUR - tz * 60_000
  }

  fn play(s: &mut Store, r: &str, a: &str, ts: i64, ms: i64) {
    s.add_play(&Play { ref_: r.into(), artist: a.into(), context: None, played_at: ts, listened_ms: ms }).unwrap();
  }

  #[test]
  fn civil_dates_round_trip() {
    assert_eq!(days_from_civil(1970, 1, 1), 0);
    assert_eq!(days_from_civil(2026, 11, 15), 20_772);
    assert_eq!(days_from_civil(2024, 3, 1) - days_from_civil(2024, 2, 1), 29);
    assert_eq!(iso_date(20_772), "2026-11-15");
    assert_eq!(iso_date(days_from_civil(2000, 2, 29)), "2000-02-29");
    for day in [-1000, 0, 11_000, 20_454, 20_772, 40_000] {
      let (y, m) = year_month(day);
      let d: u32 = iso_date(day)[8..].parse().unwrap();
      assert_eq!(days_from_civil(y, m, d), day);
    }
  }

  #[test]
  fn span_validation_and_bounds() {
    assert!(RecapSpan::parse("month", 2026, Some(13)).is_err());
    assert!(RecapSpan::parse("month", 2026, None).is_err());
    assert!(RecapSpan::parse("year", 2026, Some(1)).is_err());
    assert!(RecapSpan::parse("week", 2026, None).is_err());
    assert!(RecapSpan::parse("year", 1800, None).is_err());
    assert_eq!(RecapSpan::parse("month", 2026, Some(1)).unwrap().previous(), RecapSpan::Month(2025, 12));
    assert_eq!(RecapSpan::Year(2026).previous(), RecapSpan::Year(2025));
    let (a, b) = RecapSpan::Month(2026, 12).bounds(120);
    assert_eq!(a, at(2026, 12, 1, 0, 120));
    assert_eq!(b, at(2027, 1, 1, 0, 120));
    assert_eq!(b - a, 31 * DAY);
  }

  #[test]
  fn percents_sum_to_hundred() {
    assert_eq!(percents(&[1, 1, 1]), vec![34, 33, 33]);
    assert_eq!(percents(&[2, 1]), vec![67, 33]);
    assert_eq!(percents(&[5]), vec![100]);
    assert_eq!(percents(&[0, 0]), vec![0, 0]);
    assert_eq!(percents(&[]), Vec::<i64>::new());
    assert_eq!(percents(&[996, 2, 2]).iter().sum::<i64>(), 100);
  }

  #[test]
  fn month_recap_counts_cards() {
    let mut s = Store::memory().unwrap();
    let tz = 120;
    s.upsert_tracks(&[track("sc:1", "A"), track("ym:2", "B"), track("sc:3", "Новый")]).unwrap();
    // до периода — только A
    play(&mut s, "sc:1", "A", at(2026, 10, 20, 12, tz), 60_000);
    // ноябрь: sc:1 трижды 3-го, ym:2 дважды 5-го, новый артист 10-го
    for h in [9, 10, 23] {
      play(&mut s, "sc:1", "A", at(2026, 11, 3, h, tz), 100_000);
    }
    play(&mut s, "ym:2", "B", at(2026, 11, 5, 23, tz), 50_000);
    play(&mut s, "ym:2", "B", at(2026, 11, 5, 23, tz) + 1000, 50_000);
    play(&mut s, "sc:3", "Новый", at(2026, 11, 10, 9, tz), 200_000);
    // на границах: последняя секунда октября и первая декабря — не в ноябре
    play(&mut s, "sc:1", "A", at(2026, 11, 1, 0, tz) - 1, 1);
    play(&mut s, "sc:1", "A", at(2026, 12, 1, 0, tz), 1);

    let r = s.recap(RecapSpan::Month(2026, 11), tz).unwrap();
    assert_eq!((r.kind.as_str(), r.year, r.month), ("month", 2026, Some(11)));
    assert_eq!(r.total_ms, 600_000);
    assert_eq!((r.plays, r.tracks, r.artists, r.active_days), (6, 3, 3, 3));
    assert_eq!(r.delta_pct, Some(900)); // 600 000 против 60 001 в октябре
    assert_eq!(r.top_tracks.iter().map(|t| t.ref_.as_str()).collect::<Vec<_>>(), ["sc:1", "ym:2", "sc:3"]);
    assert_eq!(r.top_tracks[0].plays, 3);
    assert_eq!(r.top_artists.iter().map(|a| a.name.as_str()).collect::<Vec<_>>(), ["A", "Новый", "B"]);
    let na = r.new_artist.unwrap();
    assert_eq!((na.artist.name.as_str(), na.first_played.as_str()), ("Новый", "2026-11-10"));
    assert_eq!(r.hours.len(), 24);
    assert_eq!(r.hours[9], 300_000);
    assert_eq!(r.peak_hour, Some(9));
    let ld = r.longest_day.unwrap();
    assert_eq!((ld.date.as_str(), ld.ms, ld.plays), ("2026-11-03", 300_000, 3));
    let rep = r.repeat.unwrap();
    assert_eq!((rep.track.ref_.as_str(), rep.count, rep.date.as_str()), ("sc:1", 3, "2026-11-03"));
    let sv: Vec<(&str, i64)> = r.services.iter().map(|s| (s.service.as_str(), s.pct)).collect();
    assert_eq!(sv, [("sc", 83), ("ym", 17)]);
  }

  #[test]
  fn empty_and_first_ever_periods() {
    let mut s = Store::memory().unwrap();
    let empty = s.recap(RecapSpan::Year(2026), 0).unwrap();
    assert_eq!(empty.total_ms, 0);
    assert!(empty.top_tracks.is_empty() && empty.services.is_empty());
    assert_eq!((empty.peak_hour, empty.delta_pct), (None, None));
    assert!(empty.longest_day.is_none() && empty.repeat.is_none() && empty.new_artist.is_none());

    s.upsert_tracks(&[track("sc:1", "A")]).unwrap();
    play(&mut s, "sc:1", "A", at(2026, 3, 1, 12, 0), 10_000);
    play(&mut s, "sc:1", "A", at(2026, 3, 1, 13, 0), 10_000);
    let r = s.recap(RecapSpan::Year(2026), 0).unwrap();
    // первый период в истории: новым артистом никто не считается, на повтор двух раз мало
    assert!(r.new_artist.is_none());
    assert!(r.repeat.is_none());
    assert_eq!(r.services[0].pct, 100);
  }

  #[test]
  fn periods_newest_first() {
    let mut s = Store::memory().unwrap();
    play(&mut s, "sc:1", "A", at(2025, 12, 31, 23, 0), 1000);
    play(&mut s, "sc:1", "A", at(2026, 2, 1, 1, 0), 2000);
    play(&mut s, "sc:1", "A", at(2026, 2, 2, 1, 0), 3000);
    let p = s.recap_periods(0).unwrap();
    let months: Vec<(i64, Option<u32>, i64)> = p.months.iter().map(|m| (m.year, m.month, m.total_ms)).collect();
    assert_eq!(months, [(2026, Some(2), 5000), (2025, Some(12), 1000)]);
    let years: Vec<(i64, i64)> = p.years.iter().map(|y| (y.year, y.total_ms)).collect();
    assert_eq!(years, [(2026, 5000), (2025, 1000)]);
    // при +2 ч последняя ночь 2025-го уже в 2026-м
    let shifted = s.recap_periods(120).unwrap();
    assert_eq!(shifted.years.iter().map(|y| y.year).collect::<Vec<_>>(), [2026]);
  }
}
