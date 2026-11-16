//! История поиска (Система → Хранилище, строка поиска): запросы и открытые из поиска результаты —
//! только локально, в синк не идут. Повтор того же запроса или результата поднимает его наверх,
//! храним последние 100.

use super::{now_ms, Store, LOCAL_USER};
use anyhow::Result;
use rusqlite::params;
use serde::{Deserialize, Serialize};

/// Запись истории: `query` — запрос; `result` — открытый трек / исполнитель / альбом / плейлист.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SearchEntry {
  pub kind: String,
  #[serde(default)]
  pub query: String,
  #[serde(rename = "ref", default)]
  pub ref_: Option<String>,
  #[serde(default)]
  pub title: Option<String>,
  #[serde(default)]
  pub subtitle: Option<String>,
  #[serde(default)]
  pub cover_url: Option<String>,
  #[serde(default)]
  pub at: i64,
}

const KEEP: i64 = 100;

impl Store {
  pub fn add_search(&self, e: &SearchEntry) -> Result<()> {
    let query = e.query.trim();
    if e.kind == "query" && query.is_empty() {
      return Ok(());
    }
    // тот же запрос (без учёта регистра) или тот же результат — одна строка, свежая наверху
    if e.kind == "query" {
      self.db.execute(
        "DELETE FROM search_history WHERE user_id = ?1 AND kind = 'query' AND lower(query) = lower(?2)",
        params![LOCAL_USER, query],
      )?;
    } else {
      self.db.execute("DELETE FROM search_history WHERE user_id = ?1 AND kind = ?2 AND ref = ?3", params![LOCAL_USER, e.kind, e.ref_])?;
    }
    self.db.execute(
      "INSERT INTO search_history (user_id, kind, query, ref, title, subtitle, cover_url, at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
      params![LOCAL_USER, e.kind, query, e.ref_, e.title, e.subtitle, e.cover_url, now_ms()],
    )?;
    self.db.execute(
      "DELETE FROM search_history WHERE user_id = ?1 AND id NOT IN
         (SELECT id FROM search_history WHERE user_id = ?1 ORDER BY at DESC, id DESC LIMIT ?2)",
      params![LOCAL_USER, KEEP],
    )?;
    Ok(())
  }

  /// Последние записи (свежие первыми).
  pub fn search_history(&self, limit: usize) -> Result<Vec<SearchEntry>> {
    let mut st = self.db.prepare(
      "SELECT kind, query, ref, title, subtitle, cover_url, at FROM search_history WHERE user_id = ?1
       ORDER BY at DESC, id DESC LIMIT ?2",
    )?;
    let rows = st.query_map(params![LOCAL_USER, limit as i64], |r| {
      Ok(SearchEntry { kind: r.get(0)?, query: r.get(1)?, ref_: r.get(2)?, title: r.get(3)?, subtitle: r.get(4)?, cover_url: r.get(5)?, at: r.get(6)? })
    })?;
    Ok(rows.collect::<rusqlite::Result<_>>()?)
  }

  pub fn search_history_count(&self) -> Result<i64> {
    Ok(self.db.query_row("SELECT COUNT(*) FROM search_history WHERE user_id = ?1", [LOCAL_USER], |r| r.get(0))?)
  }

  pub fn clear_search_history(&self) -> Result<()> {
    self.db.execute("DELETE FROM search_history WHERE user_id = ?1", [LOCAL_USER])?;
    Ok(())
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn q(text: &str) -> SearchEntry {
    SearchEntry { kind: "query".into(), query: text.into(), ref_: None, title: None, subtitle: None, cover_url: None, at: 0 }
  }

  #[test]
  fn dedup_and_order() {
    let s = Store::memory().unwrap();
    s.add_search(&q("lil peep")).unwrap();
    s.add_search(&q("  ")).unwrap();
    s.add_search(&SearchEntry { kind: "track".into(), query: "lil".into(), ref_: Some("sc:1".into()), title: Some("Star Shopping".into()), subtitle: Some("Lil Peep".into()), cover_url: None, at: 0 }).unwrap();
    s.add_search(&q("Lil Peep")).unwrap();
    let h = s.search_history(10).unwrap();
    assert_eq!(h.len(), 2, "пустой не пишется, повтор запроса — одна строка");
    assert_eq!(h[0].query, "Lil Peep");
    assert_eq!(h[1].ref_.as_deref(), Some("sc:1"));
    assert_eq!(s.search_history_count().unwrap(), 2);
    s.clear_search_history().unwrap();
    assert!(s.search_history(10).unwrap().is_empty());
  }

  #[test]
  fn keeps_last_hundred() {
    let s = Store::memory().unwrap();
    for i in 0..120 {
      s.add_search(&q(&format!("q{i}"))).unwrap();
    }
    assert_eq!(s.search_history_count().unwrap(), KEEP);
    assert_eq!(s.search_history(1).unwrap()[0].query, "q119");
  }
}
