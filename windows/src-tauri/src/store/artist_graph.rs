//! Данные для карты исполнителей (artist_graph/): треки медиатеки с прослушиваниями, сохранённые
//! исполнители, кэш подписок SoundCloud и треки фантомных плейлистов сервисов. Схема — docs/DB.md,
//! миграция № 13.

use super::{now_ms, Store, LOCAL_USER};
use crate::artist_graph::GraphTrack;
use crate::providers::{Artist, ArtistRef, Track};
use anyhow::Result;
use rusqlite::{params, OptionalExtension};

/// Потолок треков для графа — чтобы огромная история не подвесила построение. Под потолок
/// попадают сначала треки медиатеки, потом самые прослушанные — не по алфавиту ссылок.
const MAX_GRAPH_TRACKS: i64 = 20_000;

/// Медиатека (лайки, свои плейлисты, фантомные лайки сервисов) и всё прослушанное, по одному на трек.
const GRAPH_TRACKS_SQL: &str = "
WITH lib AS (
  SELECT ref FROM likes WHERE user_id = ?1 AND kind = 'track' AND deleted = 0
  UNION SELECT i.ref FROM playlist_items i JOIN playlists p ON p.id = i.playlist_id
    WHERE p.user_id = ?1 AND p.deleted = 0 AND i.deleted = 0
  UNION SELECT ref FROM artist_phantom_tracks
),
pl AS (SELECT ref, COUNT(*) AS n, MAX(artist) AS artist FROM plays WHERE user_id = ?1 GROUP BY ref),
refs AS (SELECT ref FROM lib UNION SELECT ref FROM pl)
SELECT r.ref, t.title, t.artist, t.artists_json, r.ref IN (SELECT ref FROM lib) AS in_lib, COALESCE(pl.n, 0) AS n, pl.artist
FROM refs r LEFT JOIN tracks t ON t.ref = r.ref LEFT JOIN pl ON pl.ref = r.ref
ORDER BY in_lib DESC, n DESC, r.ref
LIMIT ?2";

type Row = (String, Option<String>, Option<String>, Option<String>, bool, i64, Option<String>);

impl Store {
  /// Треки для графа. Трек без метаданных в кэше, но с прослушиваниями, берётся с исполнителем из `plays`.
  pub fn graph_tracks(&self) -> Result<Vec<GraphTrack>> {
    let mut st = self.db.prepare(GRAPH_TRACKS_SQL)?;
    let rows = st
      .query_map(params![LOCAL_USER, MAX_GRAPH_TRACKS], |r| {
        Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?, r.get(5)?, r.get(6)?))
      })?
      .collect::<rusqlite::Result<Vec<Row>>>()?;
    Ok(rows.into_iter().filter_map(graph_track).collect())
  }

  /// Сохранённые исполнители («Исполнители» в медиатеке).
  pub fn saved_artists(&self) -> Result<Vec<Artist>> {
    Ok(self.liked_catalog("artist")?.into_iter().filter_map(|v| serde_json::from_value(v).ok()).collect())
  }

  /// Все скачанные подписки: `sca:` исполнителя → на кого он подписан.
  pub fn follow_cache(&self) -> Result<Vec<(String, Vec<Artist>)>> {
    let mut st = self.db.prepare("SELECT artist_ref, follows_json FROM artist_follows ORDER BY artist_ref")?;
    let rows = st
      .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?
      .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(rows.into_iter().map(|(who, json)| (who, serde_json::from_str(&json).unwrap_or_default())).collect())
  }

  pub fn put_follows(&self, artist_ref: &str, follows: &[Artist]) -> Result<()> {
    self.db.execute(
      "INSERT INTO artist_follows (artist_ref, follows_json, fetched_at) VALUES (?1, ?2, ?3)
       ON CONFLICT(artist_ref) DO UPDATE SET follows_json = ?2, fetched_at = ?3",
      params![artist_ref, serde_json::to_string(follows)?, now_ms()],
    )?;
    Ok(())
  }

  /// Когда скачивали подписки исполнителя (мс); `None` — ещё ни разу.
  pub fn follows_fetched_at(&self, artist_ref: &str) -> Result<Option<i64>> {
    Ok(
      self
        .db
        .query_row("SELECT fetched_at FROM artist_follows WHERE artist_ref = ?1", [artist_ref], |r| r.get(0))
        .optional()?,
    )
  }

  /// Все закэшированные «похожие» (ref трека → список) — слабые связи карты.
  pub fn similar_cache(&self) -> Result<Vec<(String, Vec<Track>)>> {
    let mut st = self.db.prepare("SELECT ref, json FROM catalog WHERE kind = 'similar' ORDER BY ref")?;
    let rows = st
      .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?
      .collect::<rusqlite::Result<Vec<_>>>()?;
    Ok(
      rows
        .into_iter()
        .filter_map(|(r, json)| {
          let seed = r.strip_prefix("similar:")?.to_string();
          Some((seed, serde_json::from_str(&json).ok()?))
        })
        .collect(),
    )
  }

  /// Заменить треки фантомного плейлиста сервиса (`scpl:likes`…) целиком.
  pub fn put_phantom(&mut self, source_ref: &str, refs: &[String]) -> Result<()> {
    let tx = self.db.transaction()?;
    tx.execute("DELETE FROM artist_phantom_tracks WHERE source_ref = ?1", [source_ref])?;
    {
      let mut st = tx.prepare(
        "INSERT OR IGNORE INTO artist_phantom_tracks (source_ref, ref, fetched_at) VALUES (?1, ?2, ?3)",
      )?;
      let now = now_ms();
      for r in refs {
        st.execute(params![source_ref, r, now])?;
      }
    }
    tx.commit()?;
    Ok(())
  }

  /// Когда обновляли фантомный плейлист (мс); `None` — ещё ни разу или он пуст.
  pub fn phantom_fetched_at(&self, source_ref: &str) -> Result<Option<i64>> {
    Ok(self.db.query_row(
      "SELECT MAX(fetched_at) FROM artist_phantom_tracks WHERE source_ref = ?1",
      [source_ref],
      |r| r.get(0),
    )?)
  }
}

fn graph_track((ref_, title, artist, artists_json, in_library, plays, play_artist): Row) -> Option<GraphTrack> {
  let artist = artist.or(play_artist).filter(|a| !a.trim().is_empty())?;
  let artists: Vec<ArtistRef> = artists_json.and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default();
  Some(GraphTrack {
    track: Track {
      ref_,
      title: title.unwrap_or_default(),
      artist,
      artists,
      album: None,
      duration_ms: 0,
      cover_url: None,
      url: None,
      explicit: false,
      available: true,
      plays: None,
      tags: None,
    },
    in_library,
    plays: u32::try_from(plays.max(0)).unwrap_or(u32::MAX),
  })
}

#[cfg(test)]
mod tests {
  use super::*;

  fn track(r: &str, title: &str, artist: &str) -> Track {
    Track {
      ref_: r.into(),
      title: title.into(),
      artist: artist.into(),
      artists: vec![ArtistRef { ref_: "sca:1".into(), name: artist.into(), avatar_url: None }],
      album: None,
      duration_ms: 1000,
      cover_url: None,
      url: None,
      explicit: false,
      available: true,
      plays: None,
      tags: None,
    }
  }

  fn artist(r: &str, name: &str) -> Artist {
    Artist { ref_: r.into(), name: name.into(), avatar_url: None, followers: None, url: None }
  }

  #[test]
  fn graph_tracks_join_library_phantom_and_plays() {
    let mut s = Store::memory().unwrap();
    s.upsert_tracks(&[track("sc:1", "Song (feat. K)", "U"), track("sc:2", "Other", "U")]).unwrap();
    s.db
      .execute(
        "INSERT INTO likes (user_id, ref, kind, added_at, rev) VALUES (?1, 'sc:1', 'track', 1, 1)",
        [LOCAL_USER],
      )
      .unwrap();
    s.put_phantom("scpl:likes", &["sc:2".into()]).unwrap();
    // прослушан, но не в медиатеке и без метаданных — исполнитель из plays
    s.db
      .execute(
        "INSERT INTO plays (user_id, ref, artist, played_at, listened_ms) VALUES (?1, 'ym:9', 'Кино', 1, 60000), (?1, 'ym:9', 'Кино', 2, 60000)",
        [LOCAL_USER],
      )
      .unwrap();
    let got = s.graph_tracks().unwrap();
    let by_ref = |r: &str| got.iter().find(|g| g.track.ref_ == r).unwrap();
    assert_eq!(got.len(), 3);
    assert!(by_ref("sc:1").in_library);
    assert_eq!(by_ref("sc:1").track.title, "Song (feat. K)");
    assert!(by_ref("sc:2").in_library);
    let played = by_ref("ym:9");
    assert!(!played.in_library);
    assert_eq!((played.plays, played.track.artist.as_str()), (2, "Кино"));
  }

  #[test]
  fn phantom_is_replaced_whole() {
    let mut s = Store::memory().unwrap();
    assert_eq!(s.phantom_fetched_at("scpl:likes").unwrap(), None);
    s.put_phantom("scpl:likes", &["sc:1".into(), "sc:2".into()]).unwrap();
    s.put_phantom("scpl:likes", &["sc:3".into()]).unwrap();
    let n: i64 = s.db.query_row("SELECT COUNT(*) FROM artist_phantom_tracks", [], |r| r.get(0)).unwrap();
    assert_eq!(n, 1);
    assert!(s.phantom_fetched_at("scpl:likes").unwrap().is_some());
  }

  #[test]
  fn follows_round_trip() {
    let s = Store::memory().unwrap();
    assert_eq!(s.follows_fetched_at("sca:1").unwrap(), None);
    s.put_follows("sca:1", &[artist("sca:2", "B")]).unwrap();
    s.put_follows("sca:1", &[artist("sca:3", "C")]).unwrap();
    let cache = s.follow_cache().unwrap();
    assert_eq!(cache.len(), 1);
    assert_eq!(cache[0].1, vec![artist("sca:3", "C")]);
    assert!(s.follows_fetched_at("sca:1").unwrap().is_some());
  }

  #[test]
  fn similar_cache_strips_prefix() {
    let s = Store::memory().unwrap();
    s.put_similar("sc:1", &[track("sc:9", "z", "Z")]).unwrap();
    let got = s.similar_cache().unwrap();
    assert_eq!(got.len(), 1);
    assert_eq!(got[0].0, "sc:1");
    assert_eq!(got[0].1[0].ref_, "sc:9");
  }
}
