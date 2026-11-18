//! Потоки YouTube Music с `*.googlevideo.com`. CDN отдаёт быстро только запросы с ограниченным
//! диапазоном (`Range: bytes=a-b`); запрос без конца (`bytes=0-` или без Range) режется до ~35 КБ/с
//! и обрывается. Поэтому аудио-сервер сам делит нужный диапазон на куски по 8 МБ и склеивает
//! их в один ответ: `<audio>` видит обычный файл с Range (проверено `server/tools/check_yt.py`).

use crate::providers::UA;
use crate::track_cache;
use axum::body::{Body, Bytes};
use axum::http::{header, HeaderValue, Response, StatusCode};
use futures_util::stream::{self, BoxStream, StreamExt};

/// Размер одного запроса к CDN.
pub const CHUNK: u64 = 8 * 1024 * 1024;
/// Тип по умолчанию: «Высокое» — Opus в WebM.
const DEFAULT_MIME: &str = "audio/webm";

type ByteStream = BoxStream<'static, Result<Bytes, std::io::Error>>;

/// Почему поток не открылся.
#[derive(Debug)]
pub enum Fail {
  /// CDN ответил не 206 (403/410 — ссылка протухла, её берут заново).
  Status(u16),
  /// Сеть; текст — без адреса (в ссылке подпись CDN).
  Net(String),
  /// Диапазон за пределами файла.
  Range(u64),
}

/// Открытый поток: какой диапазон отдаём и тело кусками.
pub struct Opened {
  pub total: u64,
  pub start: u64,
  pub end: u64,
  pub partial: bool,
  pub mime: String,
  pub body: ByteStream,
}

pub fn is_gvideo(url: &str) -> bool {
  url::Url::parse(url).ok().and_then(|u| u.host_str().map(|h| h.ends_with(".googlevideo.com"))) == Some(true)
}

fn param(url: &str, name: &str) -> Option<String> {
  url::Url::parse(url).ok()?.query_pairs().find(|(k, _)| k == name).map(|(_, v)| v.into_owned())
}

/// Тип аудио из параметра `mime` ссылки (`audio/webm`, `audio/mp4`).
pub fn mime_of(url: &str) -> String {
  param(url, "mime").filter(|m| m.starts_with("audio/")).unwrap_or_else(|| DEFAULT_MIME.into())
}

/// Размер файла из параметра `clen` ссылки.
pub fn clen_of(url: &str) -> Option<u64> {
  param(url, "clen")?.parse().ok().filter(|n| *n > 0)
}

/// Диапазон `start..=end` кусками не больше `chunk`.
pub fn spans(start: u64, end: u64, chunk: u64) -> Vec<(u64, u64)> {
  let chunk = chunk.max(1);
  let mut out = Vec::new();
  let mut a = start;
  while a <= end {
    let b = end.min(a.saturating_add(chunk - 1));
    out.push((a, b));
    if b == u64::MAX {
      break;
    }
    a = b + 1;
  }
  out
}

/// Размер из `Content-Range: bytes 0-0/12345`.
fn total_of_content_range(v: &str) -> Option<u64> {
  v.rsplit_once('/')?.1.trim().parse().ok()
}

fn net(e: reqwest::Error) -> Fail {
  Fail::Net(e.without_url().to_string())
}

async fn fetch(http: &reqwest::Client, url: &str, (a, b): (u64, u64)) -> Result<reqwest::Response, Fail> {
  let r = http.get(url).header("User-Agent", UA).header(header::RANGE, format!("bytes={a}-{b}")).send().await.map_err(net)?;
  match r.status().as_u16() {
    206 => Ok(r),
    s => Err(Fail::Status(s)),
  }
}

async fn total_len(http: &reqwest::Client, url: &str) -> Result<u64, Fail> {
  if let Some(n) = clen_of(url) {
    return Ok(n);
  }
  let r = fetch(http, url, (0, 0)).await?;
  let cr = r.headers().get(header::CONTENT_RANGE).and_then(|v| v.to_str().ok()).unwrap_or_default();
  total_of_content_range(cr).ok_or(Fail::Status(502))
}

fn body_of(r: reqwest::Response) -> ByteStream {
  r.bytes_stream().map(|c| c.map_err(|e| std::io::Error::other(e.without_url().to_string()))).boxed()
}

/// Открыть диапазон `range` (заголовок Range от `<audio>`; None — весь файл). Первый кусок
/// запрашивается сразу — так 403 протухшей ссылки виден до ответа интерфейсу.
pub async fn open(http: &reqwest::Client, url: &str, range: Option<&str>) -> Result<Opened, Fail> {
  let total = total_len(http, url).await?;
  let (start, end, partial) = match track_cache::parse_range(range, total) {
    Some((a, b)) => (a, b, true),
    None if range.is_some() => return Err(Fail::Range(total)),
    None => (0, total.saturating_sub(1), false),
  };
  let mut parts = spans(start, end, CHUNK).into_iter();
  let first = parts.next().ok_or(Fail::Range(total))?;
  let head = body_of(fetch(http, url, first).await?);
  let mime = mime_of(url);
  let (http, url) = (http.clone(), url.to_owned());
  let rest = stream::iter(parts)
    .then(move |span| {
      let (http, url) = (http.clone(), url.clone());
      async move { fetch(&http, &url, span).await }
    })
    .map(|r| match r {
      Ok(r) => body_of(r),
      Err(f) => stream::once(async move { Err(std::io::Error::other(format!("кусок потока: {f:?}"))) }).boxed(),
    })
    .flatten();
  Ok(Opened { total, start, end, partial, mime, body: head.chain(rest).boxed() })
}

impl Opened {
  /// Весь файл с начала — его можно положить в кэш треков.
  pub fn whole(&self) -> bool {
    self.start == 0 && self.end + 1 == self.total
  }

  /// Ответ `<audio>`: 206 с `Content-Range` на запрос с Range, иначе 200; тело — `body`.
  pub fn response(&self, body: Body) -> Response<Body> {
    let len = self.end + 1 - self.start;
    let mut r = Response::new(body);
    let h = r.headers_mut();
    h.insert(header::CONTENT_TYPE, HeaderValue::from_str(&self.mime).unwrap_or(HeaderValue::from_static(DEFAULT_MIME)));
    h.insert(header::ACCEPT_RANGES, HeaderValue::from_static("bytes"));
    h.insert(header::CONTENT_LENGTH, HeaderValue::from(len));
    if self.partial {
      if let Ok(v) = HeaderValue::from_str(&format!("bytes {}-{}/{}", self.start, self.end, self.total)) {
        h.insert(header::CONTENT_RANGE, v);
      }
      *r.status_mut() = StatusCode::PARTIAL_CONTENT;
    }
    r
  }
}

/// Ответ на ошибку: 403/404/410 — как есть (ссылку берут заново), диапазон — 416, остальное — 502.
pub fn fail_response(f: &Fail) -> Response<Body> {
  let (status, text) = match f {
    Fail::Status(s @ (403 | 404 | 410)) => (StatusCode::from_u16(*s).unwrap_or(StatusCode::BAD_GATEWAY), String::new()),
    Fail::Status(s) => (StatusCode::BAD_GATEWAY, format!("CDN YouTube ответил {s}")),
    Fail::Net(e) => (StatusCode::BAD_GATEWAY, e.clone()),
    Fail::Range(_) => (StatusCode::RANGE_NOT_SATISFIABLE, String::new()),
  };
  let mut r = Response::new(Body::from(text));
  *r.status_mut() = status;
  if let Fail::Range(total) = f {
    if let Ok(v) = HeaderValue::from_str(&format!("bytes */{total}")) {
      r.headers_mut().insert(header::CONTENT_RANGE, v);
    }
  }
  r
}

#[cfg(test)]
mod tests {
  use super::*;

  const URL: &str = "https://rr1---sn-abc.googlevideo.com/videoplayback?itag=251&mime=audio%2Fwebm&clen=3702768&sig=x";

  #[test]
  fn detects_googlevideo_host_only() {
    assert!(is_gvideo(URL));
    assert!(!is_gvideo("https://evil.com/?h=.googlevideo.com"));
    assert!(!is_gvideo("https://cf-media.sndcdn.com/a.mp3"));
    assert!(!is_gvideo("не ссылка"));
  }

  #[test]
  fn reads_mime_and_clen_from_query() {
    assert_eq!(mime_of(URL), "audio/webm");
    assert_eq!(clen_of(URL), Some(3_702_768));
    assert_eq!(mime_of("https://x.googlevideo.com/v?mime=video%2Fmp4"), DEFAULT_MIME);
    assert_eq!(clen_of("https://x.googlevideo.com/v?clen=0"), None);
  }

  #[test]
  fn splits_range_into_bounded_spans() {
    assert_eq!(spans(0, 9, 4), vec![(0, 3), (4, 7), (8, 9)]);
    assert_eq!(spans(5, 5, 4), vec![(5, 5)]);
    assert_eq!(spans(0, 7, 4), vec![(0, 3), (4, 7)]);
    assert!(spans(3, 2, 4).is_empty());
    let big = spans(0, 20 * 1024 * 1024 - 1, CHUNK);
    assert_eq!(big.len(), 3);
    assert!(big.iter().all(|(a, b)| b - a < CHUNK));
  }

  #[test]
  fn total_from_content_range() {
    assert_eq!(total_of_content_range("bytes 0-0/12345"), Some(12345));
    assert_eq!(total_of_content_range("bytes */9"), Some(9));
    assert_eq!(total_of_content_range("мусор"), None);
  }

  fn opened(start: u64, end: u64, partial: bool) -> Opened {
    Opened { total: 100, start, end, partial, mime: "audio/mp4".into(), body: stream::empty().boxed() }
  }

  #[test]
  fn response_headers_for_range_and_whole() {
    let o = opened(10, 19, true);
    let r = o.response(Body::empty());
    assert_eq!(r.status(), StatusCode::PARTIAL_CONTENT);
    assert_eq!(r.headers()[header::CONTENT_RANGE], "bytes 10-19/100");
    assert_eq!(r.headers()[header::CONTENT_LENGTH], "10");
    assert!(!o.whole());
    let o = opened(0, 99, false);
    let r = o.response(Body::empty());
    assert_eq!(r.status(), StatusCode::OK);
    assert_eq!(r.headers()[header::CONTENT_LENGTH], "100");
    assert_eq!(r.headers()[header::CONTENT_TYPE], "audio/mp4");
    assert!(o.whole());
  }

  #[test]
  fn fail_keeps_expired_status_and_hides_url() {
    assert_eq!(fail_response(&Fail::Status(403)).status(), StatusCode::FORBIDDEN);
    assert_eq!(fail_response(&Fail::Status(500)).status(), StatusCode::BAD_GATEWAY);
    let r = fail_response(&Fail::Range(42));
    assert_eq!(r.status(), StatusCode::RANGE_NOT_SATISFIABLE);
    assert_eq!(r.headers()[header::CONTENT_RANGE], "bytes */42");
  }
}
