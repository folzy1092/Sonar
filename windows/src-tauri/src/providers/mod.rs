//! Работа с музыкальными сервисами: модели (как в docs/API.md) и разбор ответов.
//! Потом эта же раскладка переезжает в server/sonar/providers (SPEC §9.3).

pub mod links;
pub mod matching;
pub mod registry;
pub mod soundcloud;
pub mod vk;
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
  /// Жанр и теги (SoundCloud — жанр и теги, Яндекс — жанр альбома), для режимов волны.
  #[serde(default, skip_serializing_if = "Option::is_none")]
  pub tags: Option<String>,
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
/// Трек на странице исполнителя: сам трек и то, по чему сортируют «Треки» (решение владельца
/// 2026-11-16): лайки и дата выхода. В JSON — один объект (поля трека + `likes`, `released`).
#[derive(Debug, Clone, Serialize)]
pub struct ArtistTrack {
  #[serde(flatten)]
  pub track: Track,
  /// Лайки на сервисе (SoundCloud `likes_count`; у Яндекса нет).
  pub likes: Option<u64>,
  /// Дата выхода `YYYY-MM-DD` (SoundCloud — дата релиза или загрузки, Яндекс — альбома).
  pub released: Option<String>,
}

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
  /// Подписка сервиса (Яндекс Плюс). None — сервис не говорит; старый JSON из keyring без поля — тоже None.
  #[serde(default)]
  pub premium: Option<bool>,
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

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn account_old_json_without_premium() {
    let a: Account = serde_json::from_str(r#"{"name":"a","avatar_url":null,"uid":"1"}"#).unwrap();
    assert_eq!((a.name.as_deref(), a.uid.as_deref(), a.premium), (Some("a"), Some("1"), None));
    let b: Account = serde_json::from_str(r#"{"name":null,"avatar_url":null,"uid":null,"premium":true}"#).unwrap();
    assert_eq!(b.premium, Some(true));
  }
}
