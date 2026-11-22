//! Звук трека — «Для этого трека» в меню скорости (решение владельца 2026-11-22): скорость, тон (свой или
//! связанный со скоростью), реверб и кривая эквалайзера, запомненные для одного трека. Остальные треки
//! играют по общим настройкам (`player.tempo`, `audio.eq`). Хранится в `track_prefs.sound_json` и едет
//! синком в `track_pref` (`{speed, lyrics_offset_ms, sound}`): `speed` = `sound.rate` — для клиентов, что знают
//! только «Запомнить скорость».

use super::{Store, LOCAL_USER};
use anyhow::Result;
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const EQ_BANDS: usize = 12;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TrackSound {
  /// Скорость 0.5…2.
  pub rate: f64,
  /// Свой сдвиг тона в полутонах −12…+12 (когда не связан со скоростью).
  #[serde(default)]
  pub pitch: f64,
  /// Тон едет вместе со скоростью (slowed / sped up).
  #[serde(default)]
  pub linked: bool,
  /// Реверб 0…1; 0 — выключен.
  #[serde(default)]
  pub reverb: f64,
  /// Кривая эквалайзера, 12 полос в дБ; `None` — общая кривая.
  #[serde(default)]
  pub eq: Option<Vec<f64>>,
}

/// До `per`-х долей: `round(0.8333, 100)` = 0.83 (делением — без хвостов вида 0.8300000000000001).
fn round(v: f64, per: f64) -> f64 {
  (v * per).round() / per
}

impl TrackSound {
  /// В допустимых пределах; мусор (не числа) — `None`.
  pub fn normalized(self) -> Option<Self> {
    if !self.rate.is_finite() || !self.pitch.is_finite() || !self.reverb.is_finite() {
      return None;
    }
    let eq = self
      .eq
      .filter(|g| g.len() == EQ_BANDS && g.iter().all(|x| x.is_finite()))
      .map(|g| g.into_iter().map(|x| round(x.clamp(-12.0, 12.0), 10.0)).collect());
    Some(Self {
      rate: round(self.rate.clamp(0.5, 2.0), 100.0),
      pitch: round(self.pitch.clamp(-12.0, 12.0), 10.0),
      linked: self.linked,
      reverb: round(self.reverb.clamp(0.0, 1.0), 100.0),
      eq,
    })
  }

  /// Из значения синка: `sound`, а у старых клиентов (только «Запомнить скорость») — из `speed`:
  /// та же скорость, тон сохраняется.
  pub fn from_sync(v: &Value) -> Option<Self> {
    if let Some(s) = v.get("sound").filter(|s| s.is_object()) {
      return serde_json::from_value::<Self>(s.clone()).ok()?.normalized();
    }
    let speed = v.get("speed")?.as_f64()?;
    Self { rate: speed, pitch: 0.0, linked: false, reverb: 0.0, eq: None }.normalized()
  }
}

/// Пустая запись (ничего не запомнено) — помечается удалённой, чтобы синк унёс удаление.
pub(super) const MARK_EMPTY: &str = "UPDATE track_prefs SET deleted = 1 WHERE user_id = ?1 AND ref = ?2
  AND speed IS NULL AND lyrics_offset_ms IS NULL AND eq_json IS NULL AND sound_json IS NULL";

impl Store {
  /// Звук, запомненный для трека, или `None` — трек играет по общим настройкам.
  pub fn track_sound(&self, r: &str) -> Result<Option<TrackSound>> {
    let v: Option<Option<String>> = self
      .db
      .query_row("SELECT sound_json FROM track_prefs WHERE user_id = ?1 AND ref = ?2 AND deleted = 0", [LOCAL_USER, r], |row| row.get(0))
      .optional()?;
    Ok(v.flatten().and_then(|j| serde_json::from_str::<TrackSound>(&j).ok()).and_then(TrackSound::normalized))
  }

  /// Запомнить звук для трека (`None` — забыть). `speed` пишется рядом для старых клиентов.
  pub fn set_track_sound(&self, r: &str, sound: Option<TrackSound>) -> Result<()> {
    let sound = sound.and_then(TrackSound::normalized);
    let json = sound.as_ref().map(serde_json::to_string).transpose()?;
    let speed = sound.as_ref().map(|s| s.rate);
    let rev = self.next_rev()?;
    self.db.execute(
      "INSERT INTO track_prefs (user_id, ref, speed, sound_json, deleted, rev) VALUES (?1, ?2, ?3, ?4, 0, ?5)
       ON CONFLICT(user_id, ref) DO UPDATE SET speed = ?3, sound_json = ?4, deleted = 0, rev = ?5",
      params![LOCAL_USER, r, speed, json, rev],
    )?;
    self.db.execute(MARK_EMPTY, [LOCAL_USER, r])?;
    Ok(())
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use serde_json::json;

  fn slowed() -> TrackSound {
    TrackSound { rate: 0.8, pitch: 0.0, linked: true, reverb: 0.4, eq: Some(vec![3.0; 12]) }
  }

  #[test]
  fn clamps_and_rounds() {
    let s = TrackSound { rate: 3.0, pitch: -20.0, linked: false, reverb: 1.7, eq: Some(vec![40.0; 12]) }.normalized().unwrap();
    assert_eq!((s.rate, s.pitch, s.reverb), (2.0, -12.0, 1.0));
    assert_eq!(s.eq.unwrap()[0], 12.0);
    let s = TrackSound { rate: 0.8333, pitch: 1.26, linked: false, reverb: 0.333, eq: Some(vec![1.0; 5]) }.normalized().unwrap();
    assert_eq!((s.rate, s.pitch, s.reverb), (0.83, 1.3, 0.33));
    assert!(s.eq.is_none(), "кривая не из 12 полос — общая");
    assert!(TrackSound { rate: f64::NAN, pitch: 0.0, linked: false, reverb: 0.0, eq: None }.normalized().is_none());
  }

  #[test]
  fn from_sync_reads_sound_or_old_speed() {
    let v = json!({ "speed": 0.8, "sound": { "rate": 0.8, "linked": true, "reverb": 0.4, "eq": vec![3.0; 12] } });
    assert_eq!(TrackSound::from_sync(&v), Some(slowed()));
    // старый клиент: только «Запомнить скорость» — та же скорость, тон сохраняется
    let old = TrackSound::from_sync(&json!({ "speed": 1.25, "lyrics_offset_ms": 300 })).unwrap();
    assert_eq!((old.rate, old.linked, old.reverb, old.eq), (1.25, false, 0.0, None));
    assert_eq!(TrackSound::from_sync(&json!({ "lyrics_offset_ms": 300 })), None);
  }

  #[test]
  fn set_read_and_forget() {
    let s = Store::memory().unwrap();
    assert_eq!(s.track_sound("sc:1").unwrap(), None);
    s.set_track_sound("sc:1", Some(slowed())).unwrap();
    assert_eq!(s.track_sound("sc:1").unwrap(), Some(slowed()));
    assert_eq!(s.track_sound("sc:2").unwrap(), None, "другие треки — по общим настройкам");
    s.set_track_sound("sc:1", None).unwrap();
    assert_eq!(s.track_sound("sc:1").unwrap(), None);
    assert_eq!(s.track_prefs_count().unwrap(), 0, "пустая запись помечена удалённой");
  }

  #[test]
  fn forgetting_sound_keeps_lyrics_offset() {
    let s = Store::memory().unwrap();
    s.set_lyrics_offset("sc:1", 400).unwrap();
    s.set_track_sound("sc:1", Some(slowed())).unwrap();
    s.set_track_sound("sc:1", None).unwrap();
    assert_eq!(s.lyrics_offset("sc:1").unwrap(), 400);
    assert_eq!(s.track_prefs_count().unwrap(), 1);
  }
}
