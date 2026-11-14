//! Локальный аудио-сервер на `127.0.0.1:<порт>` (приём Dotify, SPEC §9.2). Интерфейс видит
//! обычные адреса без CORS и протухших ссылок:
//! - `/file?ref=ym:1` — файл (mp3 Яндекса, mp3 SoundCloud) с поддержкой Range;
//! - `/hls?ref=sc:1` — плейлист HLS, где ссылки на куски заменены на `/seg?u=…`;
//! - `/seg?u=…` — кусок HLS с CDN SoundCloud (`*.sndcdn.com`, `*.soundcloud.cloud`).
//! Кэш на диск — вместе с экраном «Хранилище» (W5).

use crate::providers::{Source, UA};
use crate::services::Core;
use axum::body::Body;
use axum::extract::{Query, State};
use axum::http::{header, HeaderMap, HeaderValue, Response, StatusCode};
use axum::routing::get;
use axum::Router;
use serde::Deserialize;
use std::sync::Arc;

#[derive(Deserialize)]
struct RefQuery {
  #[serde(rename = "ref")]
  ref_: String,
}

#[derive(Deserialize)]
struct SegQuery {
  u: String,
}

/// Запускает сервер на свободном порту и возвращает порт.
pub async fn start(core: Arc<Core>) -> std::io::Result<u16> {
  let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
  let port = listener.local_addr()?.port();
  let app = Router::new()
    .route("/file", get(file))
    .route("/hls", get(hls))
    .route("/seg", get(seg))
    .with_state(core);
  tokio::spawn(async move {
    if let Err(e) = axum::serve(listener, app).await {
      log::error!("аудио-сервер остановился: {e}");
    }
  });
  Ok(port)
}

fn plain(status: StatusCode, text: impl Into<String>) -> Response<Body> {
  let mut r = Response::new(Body::from(text.into()));
  *r.status_mut() = status;
  cors(r)
}

fn cors(mut r: Response<Body>) -> Response<Body> {
  r.headers_mut().insert(header::ACCESS_CONTROL_ALLOW_ORIGIN, HeaderValue::from_static("*"));
  r.headers_mut().insert(header::ACCESS_CONTROL_EXPOSE_HEADERS, HeaderValue::from_static("Content-Length, Content-Range"));
  r
}

/// Проксирует ответ CDN: статус, нужные заголовки и тело потоком.
async fn proxy(core: &Core, url: &str, range: Option<&HeaderValue>) -> Result<Response<Body>, reqwest::Error> {
  let mut req = core.http.get(url).header("User-Agent", UA);
  if let Some(r) = range {
    req = req.header(header::RANGE, r.as_bytes());
  }
  let up = req.send().await?;
  let mut res = Response::builder().status(up.status().as_u16());
  for h in [header::CONTENT_TYPE, header::CONTENT_LENGTH, header::CONTENT_RANGE, header::ACCEPT_RANGES] {
    if let Some(v) = up.headers().get(h.as_str()) {
      res = res.header(h, v.as_bytes());
    }
  }
  Ok(cors(res.body(Body::from_stream(up.bytes_stream())).unwrap_or_else(|_| Response::new(Body::empty()))))
}

async fn file(State(core): State<Arc<Core>>, Query(q): Query<RefQuery>, headers: HeaderMap) -> Response<Body> {
  let range = headers.get(header::RANGE);
  for fresh in [false, true] {
    let url = match core.resolve(&q.ref_, fresh).await {
      Ok(Source::File { url, .. }) => url,
      Ok(Source::Hls { .. }) => return plain(StatusCode::BAD_REQUEST, "этот трек — HLS, нужен /hls"),
      Err(e) => return plain(StatusCode::BAD_GATEWAY, e.to_string()),
    };
    match proxy(&core, &url, range).await {
      // 403/410 — ссылка протухла: один раз берём новую
      Ok(r) if !fresh && matches!(r.status().as_u16(), 403 | 404 | 410) => continue,
      Ok(r) => return r,
      Err(e) => return plain(StatusCode::BAD_GATEWAY, e.to_string()),
    }
  }
  plain(StatusCode::BAD_GATEWAY, "поток недоступен")
}

async fn hls(State(core): State<Arc<Core>>, Query(q): Query<RefQuery>) -> Response<Body> {
  for fresh in [false, true] {
    let url = match core.resolve(&q.ref_, fresh).await {
      Ok(Source::Hls { url, .. }) => url,
      Ok(Source::File { .. }) => return plain(StatusCode::BAD_REQUEST, "этот трек — файл, нужен /file"),
      Err(e) => return plain(StatusCode::BAD_GATEWAY, e.to_string()),
    };
    let up = match core.http.get(&url).header("User-Agent", UA).send().await {
      Ok(r) => r,
      Err(e) => return plain(StatusCode::BAD_GATEWAY, e.to_string()),
    };
    if !up.status().is_success() {
      if !fresh {
        continue;
      }
      return plain(StatusCode::BAD_GATEWAY, format!("CDN ответил {}", up.status()));
    }
    let base = up.url().clone();
    let text = up.text().await.unwrap_or_default();
    let mut r = Response::new(Body::from(rewrite_m3u8(&text, &base)));
    r.headers_mut().insert(header::CONTENT_TYPE, HeaderValue::from_static("application/vnd.apple.mpegurl"));
    r.headers_mut().insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    return cors(r);
  }
  plain(StatusCode::BAD_GATEWAY, "поток недоступен")
}

async fn seg(State(core): State<Arc<Core>>, Query(q): Query<SegQuery>, headers: HeaderMap) -> Response<Body> {
  // Только CDN SoundCloud — локальный сервер не должен быть открытым прокси.
  let allowed = url::Url::parse(&q.u).ok().and_then(|u| u.host_str().map(|h| h.ends_with(".sndcdn.com") || h.ends_with(".soundcloud.cloud"))) == Some(true);
  if !allowed {
    return plain(StatusCode::FORBIDDEN, "чужой адрес");
  }
  match proxy(&core, &q.u, headers.get(header::RANGE)).await {
    Ok(r) => r,
    Err(e) => plain(StatusCode::BAD_GATEWAY, e.to_string()),
  }
}

fn seg_url(raw: &str, base: &url::Url) -> String {
  let abs = base.join(raw).map(|u| u.to_string()).unwrap_or_else(|_| raw.to_owned());
  format!("/seg?u={}", urlencoding::encode(&abs))
}

/// Ссылки на куски (строки без `#`) и `URI="…"` в тегах → `/seg?u=…` на этом же сервере.
pub fn rewrite_m3u8(text: &str, base: &url::Url) -> String {
  let mut out = String::with_capacity(text.len() * 2);
  for line in text.lines() {
    let t = line.trim();
    if t.is_empty() {
      out.push('\n');
      continue;
    }
    if !t.starts_with('#') {
      out.push_str(&seg_url(t, base));
    } else if let Some(start) = t.find("URI=\"") {
      let from = start + 5;
      match t[from..].find('"') {
        Some(len) => {
          out.push_str(&t[..from]);
          out.push_str(&seg_url(&t[from..from + len], base));
          out.push_str(&t[from + len..]);
        }
        None => out.push_str(t),
      }
    } else {
      out.push_str(t);
    }
    out.push('\n');
  }
  out
}

#[cfg(test)]
mod tests {
  use super::*;

  /// Сквозная проверка сервера: `SC_CLIENT_ID=… cargo test live_server -- --ignored --nocapture`.
  #[tokio::test]
  #[ignore]
  async fn live_server_hls() {
    let creds = crate::providers::soundcloud::Creds { client_id: std::env::var("SC_CLIENT_ID").unwrap(), oauth_token: None };
    let core = Arc::new(Core::with_soundcloud(creds));
    let port = start(core.clone()).await.unwrap();
    let track = &core.search("lil peep", "sc", 3).await.unwrap()[0];
    let http = reqwest::Client::new();
    let base = format!("http://127.0.0.1:{port}");
    let m3u8 = http.get(format!("{base}/hls?ref={}", track.ref_)).send().await.unwrap();
    assert_eq!(m3u8.headers()["access-control-allow-origin"], "*");
    let text = m3u8.text().await.unwrap();
    let seg = text.lines().find(|l| l.starts_with("/seg")).expect("в плейлисте нет кусков");
    let r = http.get(format!("{base}{seg}")).send().await.unwrap();
    assert!(r.status().is_success(), "кусок: {}", r.status());
    let bytes = r.bytes().await.unwrap();
    println!("{} — {}: кусок {} байт", track.artist, track.title, bytes.len());
    assert!(bytes.len() > 10_000);
  }

  #[test]
  fn rewrites_segments_and_map() {
    let base = url::Url::parse("https://cf-hls-media.sndcdn.com/playlist/abc/aac_160k.m3u8?Policy=x").unwrap();
    let src = "#EXTM3U\n#EXT-X-MAP:URI=\"https://cf-hls-media.sndcdn.com/init/abc.mp4?x=1\"\n#EXTINF:9.98,\n\
      https://cf-hls-media.sndcdn.com/media/0/9/abc.m4s?Policy=y\n#EXTINF:5,\nrel/1.m4s\n#EXT-X-ENDLIST\n";
    let out = rewrite_m3u8(src, &base);
    let lines: Vec<&str> = out.lines().collect();
    assert_eq!(lines[0], "#EXTM3U");
    assert_eq!(
      lines[1],
      "#EXT-X-MAP:URI=\"/seg?u=https%3A%2F%2Fcf-hls-media.sndcdn.com%2Finit%2Fabc.mp4%3Fx%3D1\""
    );
    assert_eq!(lines[3], "/seg?u=https%3A%2F%2Fcf-hls-media.sndcdn.com%2Fmedia%2F0%2F9%2Fabc.m4s%3FPolicy%3Dy");
    assert_eq!(lines[5], "/seg?u=https%3A%2F%2Fcf-hls-media.sndcdn.com%2Fplaylist%2Fabc%2Frel%2F1.m4s");
    assert_eq!(lines[6], "#EXT-X-ENDLIST");
  }
}
