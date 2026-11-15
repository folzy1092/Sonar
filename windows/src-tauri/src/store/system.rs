//! Настройки целиком, сброс и «Хранилище» (docs/SETTINGS.md `storage.*`, pc/Screenshot_18).

use super::{Store, LOCAL_USER};
use anyhow::Result;
use std::collections::HashMap;

impl Store {
  /// Все сохранённые настройки — интерфейс читает их одним вызовом при запуске.
  pub fn all_settings(&self) -> Result<HashMap<String, serde_json::Value>> {
    let mut st = self.db.prepare("SELECT key, value_json FROM settings WHERE user_id = ?1")?;
    let rows = st.query_map([LOCAL_USER], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?;
    Ok(rows.filter_map(|r| r.ok()).filter_map(|(k, v)| serde_json::from_str(&v).ok().map(|v| (k, v))).collect())
  }

  /// «Сбросить настройки»: все ключи — к значениям по умолчанию. Лайки, плейлисты, история — остаются.
  pub fn reset_settings(&self) -> Result<()> {
    self.db.execute("DELETE FROM settings WHERE user_id = ?1", [LOCAL_USER])?;
    Ok(())
  }

  /// Тексты в кэше: (сколько, байт).
  pub fn lyrics_usage(&self) -> Result<(i64, i64)> {
    Ok(self.db.query_row("SELECT COUNT(*), COALESCE(SUM(LENGTH(json)), 0) FROM lyrics_cache", [], |r| Ok((r.get(0)?, r.get(1)?)))?)
  }

  pub fn clear_lyrics_cache(&self) -> Result<()> {
    self.db.execute("DELETE FROM lyrics_cache", [])?;
    Ok(())
  }

  /// Треков с сохранёнными настройками (скорость, эквалайзер, сдвиг текста).
  pub fn track_prefs_count(&self) -> Result<i64> {
    Ok(self.db.query_row("SELECT COUNT(*) FROM track_prefs WHERE user_id = ?1 AND deleted = 0", [LOCAL_USER], |r| r.get(0))?)
  }

  /// «Настройки треков — Сбросить»: строки остаются с `deleted = 1` (для синка).
  pub fn reset_track_prefs(&self) -> Result<()> {
    let rev = self.next_rev()?;
    self.db.execute(
      "UPDATE track_prefs SET deleted = 1, speed = NULL, lyrics_offset_ms = NULL, eq_json = NULL, rev = ?2 WHERE user_id = ?1",
      rusqlite::params![LOCAL_USER, rev],
    )?;
    Ok(())
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn settings_reset_and_prefs() {
    let s = Store::memory().unwrap();
    s.set_setting("a.b", &serde_json::json!(true)).unwrap();
    assert_eq!(s.all_settings().unwrap().get("a.b"), Some(&serde_json::json!(true)));
    s.reset_settings().unwrap();
    assert!(s.all_settings().unwrap().is_empty());
    s.set_lyrics_offset("sc:1", 300).unwrap();
    assert_eq!(s.track_prefs_count().unwrap(), 1);
    s.reset_track_prefs().unwrap();
    assert_eq!(s.track_prefs_count().unwrap(), 0);
    assert_eq!(s.lyrics_offset("sc:1").unwrap(), 0);
    assert_eq!(s.lyrics_usage().unwrap().0, 0);
  }
}
