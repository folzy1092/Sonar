//! Синк по Wi‑Fi, пока сервера Sonar нет: ПК отвечает привязанным телефонам как сервер (API.md §6), сообщения
//! идут по уже открытой связи пульта (`sync_push`, `sync_pull`, `plays` — docs/API.md «Пульт»).
//! Хаб — своя копия строк в базе ПК (`store/hub.rs`). Сам ПК — такой же участник: перед ответом на `sync_pull`
//! он отдаёт хабу своё, после `sync_push` забирает чужое — тем же `sync_once`, что и с сервером, поэтому
//! правила слияния одни. Появится сервер — ПК и телефон переключаются на него, курсоры сбрасываются
//! (`Store::sync_target`), повторная отправка безопасна: сервер узнаёт `op_id`.
//! Без Tauri — весь обмен проверяется тестами на базе в памяти.

use super::protocol::{self, SyncRequest};
use crate::store::{Op, PlayUpload, Store};
use crate::sync::{sync_once, PullReply, PushReply, Transport};
use anyhow::Result;
use serde_json::json;
use std::sync::Mutex;

/// Сколько байт изменений в одном ответе `sync_pull`: телефон по умолчанию принимает сообщение до 1 МБ.
pub const PULL_BUDGET: usize = 512 * 1024;

/// Обмены ПК с хабом — по одному: два телефона сразу не должны гонять `sync_once` наперегонки.
static TURN: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

/// ПК как участник обмена с хабом в той же базе. Прослушивания хаб не берёт.
struct LocalHub<'a> {
  db: &'a Mutex<Store>,
}

impl Transport for LocalHub<'_> {
  async fn push(&self, ops: &[Op]) -> Result<PushReply> {
    let (_, applied) = self.db.lock().unwrap().hub_push(ops)?;
    Ok(PushReply { applied })
  }

  async fn pull(&self, since: i64) -> Result<PullReply> {
    let p = self.db.lock().unwrap().hub_pull(since, usize::MAX)?;
    Ok(PullReply { rev: p.rev, changes: p.changes })
  }

  async fn plays(&self, _: &[PlayUpload]) -> Result<usize> {
    Ok(0)
  }

  fn sends_plays(&self) -> bool {
    false
  }
}

/// Обмен ПК с хабом. Вернёт, сколько изменений ПК применил у себя.
async fn participate(db: &Mutex<Store>) -> Result<usize> {
  db.lock().unwrap().sync_target("lan")?;
  Ok(sync_once(db, &LocalHub { db }).await?.pulled)
}

/// Ответ телефону и сколько изменений применил ПК (больше нуля — интерфейс перечитывает библиотеку).
#[derive(Debug)]
pub struct Answer {
  pub reply: String,
  pub applied_on_pc: usize,
}

/// Ответить на запрос синка привязанного телефона `device`.
pub async fn answer(db: &Mutex<Store>, device: &str, req: SyncRequest, re: Option<&str>, now: i64) -> Result<Answer> {
  let _turn = TURN.lock().await;
  let (reply, applied_on_pc) = match req {
    SyncRequest::Push(ops) => {
      let (rev, applied) = db.lock().unwrap().hub_push(&ops)?;
      // телефонное — сразу в библиотеку ПК
      let on_pc = participate(db).await?;
      (protocol::message("sync_push", json!({ "rev": rev, "applied": applied }), re), on_pc)
    }
    SyncRequest::Pull { since } => {
      // сначала своё — в хаб, чтобы телефон забрал и его
      let on_pc = participate(db).await?;
      let pull = db.lock().unwrap().hub_pull(since, PULL_BUDGET)?;
      (protocol::message("sync_pull", serde_json::to_value(&pull)?, re), on_pc)
    }
  };
  db.lock().unwrap().hub_touch(device, now)?;
  Ok(Answer { reply, applied_on_pc })
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::store::Play;
  use serde_json::Value;

  fn block<F: std::future::Future>(f: F) -> F::Output {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap().block_on(f)
  }

  fn body(reply: &str) -> Value {
    let v: Value = serde_json::from_str(reply).unwrap();
    assert_eq!(v["re"], "m1");
    v["body"].clone()
  }

  fn phone_op(id: &str, kind: &str, key: &str, value: Option<Value>, ts: i64) -> Op {
    Op { op_id: id.into(), kind: kind.into(), key: key.into(), value, client_ts: ts, rev: 0 }
  }

  fn push(db: &Mutex<Store>, ops: Vec<Op>) -> Answer {
    block(answer(db, "phone", SyncRequest::Push(ops), Some("m1"), 100)).unwrap()
  }

  fn pull(db: &Mutex<Store>, since: i64) -> Value {
    body(&block(answer(db, "phone", SyncRequest::Pull { since }, Some("m1"), 100)).unwrap().reply)
  }

  #[test]
  fn phone_like_and_setting_reach_pc_library() {
    let pc = Mutex::new(Store::memory().unwrap());
    let a = push(
      &pc,
      vec![
        phone_op("ph:like:1", "like", "sc:1", Some(json!({ "kind": "track", "added_at": 5 })), 5),
        phone_op("ph:setting:2", "setting", "appearance.cover_theme", Some(json!(true)), 6),
      ],
    );
    assert_eq!(body(&a.reply)["applied"], json!(["ph:like:1", "ph:setting:2"]));
    assert_eq!(a.applied_on_pc, 2, "ПК сразу забрал телефонное");
    let s = pc.lock().unwrap();
    assert_eq!(s.likes("track").unwrap().into_iter().map(|x| x.0).collect::<Vec<_>>(), vec!["sc:1".to_owned()]);
    assert_eq!(s.setting("appearance.cover_theme").unwrap(), Some(json!(true)));
    assert_eq!(s.hub_peers().unwrap().get("phone"), Some(&100), "время обмена запомнено");
  }

  #[test]
  fn pc_changes_reach_phone_on_pull_and_dont_bounce() {
    let pc = Mutex::new(Store::memory().unwrap());
    {
      let mut s = pc.lock().unwrap();
      s.set_like("ym:7", true).unwrap();
      s.create_playlist("дорога", &["ym:7".into()], None).unwrap();
    }
    let first = pull(&pc, 0);
    let kinds: Vec<&str> = first["changes"].as_array().unwrap().iter().map(|c| c["type"].as_str().unwrap()).collect();
    assert!(kinds.contains(&"like") && kinds.contains(&"playlist") && kinds.contains(&"playlist_item"), "{kinds:?}");
    assert_eq!(first["more"], false);
    let rev = first["rev"].as_i64().unwrap();
    // повторный обмен: ПК своё обратно не шлёт, телефону нового нет
    let again = pull(&pc, rev);
    assert!(again["changes"].as_array().unwrap().is_empty(), "{again}");
    assert_eq!(again["rev"].as_i64().unwrap(), rev);
  }

  #[test]
  fn repeated_push_is_harmless() {
    let pc = Mutex::new(Store::memory().unwrap());
    let op = phone_op("ph:like:3", "like", "sc:2", Some(json!({ "kind": "track", "added_at": 1 })), 1);
    push(&pc, vec![op.clone()]);
    let again = push(&pc, vec![op]);
    assert_eq!(body(&again.reply)["applied"], json!(["ph:like:3"]));
    assert_eq!(again.applied_on_pc, 0, "повтор не применяется дважды");
  }

  #[test]
  fn pc_plays_are_kept_for_the_server() {
    let pc = Mutex::new(Store::memory().unwrap());
    let play = Play { ref_: "sc:1".into(), artist: "A".into(), context: None, played_at: 5, listened_ms: 90_000 };
    pc.lock().unwrap().add_play(&play).unwrap();
    pull(&pc, 0);
    assert_eq!(pc.lock().unwrap().plays_to_upload(10).unwrap().len(), 1, "хаб прослушивания не забирает");
  }
}
