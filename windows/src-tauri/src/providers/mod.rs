//! Работа с музыкальными сервисами: модели (как в docs/API.md) и разбор ответов.
//! Потом эта же раскладка переезжает в server/sonar/providers (SPEC §9.3).

pub mod matching;
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
  /// Сколько раз трек слушали на сервисе (SoundCloud `playback_count`; Яндекс не отдаёт).
  #[serde(default, skip_serializing_if = "Option::is_none")]
  pub plays: Option<u64>,
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

/// Альбом (`scalb:` — альбом SoundCloud, `ymalb:` — Яндекса). `tracks` — только на странице альбома.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Album {
  #[serde(rename = "ref")]
  pub ref_: String,
  pub title: String,
  pub artist: String,
  pub artists: Vec<ArtistRef>,
  pub cover_url: Option<String>,
  pub year: Option<u32>,
  /// Дата выхода `YYYY-MM-DD`, если сервис её знает (шапка альбома: «20 июня 2025»).
  #[serde(default)]
  pub released: Option<String>,
  pub track_count: u32,
  pub url: Option<String>,
}

/// Исполнитель (`sca:` — пользователь SoundCloud, `yma:` — артист Яндекса).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Artist {
  #[serde(rename = "ref")]
  pub ref_: String,
  pub name: String,
  pub avatar_url: Option<String>,
  pub followers: Option<u64>,
  pub url: Option<String>,
}

/// Плейлист сервиса (`scpl:<id>`, `ympl:<uid>:<kind>`) — «фантомный», виден, пока не перенесён.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ServicePlaylist {
  #[serde(rename = "ref")]
  pub ref_: String,
  pub title: String,
  pub owner: String,
  pub cover_url: Option<String>,
  pub track_count: u32,
}

/// Ответ поиска — как `GET /search` в docs/API.md §3.
#[derive(Debug, Clone, Serialize, Default)]
pub struct SearchResults {
  pub tracks: Vec<Track>,
  pub artists: Vec<Artist>,
  pub albums: Vec<Album>,
  pub playlists: Vec<ServicePlaylist>,
}

/// Страница исполнителя: шапка, популярные треки, альбомы.
#[derive(Debug, Clone, Serialize)]
pub struct ArtistPage {
  pub artist: Artist,
  pub top: Vec<Track>,
  pub albums: Vec<Album>,
}

/// Страница альбома или плейлиста сервиса: шапка и треки.
#[derive(Debug, Clone, Serialize)]
pub struct AlbumPage {
  pub album: Album,
  pub tracks: Vec<Track>,
}

/// Откуда играть: прямой файл (с Range) или плейлист HLS (его склеивает hls.js).
/// `quality` — что реально играет, для плашки в плеере: «AAC 160», «MP3 320», «FLAC».
#[derive(Debug, Clone, PartialEq)]
pub enum Source {
  File { url: String, quality: String },
  Hls { url: String, quality: String },
}

/// Подключённый аккаунт сервиса — для экрана «Сервисы».
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Account {
  pub name: Option<String>,
  pub avatar_url: Option<String>,
  /// id аккаунта в сервисе (uid Яндекса, id пользователя SoundCloud) — для его плейлистов и лайков.
  #[serde(default)]
  pub uid: Option<String>,
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
