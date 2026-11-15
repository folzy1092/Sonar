//! Данные для своей волны (SPEC §3.7): сиды, сигналы вкуса, дизлайки и пропуски.

use super::{now_ms, Store, LOCAL_USER};
use anyhow::Result;
use rusqlite::params;
use std::collections::{HashMap, HashSet};

const DAY: i64 = 24 * 3600 * 1000;

/// Вкус по истории: лайкнутые исполнители, сколько дослушано и сколько пропущено (по имени артиста
/// в нижнем регистре).
#[derive(Debug, Default, Clone)]
pub struct Taste {
  pub liked_artists: HashSet<String>,
  pub plays: HashMap<String, u32>,
  pub skips: HashMap<String, u32>,
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

  /// Пропуск в первые 30 с — минус артисту.
  pub fn add_skip(&self, r: &str, artist: &str, played_ms: i64) -> Result<()> {
    self.db.execute(
      "INSERT INTO skips (user_id, ref, artist, played_ms, at) VALUES (?1, ?2, ?3, ?4, ?5)",
      params![LOCAL_USER, r, artist, played_ms, now_ms()],
    )?;
    Ok(())
  }

  /// Сигналы вкуса за последние 90 дней.
  pub fn taste(&self) -> Result<Taste> {
    let since = now_ms() - 90 * DAY;
    let mut t = Taste::default();
    let count = |sql: &str| -> Result<HashMap<String, u32>> {
      let mut st = self.db.prepare(sql)?;
      let rows = st.query_map(params![LOCAL_USER, since], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))?;
      let mut m = HashMap::new();
      for row in rows {
        let (a, n) = row?;
        *m.entry(a.to_lowercase()).or_insert(0) += n.max(0) as u32;
      }
      Ok(m)
    };
    t.plays = count("SELECT artist, COUNT(*) FROM plays WHERE user_id = ?1 AND played_at >= ?2 GROUP BY artist")?;
    t.skips = count("SELECT artist, COUNT(*) FROM skips WHERE user_id = ?1 AND at >= ?2 GROUP BY artist")?;
    let mut st = self.db.prepare(
      "SELECT t.artist FROM likes l JOIN tracks t ON t.ref = l.ref
       WHERE l.user_id = ?1 AND l.kind = 'track' AND l.deleted = 0",
    )?;
    for a in st.query_map([LOCAL_USER], |r| r.get::<_, String>(0))? {
      t.liked_artists.insert(a?.to_lowercase());
    }
    Ok(t)
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
}
