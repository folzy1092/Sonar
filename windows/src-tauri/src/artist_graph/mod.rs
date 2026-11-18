//! Карта исполнителей (Медиатека → Исполнители → Карта): кто с кем связан в твоей музыке.
//! `parse` — участники трека из названия, `build` — граф (чистые функции с тестами), здесь — память
//! на минуту и команды для интерфейса, `follows` — фоновая подкачка подписок SoundCloud и лайков
//! сервисов. Раскладка и рисование — на стороне TS (`lib/artist-map/`).

pub mod build;
pub mod follows;
pub mod parse;

pub use build::{Graph, GraphTrack, Neighbor};

use std::collections::{HashMap, HashSet};
use std::sync::{Mutex, MutexGuard};
use std::time::{Duration, Instant};

use tauri::State;

use crate::commands::Db;
use crate::providers::Track;
use crate::store::Store;

type Res<T> = Result<T, String>;

fn err(e: impl std::fmt::Display) -> String {
  e.to_string()
}

/// Граф живёт в памяти минуту: карту, волну и «Похоже на» зовут часто, а медиатека меняется редко.
const MEMO_TTL: Duration = Duration::from_secs(60);
const DEFAULT_NEIGHBORS: usize = 12;
const MAX_NEIGHBORS: usize = 100;
/// Сколько треков максимум в плейлисте «по кучке» и сколько исполнителей можно передать.
const MAX_CLUSTER_TRACKS: usize = 200;
const MAX_CLUSTER_ARTISTS: usize = 300;

static MEMO: Mutex<Option<(Instant, Graph)>> = Mutex::new(None);

fn memo() -> MutexGuard<'static, Option<(Instant, Graph)>> {
  MEMO.lock().unwrap_or_else(|e| e.into_inner())
}

/// Забыть граф — после фоновой подкачки подписок или фантомных лайков.
pub fn invalidate() {
  *memo() = None;
}

/// Граф из базы (или из памяти, если ему меньше минуты).
pub fn graph_for(store: &Store) -> anyhow::Result<Graph> {
  if let Some((at, g)) = memo().as_ref() {
    if at.elapsed() < MEMO_TTL {
      return Ok(g.clone());
    }
  }
  let tracks = store.graph_tracks()?;
  let saved = store.saved_artists()?;
  let follows = store.follow_cache()?;
  let similar = store.similar_cache()?;
  let g = build::build(&build::Input { tracks: &tracks, saved: &saved, follows: &follows, similar: &similar });
  *memo() = Some((Instant::now(), g.clone()));
  Ok(g)
}

/// Сигнал «сцены» для волны: ключ `parse::key` исполнителя → 0..1.
pub fn scene_for(store: &Store) -> anyhow::Result<HashMap<String, f64>> {
  Ok(build::scene(&graph_for(store)?))
}

/// Треки медиатеки с кем-то из `names`: по кругу от каждого исполнителя (в порядке `names`),
/// у каждого — самые слушаемые первыми. Трек достаётся первому подходящему исполнителю.
pub fn cluster_refs(tracks: &[GraphTrack], names: &[String], limit: usize) -> Vec<String> {
  let wanted: Vec<String> = names.iter().map(|n| parse::key(n)).filter(|k| !k.is_empty()).collect();
  let mut per: Vec<Vec<&GraphTrack>> = vec![Vec::new(); wanted.len()];
  let mut seen = HashSet::new();
  for gt in tracks.iter().filter(|g| g.in_library || g.plays > 0) {
    let keys: Vec<String> = build::track_credits(&gt.track).iter().map(|c| parse::key(&c.name)).collect();
    let Some(i) = wanted.iter().position(|w| keys.contains(w)) else { continue };
    if seen.insert(gt.track.ref_.as_str()) {
      per[i].push(gt);
    }
  }
  for list in &mut per {
    list.sort_by(|a, b| b.plays.cmp(&a.plays).then(a.track.ref_.cmp(&b.track.ref_)));
  }
  let rounds = per.iter().map(Vec::len).max().unwrap_or(0);
  (0..rounds)
    .flat_map(|round| per.iter().filter_map(move |list| list.get(round)))
    .take(limit)
    .map(|gt| gt.track.ref_.clone())
    .collect()
}

// ——— команды ———

#[tauri::command]
pub fn artist_graph(db: State<'_, Db>) -> Res<Graph> {
  graph_for(&db.0.lock().unwrap()).map_err(err)
}

/// Соседи исполнителя по карте, сильные первыми. Для «Похоже на» и «Новое для тебя» на главной:
/// `discovered: false` — его ещё нет в медиатеке.
#[tauri::command]
pub fn artist_neighbors(db: State<'_, Db>, name: String, limit: Option<usize>) -> Res<Vec<Neighbor>> {
  let g = graph_for(&db.0.lock().unwrap()).map_err(err)?;
  Ok(build::neighbors(&g, &name, limit.unwrap_or(DEFAULT_NEIGHBORS).min(MAX_NEIGHBORS)))
}

/// Треки для плейлиста «по кучке»: исполнители кучки по кругу, не больше 200.
#[tauri::command]
pub fn artist_cluster_tracks(db: State<'_, Db>, names: Vec<String>, limit: Option<usize>) -> Res<Vec<Track>> {
  if names.is_empty() {
    return Ok(Vec::new());
  }
  let names: Vec<String> = names.into_iter().take(MAX_CLUSTER_ARTISTS).collect();
  let limit = limit.unwrap_or(MAX_CLUSTER_TRACKS).clamp(1, MAX_CLUSTER_TRACKS);
  let store = db.0.lock().unwrap();
  let tracks = store.graph_tracks().map_err(err)?;
  store.tracks(&cluster_refs(&tracks, &names, limit)).map_err(err)
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::providers::ArtistRef;

  fn gt(r: &str, title: &str, artist: &str, plays: u32) -> GraphTrack {
    GraphTrack {
      track: Track {
        ref_: r.into(),
        title: title.into(),
        artist: artist.into(),
        artists: vec![ArtistRef { ref_: String::new(), name: artist.into(), avatar_url: None }],
        album: None,
        duration_ms: 0,
        cover_url: None,
        url: None,
        explicit: false,
        available: true,
        plays: None,
        tags: None,
      },
      in_library: true,
      plays,
    }
  }

  #[test]
  fn cluster_takes_artists_in_turn_most_played_first() {
    let tracks = [
      gt("sc:1", "a1", "A", 1),
      gt("sc:2", "a2", "A", 5),
      gt("sc:3", "b1", "B", 0),
      gt("sc:4", "c1 (feat. A)", "C", 0),
      gt("sc:5", "x", "X", 9),
    ];
    let names = vec!["A".to_string(), "b".to_string()];
    assert_eq!(cluster_refs(&tracks, &names, 10), vec!["sc:2", "sc:3", "sc:1", "sc:4"]);
    assert_eq!(cluster_refs(&tracks, &names, 2), vec!["sc:2", "sc:3"]);
    assert!(cluster_refs(&tracks, &[], 10).is_empty());
  }

  #[test]
  fn cluster_skips_tracks_outside_library() {
    let mut outside = gt("sc:1", "a", "A", 0);
    outside.in_library = false;
    assert!(cluster_refs(&[outside], &["A".to_string()], 10).is_empty());
  }
}
