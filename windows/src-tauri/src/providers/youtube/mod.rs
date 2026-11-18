//! YouTube Music: свой клиент InnerTube (внутреннее API music.youtube.com). Готовую библиотеку
//! rustypipe не берём — она под GPL-3.0, а лицензия Sonar закрытая.
//!
//! - каталог (поиск, исполнитель, альбом, плейлист, «похожие») — клиент `WEB_REMIX`, как сайт;
//!   с cookie входа запросы подписываются `SAPISIDHASH` (`auth.rs`) — открывается библиотека;
//! - поток — `player` клиентом `VISIONOS`: он отдаёт прямые ссылки на аудио без расшифровки
//!   подписи. Ссылки googlevideo качаются только ограниченными Range-кусками (`gvideo.rs`).
//!
//! Проверка с компьютера — `server/tools/check_yt.py`, живые тесты — `cargo test youtube -- --ignored`.

pub mod auth;
pub mod parse;

use super::{http_error, Account, Album, Artist, ServicePlaylist, Source, Track, UA};
use anyhow::{anyhow, Result};
use parse::ArtistParsed;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

const API: &str = "https://music.youtube.com/youtubei/v1";
const PLAYER: &str = "https://www.youtube.com/youtubei/v1/player?prettyPrint=false";
const REMIX_VERSION: &str = "1.20251110.01.00";
const HL: &str = "ru";
const GL: &str = "LV";

/// Клиент потока: прямые ссылки на аудио (139/140/249/250/251) без `signatureCipher`.
const VISION_VERSION: &str = "0.1";
const VISION_CLIENT_ID: &str = "101";
const VISION_UA: &str = "Mozilla/5.0 (iPad; CPU OS 16_7_10 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)";

/// Фильтры поиска YouTube Music (параметр `params`).
const SEARCH_SONGS: &str = "EgWKAQIIAWoKEAkQBRAKEAMQBA==";
const SEARCH_ARTISTS: &str = "EgWKAQIgAWoKEAkQChAFEAMQBA==";
const SEARCH_ALBUMS: &str = "EgWKAQIYAWoKEAkQChAFEAMQBA==";
const SEARCH_PLAYLISTS: &str = "EgeKAQQoAEABagoQAxAEEAoQCRAF";

/// Сколько страниц продолжения читать у одного списка (по ~100 треков).
const MAX_PAGES: usize = 30;
/// Название «Понравившихся» в Sonar.
pub const LIKES_TITLE: &str = "Лайки YouTube Music";

/// Cookie входа в music.youtube.com. Секрет: в `Debug` не печатается.
#[derive(Clone, Serialize, Deserialize)]
pub struct Creds {
  pub cookie: String,
}

impl std::fmt::Debug for Creds {
  fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
    f.write_str("Creds { cookie: <скрыт> }")
  }
}

pub struct YouTube<'a> {
  pub http: &'a reqwest::Client,
  /// Без cookie работают поиск, страницы и поток; библиотеке нужен вход.
  pub creds: Option<&'a Creds>,
}

/// `visitorData` гостя — без неё `player` чаще отвечает «подтверди, что ты не бот».
pub async fn visitor_data(http: &reqwest::Client) -> Result<String> {
  let body = json!({"context": remix_context(), "browseId": "FEmusic_home"});
  let r = http
    .post(format!("{API}/browse?prettyPrint=false"))
    .header("User-Agent", UA)
    .header("Origin", auth::ORIGIN)
    .json(&body)
    .send()
    .await?;
  if !r.status().is_success() {
    return Err(http_error("YouTube Music", r.status()));
  }
  let v: Value = r.json().await?;
  v["responseContext"]["visitorData"].as_str().map(str::to_owned).ok_or_else(|| anyhow!("YouTube Music: не выдал visitorData"))
}

fn remix_context() -> Value {
  json!({"client": {"clientName": "WEB_REMIX", "clientVersion": REMIX_VERSION, "hl": HL, "gl": GL}})
}

/// Тело запроса `player` клиентом VISIONOS.
pub fn player_body(video_id: &str, visitor: &str) -> Value {
  json!({
    "context": {"client": {
      "clientName": "VISIONOS", "clientVersion": VISION_VERSION, "deviceMake": "Apple", "deviceModel": "RealityDevice14,1",
      "osName": "visionOS", "osVersion": "1.3.21O771", "hl": HL, "gl": GL, "visitorData": visitor
    }},
    "videoId": video_id,
    "contentCheckOk": true,
    "racyCheckOk": true
  })
}

impl YouTube<'_> {
  /// Запрос к InnerTube сайта; с cookie — подписанный.
  async fn post(&self, endpoint: &str, mut body: Value) -> Result<Value> {
    body["context"] = remix_context();
    let mut rb = self
      .http
      .post(format!("{API}/{endpoint}?prettyPrint=false"))
      .header("User-Agent", UA)
      .header("Origin", auth::ORIGIN)
      .header("Referer", format!("{}/", auth::ORIGIN))
      .json(&body);
    if let Some(c) = self.creds {
      let sapisid = auth::sapisid(&c.cookie).ok_or_else(|| anyhow!("YouTube Music: в cookie нет SAPISID — войди заново"))?;
      rb = rb
        .header("Cookie", &c.cookie)
        .header("Authorization", auth::sapisidhash(sapisid, auth::now_secs()))
        .header("X-Origin", auth::ORIGIN)
        .header("X-Goog-AuthUser", "0");
    }
    let r = rb.send().await?;
    if !r.status().is_success() {
      return Err(http_error("YouTube Music", r.status()));
    }
    Ok(r.json().await?)
  }

  async fn search_raw(&self, q: &str, params: &str) -> Result<Value> {
    self.post("search", json!({"query": q, "params": params})).await
  }

  pub async fn search(&self, q: &str, limit: u32) -> Result<Vec<Track>> {
    let mut t = parse::search_tracks(&self.search_raw(q, SEARCH_SONGS).await?);
    t.truncate(limit as usize);
    Ok(t)
  }

  /// Исполнители, альбомы и плейлисты для вкладок поиска (три запроса разом).
  pub async fn search_more(&self, q: &str, limit: u32) -> Result<(Vec<Artist>, Vec<Album>, Vec<ServicePlaylist>)> {
    let (a, b, c) = tokio::join!(self.search_raw(q, SEARCH_ARTISTS), self.search_raw(q, SEARCH_ALBUMS), self.search_raw(q, SEARCH_PLAYLISTS));
    let n = limit as usize;
    let mut artists = parse::search_artists(&a?);
    let mut albums = parse::search_albums(&b?);
    let mut lists = parse::search_playlists(&c?);
    artists.truncate(n);
    albums.truncate(n);
    lists.truncate(n);
    Ok((artists, albums, lists))
  }

  pub async fn artist(&self, channel_id: &str) -> Result<ArtistParsed> {
    parse::artist_page(&self.post("browse", json!({"browseId": channel_id})).await?, channel_id)
  }

  pub async fn album(&self, browse_id: &str) -> Result<(Album, Vec<Track>)> {
    parse::album_page(&self.post("browse", json!({"browseId": browse_id})).await?, browse_id)
  }

  /// Плейлист (`list_id` без `VL`; `likes` — «Понравившиеся», нужен вход) до `max` треков.
  pub async fn playlist(&self, list_id: &str, max: usize) -> Result<(ServicePlaylist, Vec<Track>)> {
    let browse = if list_id == "likes" { parse::LIKES_BROWSE_ID.to_owned() } else { format!("VL{list_id}") };
    let first = self.post("browse", json!({"browseId": browse})).await?;
    let (mut playlist, mut tracks, mut token) = parse::playlist_page(&first, list_id)?;
    let mut pages = 0;
    while let Some(t) = token.take() {
      if tracks.len() >= max || pages >= MAX_PAGES {
        break;
      }
      let (more, next) = parse::continuation_page(&self.post("browse", json!({"continuation": t})).await?);
      if more.is_empty() {
        break;
      }
      tracks.extend(more);
      token = next;
      pages += 1;
    }
    tracks.truncate(max);
    if list_id == "likes" {
      playlist.title = LIKES_TITLE.into();
      playlist.track_count = playlist.track_count.max(tracks.len() as u32);
    }
    if playlist.track_count == 0 {
      playlist.track_count = tracks.len() as u32;
    }
    Ok((playlist, tracks))
  }

  /// Очередь «радио» по треку (`RDAMVM<id>`) — похожие треки.
  pub async fn similar(&self, video_id: &str) -> Result<Vec<Track>> {
    let body = json!({
      "videoId": video_id,
      "playlistId": format!("RDAMVM{video_id}"),
      "isAudioOnly": true,
      "enablePersistentPlaylistPanel": true,
      "tunerSettingValue": "AUTOMIX_SETTING_NORMAL"
    });
    Ok(parse::next_tracks(&self.post("next", body).await?, video_id))
  }

  /// Плейлисты библиотеки (нужен вход), без «Понравившихся».
  pub async fn library_playlists(&self) -> Result<Vec<ServicePlaylist>> {
    Ok(parse::library_playlists(&self.post("browse", json!({"browseId": "FEmusic_liked_playlists"})).await?))
  }

  /// Аккаунт по cookie: имя, аватар, YouTube Premium.
  pub async fn account(&self) -> Result<Account> {
    if self.creds.is_none() {
      return Err(anyhow!("YouTube Music не подключена"));
    }
    parse::account(&self.post("account/account_menu", json!({})).await?)
  }

  /// Ответ `player` клиентом VISIONOS (гостем: подпись cookie этот клиент не принимает).
  pub async fn player(&self, video_id: &str, visitor: &str) -> Result<Value> {
    let r = self
      .http
      .post(PLAYER)
      .header("User-Agent", VISION_UA)
      .header("X-YouTube-Client-Name", VISION_CLIENT_ID)
      .header("X-YouTube-Client-Version", VISION_VERSION)
      .header("X-Goog-Visitor-Id", visitor)
      .json(&player_body(video_id, visitor))
      .send()
      .await?;
    if !r.status().is_success() {
      return Err(http_error("YouTube Music", r.status()));
    }
    Ok(r.json().await?)
  }

  /// Ссылка на аудио: «Высокое» — Opus 256/160, «Обычное» — AAC 128.
  pub async fn stream(&self, video_id: &str, visitor: &str, high: bool) -> Result<Source> {
    let formats = parse::player_formats(&self.player(video_id, visitor).await?)?;
    let f = parse::pick_format(&formats, high).ok_or_else(|| anyhow!("YouTube Music: у трека нет аудио"))?;
    Ok(Source::File { url: f.url.clone(), quality: parse::quality_label(f) })
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn creds_debug_hides_cookie() {
    let c = Creds { cookie: "SAPISID=secret-value".into() };
    let shown = format!("{c:?}");
    assert!(!shown.contains("secret-value"), "{shown}");
  }

  #[test]
  fn player_body_shape() {
    let b = player_body("abc", "vd");
    assert_eq!(b["videoId"], "abc");
    assert_eq!(b["context"]["client"]["clientName"], "VISIONOS");
    assert_eq!(b["context"]["client"]["visitorData"], "vd");
    assert_eq!(b["contentCheckOk"], true);
  }
}

/// Живые проверки: `cargo test youtube -- --ignored --nocapture`. Без cookie — гостем;
/// `YT_COOKIE=…` (из music.youtube.com) — ещё и аккаунт с библиотекой. Печатают только формат.
#[cfg(test)]
mod live {
  use super::*;

  fn client() -> reqwest::Client {
    reqwest::Client::builder().gzip(true).build().unwrap()
  }

  #[tokio::test]
  #[ignore = "живой YouTube Music"]
  async fn youtube_live_catalog_and_stream() {
    let http = client();
    let yt = YouTube { http: &http, creds: None };
    let found = yt.search("lil peep star shopping", 5).await.unwrap();
    assert!(!found.is_empty(), "поиск пуст");
    let t = &found[0];
    println!("поиск: {} — {} ({} мс)", t.artist, t.title, t.duration_ms);
    let id = t.ref_.trim_start_matches("yt:");
    let similar = yt.similar(id).await.unwrap();
    println!("похожих: {}", similar.len());
    let vd = visitor_data(&http).await.unwrap();
    for high in [false, true] {
      let Source::File { url, quality } = yt.stream(id, &vd, high).await.unwrap() else { panic!("ожидался файл") };
      let r = http.get(&url).header("User-Agent", UA).header("Range", "bytes=0-65535").send().await.unwrap();
      println!("поток {quality}: HTTP {}", r.status().as_u16());
      assert_eq!(r.status().as_u16(), 206);
    }
    if let Some(a) = t.artists.first() {
      let p = yt.artist(a.ref_.trim_start_matches("yta:")).await.unwrap();
      println!("исполнитель {}: топ {}, альбомов {}", p.artist.name, p.top.len(), p.albums.len());
    }
  }

  #[tokio::test]
  #[ignore = "живой YouTube Music с cookie из YT_COOKIE"]
  async fn youtube_live_account() {
    let Ok(cookie) = std::env::var("YT_COOKIE") else { return };
    let creds = Creds { cookie: auth::normalize_cookie(&cookie).unwrap() };
    let http = client();
    let yt = YouTube { http: &http, creds: Some(&creds) };
    let a = yt.account().await.unwrap();
    println!("аккаунт: есть имя {}, Premium {:?}", a.name.is_some(), a.premium);
    let lists = yt.library_playlists().await.unwrap();
    let (likes, tracks) = yt.playlist("likes", 200).await.unwrap();
    println!("плейлистов {}, лайков {} ({})", lists.len(), tracks.len(), likes.track_count);
  }
}
