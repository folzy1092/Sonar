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
/// Длительность — из кэша, нет там — какую знает плеер (`player_duration_ms`); неизвестна — поля нет вовсе,
/// как и пустой обложки: бот должен видеть «не знаю», а не 0 (docs/NOW_ACCURACY_PROMPT.md §2).
pub fn body(state: &PlayerState, track: Option<&Track>, player_duration_ms: Option<u64>) -> Value {
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
    let mut card = json!({ "title": t.title, "artist": t.artist });
    if let Some(cover) = t.cover_url.as_deref().filter(|c| !c.is_empty()) {
      card["cover_url"] = json!(cover);
    }
    if let Some(ms) = Some(t.duration_ms).filter(|&ms| ms > 0).or(player_duration_ms.filter(|&ms| ms > 0)) {
      card["duration_ms"] = json!(ms);
    }
    out["track"] = card;
  }
  out
}

/// Отправить в фоне. Не вошли в аккаунт или офлайн — молча ничего; сбой сети — только в журнал, без значений.
pub fn spawn(app: AppHandle, state: PlayerState, player_duration_ms: Option<u64>) {
  if crate::offline::is_on() || crate::sync::configured(&app.state::<Db>().0).is_none() {
    return;
  }
  tauri::async_runtime::spawn(async move {
    let _turn = SENDING.lock().await;
    let db = &app.state::<Db>().0;
    let core = app.state::<Arc<Core>>().inner().clone();
    let track = state.ref_.as_ref().and_then(|r| db.lock().unwrap().tracks(std::slice::from_ref(r)).ok()?.into_iter().next());
    let body = body(&state, track.as_ref(), player_duration_ms);
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
    let b = body(&state(3, Some(1)), Some(&track("sc:1")), None);
    assert_eq!(b["track"]["title"], "море стало моим домом.");
    assert_eq!(b["track"]["duration_ms"], 123000);
    assert_eq!(b["ref"], "sc:1");
    assert!(body(&state(3, Some(1)), Some(&track("sc:2")), None).get("track").is_none(), "чужой трек не подписываем");
    assert!(body(&state(3, Some(1)), None, Some(5000)).get("track").is_none());
  }

  #[test]
  fn unknown_duration_and_cover_are_omitted_not_zero() {
    let bare = Track { duration_ms: 0, cover_url: None, ..track("sc:1") };
    let b = body(&state(3, Some(1)), Some(&bare), None);
    assert!(b["track"].get("duration_ms").is_none(), "0 не шлём: {b}");
    assert!(b["track"].get("cover_url").is_none());
    assert_eq!(b["track"]["title"], "море стало моим домом.");
    let b = body(&state(3, Some(1)), Some(&Track { cover_url: Some(String::new()), ..bare.clone() }), Some(0));
    assert!(b["track"].get("cover_url").is_none() && b["track"].get("duration_ms").is_none());
    let b = body(&state(3, Some(1)), Some(&bare), Some(201_500));
    assert_eq!(b["track"]["duration_ms"], 201_500, "нет в кэше — берём из плеера");
    let b = body(&state(3, Some(1)), Some(&track("sc:1")), Some(1));
    assert_eq!(b["track"]["duration_ms"], 123000, "кэш важнее плеера");
  }

  #[test]
  fn long_queue_is_cut_around_current() {
    let b = body(&state(1000, Some(500)), None, None);
    let q = b["queue"].as_array().unwrap();
    assert_eq!(q.len(), QUEUE_MAX);
    assert_eq!(q[0], "sc:450");
    assert_eq!(b["queue_index"], 50);
    assert_eq!(q[50], "sc:500");
    let short = body(&state(3, Some(2)), None, None);
    assert_eq!(short["queue"].as_array().unwrap().len(), 3);
    assert_eq!(short["queue_index"], 2);
    assert!(body(&state(3, Some(9)), None, None)["queue_index"].is_null(), "индекс за очередью — без индекса");
  }
}
