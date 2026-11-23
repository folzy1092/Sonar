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
  /// Копия тоже очищается, иначе при следующем запуске настройки «вернулись» бы.
  pub fn reset_settings(&self) -> Result<()> {
    self.db.execute("DELETE FROM settings WHERE user_id = ?1", [LOCAL_USER])?;
    self.backup_settings();
    Ok(())
  }

  /// Записать копию настроек (атомарно: во временный файл и переименование). Ошибки — молча, копия
  /// вспомогательная.
  pub fn backup_settings(&self) {
    let Some(path) = &self.backup else { return };
    let Ok(all) = self.all_settings() else { return };
    let Ok(text) = serde_json::to_string(&all) else { return };
    let tmp = path.with_extension("json.tmp");
    if std::fs::write(&tmp, text).is_ok() {
      let _ = std::fs::rename(&tmp, path);
    }
  }

  /// Таблица настроек пустая, а копия есть — вернуть настройки из копии; сколько ключей вернули.
  pub fn restore_settings_if_empty(&self) -> Result<usize> {
    let Some(path) = &self.backup else { return Ok(0) };
    let count: i64 = self.db.query_row("SELECT COUNT(*) FROM settings WHERE user_id = ?1", [LOCAL_USER], |r| r.get(0))?;
    if count > 0 || !path.exists() {
      return Ok(0);
    }
    let all: HashMap<String, serde_json::Value> = serde_json::from_str(&std::fs::read_to_string(path)?)?;
    for (k, v) in &all {
      self.db.execute(
        "INSERT INTO settings (user_id, key, value_json, client_ts, rev) VALUES (?1, ?2, ?3, ?4, 0)
         ON CONFLICT(user_id, key) DO NOTHING",
        rusqlite::params![LOCAL_USER, k, v.to_string(), super::now_ms()],
      )?;
    }
    Ok(all.len())
  }

  /// Тексты в кэше: (сколько, байт).
  pub fn lyrics_usage(&self) -> Result<(i64, i64)> {
    Ok(self.db.query_row("SELECT COUNT(*), COALESCE(SUM(LENGTH(json)), 0) FROM lyrics_cache", [], |r| Ok((r.get(0)?, r.get(1)?)))?)
  }

  /// «Очистить тексты»: тексты скачанных треков — часть скачанного, их не трогаем.
  pub fn clear_lyrics_cache(&self) -> Result<()> {
    self.db.execute(
      "DELETE FROM lyrics_cache WHERE ref NOT IN (SELECT ref FROM offline_tracks WHERE kind = ?1)",
      [super::OFFLINE_KIND_PINNED],
    )?;
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
      "UPDATE track_prefs SET deleted = 1, speed = NULL, lyrics_offset_ms = NULL, eq_json = NULL, sound_json = NULL, rev = ?2 WHERE user_id = ?1",
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

  #[test]
  fn settings_restored_from_backup_when_table_empty() {
    let dir = std::env::temp_dir().join(format!("sonar-sb-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let db = dir.join("sonar.db");
    {
      let s = Store::open(&db).unwrap();
      s.set_setting("appearance.preset", &serde_json::json!("violet")).unwrap();
      s.set_setting("tabs.position", &serde_json::json!("top")).unwrap();
    }
    // настройки пропали из базы (как после сбоя) — копия их возвращает
    {
      let c = rusqlite::Connection::open(&db).unwrap();
      c.execute("DELETE FROM settings", []).unwrap();
    }
    let s = Store::open(&db).unwrap();
    assert_eq!(s.setting("appearance.preset").unwrap(), Some(serde_json::json!("violet")));
    assert_eq!(s.setting("tabs.position").unwrap(), Some(serde_json::json!("top")));
    // «Сбросить настройки» — копия тоже пустая, ничего не возвращается
    s.reset_settings().unwrap();
    drop(s);
    let s = Store::open(&db).unwrap();
    assert_eq!(s.setting("appearance.preset").unwrap(), None);
    let _ = std::fs::remove_dir_all(&dir);
  }
}
