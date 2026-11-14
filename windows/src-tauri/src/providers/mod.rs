//! Работа с музыкальными сервисами: модели (как в docs/API.md) и разбор ответов.
//! Потом эта же раскладка переезжает в server/sonar/providers (SPEC §9.3).

pub mod soundcloud;
pub mod yandex;

use serde::{Deserialize, Serialize};

/// Трек — тот же JSON, что `Track` в docs/API.md §3.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Track {
  #[serde(rename = "ref")]
  pub ref_: String,
  pub title: String,
  pub artist: String,
  pub artists: Vec<ArtistRef>,
  pub album: Option<AlbumRef>,
  pub duration_ms: u64,
  pub cover_url: Option<String>,
  pub url: Option<String>,
  pub explicit: bool,
  pub available: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ArtistRef {
  #[serde(rename = "ref")]
  pub ref_: String,
  pub name: String,
  pub avatar_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AlbumRef {
  #[serde(rename = "ref")]
  pub ref_: String,
  pub title: String,
}

/// Откуда играть: прямой файл (с Range) или плейлист HLS (его склеивает hls.js).
#[derive(Debug, Clone, PartialEq)]
pub enum Source {
  File { url: String },
  Hls { url: String },
}

/// Подключённый аккаунт сервиса — для экрана «Сервисы».
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Account {
  pub name: Option<String>,
  pub avatar_url: Option<String>,
}

pub const UA: &str =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36";

/// Ошибка сервиса в виде, пригодном для показа пользователю.
pub fn http_error(service: &str, status: reqwest::StatusCode) -> anyhow::Error {
  let why = match status.as_u16() {
    401 | 403 => "токен не подошёл или устарел",
    404 => "не найдено",
    429 => "слишком много запросов, подожди минуту",
    451 => "недоступно в твоей стране",
    _ => "сервис ответил ошибкой",
  };
  anyhow::anyhow!("{service}: {why} (HTTP {})", status.as_u16())
}
