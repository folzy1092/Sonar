//! «Играть из» — сервис, закреплённый за одним треком (меню трека): «Авто» (нет записи) — как раньше, резерв и
//! «SoundCloud через Яндекс» решают сами; SoundCloud / Яндекс Музыка / YouTube Music — трек играет оттуда, если
//! там нашёлся тот же (`services/fallback.rs`). Хранится в `track_prefs.source` (миграция № 19) и едет синком в
//! `track_pref` полем `source` (ключ сервиса, `null` — «Авто»).

use super::{track_sound::MARK_EMPTY, Store, LOCAL_USER};
use crate::providers::registry::ServiceId;
use crate::services::fallback::pin_of;
use anyhow::Result;
use rusqlite::{params, OptionalExtension};

impl Store {
  /// Закреплённый за треком сервис или `None` — «Авто».
  pub fn track_source(&self, r: &str) -> Result<Option<ServiceId>> {
    let v: Option<Option<String>> = self
      .db
      .query_row("SELECT source FROM track_prefs WHERE user_id = ?1 AND ref = ?2 AND deleted = 0", [LOCAL_USER, r], |row| row.get(0))
      .optional()?;
    Ok(v.flatten().as_deref().and_then(pin_of))
  }

  /// Закрепить сервис за треком (`None` — «Авто»). Возвращает, поменялся ли выбор.
  pub fn set_track_source(&self, r: &str, source: Option<ServiceId>) -> Result<bool> {
    let source = source.filter(|s| pin_of(s.as_str()).is_some());
    if self.track_source(r)? == source {
      return Ok(false);
    }
    let rev = self.next_rev()?;
    self.db.execute(
      "INSERT INTO track_prefs (user_id, ref, source, deleted, rev) VALUES (?1, ?2, ?3, 0, ?4)
       ON CONFLICT(user_id, ref) DO UPDATE SET source = ?3, deleted = 0, rev = ?4",
      params![LOCAL_USER, r, source.map(|s| s.as_str()), rev],
    )?;
    self.db.execute(MARK_EMPTY, [LOCAL_USER, r])?;
    Ok(true)
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::store::TrackSound;

  #[test]
  fn set_read_and_back_to_auto() {
    let s = Store::memory().unwrap();
    assert_eq!(s.track_source("sc:1").unwrap(), None);
    assert!(s.set_track_source("sc:1", Some(ServiceId::Ym)).unwrap());
    assert!(!s.set_track_source("sc:1", Some(ServiceId::Ym)).unwrap(), "тот же выбор — без новой ревизии");
    assert_eq!(s.track_source("sc:1").unwrap(), Some(ServiceId::Ym));
    assert_eq!(s.track_source("sc:2").unwrap(), None, "другие треки — «Авто»");
    assert!(s.set_track_source("sc:1", None).unwrap());
    assert_eq!(s.track_source("sc:1").unwrap(), None);
    assert_eq!(s.track_prefs_count().unwrap(), 0, "пустая запись помечена удалённой");
  }

  #[test]
  fn source_rides_sync_both_ways() {
    let a = Store::memory().unwrap();
    a.set_track_source("sc:1", Some(ServiceId::Ym)).unwrap();
    let plan = a.pending_ops(100).unwrap();
    let op = plan.ops.iter().find(|o| o.kind == "track_pref" && o.key == "sc:1").expect("выбор уехал в синк");
    assert_eq!(op.value.as_ref().unwrap()["source"], "ym");
    let mut b = Store::memory().unwrap();
    let change = crate::store::Change { kind: "track_pref".into(), key: "sc:1".into(), value: op.value.clone(), rev: 5 };
    b.apply_changes(&[change]).unwrap();
    assert_eq!(b.track_source("sc:1").unwrap(), Some(ServiceId::Ym), "на другом устройстве — то же");
    // «Авто» на другом устройстве: значения нет — запись удалена
    let back = crate::store::Change { kind: "track_pref".into(), key: "sc:1".into(), value: None, rev: 6 };
    b.apply_changes(&[back]).unwrap();
    assert_eq!(b.track_source("sc:1").unwrap(), None);
    // чужое значение — «Авто», а не ошибка
    let odd = serde_json::json!({ "speed": null, "lyrics_offset_ms": null, "sound": null, "source": "sp" });
    b.apply_changes(&[crate::store::Change { kind: "track_pref".into(), key: "sc:2".into(), value: Some(odd), rev: 7 }]).unwrap();
    assert_eq!(b.track_source("sc:2").unwrap(), None);
  }

  #[test]
  fn services_without_stream_are_not_pinned() {
    let s = Store::memory().unwrap();
    assert!(!s.set_track_source("sc:1", Some(ServiceId::Sp)).unwrap());
    assert_eq!(s.track_source("sc:1").unwrap(), None);
  }

  #[test]
  fn source_lives_next_to_sound_and_offset() {
    let s = Store::memory().unwrap();
    let sound = TrackSound { rate: 0.8, pitch: 0.0, linked: true, reverb: 0.0, eq: None, space: 0.0 };
    s.set_track_sound("sc:1", Some(sound.clone())).unwrap();
    s.set_lyrics_offset("sc:1", 300).unwrap();
    s.set_track_source("sc:1", Some(ServiceId::Sc)).unwrap();
    s.set_track_sound("sc:1", None).unwrap();
    s.set_lyrics_offset("sc:1", 0).unwrap();
    assert_eq!(s.track_source("sc:1").unwrap(), Some(ServiceId::Sc), "забытый звук и сдвиг не трогают выбор");
    assert_eq!(s.track_prefs_count().unwrap(), 1);
    s.set_track_source("sc:1", None).unwrap();
    s.set_track_sound("sc:1", Some(sound.clone())).unwrap();
    assert_eq!(s.track_sound("sc:1").unwrap(), Some(sound));
  }
}
