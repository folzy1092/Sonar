//! Умные плейлисты (NEXT_PROMPT, этап 6): в базе — только имя и правила, треки пересчитываются
//! при каждом открытии из `likes`, `playlist_items`, `plays` и кэша `tracks`. Схема — docs/DB.md.

use super::smart_rules::{evaluate, Candidate, History, Rules, Source};
use super::{new_id, now_ms, ListTrack, Store, LOCAL_USER};
use anyhow::Result;
use rusqlite::{params, OptionalExtension};
use serde::Serialize;

/// Сколько треков отдаёт предпросмотр в конструкторе (остальное — только счётчик).
const PREVIEW_TRACKS: usize = 5;
const COVERS: usize = 4;

/// Почему плейлист не посчитался: правила не читаются или исходного плейлиста больше нет.
#[derive(Debug, Clone, Copy, Serialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum SmartError {
  Invalid,
  SourceMissing,
}

/// Умный плейлист — как `Playlist`, плюс правила. `tracks` — только при открытии.
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct SmartPlaylist {
  pub id: String,
  pub name: String,
  /// Правила как сохранены (JSON из docs/PLATFORMS.md «Умные плейлисты»).
  pub rules: serde_json::Value,
  pub created_at: i64,
  pub updated_at: i64,
  pub track_count: i64,
  pub duration_ms: i64,
  pub covers: Vec<String>,
  pub tracks: Option<Vec<ListTrack>>,
  pub error: Option<SmartError>,
}

/// Результат правил без сохранения — для живого счётчика в конструкторе.
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct SmartPreview {
  pub track_count: i64,
  pub duration_ms: i64,
  pub covers: Vec<String>,
  pub tracks: Vec<ListTrack>,
  pub error: Option<SmartError>,
}

struct Row {
  id: String,
  name: String,
  rules_json: String,
  created_at: i64,
  updated_at: i64,
}

impl Store {
  /// История прослушиваний одним запросом — общая для всех умных плейлистов.
  fn smart_history(&self) -> Result<History> {
    let mut st = self.db.prepare("SELECT ref, played_at FROM plays WHERE user_id = ?1")?;
    let rows = st.query_map([LOCAL_USER], |r| Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?)))?;
    Ok(History::from_rows(rows.collect::<rusqlite::Result<Vec<_>>>()?))
  }

  /// Кандидаты из источника правил; `None` — исходного плейлиста нет.
  fn smart_candidates(&self, source: &Source, history: &History) -> Result<Option<Vec<Candidate>>> {
    let pairs: Vec<(String, i64)> = match source {
      Source::Liked => self.likes("track")?,
      Source::Playlist { id } => {
        let exists: Option<i64> = self
          .db
          .query_row("SELECT 1 FROM playlists WHERE user_id = ?1 AND id = ?2 AND deleted = 0", [LOCAL_USER, id], |r| {
            r.get(0)
          })
          .optional()?;
        if exists.is_none() {
          return Ok(None);
        }
        let mut st = self
          .db
          .prepare("SELECT ref, added_at FROM playlist_items WHERE playlist_id = ?1 AND deleted = 0 ORDER BY position")?;
        st.query_map([id], |r| Ok((r.get(0)?, r.get(1)?)))?.collect::<rusqlite::Result<_>>()?
      }
      Source::Played => {
        // «добавлен» для истории — первое прослушивание; порядок — последние прослушанные сверху
        let mut list: Vec<(String, i64, i64)> = history.refs().map(|(r, first, last)| (r.to_string(), first, last)).collect();
        list.sort_by(|a, b| b.2.cmp(&a.2).then_with(|| a.0.cmp(&b.0)));
        list.into_iter().map(|(r, first, _)| (r, first)).collect()
      }
    };
    let refs: Vec<String> = pairs.iter().map(|(r, _)| r.clone()).collect();
    let by_ref: std::collections::HashMap<String, crate::providers::Track> =
      self.tracks(&refs)?.into_iter().map(|t| (t.ref_.clone(), t)).collect();
    Ok(Some(
      pairs
        .into_iter()
        .filter_map(|(r, added_at)| by_ref.get(&r).map(|t| Candidate { track: t.clone(), added_at }))
        .collect(),
    ))
  }

  /// Посчитать правила: треки или причина, почему не вышло.
  fn smart_run(&self, rules_json: &str, history: &History) -> Result<std::result::Result<Vec<ListTrack>, SmartError>> {
    let Ok(rules) = serde_json::from_str::<Rules>(rules_json) else { return Ok(Err(SmartError::Invalid)) };
    if rules.validate().is_err() {
      return Ok(Err(SmartError::Invalid));
    }
    let Some(candidates) = self.smart_candidates(&rules.source, history)? else {
      return Ok(Err(SmartError::SourceMissing));
    };
    Ok(Ok(
      evaluate(&rules, candidates, history, now_ms())
        .into_iter()
        .map(|c| ListTrack { item_id: c.track.ref_.clone(), added_at: c.added_at, track: c.track })
        .collect(),
    ))
  }

  fn smart_rows(&self, id: Option<&str>) -> Result<Vec<Row>> {
    let mut st = self.db.prepare(
      "SELECT id, name, rules_json, created_at, updated_at FROM smart_playlists
       WHERE user_id = ?1 AND deleted = 0 AND (?2 IS NULL OR id = ?2) ORDER BY created_at DESC",
    )?;
    let rows = st.query_map(params![LOCAL_USER, id], |r| {
      Ok(Row { id: r.get(0)?, name: r.get(1)?, rules_json: r.get(2)?, created_at: r.get(3)?, updated_at: r.get(4)? })
    })?;
    Ok(rows.collect::<rusqlite::Result<_>>()?)
  }

  fn smart_view(&self, row: Row, history: &History, with_tracks: bool) -> Result<SmartPlaylist> {
    let rules = serde_json::from_str(&row.rules_json).unwrap_or(serde_json::Value::Null);
    let (tracks, error) = match self.smart_run(&row.rules_json, history)? {
      Ok(t) => (t, None),
      Err(e) => (Vec::new(), Some(e)),
    };
    Ok(SmartPlaylist {
      id: row.id,
      name: row.name,
      rules,
      created_at: row.created_at,
      updated_at: row.updated_at,
      track_count: tracks.len() as i64,
      duration_ms: total_ms(&tracks),
      covers: covers(&tracks),
      tracks: with_tracks.then_some(tracks),
      error,
    })
  }

  /// Все умные плейлисты без треков (счётчик и обложки уже посчитаны), новые сверху.
  pub fn smart_playlists(&self) -> Result<Vec<SmartPlaylist>> {
    let history = self.smart_history()?;
    self.smart_rows(None)?.into_iter().map(|row| self.smart_view(row, &history, false)).collect()
  }

  /// Один умный плейлист с треками — пересчитывается при каждом открытии.
  pub fn smart_playlist(&self, id: &str) -> Result<Option<SmartPlaylist>> {
    let Some(row) = self.smart_rows(Some(id))?.into_iter().next() else { return Ok(None) };
    let history = self.smart_history()?;
    Ok(Some(self.smart_view(row, &history, true)?))
  }

  /// Предпросмотр правил из конструктора, без сохранения.
  pub fn smart_preview(&self, rules: &Rules) -> Result<SmartPreview> {
    let history = self.smart_history()?;
    let (tracks, error) = match self.smart_run(&serde_json::to_string(rules)?, &history)? {
      Ok(t) => (t, None),
      Err(e) => (Vec::new(), Some(e)),
    };
    Ok(SmartPreview {
      track_count: tracks.len() as i64,
      duration_ms: total_ms(&tracks),
      covers: covers(&tracks),
      tracks: tracks.into_iter().take(PREVIEW_TRACKS).collect(),
      error,
    })
  }

  pub fn create_smart_playlist(&self, name: &str, rules: &Rules) -> Result<String> {
    rules.validate().map_err(anyhow::Error::msg)?;
    let id = new_id("sm");
    let now = now_ms();
    let rev = self.next_rev()?;
    self.db.execute(
      "INSERT INTO smart_playlists (id, user_id, name, rules_json, created_at, updated_at, rev)
       VALUES (?1, ?2, ?3, ?4, ?5, ?5, ?6)",
      params![id, LOCAL_USER, name.trim(), serde_json::to_string(rules)?, now, rev],
    )?;
    Ok(id)
  }

  pub fn update_smart_playlist(&self, id: &str, name: Option<&str>, rules: Option<&Rules>) -> Result<()> {
    if let Some(r) = rules {
      r.validate().map_err(anyhow::Error::msg)?;
    }
    let name = name.map(str::trim).filter(|n| !n.is_empty());
    let rules_json = rules.map(serde_json::to_string).transpose()?;
    let rev = self.next_rev()?;
    let n = self.db.execute(
      "UPDATE smart_playlists SET name = COALESCE(?3, name), rules_json = COALESCE(?4, rules_json),
         updated_at = ?5, rev = ?6 WHERE user_id = ?1 AND id = ?2 AND deleted = 0",
      params![LOCAL_USER, id, name, rules_json, now_ms(), rev],
    )?;
    found(n)
  }

  pub fn delete_smart_playlist(&self, id: &str) -> Result<()> {
    let rev = self.next_rev()?;
    let n = self.db.execute(
      "UPDATE smart_playlists SET deleted = 1, updated_at = ?3, rev = ?4 WHERE user_id = ?1 AND id = ?2 AND deleted = 0",
      params![LOCAL_USER, id, now_ms(), rev],
    )?;
    found(n)
  }
}

fn found(changed: usize) -> Result<()> {
  if changed == 0 {
    anyhow::bail!("умный плейлист не найден");
  }
  Ok(())
}

fn total_ms(tracks: &[ListTrack]) -> i64 {
  tracks.iter().map(|t| t.track.duration_ms as i64).sum()
}

fn covers(tracks: &[ListTrack]) -> Vec<String> {
  tracks.iter().filter_map(|t| t.track.cover_url.clone()).take(COVERS).collect()
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::providers::Track;
  use crate::store::Play;

  fn track(r: &str) -> Track {
    Track {
      ref_: r.into(),
      title: format!("T {r}"),
      artist: "A".into(),
      artists: vec![],
      album: None,
      duration_ms: 120_000,
      cover_url: Some(format!("https://c/{r}")),
      url: None,
      explicit: false,
      available: true,
      plays: None,
      tags: None,
    }
  }

  fn rules(json: &str) -> Rules {
    serde_json::from_str(json).unwrap()
  }

  fn seeded() -> Store {
    let mut s = Store::memory().unwrap();
    s.upsert_tracks(&[track("sc:1"), track("sc:2"), track("ym:3")]).unwrap();
    for r in ["sc:1", "sc:2"] {
      s.set_like(r, true).unwrap();
    }
    let now = now_ms();
    for i in 0..3 {
      s.add_play(&Play { ref_: "sc:2".into(), artist: "A".into(), context: None, played_at: now - i, listened_ms: 1 }).unwrap();
    }
    s.add_play(&Play { ref_: "ym:3".into(), artist: "A".into(), context: None, played_at: now_ms(), listened_ms: 1 }).unwrap();
    s
  }

  #[test]
  fn create_open_update_delete() {
    let s = seeded();
    let r = rules(r#"{"v":1,"source":{"kind":"liked"},"conditions":[{"field":"plays","op":"lte","value":2}]}"#);
    let id = s.create_smart_playlist(" Почти не слушаю ", &r).unwrap();
    assert!(id.starts_with("sm_"));
    let p = s.smart_playlist(&id).unwrap().unwrap();
    assert_eq!(p.name, "Почти не слушаю");
    assert_eq!(p.error, None);
    let refs: Vec<String> = p.tracks.unwrap().into_iter().map(|t| t.item_id).collect();
    assert_eq!(refs, ["sc:1"]);
    assert_eq!(p.covers, ["https://c/sc:1"]);

    let played = rules(r#"{"v":1,"source":{"kind":"played"},"sort":{"by":"plays","desc":true}}"#);
    s.update_smart_playlist(&id, Some("Слушаю"), Some(&played)).unwrap();
    let p = s.smart_playlist(&id).unwrap().unwrap();
    assert_eq!(p.name, "Слушаю");
    let refs: Vec<String> = p.tracks.unwrap().into_iter().map(|t| t.item_id).collect();
    assert_eq!(refs, ["sc:2", "ym:3"]);

    let list = s.smart_playlists().unwrap();
    assert_eq!(list.len(), 1);
    assert_eq!(list[0].track_count, 2);
    assert!(list[0].tracks.is_none());

    s.delete_smart_playlist(&id).unwrap();
    assert!(s.smart_playlist(&id).unwrap().is_none());
    assert!(s.delete_smart_playlist(&id).is_err());
  }

  #[test]
  fn playlist_source_and_missing_source() {
    let mut s = seeded();
    let pl = s.create_playlist("Мой", &["ym:3".into(), "sc:1".into(), "ym:3".into()], None).unwrap();
    let r = rules(&format!(r#"{{"v":1,"source":{{"kind":"playlist","id":"{pl}"}}}}"#));
    let id = s.create_smart_playlist("Из плейлиста", &r).unwrap();
    let p = s.smart_playlist(&id).unwrap().unwrap();
    let refs: Vec<String> = p.tracks.unwrap().into_iter().map(|t| t.item_id).collect();
    assert_eq!(refs, ["ym:3", "sc:1"]);

    s.delete_playlist(&pl).unwrap();
    let p = s.smart_playlist(&id).unwrap().unwrap();
    assert_eq!(p.error, Some(SmartError::SourceMissing));
    assert_eq!(p.track_count, 0);
  }

  #[test]
  fn invalid_rules_are_refused_and_broken_rows_flagged() {
    let s = seeded();
    let bad = rules(r#"{"v":1,"source":{"kind":"playlist","id":""}}"#);
    assert!(s.create_smart_playlist("x", &bad).is_err());
    let id = s.create_smart_playlist("x", &rules(r#"{"v":1,"source":{"kind":"liked"}}"#)).unwrap();
    s.db.execute("UPDATE smart_playlists SET rules_json = '{\"v\":9}' WHERE id = ?1", [&id]).unwrap();
    let p = s.smart_playlist(&id).unwrap().unwrap();
    assert_eq!(p.error, Some(SmartError::Invalid));
  }

  #[test]
  fn preview_caps_tracks_but_counts_all() {
    let s = seeded();
    let r = rules(r#"{"v":1,"source":{"kind":"played"}}"#);
    let p = s.smart_preview(&r).unwrap();
    assert_eq!(p.track_count, 2);
    assert_eq!(p.duration_ms, 240_000);
    assert!(p.tracks.len() <= PREVIEW_TRACKS);
  }
}
