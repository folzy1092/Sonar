//! Данные для своей волны (SPEC §3.7): сиды, сигналы вкуса, дизлайки и пропуски.

use super::{now_ms, Store, LOCAL_USER};
use anyhow::Result;
use rusqlite::params;
use std::collections::{HashMap, HashSet};

const DAY: i64 = 24 * 3600 * 1000;

/// Артисты строки истории: из `artists_json` кэша треков (совместный трек — все), а если записи
/// нет — сохранённая строка `artist` (как `wave::artist_names`).
fn row_artists(artist: &str, json: Option<String>) -> Vec<String> {
  let list: Vec<crate::providers::ArtistRef> = json.and_then(|j| serde_json::from_str(&j).ok()).unwrap_or_default();
  crate::wave::artist_names(artist, &list)
}

/// Вкус по истории: лайкнутые исполнители, сколько дослушано и сколько пропущено (по имени артиста
/// в нижнем регистре; у совместного трека засчитывается каждому артисту — `wave::artist_keys`).
#[derive(Debug, Default, Clone)]
pub struct Taste {
  pub liked_artists: HashSet<String>,
  pub plays: HashMap<String, u32>,
  pub skips: HashMap<String, u32>,
  /// Доля прослушиваний артиста в это время суток (±2 ч от текущего часа, за 60 дней), 0…1.
  pub hour_share: HashMap<String, f64>,
}

impl Store {
  fn refs(&self, sql: &str, p: impl rusqlite::Params) -> Result<Vec<String>> {
    let mut st = self.db.prepare(sql)?;
    let rows = st.query_map(p, |r| r.get::<_, String>(0))?;
    Ok(rows.collect::<rusqlite::Result<_>>()?)
  }

  /// Последние лайки треков (новые первыми).
  pub fn recent_like_refs(&self, n: usize) -> Result<Vec<String>> {
    self.refs(
      "SELECT ref FROM likes WHERE user_id = ?1 AND kind = 'track' AND deleted = 0 ORDER BY added_at DESC LIMIT ?2",
      params![LOCAL_USER, n as i64],
    )
  }

  /// Старые лайки (после `skip` последних) — для «разведки».
  pub fn old_like_refs(&self, skip: usize, n: usize) -> Result<Vec<String>> {
    self.refs(
      "SELECT ref FROM likes WHERE user_id = ?1 AND kind = 'track' AND deleted = 0
       ORDER BY added_at DESC LIMIT ?3 OFFSET ?2",
      params![LOCAL_USER, skip as i64, n as i64],
    )
  }

  /// Последние дослушанные (≥ 80 % длительности) — «вкус сейчас».
  pub fn recent_finished_refs(&self, n: usize) -> Result<Vec<String>> {
    self.refs(
      "SELECT p.ref FROM plays p JOIN tracks t ON t.ref = p.ref
       WHERE p.user_id = ?1 AND t.duration_ms > 0 AND p.listened_ms * 5 >= t.duration_ms * 4
       GROUP BY p.ref ORDER BY MAX(p.played_at) DESC LIMIT ?2",
      params![LOCAL_USER, n as i64],
    )
  }

  /// Недавно игравшие треки (без повторов, свежие первыми) — «Недавнее» на главной.
  pub fn recent_play_refs(&self, n: usize) -> Result<Vec<String>> {
    self.refs(
      "SELECT ref FROM plays WHERE user_id = ?1 GROUP BY ref ORDER BY MAX(played_at) DESC LIMIT ?2",
      params![LOCAL_USER, n as i64],
    )
  }

  /// Что слушали за последние `days` дней — волна это не повторяет.
  pub fn played_since_days(&self, days: i64) -> Result<HashSet<String>> {
    Ok(self
      .refs("SELECT DISTINCT ref FROM plays WHERE user_id = ?1 AND played_at >= ?2", params![LOCAL_USER, now_ms() - days * DAY])?
      .into_iter()
      .collect())
  }

  pub fn disliked_refs(&self) -> Result<Vec<String>> {
    self.refs("SELECT ref FROM dislikes WHERE user_id = ?1 AND deleted = 0", params![LOCAL_USER])
  }

  /// 👎: трек больше не попадает в волну (снятие — `on = false`, строка остаётся для синка).
  pub fn set_dislike(&self, r: &str, artist: &str, on: bool) -> Result<()> {
    let rev = self.next_rev()?;
    self.db.execute(
      "INSERT INTO dislikes (user_id, ref, artist, added_at, deleted, rev) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
       ON CONFLICT(user_id, ref) DO UPDATE SET deleted = ?5, added_at = ?4, rev = ?6",
      params![LOCAL_USER, r, artist, now_ms(), if on { 0 } else { 1 }, rev],
    )?;
    Ok(())
  }

  /// Ручной пропуск в волне с оценкой < 0 (`wave::reward`) — минус артисту и треку.
  pub fn add_skip(&self, r: &str, artist: &str, played_ms: i64) -> Result<()> {
    self.db.execute(
      "INSERT INTO skips (user_id, ref, artist, played_ms, at) VALUES (?1, ?2, ?3, ?4, ?5)",
      params![LOCAL_USER, r, artist, played_ms, now_ms()],
    )?;
    Ok(())
  }

  /// Сигналы вкуса за последние 90 дней.
  /// Время суток: кого ты слушаешь в эти часы (±2 ч) чаще, чем обычно. `tz_min` — смещение
  /// часового пояса как у `Date.getTimezoneOffset()` (минуты, UTC минус местное).
  pub fn hour_share(&self, tz_min: i64) -> Result<HashMap<String, f64>> {
    let since = now_ms() - 60 * DAY;
    let local_ms = now_ms() - tz_min * 60_000;
    let hour = (local_ms / 3_600_000).rem_euclid(24);
    let mut st = self.db.prepare(
      "SELECT p.artist, t.artists_json, ((p.played_at - ?3 * 60000) / 3600000) % 24 AS h
       FROM plays p LEFT JOIN tracks t ON t.ref = p.ref WHERE p.user_id = ?1 AND p.played_at >= ?2",
    )?;
    let rows = st.query_map(params![LOCAL_USER, since, tz_min], |r| {
      Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?, r.get::<_, i64>(2)?))
    })?;
    let mut near: HashMap<String, f64> = HashMap::new();
    let mut all: HashMap<String, f64> = HashMap::new();
    for row in rows {
      let (artist, json, h) = row?;
      let d = (h.rem_euclid(24) - hour).rem_euclid(24);
      for a in row_artists(&artist, json) {
        *all.entry(a.clone()).or_insert(0.0) += 1.0;
        if d <= 2 || d >= 22 {
          *near.entry(a).or_insert(0.0) += 1.0;
        }
      }
    }
    Ok(near.into_iter().filter_map(|(a, n)| all.get(&a).filter(|&&t| t >= 3.0).map(|t| (a, n / t))).collect())
  }

  pub fn taste(&self) -> Result<Taste> {
    let since = now_ms() - 90 * DAY;
    let mut t = Taste::default();
    // артисты — из кэша треков (совместный трек засчитывается каждому), нет записи — строка из истории
    let count = |sql: &str| -> Result<HashMap<String, u32>> {
      let mut st = self.db.prepare(sql)?;
      let rows = st.query_map(params![LOCAL_USER, since], |r| {
        Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?, r.get::<_, i64>(2)?))
      })?;
      let mut m = HashMap::new();
      for row in rows {
        let (artist, json, n) = row?;
        for a in row_artists(&artist, json) {
          *m.entry(a).or_insert(0) += n.max(0) as u32;
        }
      }
      Ok(m)
    };
    t.plays = count(
      "SELECT p.artist, t.artists_json, COUNT(*) FROM plays p LEFT JOIN tracks t ON t.ref = p.ref
       WHERE p.user_id = ?1 AND p.played_at >= ?2 GROUP BY p.ref, p.artist",
    )?;
    t.skips = count(
      "SELECT s.artist, t.artists_json, COUNT(*) FROM skips s LEFT JOIN tracks t ON t.ref = s.ref
       WHERE s.user_id = ?1 AND s.at >= ?2 GROUP BY s.ref, s.artist",
    )?;
    let mut st = self.db.prepare(
      "SELECT t.artist, t.artists_json FROM likes l JOIN tracks t ON t.ref = l.ref
       WHERE l.user_id = ?1 AND l.kind = 'track' AND l.deleted = 0",
    )?;
    for row in st.query_map([LOCAL_USER], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?)))? {
      let (artist, json) = row?;
      t.liked_artists.extend(row_artists(&artist, json));
    }
    Ok(t)
  }

  /// Подборка «под время суток» на главной: треки, которые ты слушаешь в эти часы (±2 ч от
  /// текущего, за 90 дней), вперемешку с лайками; лайки сдвигаются по дню, чтобы подборка
  /// менялась каждый день, но не прыгала в течение дня. `tz_min` — как `Date.getTimezoneOffset()`.
  pub fn daypart_refs(&self, tz_min: i64, n: usize) -> Result<Vec<String>> {
    let now = now_ms();
    let local = now - tz_min * 60_000;
    let hour = (local / 3_600_000).rem_euclid(24);
    let day = local.div_euclid(DAY);
    let mut st = self.db.prepare(
      "SELECT ref, ((played_at - ?3 * 60000) / 3600000) % 24 AS h, played_at FROM plays
       WHERE user_id = ?1 AND played_at >= ?2",
    )?;
    let rows = st.query_map(params![LOCAL_USER, now - 90 * DAY, tz_min], |r| {
      Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?, r.get::<_, i64>(2)?))
    })?;
    let mut score: HashMap<String, (u32, i64)> = HashMap::new();
    for row in rows {
      let (r, h, at) = row?;
      let d = (h.rem_euclid(24) - hour).rem_euclid(24);
      if d <= 2 || d >= 22 {
        let e = score.entry(r).or_insert((0, 0));
        e.0 += 1;
        e.1 = e.1.max(at);
      }
    }
    let disliked: HashSet<String> = self.disliked_refs()?.into_iter().collect();
    let mut hours: Vec<(String, (u32, i64))> = score.into_iter().filter(|(r, _)| !disliked.contains(r)).collect();
    hours.sort_by(|a, b| b.1 .0.cmp(&a.1 .0).then(b.1 .1.cmp(&a.1 .1)));
    let mut likes = self.recent_like_refs(120)?;
    likes.retain(|r| !disliked.contains(r));
    if !likes.is_empty() {
      let k = (day as usize).wrapping_mul(7) % likes.len();
      likes.rotate_left(k);
    }
    // по два «своих часа» на один лайк: подборка про это время, а лайки её освежают
    let mut out = Vec::with_capacity(n);
    let mut seen = HashSet::new();
    let (mut h, mut l) = (hours.into_iter().map(|x| x.0), likes.into_iter());
    let mut turn = 0;
    while out.len() < n {
      let next = if turn % 3 == 2 { l.next().or_else(|| h.next()) } else { h.next().or_else(|| l.next()) };
      let Some(r) = next else { break };
      turn += 1;
      if seen.insert(r.clone()) {
        out.push(r);
      }
    }
    Ok(out)
  }

  /// Исполнители для «Релизов недели»: на кого стоят лайки — лайкнутые исполнители, потом авторы
  /// лайкнутых треков (свежие лайки первыми), потом самые слушаемые. Только `sca:`/`yma:`.
  pub fn release_artist_refs(&self, n: usize) -> Result<Vec<String>> {
    let mut out: Vec<String> = self.refs(
      "SELECT ref FROM likes WHERE user_id = ?1 AND kind = 'artist' AND deleted = 0 ORDER BY added_at DESC LIMIT ?2",
      params![LOCAL_USER, n as i64],
    )?;
    let mut st = self.db.prepare(
      "SELECT t.artists_json FROM likes l JOIN tracks t ON t.ref = l.ref
       WHERE l.user_id = ?1 AND l.kind = 'track' AND l.deleted = 0 ORDER BY l.added_at DESC LIMIT 300",
    )?;
    let rows = st.query_map([LOCAL_USER], |r| r.get::<_, Option<String>>(0))?;
    for json in rows.flatten().flatten() {
      if out.len() >= n {
        break;
      }
      let Ok(list) = serde_json::from_str::<Vec<crate::providers::ArtistRef>>(&json) else { continue };
      if let Some(a) = list.first() {
        if (a.ref_.starts_with("sca:") || a.ref_.starts_with("yma:")) && !out.contains(&a.ref_) {
          out.push(a.ref_.clone());
        }
      }
    }
    for r in self.favorite_artist_refs(n)? {
      if out.len() >= n {
        break;
      }
      if !out.contains(&r) {
        out.push(r);
      }
    }
    out.truncate(n);
    Ok(out)
  }

  /// Исполнители для «Релизов»: лайкнутые и самые слушаемые (ref `sca:`/`yma:`), без повторов.
  pub fn favorite_artist_refs(&self, n: usize) -> Result<Vec<String>> {
    let mut out: Vec<String> = self.refs(
      "SELECT ref FROM likes WHERE user_id = ?1 AND kind = 'artist' AND deleted = 0 ORDER BY added_at DESC LIMIT ?2",
      params![LOCAL_USER, n as i64],
    )?;
    let mut st = self.db.prepare(
      "SELECT t.artists_json FROM plays p JOIN tracks t ON t.ref = p.ref
       WHERE p.user_id = ?1 GROUP BY p.ref ORDER BY COUNT(*) DESC LIMIT 60",
    )?;
    let rows = st.query_map([LOCAL_USER], |r| r.get::<_, Option<String>>(0))?;
    for json in rows.flatten().flatten() {
      let Ok(list) = serde_json::from_str::<Vec<crate::providers::ArtistRef>>(&json) else { continue };
      if let Some(a) = list.first() {
        if !out.contains(&a.ref_) {
          out.push(a.ref_.clone());
        }
      }
      if out.len() >= n {
        break;
      }
    }
    out.truncate(n);
    Ok(out)
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::store::Play;

  #[test]
  fn dislikes_and_skips() {
    let s = Store::memory().unwrap();
    s.set_dislike("sc:1", "A", true).unwrap();
    s.set_dislike("sc:2", "B", true).unwrap();
    s.set_dislike("sc:2", "B", false).unwrap();
    assert_eq!(s.disliked_refs().unwrap(), vec!["sc:1".to_owned()]);
    s.add_skip("sc:3", "Art", 4000).unwrap();
    s.add_skip("sc:4", "art", 2000).unwrap();
    s.add_play(&Play { ref_: "sc:5".into(), artist: "Art".into(), context: None, played_at: now_ms(), listened_ms: 60_000 }).unwrap();
    let t = s.taste().unwrap();
    assert_eq!(t.skips.get("art"), Some(&2));
    assert_eq!(t.plays.get("art"), Some(&1));
    assert!(s.played_since_days(7).unwrap().contains("sc:5"));
    assert_eq!(s.recent_play_refs(5).unwrap(), vec!["sc:5".to_owned()]);
  }

  #[test]
  fn taste_counts_every_artist_of_joint_track() {
    use crate::providers::{ArtistRef, Track};
    let mut s = Store::memory().unwrap();
    let joint = Track {
      ref_: "ym:1".into(),
      title: "t".into(),
      artist: "A, B".into(),
      artists: ["A", "B"].iter().map(|n| ArtistRef { ref_: format!("yma:{n}"), name: (*n).into(), avatar_url: None }).collect(),
      album: None,
      duration_ms: 200_000,
      cover_url: None,
      url: None,
      explicit: false,
      available: true,
      plays: None,
      tags: None,
    };
    s.upsert_tracks(&[joint]).unwrap();
    s.add_play(&Play { ref_: "ym:1".into(), artist: "A, B".into(), context: None, played_at: now_ms(), listened_ms: 200_000 }).unwrap();
    s.add_skip("ym:1", "A, B", 5000).unwrap();
    s.set_like("ym:1", true).unwrap();
    // трека без записи в кэше — по строке из истории
    s.add_play(&Play { ref_: "sc:7".into(), artist: "Solo".into(), context: None, played_at: now_ms(), listened_ms: 60_000 }).unwrap();
    let t = s.taste().unwrap();
    assert_eq!(t.plays.get("a"), Some(&1));
    assert_eq!(t.plays.get("b"), Some(&1));
    assert_eq!(t.plays.get("a, b"), None);
    assert_eq!(t.skips.get("b"), Some(&1));
    assert!(t.liked_artists.contains("a") && t.liked_artists.contains("b"));
    assert_eq!(t.plays.get("solo"), Some(&1));
    assert!(s.hour_share(0).unwrap().is_empty(), "меньше трёх прослушиваний — без доли");
  }

  #[test]
  fn daypart_mixes_hours_and_likes() {
    let s = Store::memory().unwrap();
    let now = now_ms();
    let play = |r: &str, at: i64| {
      s.add_play(&Play { ref_: r.into(), artist: "A".into(), context: None, played_at: at, listened_ms: 60_000 }).unwrap()
    };
    // в это время суток (сегодня и вчера) — sc:1 дважды, sc:2 раз; sc:3 — через 12 часов
    play("sc:1", now - 60_000);
    play("sc:1", now - DAY);
    play("sc:2", now - DAY - 3_600_000);
    play("sc:3", now - 12 * 3_600_000);
    s.set_like("sc:9", true).unwrap();
    s.set_dislike("sc:2", "A", true).unwrap();
    let out = s.daypart_refs(0, 10).unwrap();
    assert_eq!(out, vec!["sc:1".to_owned(), "sc:9".to_owned()]);
  }
}
