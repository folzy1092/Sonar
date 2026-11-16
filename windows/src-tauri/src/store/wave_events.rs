//! Журнал выдачи и исходов своей волны (docs/WAVE.md, этап 6): что выдали, с какими признаками и
//! чем кончилось. По нему считается `wave_stats`, а позже — подбор весов. С миграции № 8 события
//! едут в синк аккаунта (docs/WAVE.md §3а): текстовый `id`, `device_id`, `rev` — выдача и исход
//! поднимают `rev`, `features_json` в синк не идёт.

use super::{now_ms, Store, LOCAL_USER};
use anyhow::Result;
use rusqlite::params;
use serde::Serialize;

const DAY: i64 = 24 * 3600 * 1000;
/// Строки старше стольких дней удаляются при запуске.
pub const KEEP_DAYS: i64 = 180;

/// Один выданный трек волны.
#[derive(Debug, Clone)]
pub struct ServedEvent {
  pub ref_: String,
  /// Главный артист (нижний регистр, как в `wave::artist_key`).
  pub artist: String,
  /// Откуда кандидат: `similar` / `hop2` / `liked` / `seed`.
  pub source: String,
  /// От какого сида пришёл.
  pub seed_ref: Option<String>,
  /// `wave::Features` на момент выдачи, JSON.
  pub features_json: Option<String>,
}

/// Строка сводки: `key` — режим или источник.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct WaveStatRow {
  pub key: String,
  /// Выдано.
  pub served: i64,
  /// Сыграно (есть исход).
  pub played: i64,
  /// Доля ранних пропусков среди сыгранных (оценка ≤ −1).
  pub early_skip_share: f64,
  /// Доля дослушанных или лайкнутых среди сыгранных (оценка ≥ +1).
  pub finished_share: f64,
  /// Средняя оценка сыгранных.
  pub avg_reward: f64,
}

/// Сводка `wave_stats`: по режимам и по источникам кандидатов.
#[derive(Debug, Clone, Serialize)]
pub struct WaveStats {
  pub days: i64,
  pub by_mode: Vec<WaveStatRow>,
  pub by_source: Vec<WaveStatRow>,
}

impl Store {
  /// Записать выданную порцию. `session_id` — сессия волны (создаёт интерфейс).
  pub fn log_wave_served(&mut self, session_id: &str, mode: &str, items: &[ServedEvent]) -> Result<()> {
    let tx = self.db.transaction()?;
    {
      let device: String = tx.query_row("SELECT value FROM sync_state WHERE key = 'device_id'", [], |r| r.get(0)).unwrap_or_default();
      let rev: i64 = tx.query_row("UPDATE sync_rev SET value = value + 1 WHERE id = 1 RETURNING value", [], |r| r.get(0))?;
      let mut st = tx.prepare(
        "INSERT INTO wave_events (id, user_id, device_id, session_id, ref, artist, mode, source, seed_ref, features_json, served_at, rev)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)",
      )?;
      let now = now_ms();
      for e in items {
        st.execute(params![
          super::new_id("we"),
          LOCAL_USER,
          device,
          session_id,
          e.ref_,
          e.artist,
          mode,
          e.source,
          e.seed_ref,
          e.features_json,
          now,
          rev
        ])?;
      }
    }
    tx.commit()?;
    Ok(())
  }

  /// Записать исход трека: к последней выдаче этого трека в сессии, у которой исхода ещё нет.
  /// Вернёт `false`, если подходящей строки нет (трек выдан не волной или до журнала).
  pub fn finish_wave_event(&self, session_id: &str, r: &str, reward: f64, listened_ms: i64) -> Result<bool> {
    let rev = self.next_rev()?;
    let n = self.db.execute(
      "UPDATE wave_events SET reward = ?4, listened_ms = ?5, ended_at = ?6, rev = ?7
       WHERE rowid = (SELECT rowid FROM wave_events
                      WHERE user_id = ?1 AND session_id = ?2 AND ref = ?3 AND ended_at IS NULL
                      ORDER BY served_at DESC, rowid DESC LIMIT 1)",
      params![LOCAL_USER, session_id, r, reward, listened_ms, now_ms(), rev],
    )?;
    Ok(n > 0)
  }

  /// Сводка за `days` дней: по режимам и по источникам.
  pub fn wave_stats(&self, days: i64) -> Result<WaveStats> {
    let since = now_ms() - days.max(1) * DAY;
    Ok(WaveStats { days, by_mode: self.stat_rows("mode", since)?, by_source: self.stat_rows("source", since)? })
  }

  /// `column` — только литерал из этого файла, не пользовательский ввод.
  fn stat_rows(&self, column: &str, since: i64) -> Result<Vec<WaveStatRow>> {
    let mut st = self.db.prepare(&format!(
      "SELECT {column}, COUNT(*), COALESCE(SUM(ended_at IS NOT NULL), 0), COALESCE(SUM(reward <= -1), 0),
              COALESCE(SUM(reward >= 1), 0), COALESCE(SUM(reward), 0)
       FROM wave_events WHERE user_id = ?1 AND served_at >= ?2 GROUP BY {column} ORDER BY COUNT(*) DESC, {column}"
    ))?;
    let rows = st.query_map(params![LOCAL_USER, since], |r| {
      Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?, r.get::<_, i64>(2)?, r.get::<_, i64>(3)?, r.get::<_, i64>(4)?, r.get::<_, f64>(5)?))
    })?;
    let mut out = Vec::new();
    for row in rows {
      let (key, served, played, early, finished, sum) = row?;
      let share = |n: i64| if played > 0 { n as f64 / played as f64 } else { 0.0 };
      out.push(WaveStatRow {
        key,
        served,
        played,
        early_skip_share: share(early),
        finished_share: share(finished),
        avg_reward: if played > 0 { sum / played as f64 } else { 0.0 },
      });
    }
    Ok(out)
  }

  /// Удалить строки старше `KEEP_DAYS` — при запуске.
  pub(super) fn prune_wave_events(&self) -> Result<usize> {
    Ok(self.db.execute("DELETE FROM wave_events WHERE served_at < ?1", params![now_ms() - KEEP_DAYS * DAY])?)
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn ev(r: &str, source: &str) -> ServedEvent {
    ServedEvent { ref_: r.into(), artist: format!("art-{r}"), source: source.into(), seed_ref: Some("sc:seed".into()), features_json: Some("{}".into()) }
  }

  #[test]
  fn served_finished_and_stats() {
    let mut s = Store::memory().unwrap();
    s.log_wave_served("s1", "own", &[ev("sc:1", "similar"), ev("sc:2", "similar"), ev("sc:3", "liked")]).unwrap();
    s.log_wave_served("s2", "sad", &[ev("sc:4", "similar")]).unwrap();
    assert!(s.finish_wave_event("s1", "sc:1", -1.0, 4_000).unwrap(), "ранний пропуск");
    assert!(s.finish_wave_event("s1", "sc:2", 1.0, 200_000).unwrap(), "дослушан");
    assert!(s.finish_wave_event("s2", "sc:4", 1.5, 90_000).unwrap(), "лайк");
    // sc:3 не сыгран — в «сыграно» не попадает, но «выдано» считается
    let st = s.wave_stats(30).unwrap();
    let own = st.by_mode.iter().find(|r| r.key == "own").unwrap();
    assert_eq!((own.served, own.played), (3, 2));
    assert_eq!(own.early_skip_share, 0.5);
    assert_eq!(own.finished_share, 0.5);
    assert_eq!(own.avg_reward, 0.0);
    let sad = st.by_mode.iter().find(|r| r.key == "sad").unwrap();
    assert_eq!((sad.served, sad.played, sad.avg_reward), (1, 1, 1.5));
    let liked = st.by_source.iter().find(|r| r.key == "liked").unwrap();
    assert_eq!((liked.served, liked.played, liked.avg_reward), (1, 0, 0.0), "без исходов — нули, а не деление на ноль");
    let similar = st.by_source.iter().find(|r| r.key == "similar").unwrap();
    assert_eq!((similar.served, similar.played), (3, 3));
  }

  #[test]
  fn outcome_goes_to_latest_open_row_of_this_session() {
    let mut s = Store::memory().unwrap();
    s.log_wave_served("s1", "own", &[ev("sc:1", "similar")]).unwrap();
    // тот же трек выдан снова (после пересборки очереди) — исход ложится на последнюю выдачу
    std::thread::sleep(std::time::Duration::from_millis(2));
    s.log_wave_served("s1", "own", &[ev("sc:1", "similar")]).unwrap();
    assert!(s.finish_wave_event("s1", "sc:1", 1.0, 100_000).unwrap());
    let latest: Option<i64> = s.db.query_row("SELECT ended_at FROM wave_events WHERE rowid = 2", [], |r| r.get(0)).unwrap();
    let first: Option<i64> = s.db.query_row("SELECT ended_at FROM wave_events WHERE rowid = 1", [], |r| r.get(0)).unwrap();
    assert!(latest.is_some() && first.is_none());
    // чужая сессия и трек без выдачи — ничего не меняется
    assert!(!s.finish_wave_event("other", "sc:1", 1.0, 1).unwrap());
    assert!(!s.finish_wave_event("s1", "sc:99", 1.0, 1).unwrap());
    // исход пишется один раз; второй вызов уходит на оставшуюся открытую строку
    assert!(s.finish_wave_event("s1", "sc:1", -1.0, 2_000).unwrap());
    assert!(!s.finish_wave_event("s1", "sc:1", -1.0, 2_000).unwrap());
  }

  #[test]
  fn old_rows_are_pruned_on_open_and_features_are_kept() {
    let mut s = Store::memory().unwrap();
    s.log_wave_served("s1", "own", &[ev("sc:1", "similar")]).unwrap();
    s.db
      .execute(
        "INSERT INTO wave_events (user_id, session_id, ref, artist, mode, source, served_at) VALUES (?1, 'old', 'sc:0', 'a', 'own', 'similar', ?2)",
        params![LOCAL_USER, now_ms() - (KEEP_DAYS + 1) * DAY],
      )
      .unwrap();
    assert_eq!(s.prune_wave_events().unwrap(), 1);
    let left: i64 = s.db.query_row("SELECT COUNT(*) FROM wave_events", [], |r| r.get(0)).unwrap();
    assert_eq!(left, 1);
    let f: String = s.db.query_row("SELECT features_json FROM wave_events", [], |r| r.get(0)).unwrap();
    assert_eq!(f, "{}");
  }
}
