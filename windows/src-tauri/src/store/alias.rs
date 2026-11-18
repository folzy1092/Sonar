//! `track_alias` — тот же трек на другом сервисе (резервный сервис, «SoundCloud через Яндекс»):
//! найденный ref запоминается, чтобы не искать заново; «не нашлось» живёт неделю — каталоги
//! пополняются (docs/DB.md «track_alias»).

use super::{now_ms, Store};
use crate::services::fallback::AliasWrite;
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

  /// Изменения резервного сервиса (`Fallback::take_writes`) — одной транзакцией, по порядку:
  /// найденное / «не нашлось» — запись, перестало играть — прочь.
  pub fn apply_track_alias_writes(&mut self, writes: &[AliasWrite]) -> Result<()> {
    let tx = self.db.transaction()?;
    for w in writes {
      match w {
        AliasWrite::Put(a) => {
          tx.execute(
            "INSERT INTO track_alias (source_ref, service, alias_ref, found_at) VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT(source_ref, service) DO UPDATE SET alias_ref = ?3, found_at = ?4",
            params![a.source_ref, a.service, a.alias_ref, a.found_at],
          )?;
        }
        AliasWrite::Drop { source_ref, service } => {
          tx.execute("DELETE FROM track_alias WHERE source_ref = ?1 AND service = ?2", params![source_ref, service])?;
        }
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

  fn put(s: &mut Store, rows: &[TrackAlias]) {
    let writes: Vec<AliasWrite> = rows.iter().cloned().map(AliasWrite::Put).collect();
    s.apply_track_alias_writes(&writes).unwrap();
  }

  #[test]
  fn stores_found_and_missing_aliases() {
    let mut s = Store::memory().unwrap();
    let now = now_ms();
    put(&mut s, &[row("ym", Some("ym:9"), now), row("yt", None, now)]);
    assert_eq!(s.track_aliases("sc:1").unwrap(), vec![row("ym", Some("ym:9"), now), row("yt", None, now)]);
    assert!(s.track_aliases("sc:2").unwrap().is_empty());
    // повтор — перезапись, а не вторая строка
    put(&mut s, &[row("yt", Some("yt:abc"), now + 1)]);
    assert_eq!(s.track_aliases("sc:1").unwrap()[1], row("yt", Some("yt:abc"), now + 1));
  }

  #[test]
  fn drops_alias_that_stopped_playing() {
    let mut s = Store::memory().unwrap();
    let now = now_ms();
    let drop = |service: &str| AliasWrite::Drop { source_ref: "sc:1".into(), service: service.into() };
    let writes = [AliasWrite::Put(row("ym", Some("ym:9"), now)), AliasWrite::Put(row("yt", Some("yt:1"), now)), drop("yt"), drop("vk")];
    s.apply_track_alias_writes(&writes).unwrap();
    assert_eq!(s.track_aliases("sc:1").unwrap(), vec![row("ym", Some("ym:9"), now)]);
  }

  #[test]
  fn old_misses_expire_but_found_stay() {
    let mut s = Store::memory().unwrap();
    let old = now_ms() - MISS_TTL_MS - 1000;
    put(&mut s, &[row("ym", Some("ym:9"), old), row("yt", None, old)]);
    assert_eq!(s.track_aliases("sc:1").unwrap(), vec![row("ym", Some("ym:9"), old)]);
    assert_eq!(s.prune_track_aliases().unwrap(), 1);
  }
}
