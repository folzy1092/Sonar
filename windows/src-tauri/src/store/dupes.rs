//! «Убрать отмеченные» на экране дублей — одна правка (одна транзакция, один `rev` синка) и
//! «Отменить» во всплывашке: убранное возвращается как было (в Любимых — с прежней датой
//! добавления, в плейлисте — на прежнее место, строки только снимают `deleted`).

use super::{Store, LOCAL_USER};
use anyhow::{bail, Result};
use rusqlite::{params, OptionalExtension, Transaction};
use serde::{Deserialize, Serialize};

/// Id «списка» Любимых для команд дублей; остальное — id своего плейлиста.
pub const FAVORITES_LIST: &str = "favorites";

/// Где ищем дубли.
#[derive(Debug, Clone, PartialEq)]
pub enum DupeList {
  Favorites,
  Playlist(String),
}

impl DupeList {
  /// `favorites` или id своего плейлиста (`pl_…`); остальное — ошибка для интерфейса.
  pub fn parse(list: &str) -> Result<Self> {
    match list {
      FAVORITES_LIST => Ok(Self::Favorites),
      id if id.starts_with("pl_") && id.len() > 3 => Ok(Self::Playlist(id.to_string())),
      _ => bail!("Дубли ищутся только в Любимых и своих плейлистах"),
    }
  }
}

/// Убранная строка: `item_id` (в Любимых — ref) и когда её добавили — чтобы вернуть как было.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct RemovedItem {
  pub item_id: String,
  pub added_at: i64,
}

/// Что убрали одной правкой — интерфейс держит это до «Отменить».
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Removed {
  pub list: String,
  pub items: Vec<RemovedItem>,
}

impl Store {
  /// Убрать строки разом. Уже убранные и чужие id пропускаются; в ответе — только убранное.
  pub fn remove_dupes(&mut self, list: &str, item_ids: &[String]) -> Result<Removed> {
    let target = DupeList::parse(list)?;
    if let DupeList::Playlist(id) = &target {
      self.touch(id)?;
    }
    let rev = self.next_rev()?;
    let tx = self.db.transaction()?;
    let mut items = Vec::with_capacity(item_ids.len());
    for item_id in item_ids {
      if let Some(added_at) = remove_one(&tx, &target, item_id, rev)? {
        items.push(RemovedItem { item_id: item_id.clone(), added_at });
      }
    }
    tx.commit()?;
    Ok(Removed { list: list.to_string(), items })
  }

  /// Вернуть убранное («Отменить»). Вернёт, сколько строк вернулось (снова добавленное
  /// пользователем за это время не трогается).
  pub fn restore_dupes(&mut self, removed: &Removed) -> Result<usize> {
    let target = DupeList::parse(&removed.list)?;
    if let DupeList::Playlist(id) = &target {
      self.touch(id)?;
    }
    let rev = self.next_rev()?;
    let tx = self.db.transaction()?;
    let mut restored = 0;
    for item in &removed.items {
      restored += restore_one(&tx, &target, item, rev)?;
    }
    tx.commit()?;
    Ok(restored)
  }
}

/// Снять одну строку; `Some(added_at)` — если она была на месте.
fn remove_one(tx: &Transaction, target: &DupeList, item_id: &str, rev: i64) -> Result<Option<i64>> {
  let added_at: Option<i64> = match target {
    DupeList::Favorites => tx
      .query_row(
        "SELECT added_at FROM likes WHERE user_id = ?1 AND ref = ?2 AND kind = 'track' AND deleted = 0",
        params![LOCAL_USER, item_id],
        |r| r.get(0),
      )
      .optional()?,
    DupeList::Playlist(id) => tx
      .query_row(
        "SELECT added_at FROM playlist_items WHERE playlist_id = ?1 AND id = ?2 AND deleted = 0",
        params![id, item_id],
        |r| r.get(0),
      )
      .optional()?,
  };
  if added_at.is_none() {
    return Ok(None);
  }
  match target {
    DupeList::Favorites => tx.execute(
      "UPDATE likes SET deleted = 1, rev = ?3 WHERE user_id = ?1 AND ref = ?2",
      params![LOCAL_USER, item_id, rev],
    )?,
    DupeList::Playlist(id) => tx.execute(
      "UPDATE playlist_items SET deleted = 1, rev = ?3 WHERE playlist_id = ?1 AND id = ?2",
      params![id, item_id, rev],
    )?,
  };
  Ok(added_at)
}

/// Вернуть одну строку, если она всё ещё убрана.
fn restore_one(tx: &Transaction, target: &DupeList, item: &RemovedItem, rev: i64) -> Result<usize> {
  Ok(match target {
    DupeList::Favorites => tx.execute(
      "UPDATE likes SET deleted = 0, added_at = ?3, rev = ?4
       WHERE user_id = ?1 AND ref = ?2 AND kind = 'track' AND deleted = 1",
      params![LOCAL_USER, item.item_id, item.added_at, rev],
    )?,
    DupeList::Playlist(id) => tx.execute(
      "UPDATE playlist_items SET deleted = 0, rev = ?3 WHERE playlist_id = ?1 AND id = ?2 AND deleted = 1",
      params![id, item.item_id, rev],
    )?,
  })
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::providers::{ArtistRef, Track};

  fn track(r: &str) -> Track {
    Track {
      ref_: r.into(),
      title: "Song".into(),
      artist: "A".into(),
      artists: vec![ArtistRef { ref_: "sca:1".into(), name: "A".into(), avatar_url: None }],
      album: None,
      duration_ms: 100_000,
      cover_url: None,
      url: None,
      explicit: false,
      available: true,
      plays: None,
      tags: None,
    }
  }

  /// Лайк с заданной датой добавления.
  fn like_at(store: &Store, r: &str, added_at: i64) {
    store.set_like(r, true).unwrap();
    store.db.execute("UPDATE likes SET added_at = ?2 WHERE ref = ?1", params![r, added_at]).unwrap();
  }

  fn fav_refs(store: &Store) -> Vec<String> {
    store.favorites().unwrap().into_iter().map(|t| t.item_id).collect()
  }

  #[test]
  fn list_ids_are_validated() {
    assert_eq!(DupeList::parse("favorites").unwrap(), DupeList::Favorites);
    assert_eq!(DupeList::parse("pl_abc").unwrap(), DupeList::Playlist("pl_abc".into()));
    for bad in ["", "pl_", "scpl:likes", "ympl:1:3", "Favorites"] {
      assert!(DupeList::parse(bad).is_err(), "{bad}");
    }
  }

  #[test]
  fn favorites_remove_and_undo_keep_the_date() {
    let mut store = Store::memory().unwrap();
    store.upsert_tracks(&[track("sc:1"), track("ym:1"), track("yt:1")]).unwrap();
    like_at(&store, "sc:1", 100);
    like_at(&store, "ym:1", 200);
    like_at(&store, "yt:1", 300);
    let before = store.next_rev().unwrap();

    let removed = store.remove_dupes("favorites", &["sc:1".into(), "yt:1".into(), "nope:1".into()]).unwrap();
    assert_eq!(removed.items, [
      RemovedItem { item_id: "sc:1".into(), added_at: 100 },
      RemovedItem { item_id: "yt:1".into(), added_at: 300 },
    ]);
    assert_eq!(fav_refs(&store), ["ym:1"]);
    let revs: Vec<i64> = store
      .db
      .prepare("SELECT DISTINCT rev FROM likes WHERE deleted = 1")
      .unwrap()
      .query_map([], |r| r.get(0))
      .unwrap()
      .collect::<rusqlite::Result<_>>()
      .unwrap();
    assert_eq!(revs, [before + 1], "одна правка — один rev");

    assert_eq!(store.restore_dupes(&removed).unwrap(), 2);
    assert_eq!(fav_refs(&store), ["yt:1", "ym:1", "sc:1"], "на прежних местах по дате");
    assert_eq!(store.restore_dupes(&removed).unwrap(), 0, "повторная отмена ничего не делает");
  }

  #[test]
  fn playlist_remove_and_undo_return_items_in_place() {
    let mut store = Store::memory().unwrap();
    store.upsert_tracks(&[track("sc:1"), track("ym:1")]).unwrap();
    let refs: Vec<String> = ["sc:1", "ym:1", "sc:1"].map(String::from).to_vec();
    let id = store.create_playlist("Mix", &refs, None).unwrap();
    let items = store.playlist(&id).unwrap().unwrap().tracks.unwrap();
    let ids: Vec<String> = items.iter().map(|t| t.item_id.clone()).collect();

    let removed = store.remove_dupes(&id, &[ids[0].clone(), ids[2].clone()]).unwrap();
    assert_eq!(removed.items.len(), 2);
    let left: Vec<String> = store.playlist(&id).unwrap().unwrap().tracks.unwrap().into_iter().map(|t| t.item_id).collect();
    assert_eq!(left, [ids[1].clone()]);

    assert_eq!(store.restore_dupes(&removed).unwrap(), 2);
    let back: Vec<String> = store.playlist(&id).unwrap().unwrap().tracks.unwrap().into_iter().map(|t| t.item_id).collect();
    assert_eq!(back, ids);
  }

  #[test]
  fn foreign_or_missing_playlist_is_an_error() {
    let mut store = Store::memory().unwrap();
    assert!(store.remove_dupes("pl_missing", &["x".into()]).is_err());
    assert!(store.remove_dupes("ympl:1:3", &["x".into()]).is_err());
    store.upsert_tracks(&[track("sc:1")]).unwrap();
    let other = store.create_playlist("Other", &["sc:1".into()], None).unwrap();
    let mine = store.create_playlist("Mine", &[], None).unwrap();
    let foreign = store.playlist(&other).unwrap().unwrap();
    let foreign_ids: Vec<String> = foreign.tracks.unwrap().into_iter().map(|t| t.item_id).collect();
    let removed = store.remove_dupes(&mine, &foreign_ids).unwrap();
    assert!(removed.items.is_empty(), "строки другого плейлиста не трогаются");
  }
}
