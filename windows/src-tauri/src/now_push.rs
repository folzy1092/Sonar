//! «Сейчас играет» на сервере (SERVER_PROMPT этап 5, API.md §5 и §7): каждое сохранение состояния плеера
//! уходит `PUT /player/state` вместе с названием трека — из этого сервер собирает `GET /oauth/now` для selfbot.
//! Таблицу `tracks` на сервере заполняет только перенос из Dotify, поэтому название, артист и обложка едут в `track`.
use std::sync::Arc;

use serde_json::{json, Value};
use tauri::{AppHandle, Manager};

use crate::commands::Db;
use crate::providers::Track;
use crate::services::Core;
use crate::store::PlayerState;

/// Очередь серверу — окном вокруг текущего трека: длинный плейлист иначе не влезет в 64 КБ `PlayerState`.
const QUEUE_BEFORE: usize = 50;
const QUEUE_MAX: usize = 200;

/// Отправки по очереди (tokio-мьютекс честный): старое состояние не перетрёт новое.
static SENDING: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());

/// Тело `PUT /player/state`: состояние с окном очереди и `track` (если трек есть в кэше).
pub fn body(state: &PlayerState, track: Option<&Track>) -> Value {
  let index = state.queue_index.and_then(|i| usize::try_from(i).ok()).filter(|&i| i < state.queue.len());
  let start = index.map_or(0, |i| i.saturating_sub(QUEUE_BEFORE));
  let queue: Vec<&String> = state.queue.iter().skip(start).take(QUEUE_MAX).collect();
  let mut out = json!({
    "device_id": state.device_id,
    "ref": state.ref_,
    "context": state.context,
    "is_playing": state.is_playing,
    "position_ms": state.position_ms,
    "queue": queue,
    "queue_index": index.map(|i| (i - start) as i64),
    "shuffle": state.shuffle,
    "repeat": state.repeat,
    "client_ts": state.client_ts,
  });
  if let Some(t) = track.filter(|t| Some(&t.ref_) == state.ref_.as_ref()) {
    out["track"] = json!({ "title": t.title, "artist": t.artist, "cover_url": t.cover_url, "duration_ms": t.duration_ms });
  }
  out
}

/// Отправить в фоне. Не вошли в аккаунт или офлайн — молча ничего; сбой сети — только в журнал, без значений.
pub fn spawn(app: AppHandle, state: PlayerState) {
  if crate::offline::is_on() || crate::sync::configured(&app.state::<Db>().0).is_none() {
    return;
  }
  tauri::async_runtime::spawn(async move {
    let _turn = SENDING.lock().await;
    let db = &app.state::<Db>().0;
    let core = app.state::<Arc<Core>>().inner().clone();
    let track = state.ref_.as_ref().and_then(|r| db.lock().unwrap().tracks(std::slice::from_ref(r)).ok()?.into_iter().next());
    let body = body(&state, track.as_ref());
    if let Err(e) = crate::account::call(&core, db, reqwest::Method::PUT, "player/state", Some(body), true).await {
      log::debug!("«сейчас играет» на сервер не ушло: {e}");
      crate::account::notify_ended(&app, &e);
    }
  });
}

#[cfg(test)]
mod tests {
  use super::*;

  fn state(queue: usize, index: Option<i64>) -> PlayerState {
    PlayerState {
      device_id: None,
      ref_: Some("sc:1".into()),
      context: Some("favorites".into()),
      is_playing: true,
      position_ms: 1000,
      queue: (0..queue).map(|i| format!("sc:{i}")).collect(),
      queue_index: index,
      shuffle: false,
      repeat: "off".into(),
      client_ts: 7,
    }
  }

  fn track(r: &str) -> Track {
    serde_json::from_value(json!({
      "ref": r, "title": "море стало моим домом.", "artist": "одиссея", "artists": [], "album": null,
      "duration_ms": 123000, "cover_url": "https://i1.sndcdn.com/a.png", "url": null, "explicit": false, "available": true
    }))
    .unwrap()
  }

  #[test]
  fn adds_track_of_current_ref_only() {
    let b = body(&state(3, Some(1)), Some(&track("sc:1")));
    assert_eq!(b["track"]["title"], "море стало моим домом.");
    assert_eq!(b["track"]["duration_ms"], 123000);
    assert_eq!(b["ref"], "sc:1");
    assert!(body(&state(3, Some(1)), Some(&track("sc:2"))).get("track").is_none(), "чужой трек не подписываем");
    assert!(body(&state(3, Some(1)), None).get("track").is_none());
  }

  #[test]
  fn long_queue_is_cut_around_current() {
    let b = body(&state(1000, Some(500)), None);
    let q = b["queue"].as_array().unwrap();
    assert_eq!(q.len(), QUEUE_MAX);
    assert_eq!(q[0], "sc:450");
    assert_eq!(b["queue_index"], 50);
    assert_eq!(q[50], "sc:500");
    let short = body(&state(3, Some(2)), None);
    assert_eq!(short["queue"].as_array().unwrap().len(), 3);
    assert_eq!(short["queue_index"], 2);
    assert!(body(&state(3, Some(9)), None)["queue_index"].is_null(), "индекс за очередью — без индекса");
  }
}
