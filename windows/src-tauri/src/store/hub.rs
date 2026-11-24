//! Хаб синка в локальной сети: пока сервера Sonar нет, ПК сам отвечает привязанным телефонам как сервер
//! (API.md §6). Та же логика, что у `MemoryServer` в `sync.rs`: глобальный `rev`, повтор `op_id` не
//! применяется дважды, настройки — «побеждает позднее» по `client_ts`. Хаб хранит свою копию строк
//! (`hub_rows`), а не правит библиотеку ПК напрямую: ПК — такой же участник и меняется с хабом через
//! `sync_once` (`remote/sync_hub.rs`), поэтому правила слияния везде одни.
//! Прослушиваний телефона хаб не принимает: переслать их на сервер ПК не может, телефон держит их до сервера.

use super::{Change, Op, Store};
use anyhow::Result;
use rusqlite::{params, OptionalExtension};
use serde::Serialize;
use serde_json::Value;
use std::collections::HashMap;

/// Ответ `sync_pull`: изменения после `since` по возрастанию `rev`; `more` — отдали не всё (предел по
/// размеру), телефон просит ещё с нового `rev`.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct HubPull {
  pub rev: i64,
  pub changes: Vec<Change>,
  pub more: bool,
}

/// Сколько байт сверх значения считаем на одно изменение (тип, ключ, rev, обвязка JSON).
const CHANGE_OVERHEAD: usize = 64;

impl Store {
  /// Последний `rev` хаба: строки не удаляются (удалённое — `value = null`), так что максимум только растёт.
  pub fn hub_rev(&self) -> Result<i64> {
    Ok(self.db.query_row("SELECT COALESCE(MAX(rev), 0) FROM hub_rows", [], |r| r.get(0))?)
  }

  /// `sync_push`: принять операции. Вернёт новый `rev` и все `op_id` (и применённые, и уже виденные, и
  /// проигравшие по времени настройки — их отправитель заберёт победителя в `pull`, как `MemorySyncServer` на iPhone).
  pub fn hub_push(&mut self, ops: &[Op]) -> Result<(i64, Vec<String>)> {
    let tx = self.db.transaction()?;
    let mut rev: i64 = tx.query_row("SELECT COALESCE(MAX(rev), 0) FROM hub_rows", [], |r| r.get(0))?;
    let mut applied = Vec::with_capacity(ops.len());
    for o in ops {
      let fresh = tx.execute("INSERT OR IGNORE INTO hub_ops (op_id) VALUES (?1)", [&o.op_id])? == 1;
      if fresh {
        let ts: Option<i64> = tx
          .query_row("SELECT client_ts FROM hub_rows WHERE kind = ?1 AND key = ?2", params![o.kind, o.key], |r| r.get(0))
          .optional()?;
        let older = o.kind == "setting" && ts.is_some_and(|ts| ts > o.client_ts);
        rev += 1;
        if older {
          // проигравший мог уже забрать победителя раньше — поднимаем его rev, чтобы пришёл в pull заново
          tx.execute("UPDATE hub_rows SET rev = ?1 WHERE kind = ?2 AND key = ?3", params![rev, o.kind, o.key])?;
        } else {
          let value = o.value.as_ref().map(Value::to_string);
          tx.execute(
            "INSERT INTO hub_rows (kind, key, value_json, rev, client_ts) VALUES (?1, ?2, ?3, ?4, ?5)
             ON CONFLICT(kind, key) DO UPDATE SET value_json = ?3, rev = ?4, client_ts = ?5",
            params![o.kind, o.key, value, rev, o.client_ts],
          )?;
        }
      }
      applied.push(o.op_id.clone());
    }
    tx.commit()?;
    Ok((rev, applied))
  }

  /// `sync_pull`: изменения после `since`, пока влезают в `budget` байт (хотя бы одно, даже большое).
  pub fn hub_pull(&self, since: i64, budget: usize) -> Result<HubPull> {
    let mut st = self.db.prepare("SELECT kind, key, value_json, rev FROM hub_rows WHERE rev > ?1 ORDER BY rev")?;
    let mut rows = st.query([since])?;
    let mut out = HubPull { rev: since, ..HubPull::default() };
    let mut used = 0usize;
    while let Some(r) = rows.next()? {
      let raw: Option<String> = r.get(2)?;
      let size = raw.as_ref().map_or(4, String::len) + CHANGE_OVERHEAD;
      if !out.changes.is_empty() && used + size > budget {
        out.more = true;
        break;
      }
      used += size;
      let value = raw.map(|s| serde_json::from_str(&s)).transpose()?;
      let change = Change { kind: r.get(0)?, key: r.get(1)?, value, rev: r.get(3)? };
      out.rev = change.rev;
      out.changes.push(change);
    }
    if !out.more {
      out.rev = out.rev.max(self.hub_rev()?);
    }
    Ok(out)
  }

  /// Телефон только что обменялся с хабом.
  pub fn hub_touch(&self, device: &str, now: i64) -> Result<()> {
    self.db.execute(
      "INSERT INTO hub_peers (device_id, last_sync) VALUES (?1, ?2) ON CONFLICT(device_id) DO UPDATE SET last_sync = ?2",
      params![device, now],
    )?;
    Ok(())
  }

  /// Когда каждый телефон последний раз обменивался (для «Система → Пульт»).
  pub fn hub_peers(&self) -> Result<HashMap<String, i64>> {
    let mut st = self.db.prepare("SELECT device_id, last_sync FROM hub_peers")?;
    let rows = st.query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?;
    Ok(rows.collect::<rusqlite::Result<_>>()?)
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use serde_json::json;

  const ALL: usize = 1 << 20;

  fn op(id: &str, kind: &str, key: &str, value: Option<Value>, ts: i64) -> Op {
    Op { op_id: id.into(), kind: kind.into(), key: key.into(), value, client_ts: ts, rev: 0 }
  }

  #[test]
  fn push_then_pull_returns_rows_in_rev_order() {
    let mut s = Store::memory().unwrap();
    let (rev, applied) =
      s.hub_push(&[op("a", "like", "sc:1", Some(json!({"liked_at": 1})), 1), op("b", "setting", "x", Some(json!(1)), 2)]).unwrap();
    assert_eq!(rev, 2);
    assert_eq!(applied, vec!["a", "b"]);
    let pull = s.hub_pull(0, ALL).unwrap();
    assert_eq!(pull.rev, 2);
    assert!(!pull.more);
    assert_eq!(pull.changes.iter().map(|c| c.key.as_str()).collect::<Vec<_>>(), ["sc:1", "x"]);
    assert!(s.hub_pull(2, ALL).unwrap().changes.is_empty());
  }

  #[test]
  fn repeated_op_is_listed_but_not_applied_twice() {
    let mut s = Store::memory().unwrap();
    s.hub_push(&[op("a", "like", "sc:1", Some(json!({})), 1)]).unwrap();
    let (rev, applied) = s.hub_push(&[op("a", "like", "sc:1", None, 5)]).unwrap();
    assert_eq!(rev, 1, "повтор не поднимает rev");
    assert_eq!(applied, vec!["a"]);
    assert!(s.hub_pull(0, ALL).unwrap().changes[0].value.is_some(), "удаление из повтора не применилось");
  }

  #[test]
  fn later_setting_wins_by_client_ts() {
    let mut s = Store::memory().unwrap();
    s.hub_push(&[op("new", "setting", "theme", Some(json!("dark")), 200)]).unwrap();
    let (_, applied) = s.hub_push(&[op("old", "setting", "theme", Some(json!("light")), 100)]).unwrap();
    assert_eq!(applied, vec!["old"], "проигравшая настройка тоже подтверждается");
    let again = s.hub_pull(1, ALL).unwrap();
    assert_eq!(again.changes.len(), 1, "победитель уходит в pull заново");
    assert_eq!(again.changes[0].value, Some(json!("dark")));
    // лайки — по порядку прихода, время не сравнивается
    s.hub_push(&[op("l1", "like", "sc:1", Some(json!({})), 200), op("l2", "like", "sc:1", None, 100)]).unwrap();
    let likes: Vec<_> = s.hub_pull(0, ALL).unwrap().changes.into_iter().filter(|c| c.kind == "like").collect();
    assert_eq!(likes[0].value, None);
  }

  #[test]
  fn pull_pages_by_size_and_always_moves() {
    let mut s = Store::memory().unwrap();
    let big = json!("x".repeat(500));
    let ops: Vec<Op> = (0..5).map(|i| op(&format!("o{i}"), "like", &format!("sc:{i}"), Some(big.clone()), i)).collect();
    s.hub_push(&ops).unwrap();
    let first = s.hub_pull(0, 1200).unwrap();
    assert!(first.more);
    assert_eq!(first.changes.len(), 2);
    assert_eq!(first.rev, 2);
    let tiny = s.hub_pull(first.rev, 1).unwrap();
    assert_eq!(tiny.changes.len(), 1, "даже большое изменение отдаётся по одному");
    let mut since = tiny.rev;
    loop {
      let p = s.hub_pull(since, 1200).unwrap();
      since = p.rev;
      if !p.more {
        break;
      }
    }
    assert_eq!(since, 5);
  }

  #[test]
  fn peers_remember_last_sync() {
    let s = Store::memory().unwrap();
    s.hub_touch("phone", 100).unwrap();
    s.hub_touch("phone", 200).unwrap();
    assert_eq!(s.hub_peers().unwrap().get("phone"), Some(&200));
  }

  #[test]
  fn switching_sync_target_resets_cursors() {
    let mut s = Store::memory().unwrap();
    s.sync_target("lan").unwrap();
    s.set_pulled_rev(7).unwrap();
    s.mark_pushed(5).unwrap();
    s.sync_target("lan").unwrap();
    assert_eq!(s.pulled_rev().unwrap(), 7, "та же сторона — курсоры на месте");
    s.sync_target("server").unwrap();
    assert_eq!(s.pulled_rev().unwrap(), 0);
    assert!(s.pending_ops(10).is_ok());
  }

  #[test]
  fn switching_sync_target_resends_rows_that_came_back_as_echo() {
    let mut s = Store::memory().unwrap();
    s.sync_target("server").unwrap();
    s.set_like("sc:1", true).unwrap();
    let plan = s.pending_ops(10).unwrap();
    s.mark_pushed(plan.upto).unwrap();
    // сервер вернул наше же изменение: строка стала rev = 0, как пришедшая
    let echo = Change { kind: "like".into(), key: "sc:1".into(), value: Some(json!({ "kind": "track", "added_at": 1 })), rev: 3 };
    s.apply_changes(&[echo]).unwrap();
    assert!(s.pending_ops(10).unwrap().ops.is_empty());
    s.sync_target("lan").unwrap();
    let again = s.pending_ops(10).unwrap();
    assert_eq!(again.ops.iter().map(|o| o.key.as_str()).collect::<Vec<_>>(), vec!["sc:1"], "новая сторона получит всё");
    s.mark_pushed(again.upto).unwrap();
    assert!(s.pending_ops(10).unwrap().ops.is_empty(), "после отправки снова тихо");
  }
}
