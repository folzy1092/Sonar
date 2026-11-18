//! `track_alias` — тот же трек на другом сервисе (резервный сервис, «SoundCloud через Яндекс»):
//! найденный ref запоминается, чтобы не искать заново; «не нашлось» живёт неделю — каталоги
//! пополняются (docs/DB.md «track_alias»).

use super::{now_ms, Store};
use anyhow::Result;
use rusqlite::params;

const DAY_MS: i64 = 24 * 3600 * 1000;
/// Сколько помнить «на этом сервисе такого трека нет».
pub const MISS_TTL_MS: i64 = 7 * DAY_MS;

/// Строка `track_alias`: `alias_ref = None` — искали и не нашли.
#[derive(Debug, Clone, PartialEq)]
pub struct TrackAlias {
  pub source_ref: String,
  /// Короткий id сервиса, где искали (`ym`, `yt`…).
  pub service: String,
  pub alias_ref: Option<String>,
  pub found_at: i64,
}

impl Store {
  /// Все живые записи для трека: найденные — всегда, «не нашлось» — младше `MISS_TTL_MS`.
  pub fn track_aliases(&self, source_ref: &str) -> Result<Vec<TrackAlias>> {
    let mut st = self.db.prepare(
      "SELECT service, alias_ref, found_at FROM track_alias
       WHERE source_ref = ?1 AND (alias_ref IS NOT NULL OR found_at >= ?2) ORDER BY service",
    )?;
    let rows = st.query_map(params![source_ref, now_ms() - MISS_TTL_MS], |r| {
      Ok(TrackAlias { source_ref: source_ref.to_owned(), service: r.get(0)?, alias_ref: r.get(1)?, found_at: r.get(2)? })
    })?;
    Ok(rows.collect::<rusqlite::Result<_>>()?)
  }

  pub fn put_track_aliases(&mut self, rows: &[TrackAlias]) -> Result<()> {
    let tx = self.db.transaction()?;
    {
      let mut st = tx.prepare(
        "INSERT INTO track_alias (source_ref, service, alias_ref, found_at) VALUES (?1, ?2, ?3, ?4)
         ON CONFLICT(source_ref, service) DO UPDATE SET alias_ref = ?3, found_at = ?4",
      )?;
      for a in rows {
        st.execute(params![a.source_ref, a.service, a.alias_ref, a.found_at])?;
      }
    }
    tx.commit()?;
    Ok(())
  }

  /// Устаревшие «не нашлось» — при открытии базы.
  pub(super) fn prune_track_aliases(&self) -> Result<usize> {
    Ok(self.db.execute("DELETE FROM track_alias WHERE alias_ref IS NULL AND found_at < ?1", [now_ms() - MISS_TTL_MS])?)
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn row(service: &str, alias: Option<&str>, at: i64) -> TrackAlias {
    TrackAlias { source_ref: "sc:1".into(), service: service.into(), alias_ref: alias.map(str::to_owned), found_at: at }
  }

  #[test]
  fn stores_found_and_missing_aliases() {
    let mut s = Store::memory().unwrap();
    let now = now_ms();
    s.put_track_aliases(&[row("ym", Some("ym:9"), now), row("yt", None, now)]).unwrap();
    assert_eq!(s.track_aliases("sc:1").unwrap(), vec![row("ym", Some("ym:9"), now), row("yt", None, now)]);
    assert!(s.track_aliases("sc:2").unwrap().is_empty());
    // повтор — перезапись, а не вторая строка
    s.put_track_aliases(&[row("yt", Some("yt:abc"), now + 1)]).unwrap();
    assert_eq!(s.track_aliases("sc:1").unwrap()[1], row("yt", Some("yt:abc"), now + 1));
  }

  #[test]
  fn old_misses_expire_but_found_stay() {
    let mut s = Store::memory().unwrap();
    let old = now_ms() - MISS_TTL_MS - 1000;
    s.put_track_aliases(&[row("ym", Some("ym:9"), old), row("yt", None, old)]).unwrap();
    assert_eq!(s.track_aliases("sc:1").unwrap(), vec![row("ym", Some("ym:9"), old)]);
    assert_eq!(s.prune_track_aliases().unwrap(), 1);
  }
}
