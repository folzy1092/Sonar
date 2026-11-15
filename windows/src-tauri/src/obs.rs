//! Плашка «сейчас играет» для OBS без сервера: Sonar сам отдаёт страницу на постоянном адресе
//! `http://127.0.0.1:53119/obs` (OBS стоит на том же компьютере — источник «Браузер»).
//! Страница (`obs.html`) раз в секунду берёт `/obs/now` и сама плавно двигает полосу между запросами.
//! Данные — те же, что для плашки Windows и Discord (`media_update`). Настройки: `obs.size`
//! (`standard` 450×130 / `compact` 320×72) и `obs.hide_paused`.

use crate::media::MediaInfo;
use axum::{
  body::Body,
  extract::State,
  http::{header, HeaderValue, Response},
  routing::get,
  Router,
};
use serde_json::json;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, RwLock};
use std::time::Instant;

pub const PORT: u16 = 53119;
const PAGE: &str = include_str!("obs.html");

pub struct Obs {
  info: RwLock<Option<(MediaInfo, Instant)>>,
  pub size: RwLock<String>,
  pub hide_paused: AtomicBool,
  /// Порт занят другой программой — плашка недоступна (показываем в настройках).
  pub failed: AtomicBool,
}

impl Obs {
  pub fn new(size: Option<String>, hide_paused: bool) -> Arc<Self> {
    Arc::new(Self {
      info: RwLock::new(None),
      size: RwLock::new(size.unwrap_or_else(|| "standard".into())),
      hide_paused: AtomicBool::new(hide_paused),
      failed: AtomicBool::new(false),
    })
  }

  pub fn update(&self, info: &MediaInfo) {
    *self.info.write().unwrap() = Some((info.clone(), Instant::now()));
  }

  fn now(&self) -> serde_json::Value {
    let size = self.size.read().unwrap().clone();
    let hide = self.hide_paused.load(Ordering::Relaxed);
    let guard = self.info.read().unwrap();
    let Some((i, at)) = guard.as_ref().filter(|(i, _)| i.active) else {
      return json!({ "active": false, "size": size, "hide_paused": hide });
    };
    // позицию досчитываем от момента последнего обновления
    let mut pos = i.position_ms.unwrap_or(0);
    if i.playing {
      pos += at.elapsed().as_millis() as u64;
    }
    if let Some(d) = i.duration_ms.filter(|d| *d > 0) {
      pos = pos.min(d);
    }
    json!({
      "active": true,
      "playing": i.playing,
      "title": i.title,
      "artist": i.artist,
      "cover_url": i.cover_url,
      "duration_ms": i.duration_ms,
      "position_ms": pos,
      "size": size,
      "hide_paused": hide,
    })
  }
}

fn with_type(body: impl Into<Body>, ty: &'static str) -> Response<Body> {
  let mut r = Response::new(body.into());
  r.headers_mut().insert(header::CONTENT_TYPE, HeaderValue::from_static(ty));
  r.headers_mut().insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
  r.headers_mut().insert(header::ACCESS_CONTROL_ALLOW_ORIGIN, HeaderValue::from_static("*"));
  r
}

async fn page() -> Response<Body> {
  with_type(PAGE, "text/html; charset=utf-8")
}

async fn now(State(obs): State<Arc<Obs>>) -> Response<Body> {
  with_type(obs.now().to_string(), "application/json")
}

/// Сервер плашки на постоянном порту (только 127.0.0.1 — снаружи недоступен).
pub async fn start(obs: Arc<Obs>) {
  let listener = match tokio::net::TcpListener::bind(("127.0.0.1", PORT)).await {
    Ok(l) => l,
    Err(e) => {
      log::warn!("плашка OBS: порт {PORT} занят — {e}");
      obs.failed.store(true, Ordering::Relaxed);
      return;
    }
  };
  let app = Router::new().route("/obs", get(page)).route("/obs/now", get(now)).with_state(obs);
  if let Err(e) = axum::serve(listener, app).await {
    log::error!("сервер плашки OBS остановился: {e}");
  }
}
