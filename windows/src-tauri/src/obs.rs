//! Плашка «сейчас играет» для OBS без сервера: Sonar сам отдаёт страницу на постоянном адресе
//! `http://127.0.0.1:53119/obs` (OBS стоит на том же компьютере — источник «Браузер»).
//! Страница (`obs.html`) раз в секунду берёт `/obs/now` и сама плавно двигает полосу между запросами.
//! Данные — те же, что для плашки Windows и Discord (`media_update`). Настройки: `obs.size`
//! (`standard` 450×130 / `compact` 320×72) и `obs.hide_paused`.

use crate::media::MediaInfo;
use axum::{
  body::Body,
  extract::{Query, State},
  http::{header, HeaderValue, Response},
  routing::get,
  Router,
};
use serde_json::json;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, RwLock};
use std::time::Instant;

/// Случайный токен плашки (32 знака) — без него `/obs` и `/obs/now` отвечают 403.
pub fn new_token() -> String {
  crate::store::new_id("obs").trim_start_matches("obs_").to_lowercase()
}

pub const PORT: u16 = 53119;
const PAGE: &str = include_str!("obs.html");

pub struct Obs {
  info: RwLock<Option<(MediaInfo, Instant)>>,
  pub size: RwLock<String>,
  pub hide_paused: AtomicBool,
  /// Порт занят другой программой — плашка недоступна (показываем в настройках).
  pub failed: AtomicBool,
  /// Токен в адресе: страницу и данные видит только тот, у кого ссылка (`obs.token`).
  pub token: RwLock<String>,
}

impl Obs {
  pub fn new(size: Option<String>, hide_paused: bool, token: String) -> Arc<Self> {
    Arc::new(Self {
      token: RwLock::new(token),
      info: RwLock::new(None),
      size: RwLock::new(size.unwrap_or_else(|| "standard".into())),
      hide_paused: AtomicBool::new(hide_paused),
      failed: AtomicBool::new(false),
    })
  }

  /// Адрес для источника «Браузер» в OBS — с токеном. Токена нет (удалён) — пусто: плашка выключена.
  pub fn url(&self) -> String {
    let t = self.token.read().unwrap();
    if t.is_empty() {
      return String::new();
    }
    format!("http://127.0.0.1:{PORT}/obs?token={t}")
  }

  fn allowed(&self, q: &TokenQuery) -> bool {
    let t = self.token.read().unwrap();
    !t.is_empty() && q.token.as_deref() == Some(t.as_str())
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

#[derive(serde::Deserialize)]
struct TokenQuery {
  token: Option<String>,
}

fn forbidden() -> Response<Body> {
  let mut r = with_type("Нужна ссылка с токеном из Sonar → Настройки → Интеграции", "text/plain; charset=utf-8");
  *r.status_mut() = axum::http::StatusCode::FORBIDDEN;
  r
}

async fn page(State(obs): State<Arc<Obs>>, Query(q): Query<TokenQuery>) -> Response<Body> {
  if !obs.allowed(&q) {
    return forbidden();
  }
  with_type(PAGE, "text/html; charset=utf-8")
}

async fn now(State(obs): State<Arc<Obs>>, Query(q): Query<TokenQuery>) -> Response<Body> {
  if !obs.allowed(&q) {
    return forbidden();
  }
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
