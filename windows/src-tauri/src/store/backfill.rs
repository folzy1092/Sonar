//! Дозаполнение карточек треков (docs/NOW_ACCURACY_PROMPT.md §2): у треков, перенесённых из Dotify, нет обложки и
//! длительности. Свежая карточка из сервиса добавляет в кэш `tracks` только недостающее; лайкнутый трек получает новый
//! `rev` — карточка уходит синком вместе с лайком (`pending_ops` кладёт её в `track`).
//!
//! Правила менять во всех трёх местах: здесь (`merge_missing`), `windows/src/lib/track-backfill.ts`
//! (`mergeMissing`) и iPhone `ios/Sonar/Core/Library/TrackBackfill.swift`.

use super::{Store, LOCAL_USER};
use crate::providers::Track;
use anyhow::Result;
use rusqlite::params;

/// Старая карточка, дополненная свежей: обложка — если своей нет, длительность — если своя 0. Название, артист и
/// остальное не трогаем (их мог поправить пользователь или перенос). `None` — добавить нечего.
pub fn merge_missing(old: &Track, fresh: &Track) -> Option<Track> {
  let cover = old.cover_url.as_deref().is_none_or(str::is_empty).then(|| fresh.cover_url.clone()).flatten().filter(|c| !c.is_empty());
  let duration = (old.duration_ms == 0 && fresh.duration_ms > 0).then_some(fresh.duration_ms);
  if cover.is_none() && duration.is_none() {
    return None;
  }
  Some(Track { cover_url: cover.or_else(|| old.cover_url.clone()), duration_ms: duration.unwrap_or(old.duration_ms), ..old.clone() })
}

impl Store {
  /// Свежие карточки из сервиса — в кэш по правилам `merge_missing` (трека в кэше нет — кладём целиком).
  /// Изменившиеся лайкнутые треки получают новый `rev`. Вернёт, сколько карточек поменялось.
  pub fn apply_backfill(&mut self, fresh: &[Track]) -> Result<usize> {
    let refs: Vec<String> = fresh.iter().map(|t| t.ref_.clone()).collect();
    let cached: std::collections::HashMap<String, Track> = self.tracks(&refs)?.into_iter().map(|t| (t.ref_.clone(), t)).collect();
    let changed: Vec<Track> = fresh
      .iter()
      .filter_map(|f| match cached.get(&f.ref_) {
        Some(old) => merge_missing(old, f),
        None => Some(f.clone()),
      })
      .collect();
    if changed.is_empty() {
      return Ok(0);
    }
    self.upsert_tracks(&changed)?;
    let rev = self.next_rev()?;
    let mut st = self.db.prepare("UPDATE likes SET rev = ?3 WHERE user_id = ?1 AND ref = ?2 AND deleted = 0")?;
    for t in &changed {
      st.execute(params![LOCAL_USER, t.ref_, rev])?;
    }
    Ok(changed.len())
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn card(r: &str, cover: Option<&str>, duration_ms: u64) -> Track {
    Track {
      ref_: r.into(),
      title: "из Dotify".into(),
      artist: "одиссея".into(),
      artists: vec![],
      album: None,
      duration_ms,
      cover_url: cover.map(str::to_owned),
      url: None,
      explicit: false,
      available: true,
      plays: None,
      tags: None,
    }
  }

  #[test]
  fn merge_takes_only_missing_fields() {
    let fresh = Track { title: "Другое название".into(), artist: "другой".into(), ..card("sc:1", Some("https://new"), 90_000) };
    let m = merge_missing(&card("sc:1", None, 0), &fresh).unwrap();
    assert_eq!((m.cover_url.as_deref(), m.duration_ms), (Some("https://new"), 90_000));
    assert_eq!((m.title.as_str(), m.artist.as_str()), ("из Dotify", "одиссея"), "название и артист — старые");
    let m = merge_missing(&card("sc:1", Some("https://old"), 0), &fresh).unwrap();
    assert_eq!((m.cover_url.as_deref(), m.duration_ms), (Some("https://old"), 90_000), "своя обложка остаётся");
    assert!(merge_missing(&card("sc:1", Some("https://old"), 5), &fresh).is_none());
    assert!(merge_missing(&card("sc:1", None, 0), &card("sc:1", None, 0)).is_none(), "свежая тоже пустая — нечего");
  }

  #[test]
  fn backfill_fills_cache_and_resends_like_with_card() {
    let mut s = Store::memory().unwrap();
    s.upsert_tracks(&[card("sc:1", None, 0), card("sc:2", None, 0)]).unwrap();
    s.set_like("sc:1", true).unwrap();
    let pushed = s.pending_ops(100).unwrap();
    s.mark_pushed(pushed.upto).unwrap();
    let n = s.apply_backfill(&[card("sc:1", Some("https://c"), 120_000), card("sc:2", Some("https://d"), 0)]).unwrap();
    assert_eq!(n, 2);
    let got = s.tracks(&["sc:1".into(), "sc:2".into()]).unwrap();
    assert_eq!((got[0].cover_url.as_deref(), got[0].duration_ms), (Some("https://c"), 120_000));
    assert_eq!((got[1].cover_url.as_deref(), got[1].duration_ms), (Some("https://d"), 0));
    let ops = s.pending_ops(100).unwrap().ops;
    assert_eq!(ops.len(), 1, "снова уходит только лайк, нелайкнутый трек — только в кэш");
    assert_eq!(ops[0].key, "sc:1");
    assert_eq!(ops[0].value.as_ref().unwrap()["track"]["duration_ms"], 120_000);
    assert_eq!(s.apply_backfill(&[card("sc:1", Some("https://x"), 1)]).unwrap(), 0, "второй раз нечего");
  }

  #[test]
  fn backfill_puts_unknown_track_whole() {
    let mut s = Store::memory().unwrap();
    assert_eq!(s.apply_backfill(&[card("ym:7", Some("https://c"), 1000)]).unwrap(), 1);
    assert_eq!(s.tracks(&["ym:7".into()]).unwrap()[0].title, "из Dotify");
  }
}
