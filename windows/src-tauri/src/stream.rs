//! Локальный аудио-сервер на `127.0.0.1:<порт>` (приём Dotify, SPEC §9.2). Интерфейс видит
//! обычные адреса без CORS и протухших ссылок:
//! - `/file?ref=ym:1` — файл (mp3 Яндекса, mp3 SoundCloud) с поддержкой Range;
//! - `/hls?ref=sc:1` — плейлист HLS, где ссылки на куски заменены на `/seg?u=…`;
//! - `/seg?u=…` — кусок HLS (и ключ AES-128) с CDN SoundCloud (`*.sndcdn.com`, `*.soundcloud.cloud`)
//!   или VK (`*.vkuseraudio.net` и соседи; к CDN VK — с User-Agent Kate Mobile, `ua_for`).
//! - `/file?ref=yt:…` — YouTube Music: CDN `*.googlevideo.com` читается кусками (`gvideo.rs`).
//! - `/cover?u=…` — обложка с CDN SoundCloud/Яндекса/VK/YouTube с кэшем на диске (`<кэш>/covers`) и CORS —
//!   из неё интерфейс берёт цвет темы (SPEC §4.4); размер и очистка — экран «Хранилище».
//!
//! Локальные файлы (`local:<sha1>`): `/file` отдаёт файл с диска с Range, но только из индекса
//! `Core::local` (копия таблицы `local_files`) и только с ключом сессии `&k=` (`local_key`);
//! `/cover` — их обложки `sonarcover://…` из кэша обложек. CORS у них — не `*`, а лишь окну Sonar:
//! чужая страница в браузере не прочитает музыку и обложки с диска, даже угадав порт и путь.
//! Кэш треков (`track_cache.rs`): трек на диске — `/file` отдаёт его с диска (Range — кусками);
//! файл, прочитанный с начала до конца, ложится в кэш на лету; HLS — фоновая загрузка и склейка.

use crate::providers::{vk, Source, UA};
use crate::services::Core;
use axum::body::Body;
use axum::extract::{Query, State};
use axum::http::{header, HeaderMap, HeaderValue, Response, StatusCode};
use axum::routing::get;
use axum::Router;
use serde::Deserialize;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};
use crate::{gvideo, track_cache};

/// Папка кэша обложек (`%LOCALAPPDATA%/com.folzy.sonar/covers`), задаётся при запуске.
static COVER_DIR: OnceLock<PathBuf> = OnceLock::new();

pub fn set_cover_dir(dir: PathBuf) {
  let _ = std::fs::create_dir_all(&dir);
  let _ = COVER_DIR.set(dir);
  // при запуске — в фоне: папка может быть большой, окно ждать не должно
  std::thread::spawn(|| {
    if let Some(d) = cover_dir() {
      prune_covers(d, COVER_CACHE_LIMIT);
    }
  });
}

/// Предел кэша обложек с CDN, байт (docs/AUDIT.md п. 2). Обложка — 50–200 КБ, это тысячи обложек.
pub const COVER_CACHE_LIMIT: u64 = 300 * 1024 * 1024;
/// Раз в сколько новых обложек проверять предел.
const COVER_PRUNE_EVERY: u32 = 200;
static COVER_WRITES: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);

/// Обложка с CDN — имя `md5(адрес)`, 32 hex. Обложки локальных файлов (`local-….png`) не трогаем:
/// без сканирования папок их не вернуть.
fn is_remote_cover(name: &str) -> bool {
  name.len() == 32 && name.bytes().all(|b| b.is_ascii_hexdigit())
}

/// Убрать давно не открывавшиеся обложки с CDN, пока кэш больше `limit`. Вернёт, сколько удалено.
pub fn prune_covers(dir: &std::path::Path, limit: u64) -> usize {
  let mut list: Vec<(PathBuf, u64, std::time::SystemTime)> = std::fs::read_dir(dir)
    .map(|rd| {
      rd.flatten()
        .filter(|e| e.file_name().to_str().is_some_and(is_remote_cover))
        .filter_map(|e| {
          let m = e.metadata().ok()?;
          Some((e.path(), m.len(), m.modified().unwrap_or(std::time::SystemTime::UNIX_EPOCH)))
        })
        .collect()
    })
    .unwrap_or_default();
  let mut total: u64 = list.iter().map(|e| e.1).sum();
  list.sort_by_key(|e| e.2);
  let mut removed = 0;
  for (p, len, _) in list {
    if total <= limit {
      break;
    }
    if std::fs::remove_file(&p).is_ok() {
      total = total.saturating_sub(len);
      removed += 1;
    }
  }
  removed
}

/// Обложку открыли — она «свежая»: вытеснение идёт от давно не открывавшихся, а не от старых.
fn touch(p: &std::path::Path) {
  if let Ok(f) = std::fs::File::options().write(true).open(p) {
    let _ = f.set_modified(std::time::SystemTime::now());
  }
}

pub fn cover_dir() -> Option<&'static PathBuf> {
  COVER_DIR.get()
}

#[derive(Deserialize)]
struct CoverQuery {
  u: String,
}

#[derive(Deserialize)]
struct RefQuery {
  #[serde(rename = "ref")]
  ref_: String,
  /// Ключ сессии — нужен только локальным файлам.
  #[serde(default)]
  k: Option<String>,
}

/// Ключ сессии для локальных файлов: случайный на каждый запуск, в адрес `/file` его кладёт
/// `stream_url`. Без новых зависимостей — `RandomState` берёт случайные ключи у системы.
pub fn local_key() -> &'static str {
  static KEY: OnceLock<String> = OnceLock::new();
  KEY.get_or_init(|| {
    use std::hash::{BuildHasher, Hasher};
    let nanos = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0);
    (0..2u8)
      .map(|i| {
        let mut h = std::collections::hash_map::RandomState::new().build_hasher();
        h.write_u128(nanos);
        h.write_u32(std::process::id());
        h.write_u8(i);
        format!("{:016x}", h.finish())
      })
      .collect()
  })
}

/// Адрес трека на этом сервере (`file` или `hls`); локальному файлу — с ключом сессии.
pub fn track_url(port: u16, kind: &str, track_ref: &str) -> String {
  let base = format!("http://127.0.0.1:{port}/{kind}?ref={}", urlencoding::encode(track_ref));
  if crate::local::is_local_ref(track_ref) {
    format!("{base}&k={}", local_key())
  } else {
    base
  }
}

/// Откуда может прийти окно Sonar: WebView2 (`http(s)://tauri.localhost`), macOS/Linux
/// (`tauri://localhost`), а в отладке — dev-сервер Vite.
fn app_origin(origin: &str) -> bool {
  matches!(origin, "http://tauri.localhost" | "https://tauri.localhost" | "tauri://localhost")
    || (cfg!(debug_assertions) && origin == "http://localhost:5173")
}

/// CORS для данных с диска: разрешаем только окну Sonar, а не `*`.
fn app_cors(mut r: Response<Body>, headers: &HeaderMap) -> Response<Body> {
  let h = r.headers_mut();
  h.insert(header::VARY, HeaderValue::from_static("Origin"));
  if let Some(o) = headers.get(header::ORIGIN).filter(|o| o.to_str().is_ok_and(app_origin)) {
    h.insert(header::ACCESS_CONTROL_ALLOW_ORIGIN, o.clone());
    h.insert(header::ACCESS_CONTROL_EXPOSE_HEADERS, HeaderValue::from_static("Content-Length, Content-Range"));
  }
  r
}

fn local_plain(status: StatusCode, text: &'static str, headers: &HeaderMap) -> Response<Body> {
  let mut r = Response::new(Body::from(text));
  *r.status_mut() = status;
  app_cors(r, headers)
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
    .route("/cover", get(cover))
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
  let mut req = core.http.get(url).header("User-Agent", ua_for(url));
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

/// Трек из кэша на диске: без Range — целиком, с Range — кусками до 8 МБ (206).
fn serve_cached(path: &std::path::Path, mime: &str, total: u64, range: Option<&HeaderValue>) -> Response<Body> {
  let asked = range.and_then(|h| h.to_str().ok());
  let (start, end, partial) = match track_cache::parse_range(asked, total) {
    Some((a, b)) => (a, b, true),
    None if asked.is_some() => {
      let mut r = plain(StatusCode::RANGE_NOT_SATISFIABLE, "");
      if let Ok(v) = HeaderValue::from_str(&format!("bytes */{total}")) {
        r.headers_mut().insert(header::CONTENT_RANGE, v);
      }
      return r;
    }
    None => (0, total.saturating_sub(1), false),
  };
  let data = if partial { track_cache::read_range(path, start, end) } else { std::fs::read(path) };
  let Ok(data) = data else { return plain(StatusCode::INTERNAL_SERVER_ERROR, "кэш не читается") };
  let len = data.len() as u64;
  let mut r = Response::new(Body::from(data));
  let h = r.headers_mut();
  h.insert(header::CONTENT_TYPE, HeaderValue::from_str(mime).unwrap_or(HeaderValue::from_static("audio/mpeg")));
  h.insert(header::ACCEPT_RANGES, HeaderValue::from_static("bytes"));
  h.insert(header::CONTENT_LENGTH, HeaderValue::from(len));
  if partial {
    if let Ok(v) = HeaderValue::from_str(&format!("bytes {start}-{}/{total}", start + len.saturating_sub(1))) {
      h.insert(header::CONTENT_RANGE, v);
    }
    *r.status_mut() = StatusCode::PARTIAL_CONTENT;
  }
  cors(r)
}

/// Трек из памяти (Spotify через librespot) с поддержкой Range.
#[cfg(feature = "spotify-playback")]
fn serve_bytes(bytes: std::sync::Arc<Vec<u8>>, mime: &'static str, range: Option<&HeaderValue>) -> Response<Body> {
  let total = bytes.len() as u64;
  let asked = range.and_then(|h| h.to_str().ok());
  let (start, end, partial) = match track_cache::parse_range(asked, total) {
    Some((a, b)) => (a, b.min(total.saturating_sub(1)), true),
    None if asked.is_some() => return plain(StatusCode::RANGE_NOT_SATISFIABLE, ""),
    None => (0, total.saturating_sub(1), false),
  };
  let data = bytes.get(start as usize..=end as usize).unwrap_or_default().to_vec();
  let len = data.len() as u64;
  let mut r = Response::new(Body::from(data));
  let h = r.headers_mut();
  h.insert(header::CONTENT_TYPE, HeaderValue::from_static(mime));
  h.insert(header::ACCEPT_RANGES, HeaderValue::from_static("bytes"));
  h.insert(header::CONTENT_LENGTH, HeaderValue::from(len));
  if partial {
    if let Ok(v) = HeaderValue::from_str(&format!("bytes {start}-{end}/{total}")) {
      h.insert(header::CONTENT_RANGE, v);
    }
    *r.status_mut() = StatusCode::PARTIAL_CONTENT;
  }
  cors(r)
}

/// Как `proxy`, но если ответ — весь файл с начала, тело по пути пишется в кэш треков.
async fn proxy_cached(core: &Core, url: &str, range: Option<&HeaderValue>, track_ref: &str) -> Result<Response<Body>, reqwest::Error> {
  let mut req = core.http.get(url).header("User-Agent", ua_for(url));
  if let Some(r) = range {
    req = req.header(header::RANGE, r.as_bytes());
  }
  let up = req.send().await?;
  let status = up.status().as_u16();
  let hv = |n: header::HeaderName| up.headers().get(n.as_str()).and_then(|v| v.to_str().ok()).map(str::to_owned);
  let len: Option<u64> = hv(header::CONTENT_LENGTH).and_then(|v| v.parse().ok());
  // весь файл: 200 или 206 «bytes 0-(N-1)/N»
  let whole = status == 200
    || (status == 206
      && hv(header::CONTENT_RANGE).is_some_and(|cr| {
        let cr = cr.trim_start_matches("bytes ");
        cr.split_once('/').is_some_and(|(span, total)| span.split_once('-').is_some_and(|(a, b)| a == "0" && b.parse::<u64>().ok().map(|b| b + 1) == total.parse().ok()))
      }));
  let mime = hv(header::CONTENT_TYPE).unwrap_or_else(|| "audio/mpeg".into());
  let writer = if whole { track_cache::Writer::new(track_ref, &mime, len) } else { None };
  let mut res = Response::builder().status(status);
  for h in [header::CONTENT_TYPE, header::CONTENT_LENGTH, header::CONTENT_RANGE, header::ACCEPT_RANGES] {
    if let Some(v) = up.headers().get(h.as_str()) {
      res = res.header(h, v.as_bytes());
    }
  }
  let Some(w) = writer else {
    return Ok(cors(res.body(Body::from_stream(up.bytes_stream())).unwrap_or_else(|_| Response::new(Body::empty()))));
  };
  Ok(cors(res.body(Body::from_stream(tee(up.bytes_stream(), w))).unwrap_or_else(|_| Response::new(Body::empty()))))
}

/// Тело ответа, которое по пути пишется в кэш треков; дошло до конца — файл готов, оборвалось —
/// недописанный файл удалит `Drop` у `Writer`.
fn tee<E: Send + 'static>(
  body: impl futures_util::Stream<Item = Result<axum::body::Bytes, E>> + Send + 'static,
  w: track_cache::Writer,
) -> impl futures_util::Stream<Item = Result<axum::body::Bytes, E>> + Send + 'static {
  use futures_util::StreamExt;
  let w = Arc::new(Mutex::new(Some(w)));
  let w1 = w.clone();
  let body = body.map(move |chunk| {
    match &chunk {
      Ok(b) => {
        if let Some(w) = w1.lock().unwrap().as_mut() {
          w.write(b)
        }
      }
      Err(_) => drop(w1.lock().unwrap().take()),
    }
    chunk
  });
  let tail = futures_util::stream::once(async move {
    let done = w.lock().unwrap().take();
    if let Some(done) = done {
      done.finish();
    }
    Ok::<_, E>(axum::body::Bytes::new())
  });
  body.chain(tail)
}

/// YouTube Music: диапазон с `*.googlevideo.com` кусками; весь файл с начала — ещё и в кэш.
async fn serve_gvideo(core: &Core, url: &str, range: Option<&HeaderValue>, track_ref: &str) -> Response<Body> {
  let asked = range.and_then(|h| h.to_str().ok());
  match gvideo::open(&core.http, url, asked).await {
    Ok(o) => {
      let writer = if o.whole() { track_cache::Writer::new(track_ref, &o.mime, Some(o.total)) } else { None };
      let head = o.response(Body::empty());
      let body = match writer {
        Some(w) => Body::from_stream(tee(o.body, w)),
        None => Body::from_stream(o.body),
      };
      let (parts, _) = head.into_parts();
      cors(Response::from_parts(parts, body))
    }
    Err(f) => cors(gvideo::fail_response(&f)),
  }
}

/// HLS SoundCloud в кэш: скачать init-кусок и все куски по порядку и склеить в один файл (в фоне).
async fn cache_hls(core: Arc<Core>, track_ref: String, playlist: String, base: url::Url) {
  let fetch_all = async {
    let (init, segs, mime) = track_cache::hls_parts(&playlist, &base)?;
    let mut w = track_cache::Writer::new(&track_ref, mime, None)?;
    for u in init.into_iter().chain(segs) {
      let r = core.http.get(&u).header("User-Agent", ua_for(&u)).send().await.ok()?;
      if !r.status().is_success() {
        return None;
      }
      w.write(&r.bytes().await.ok()?);
    }
    w.finish();
    Some(())
  };
  if fetch_all.await.is_none() {
    log::info!("кэш: HLS {track_ref} не склеился");
  }
  track_cache::release(&track_ref);
}

/// Поколение заказа «волна офлайн»: новый заказ отменяет недокачанный старый.
static PREFETCH_GEN: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// «Волна офлайн» (Система → Хранилище): заранее скачать следующие треки волны в кэш треков, по
/// одному, чтобы не забивать сеть. Только при включённом кэше; уже лежащие на диске — мимо.
pub async fn prefetch(core: Arc<Core>, refs: Vec<String>) {
  use std::sync::atomic::Ordering;
  let ticket = PREFETCH_GEN.fetch_add(1, Ordering::SeqCst) + 1;
  for r in refs {
    if PREFETCH_GEN.load(Ordering::SeqCst) != ticket || !track_cache::enabled() {
      return;
    }
    // локальный файл и так на диске
    if crate::local::is_local_ref(&r) {
      continue;
    }
    if !track_cache::claim(&r) {
      continue;
    }
    match core.resolve(&r, false).await {
      Ok(Source::Hls { url, .. }) => {
        let up = core.http.get(&url).header("User-Agent", ua_for(&url)).send().await;
        match up {
          Ok(up) if up.status().is_success() => {
            let base = up.url().clone();
            let text = up.text().await.unwrap_or_default();
            // cache_hls сам отпустит трек
            cache_hls(core.clone(), r.clone(), text, base).await;
            continue;
          }
          _ => {}
        }
      }
      Ok(Source::File { url, .. }) if gvideo::is_gvideo(&url) => {
        let ok = async {
          let o = gvideo::open(&core.http, &url, None).await.ok()?;
          let mut w = track_cache::Writer::new(&r, &o.mime, Some(o.total))?;
          use futures_util::StreamExt;
          let mut body = o.body;
          while let Some(chunk) = body.next().await {
            w.write(&chunk.ok()?);
          }
          w.finish();
          Some(())
        }
        .await;
        if ok.is_none() {
          log::info!("волна офлайн: {r} не скачался");
        }
      }
      Ok(Source::File { url, .. }) => {
        let ok = async {
          let up = core.http.get(&url).header("User-Agent", ua_for(&url)).send().await.ok()?;
          if !up.status().is_success() {
            return None;
          }
          let mime = up.headers().get(header::CONTENT_TYPE).and_then(|v| v.to_str().ok()).unwrap_or("audio/mpeg").to_owned();
          let mut w = track_cache::Writer::new(&r, &mime, up.content_length())?;
          // потоком, а не целиком в память: FLAC бывает за 40 МБ
          use futures_util::StreamExt;
          let mut body = up.bytes_stream();
          while let Some(chunk) = body.next().await {
            w.write(&chunk.ok()?);
          }
          w.finish();
          Some(())
        }
        .await;
        if ok.is_none() {
          log::info!("волна офлайн: {r} не скачался");
        }
      }
      Err(e) => log::info!("волна офлайн: {r}: {e}"),
    }
    track_cache::release(&r);
  }
}

/// Локальный файл: путь — только из индекса, ref из запроса путём не становится; без ключа
/// сессии — 403.
fn local_file(core: &Core, q: &RefQuery, headers: &HeaderMap) -> Response<Body> {
  if q.k.as_deref() != Some(local_key()) {
    return local_plain(StatusCode::FORBIDDEN, "нет ключа", headers);
  }
  let Some(path) = core.local.get(&q.ref_) else { return local_plain(StatusCode::NOT_FOUND, "Файл не найден", headers) };
  match std::fs::metadata(&path) {
    Ok(m) if m.is_file() => {
      let mut r = serve_cached(&path, crate::local::audio_mime(&path), m.len(), headers.get(header::RANGE));
      r.headers_mut().remove(header::ACCESS_CONTROL_ALLOW_ORIGIN);
      r.headers_mut().remove(header::ACCESS_CONTROL_EXPOSE_HEADERS);
      app_cors(r, headers)
    }
    _ => local_plain(StatusCode::NOT_FOUND, "Файл не найден", headers),
  }
}

async fn file(State(core): State<Arc<Core>>, Query(q): Query<RefQuery>, headers: HeaderMap) -> Response<Body> {
  if crate::local::is_local_ref(&q.ref_) {
    return local_file(&core, &q, &headers);
  }
  let range = headers.get(header::RANGE);
  // трек уже на диске — без сети
  if let Some((path, mime, total)) = track_cache::lookup(&q.ref_) {
    return serve_cached(&path, &mime, total, range);
  }
  let from_start = range.is_none_or(|r| r.as_bytes() == b"bytes=0-");
  for fresh in [false, true] {
    let url = match core.resolve(&q.ref_, fresh).await {
      Ok(Source::File { url, .. }) => url,
      Ok(Source::Hls { .. }) => return plain(StatusCode::BAD_REQUEST, "этот трек — HLS, нужен /hls"),
      // повтор — только YouTube Music (новая visitorData); у остальных ошибка не временная
      Err(e) if !fresh && crate::services::retries_resolve(&q.ref_) => {
        log::warn!("поток {}: {e}; пробую ещё раз", q.ref_);
        continue;
      }
      Err(e) => {
        if fresh {
          log::error!("поток {}: {e}", q.ref_);
        } else {
          log::warn!("поток {}: {e}", q.ref_);
        }
        return plain(StatusCode::BAD_GATEWAY, e.to_string());
      }
    };
    #[cfg(feature = "spotify-playback")]
    if let Some(id) = url.strip_prefix(crate::spotify_play::SCHEME) {
      return match core.spotify_ogg(id).await {
        Ok((bytes, _)) => serve_bytes(bytes, "audio/ogg", range),
        Err(e) => plain(StatusCode::BAD_GATEWAY, e.to_string()),
      };
    }
    let res = if gvideo::is_gvideo(&url) {
      Ok(serve_gvideo(&core, &url, range, &q.ref_).await)
    } else if track_cache::enabled() && from_start {
      proxy_cached(&core, &url, range, &q.ref_).await
    } else {
      proxy(&core, &url, range).await
    };
    match res {
      // 403/410 — ссылка протухла, 5xx — сбой CDN: один раз берём новую
      Ok(r) if !fresh && retry_status(r.status()) => {
        log::warn!("поток {}: CDN ответил {}, беру ссылку заново", q.ref_, r.status().as_u16());
        continue;
      }
      Ok(r) => {
        log_cdn_status(&q.ref_, r.status());
        return r;
      }
      // без адреса: в ссылке подпись CDN
      Err(e) => {
        let e = e.without_url();
        log::error!("поток {}: {e}", q.ref_);
        return plain(StatusCode::BAD_GATEWAY, e.to_string());
      }
    }
  }
  plain(StatusCode::BAD_GATEWAY, "поток недоступен")
}

/// Обложки YouTube Music — только их хосты, а не весь `*.googleusercontent.com` (там и Диск, и Сайты).
fn yt_cover_host(h: &str) -> bool {
  matches!(h, "lh3.googleusercontent.com" | "lh4.googleusercontent.com" | "lh5.googleusercontent.com" | "lh6.googleusercontent.com")
    || matches!(h, "yt3.googleusercontent.com" | "yt3.ggpht.com" | "i.ytimg.com")
    || (h.starts_with('i') && h.ends_with(".ytimg.com") && h[1..h.len() - ".ytimg.com".len()].chars().all(|c| c.is_ascii_digit()))
}

/// Ответ CDN в журнал: 416 — обычный конец диапазона (перемотка, проба за концом файла), не ошибка.
fn log_cdn_status(track_ref: &str, s: StatusCode) {
  match s.as_u16() {
    416 => log::debug!("поток {track_ref}: CDN ответил 416"),
    400..=599 => log::error!("поток {track_ref}: CDN ответил {}", s.as_u16()),
    _ => {}
  }
}

/// Ответ CDN, после которого ссылку стоит взять заново (один раз).
fn retry_status(s: StatusCode) -> bool {
  matches!(s.as_u16(), 403 | 404 | 410) || s.is_server_error()
}

async fn hls(State(core): State<Arc<Core>>, Query(q): Query<RefQuery>) -> Response<Body> {
  for fresh in [false, true] {
    let url = match core.resolve(&q.ref_, fresh).await {
      Ok(Source::Hls { url, .. }) => url,
      Ok(Source::File { .. }) => return plain(StatusCode::BAD_REQUEST, "этот трек — файл, нужен /file"),
      Err(e) => return plain(StatusCode::BAD_GATEWAY, e.to_string()),
    };
    let up = match core.http.get(&url).header("User-Agent", ua_for(&url)).send().await {
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
    // кэш треков: в фоне скачать и склеить весь трек, в следующий раз он сыграет файлом с диска
    if track_cache::enabled() && track_cache::claim(&q.ref_) {
      tokio::spawn(cache_hls(core.clone(), q.ref_.clone(), text.clone(), base.clone()));
    }
    let mut r = Response::new(Body::from(rewrite_m3u8(&text, &base)));
    r.headers_mut().insert(header::CONTENT_TYPE, HeaderValue::from_static("application/vnd.apple.mpegurl"));
    r.headers_mut().insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    return cors(r);
  }
  plain(StatusCode::BAD_GATEWAY, "поток недоступен")
}

/// CDN VK: потоки, ключи HLS и картинки.
const VK_HOSTS: [&str; 4] = [".vkuseraudio.net", ".vkuseraudio.com", ".vk-cdn.net", ".userapi.com"];

fn host_of(u: &str) -> Option<String> {
  url::Url::parse(u).ok().and_then(|u| u.host_str().map(str::to_owned))
}

fn is_vk_host(h: &str) -> bool {
  VK_HOSTS.iter().any(|s| h.ends_with(s))
}

/// User-Agent для запроса к CDN: VK отдаёт музыку только клиенту Kate Mobile, остальным — браузерный.
pub fn ua_for(u: &str) -> &'static str {
  if host_of(u).is_some_and(|h| is_vk_host(&h)) {
    vk::UA
  } else {
    UA
  }
}

/// Хосты, с которых `/seg` берёт куски HLS: только CDN SoundCloud и VK — не открытый прокси.
pub fn seg_host_allowed(u: &str) -> bool {
  host_of(u).is_some_and(|h| h.ends_with(".sndcdn.com") || h.ends_with(".soundcloud.cloud") || is_vk_host(&h))
}

async fn seg(State(core): State<Arc<Core>>, Query(q): Query<SegQuery>, headers: HeaderMap) -> Response<Body> {
  if !seg_host_allowed(&q.u) {
    return plain(StatusCode::FORBIDDEN, "чужой адрес");
  }
  match proxy(&core, &q.u, headers.get(header::RANGE)).await {
    Ok(r) => r,
    Err(e) => plain(StatusCode::BAD_GATEWAY, e.to_string()),
  }
}

/// Хосты картинок, которые можно отдавать через `/cover` (не открытый прокси).
pub fn cover_host_allowed(u: &str) -> bool {
  url::Url::parse(u)
    .ok()
    .filter(|u| u.scheme() == "https")
    .and_then(|u| {
      u.host_str().map(|h| {
        h.ends_with(".sndcdn.com")
          || h == "avatars.yandex.net"
          || h.ends_with(".yandex.net")
          || h.ends_with(".genius.com")
          || yt_cover_host(h)
          || is_vk_host(h)
          || h.ends_with(".vkuserphoto.ru")
          // обложки и аватары Spotify
          || h == "i.scdn.co"
          || h == "mosaic.scdn.co"
          || h.ends_with(".spotifycdn.com")
      })
    })
    .unwrap_or(false)
}

/// Обложка локального файла (`sonarcover://…/local-<sha1>.<ext>`) — из кэша обложек.
fn local_cover(name: &str, headers: &HeaderMap) -> Response<Body> {
  match cover_dir().and_then(|d| crate::local::read_cover(d, name)) {
    Some((bytes, mime)) => {
      let mut r = Response::new(Body::from(bytes));
      r.headers_mut().insert(header::CONTENT_TYPE, HeaderValue::from_static(mime));
      app_cors(r, headers)
    }
    None => local_plain(StatusCode::NOT_FOUND, "нет обложки", headers),
  }
}

async fn cover(State(core): State<Arc<Core>>, Query(q): Query<CoverQuery>, headers: HeaderMap) -> Response<Body> {
  if let Some(name) = crate::local::cover_name_from_url(&q.u) {
    return local_cover(name, &headers);
  }
  if !cover_host_allowed(&q.u) {
    return plain(StatusCode::FORBIDDEN, "чужой адрес");
  }
  let path = cover_dir().map(|d| d.join(format!("{:x}", md5::compute(q.u.as_bytes()))));
  let image = |bytes: Vec<u8>| {
    let mut r = Response::new(Body::from(bytes));
    r.headers_mut().insert(header::CONTENT_TYPE, HeaderValue::from_static("image/jpeg"));
    r.headers_mut().insert(header::CACHE_CONTROL, HeaderValue::from_static("max-age=604800"));
    cors(r)
  };
  if let Some(p) = &path {
    if let Ok(bytes) = tokio::fs::read(p).await {
      let p = p.clone();
      tokio::task::spawn_blocking(move || touch(&p));
      return image(bytes);
    }
  }
  let res = match core.http.get(&q.u).header("User-Agent", ua_for(&q.u)).send().await {
    Ok(r) if r.status().is_success() => r,
    Ok(r) => return plain(StatusCode::BAD_GATEWAY, format!("HTTP {}", r.status().as_u16())),
    Err(e) => return plain(StatusCode::BAD_GATEWAY, e.to_string()),
  };
  match res.bytes().await {
    Ok(b) => {
      if let Some(p) = &path {
        if tokio::fs::write(p, &b).await.is_ok()
          && COVER_WRITES.fetch_add(1, std::sync::atomic::Ordering::Relaxed) % COVER_PRUNE_EVERY == COVER_PRUNE_EVERY - 1
        {
          if let Some(d) = cover_dir() {
            tokio::task::spawn_blocking(move || prune_covers(d, COVER_CACHE_LIMIT));
          }
        }
      }
      image(b.to_vec())
    }
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

  fn indexed_core(path: &std::path::Path) -> (Arc<Core>, String) {
    let core = Core::new_empty_for_tests();
    let r = crate::local::local_ref(path);
    core.local.replace(&[crate::store::LocalFile {
      ref_: r.clone(),
      path: path.to_string_lossy().into_owned(),
      mtime: 0,
      size: 0,
      title: "T".into(),
      artist: String::new(),
      album: None,
      duration_ms: 0,
      cover_path: None,
    }]);
    (Arc::new(core), r)
  }

  #[tokio::test]
  async fn local_file_served_with_range_only_from_index() {
    use crate::local::fixtures::{temp_dir, wav_bytes, write_wav};
    let dir = temp_dir("stream");
    let path = dir.join("song.wav");
    write_wav(&path, 500);
    let bytes = wav_bytes(500);
    let (core, r) = indexed_core(&path);
    let port = start(core).await.unwrap();
    let http = reqwest::Client::new();
    let base = format!("http://127.0.0.1:{port}");

    let url = track_url(port, "file", &r);
    assert!(url.ends_with(&format!("&k={}", local_key())));
    let res = http.get(&url).header("Range", "bytes=10-19").header("Origin", "http://tauri.localhost").send().await.unwrap();
    assert_eq!(res.status(), 206);
    assert_eq!(res.headers()["access-control-allow-origin"], "http://tauri.localhost");
    assert_eq!(res.headers()["content-type"], "audio/wav");
    assert_eq!(res.headers()["content-range"], format!("bytes 10-19/{}", bytes.len()).as_str());
    assert_eq!(res.bytes().await.unwrap().as_ref(), &bytes[10..20]);

    // чужая страница: CORS ей не открыт, а без ключа файла нет вовсе
    let res = http.get(&url).header("Origin", "https://evil.example").send().await.unwrap();
    assert_eq!(res.status(), 200);
    assert!(res.headers().get("access-control-allow-origin").is_none());
    assert_eq!(res.bytes().await.unwrap().len(), bytes.len());
    assert_eq!(http.get(format!("{base}/file?ref={r}")).send().await.unwrap().status(), 403);
    assert_eq!(http.get(format!("{base}/file?ref={r}&k=0")).send().await.unwrap().status(), 403);

    // не из индекса — 404, путь в ref не читается
    let key = local_key();
    let fake = format!("local:{}", "0".repeat(40));
    assert_eq!(http.get(format!("{base}/file?ref={fake}&k={key}")).send().await.unwrap().status(), 404);
    let sneaky = format!("{base}/file?ref=local:{}&k={key}", urlencoding_path(&path));
    assert_eq!(http.get(sneaky).send().await.unwrap().status(), 404);

    // файл удалили — 404
    std::fs::remove_file(&path).unwrap();
    assert_eq!(http.get(&url).send().await.unwrap().status(), 404);
    let _ = std::fs::remove_dir_all(dir);
  }

  fn urlencoding_path(p: &std::path::Path) -> String {
    url::form_urlencoded::byte_serialize(p.to_string_lossy().as_bytes()).collect()
  }

  #[tokio::test]
  async fn foreign_cover_urls_still_refused() {
    let core = Arc::new(Core::new_empty_for_tests());
    let port = start(core).await.unwrap();
    let http = reqwest::Client::new();
    let base = format!("http://127.0.0.1:{port}");
    let ask = |u: String| {
      let http = http.clone();
      let base = base.clone();
      async move {
        let q: String = url::form_urlencoded::byte_serialize(u.as_bytes()).collect();
        http.get(format!("{base}/cover?u={q}")).send().await.unwrap().status().as_u16()
      }
    };
    assert_eq!(ask(crate::local::cover_url("../sonar.db")).await, 403);
    assert_eq!(ask("file:///etc/passwd".into()).await, 403);
    // имя правильное, но такой обложки нет — 404, не чтение чего попало
    assert_eq!(ask(crate::local::cover_url(&format!("local-{}.jpg", "e".repeat(40)))).await, 404);
  }

  #[test]
  fn retries_expired_links_and_cdn_failures_only() {
    for s in [403, 404, 410, 500, 502, 503] {
      assert!(retry_status(StatusCode::from_u16(s).unwrap()), "{s}");
    }
    for s in [200, 206, 400, 416] {
      assert!(!retry_status(StatusCode::from_u16(s).unwrap()), "{s}");
    }
  }

  /// YouTube Music через аудио-сервер: Range за пределами первого мегабайта и весь файл кусками.
  #[tokio::test]
  #[ignore = "живой YouTube Music (гостем)"]
  async fn live_server_youtube() {
    let core = Arc::new(Core::new_empty_for_tests());
    let port = start(core.clone()).await.unwrap();
    let track = &core.search("Caort Star$Hopping", "yt", 3).await.unwrap()[0];
    let http = reqwest::Client::new();
    let url = format!("http://127.0.0.1:{port}/file?ref={}", track.ref_);
    let r = http.get(&url).header(header::RANGE, "bytes=1048576-2097151").send().await.unwrap();
    let status = r.status().as_u16();
    if status != 206 {
      panic!("диапазон: {status} {}", r.text().await.unwrap_or_default());
    }
    println!("{} — {}: {}", track.artist, track.title, r.headers()[header::CONTENT_RANGE].to_str().unwrap());
    assert_eq!(r.bytes().await.unwrap().len(), 1_048_576);
    let t = std::time::Instant::now();
    let whole = http.get(&url).send().await.unwrap().bytes().await.unwrap();
    println!("весь файл: {} байт за {:?}", whole.len(), t.elapsed());
    assert!(whole.len() > 2_000_000);
  }

  #[test]
  fn prune_covers_keeps_local_and_fresh() {
    use std::time::{Duration, SystemTime};
    let dir = crate::local::fixtures::temp_dir("cover-prune");
    let put = |name: &str, len: usize, age_s: u64| {
      let p = dir.join(name);
      std::fs::write(&p, vec![0u8; len]).unwrap();
      let f = std::fs::File::options().write(true).open(&p).unwrap();
      f.set_modified(SystemTime::now() - Duration::from_secs(age_s)).unwrap();
    };
    let old = "a".repeat(32);
    let mid = "b".repeat(32);
    let new = "c".repeat(32);
    let local = format!("local-{}.png", "d".repeat(40));
    put(&old, 100, 300);
    put(&mid, 100, 200);
    put(&new, 100, 100);
    put(&local, 1000, 400);
    // предел 150 байт: уходят две самые старые обложки CDN, локальная (хоть и старше и больше) остаётся
    assert_eq!(prune_covers(&dir, 150), 2);
    assert!(!dir.join(&old).exists() && !dir.join(&mid).exists());
    assert!(dir.join(&new).exists() && dir.join(&local).exists());
    // уже в пределе — ничего не трогаем
    assert_eq!(prune_covers(&dir, 150), 0);
  }

  #[test]
  fn cover_hosts() {
    assert!(cover_host_allowed("https://i1.sndcdn.com/artworks-1-t500x500.jpg"));
    assert!(cover_host_allowed("https://avatars.yandex.net/get-music-content/1/400x400"));
    assert!(!cover_host_allowed("http://i1.sndcdn.com/a.jpg"));
    assert!(!cover_host_allowed("https://evil.com/?x=.sndcdn.com"));
    assert!(cover_host_allowed("https://lh3.googleusercontent.com/abc=w544-h544"));
    assert!(cover_host_allowed("https://yt3.ggpht.com/abc=s544"));
    assert!(cover_host_allowed("https://i.ytimg.com/vi/x/hqdefault.jpg"));
    assert!(cover_host_allowed("https://yt3.googleusercontent.com/abc=s544"));
    assert!(cover_host_allowed("https://i9.ytimg.com/vi/x/sddefault.jpg"));
    assert!(!cover_host_allowed("https://googleusercontent.com.evil.com/a.jpg"));
    assert!(!cover_host_allowed("https://storage.googleusercontent.com/bucket/a.jpg"));
    assert!(!cover_host_allowed("https://doc-0s-docs.googleusercontent.com/a.jpg"));
    assert!(!cover_host_allowed("https://evil.ggpht.com/a.jpg"));
    assert!(!cover_host_allowed("https://ievil.ytimg.com/a.jpg"));
    assert!(cover_host_allowed("https://sun9-1.userapi.com/impg/a.jpg?size=600x600"));
    assert!(cover_host_allowed("https://sun1-2.vkuserphoto.ru/a.jpg"));
    assert!(!cover_host_allowed("https://userapi.com.evil.com/a.jpg"));
  }

  #[test]
  fn seg_hosts_and_vk_user_agent() {
    assert!(seg_host_allowed("https://cf-hls-media.sndcdn.com/media/1.m4s"));
    assert!(seg_host_allowed("https://cs1-2v4.vkuseraudio.net/s/v1/ac/x/seg-1-a1.ts"));
    assert!(seg_host_allowed("https://cs9-1v4.vkuseraudio.com/s/v1/ac/x/key.pub"));
    assert!(!seg_host_allowed("https://evil.com/?x=.vkuseraudio.net"));
    assert!(!seg_host_allowed("not a url"));
    assert_eq!(ua_for("https://cs1-2v4.vkuseraudio.net/s/v1/ac/x/index.m3u8"), vk::UA);
    assert_eq!(ua_for("https://cf-hls-media.sndcdn.com/x.m3u8"), UA);
    assert_eq!(ua_for("garbage"), UA);
  }

  /// HLS VK: куски и ключ AES-128 идут через `/seg`, hls.js расшифровывает сам.
  #[test]
  fn rewrites_vk_aes_key() {
    let base = url::Url::parse("https://cs1-2v4.vkuseraudio.net/s/v1/ac/abc/index.m3u8?siren=1").unwrap();
    let src = "#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI=\"https://cs1-2v4.vkuseraudio.net/s/v1/ac/abc/key.pub?siren=1\"\n#EXTINF:5,\nseg-1-a1.ts?siren=1\n#EXT-X-KEY:METHOD=NONE\n#EXTINF:5,\nseg-2-a1.ts\n";
    let out = rewrite_m3u8(src, &base);
    let lines: Vec<_> = out.lines().collect();
    assert_eq!(lines[1], "#EXT-X-KEY:METHOD=AES-128,URI=\"/seg?u=https%3A%2F%2Fcs1-2v4.vkuseraudio.net%2Fs%2Fv1%2Fac%2Fabc%2Fkey.pub%3Fsiren%3D1\"");
    assert_eq!(lines[3], "/seg?u=https%3A%2F%2Fcs1-2v4.vkuseraudio.net%2Fs%2Fv1%2Fac%2Fabc%2Fseg-1-a1.ts%3Fsiren%3D1");
    assert_eq!(lines[4], "#EXT-X-KEY:METHOD=NONE");
    assert!(lines.iter().filter(|l| !l.starts_with('#')).all(|l| seg_host_allowed(&urlencoding::decode(l.trim_start_matches("/seg?u=")).unwrap())));

  }

  #[test]
  fn spotify_cover_hosts() {
    assert!(cover_host_allowed("https://i.scdn.co/image/ab67616d0000b273"));
    assert!(cover_host_allowed("https://mosaic.scdn.co/640/ab67616d"));
    assert!(cover_host_allowed("https://image-cdn-ak.spotifycdn.com/image/ab67"));
    assert!(!cover_host_allowed("https://i.scdn.co.evil.com/x"));
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
