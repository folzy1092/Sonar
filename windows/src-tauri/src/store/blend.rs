//! Сведение (`docs/BLEND.md` §5, миграция № 17): анализ треков и оценки переходов.
//! Только на этом устройстве, в синк не идёт: анализ одинаков на любом ПК, оценки — личный вкус.

use super::{now_ms, Store};
use anyhow::{bail, Result};
use rusqlite::params;
use serde::Serialize;
use std::collections::HashMap;

/// Виды перехода (`player/blend/curves.ts`) — других в оценки не пишем.
pub const BLEND_KINDS: [&str; 5] = ["bass", "filter", "echo", "smooth", "drop"];
/// Результат анализа одного трека — десятки КБ; больше — точно мусор.
pub const BLEND_JSON_MAX: usize = 512 * 1024;
/// За один вызов `blend_get` — не больше стольких ref.
pub const BLEND_GET_MAX: usize = 500;

#[derive(Debug, Serialize, PartialEq)]
pub struct BlendRow {
  pub version: i64,
  /// JSON `BlendAnalysis` как его положил фронт.
  pub data: String,
}

impl Store {
  /// Сохранённые анализы для этих ref (каких нет — тех нет и в ответе).
  pub fn blend_get(&self, refs: &[String]) -> Result<HashMap<String, BlendRow>> {
    if refs.len() > BLEND_GET_MAX {
      bail!("слишком много треков за раз: {}", refs.len());
    }
    let mut stmt = self.db.prepare_cached("SELECT version, data_json FROM blend_analysis WHERE ref = ?1")?;
    let mut out = HashMap::new();
    for r in refs {
      let row = stmt.query_row([r], |row| Ok(BlendRow { version: row.get(0)?, data: row.get(1)? }));
      match row {
        Ok(v) => {
          out.insert(r.clone(), v);
        }
        Err(rusqlite::Error::QueryReturnedNoRows) => {}
        Err(e) => return Err(e.into()),
      }
    }
    Ok(out)
  }

  /// Записать анализ трека (новая версия анализатора перезаписывает старую).
  pub fn blend_put(&self, track_ref: &str, version: i64, data_json: &str) -> Result<()> {
    if track_ref.is_empty() || version <= 0 {
      bail!("пустой ref или версия анализа");
    }
    if data_json.len() > BLEND_JSON_MAX {
      bail!("анализ слишком большой: {} байт", data_json.len());
    }
    serde_json::from_str::<serde_json::Value>(data_json)?;
    self.db.execute(
      "INSERT INTO blend_analysis (ref, version, data_json, analyzed_at) VALUES (?1, ?2, ?3, ?4)
       ON CONFLICT(ref) DO UPDATE SET version = ?2, data_json = ?3, analyzed_at = ?4",
      params![track_ref, version, data_json, now_ms()],
    )?;
    Ok(())
  }

  /// Оценка прошлого перехода: `score` −1 или +1.
  pub fn blend_rate(&self, from_ref: &str, to_ref: &str, kind: &str, score: i64) -> Result<()> {
    if !BLEND_KINDS.contains(&kind) {
      bail!("неизвестный вид перехода: {kind}");
    }
    if score != 1 && score != -1 {
      bail!("оценка — только ±1");
    }
    self.db.execute(
      "INSERT INTO blend_ratings (from_ref, to_ref, kind, score, at) VALUES (?1, ?2, ?3, ?4, ?5)",
      params![from_ref, to_ref, kind, score, now_ms()],
    )?;
    Ok(())
  }

  /// «Хранилище»: сколько треков проанализировано и сколько это байт.
  pub fn blend_usage(&self) -> Result<(i64, i64)> {
    Ok(self.db.query_row("SELECT COUNT(*), COALESCE(SUM(LENGTH(data_json)), 0) FROM blend_analysis", [], |r| {
      Ok((r.get(0)?, r.get(1)?))
    })?)
  }

  /// «Очистить» анализ: оценки — личный вкус, их не трогаем.
  pub fn blend_clear(&self) -> Result<()> {
    self.db.execute("DELETE FROM blend_analysis", [])?;
    Ok(())
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn put_then_get_returns_only_known_refs() {
    let s = Store::memory().unwrap();
    s.blend_put("sc:1", 1, r#"{"bpm":128}"#).unwrap();
    let got = s.blend_get(&["sc:1".into(), "ym:2".into()]).unwrap();
    assert_eq!(got.len(), 1);
    assert_eq!(got["sc:1"], BlendRow { version: 1, data: r#"{"bpm":128}"#.into() });
  }

  #[test]
  fn new_version_overwrites_old() {
    let s = Store::memory().unwrap();
    s.blend_put("sc:1", 1, "{}").unwrap();
    s.blend_put("sc:1", 2, r#"{"bpm":90}"#).unwrap();
    assert_eq!(s.blend_get(&["sc:1".into()]).unwrap()["sc:1"].version, 2);
    assert_eq!(s.blend_usage().unwrap().0, 1);
  }

  #[test]
  fn put_rejects_garbage() {
    let s = Store::memory().unwrap();
    assert!(s.blend_put("sc:1", 1, "не json").is_err());
    assert!(s.blend_put("", 1, "{}").is_err());
    assert!(s.blend_put("sc:1", 0, "{}").is_err());
    assert!(s.blend_put("sc:1", 1, &format!("\"{}\"", "x".repeat(BLEND_JSON_MAX))).is_err());
  }

  #[test]
  fn rate_checks_kind_and_score() {
    let s = Store::memory().unwrap();
    s.blend_rate("sc:1", "ym:2", "bass", 1).unwrap();
    assert!(s.blend_rate("sc:1", "ym:2", "wobble", 1).is_err());
    assert!(s.blend_rate("sc:1", "ym:2", "echo", 5).is_err());
  }

  #[test]
  fn clear_keeps_ratings() {
    let s = Store::memory().unwrap();
    s.blend_put("sc:1", 1, "{}").unwrap();
    s.blend_rate("sc:1", "ym:2", "drop", -1).unwrap();
    s.blend_clear().unwrap();
    assert_eq!(s.blend_usage().unwrap(), (0, 0));
    let n: i64 = s.db.query_row("SELECT COUNT(*) FROM blend_ratings", [], |r| r.get(0)).unwrap();
    assert_eq!(n, 1);
  }
}
