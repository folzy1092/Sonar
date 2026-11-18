//! Apple Music — только для импорта по ссылке (docs/NEXT_PROMPT.md, этап 5): своего сервиса Apple в
//! Sonar нет, слушать оттуда нельзя. Публичная страница `music.apple.com/<страна>/playlist|album/…`
//! отдаёт данные JSON'ом в `<script id="serialized-server-data">`: название, автор, обложка и
//! треки (название, исполнитель, длительность). Входа не нужно.
//!
//! Страница с сервера несёт не больше ~100 треков; сколько их всего — `trackCount` шапки.

use super::{Track, UA};
use anyhow::{anyhow, bail, Result};
use serde_json::Value;

/// Префикс ref трека Apple Music: только для экрана импорта, в медиатеку такие ref не попадают.
pub const TRACK_PREFIX: &str = "am";
/// Размер обложки вместо `{w}x{h}` шаблона Apple.
const COVER_SIZE: u32 = 600;
const DATA_TAG: &str = "id=\"serialized-server-data\"";

/// Плейлист или альбом Apple Music.
#[derive(Debug, Clone, PartialEq)]
pub struct ApplePage {
  pub album: bool,
  pub title: String,
  pub owner: String,
  pub cover_url: Option<String>,
  /// Сколько треков всего (на странице может быть меньше).
  pub track_count: u32,
  pub tracks: Vec<Track>,
}

/// Скачать и разобрать страницу.
pub async fn fetch(http: &reqwest::Client, url: &str) -> Result<ApplePage> {
  let res = http.get(url).header("User-Agent", UA).header("Accept-Language", "en").send().await?;
  if !res.status().is_success() {
    return Err(super::http_error("Apple Music", res.status()));
  }
  parse_page(&res.text().await?)
}

/// Разбор HTML страницы плейлиста или альбома.
pub fn parse_page(html: &str) -> Result<ApplePage> {
  let json = data_json(html).ok_or_else(|| anyhow!("Apple Music: на странице нет данных плейлиста"))?;
  let v: Value = serde_json::from_str(json).map_err(|e| anyhow!("Apple Music: не разобрал страницу ({e})"))?;
  let root = &v["data"][0];
  let album = match root["intent"]["$kind"].as_str() {
    Some("PlaylistDetailPageIntent") => false,
    Some("AlbumDetailPageIntent") => true,
    _ => bail!("Apple Music: по ссылке не плейлист и не альбом"),
  };
  let sections = root["data"]["sections"].as_array().map(Vec::as_slice).unwrap_or_default();
  let header = section(sections, "containerDetailHeaderLockup")
    .and_then(|s| s.first())
    .ok_or_else(|| anyhow!("Apple Music: на странице нет шапки плейлиста"))?;
  let title = str_of(&header["title"]);
  let owner = header["subtitleLinks"][0]["title"].as_str().unwrap_or_default().to_owned();
  let cover_url = cover(&header["artwork"]);
  let items = section(sections, "trackLockup").unwrap_or_default();
  let tracks: Vec<Track> = items
    .iter()
    .filter_map(|t| track(t, album.then_some((title.as_str(), cover_url.as_deref()))))
    .collect();
  let track_count = header["trackCount"].as_u64().map(|n| n as u32).unwrap_or(tracks.len() as u32);
  Ok(ApplePage { album, title, owner, cover_url, track_count, tracks })
}

/// Текст JSON внутри `<script id="serialized-server-data">…</script>`.
fn data_json(html: &str) -> Option<&str> {
  let tag = html.find(DATA_TAG)?;
  let start = tag + html[tag..].find('>')? + 1;
  let len = html[start..].find("</script>")?;
  Some(html[start..start + len].trim())
}

fn section<'a>(sections: &'a [Value], kind: &str) -> Option<&'a [Value]> {
  sections
    .iter()
    .find(|s| s["itemKind"].as_str() == Some(kind))
    .and_then(|s| s["items"].as_array())
    .map(Vec::as_slice)
}

fn str_of(v: &Value) -> String {
  v.as_str().unwrap_or_default().trim().to_owned()
}

/// Ссылка на обложку из шаблона `…/{w}x{h}bb.{f}`.
fn cover(artwork: &Value) -> Option<String> {
  let url = artwork["dictionary"]["url"].as_str()?;
  Some(url.replace("{w}", &COVER_SIZE.to_string()).replace("{h}", &COVER_SIZE.to_string()).replace("{f}", "jpg"))
}

/// Трек из `trackLockup`. У альбома своих обложки и названия альбома в строке нет — `album` их даёт.
fn track(t: &Value, album: Option<(&str, Option<&str>)>) -> Option<Track> {
  let title = str_of(&t["title"]);
  let id = t["contentDescriptor"]["identifiers"]["storeAdamID"].as_str()?;
  if title.is_empty() {
    return None;
  }
  let names: Vec<String> =
    t["subtitleLinks"].as_array().into_iter().flatten().map(|l| str_of(&l["title"])).filter(|n| !n.is_empty()).collect();
  let artist = match t["artistName"].as_str().map(str::trim) {
    Some(a) if !a.is_empty() => a.to_owned(),
    _ => names.join(", "),
  };
  let cover_url = cover(&t["artwork"]).or_else(|| album.and_then(|a| a.1).map(str::to_owned));
  Some(Track {
    ref_: format!("{TRACK_PREFIX}:{id}"),
    title,
    artist,
    artists: vec![],
    album: None,
    duration_ms: t["duration"].as_u64().unwrap_or(0),
    cover_url,
    url: None,
    explicit: t["showExplicitBadge"].as_bool().unwrap_or(false),
    available: !t["isDisabled"].as_bool().unwrap_or(false),
    plays: None,
    tags: None,
  })
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::providers::matching::Wanted;

  const PLAYLIST: &str = include_str!("fixtures/apple-playlist.html");
  const ALBUM: &str = include_str!("fixtures/apple-album.html");

  #[test]
  fn parses_saved_playlist_page() {
    let p = parse_page(PLAYLIST).unwrap();
    assert!(!p.album);
    assert_eq!(p.title, "Today’s Hits");
    assert_eq!(p.owner, "Apple Music Hits");
    assert_eq!(p.track_count, 50);
    assert!(p.cover_url.as_deref().unwrap().ends_with("/600x600bb.jpg"));
    assert_eq!(p.tracks.len(), 4);
    let first = &p.tracks[0];
    assert_eq!(first.ref_, "am:6822497774");
    assert_eq!((first.title.as_str(), first.artist.as_str(), first.duration_ms), ("Housewife", "Tate McRae", 208810));
    assert!(first.available && first.cover_url.is_some());
    // несколько исполнителей — одной строкой, сверка всё равно делит их
    let duo = p.tracks.iter().find(|t| t.artist.contains('&')).unwrap();
    assert_eq!(duo.artist, "Drake & Don Toliver");
    assert!(Wanted::from_track(duo).artists.iter().any(|a| a.contains("Drake")));
    assert!(p.tracks.iter().any(|t| t.explicit));
  }

  #[test]
  fn parses_saved_album_page() {
    let p = parse_page(ALBUM).unwrap();
    assert!(p.album);
    assert_eq!(p.title, "Housewife - Single");
    assert_eq!(p.owner, "Tate McRae");
    assert_eq!(p.tracks.len(), 1);
    // у треков альбома нет своей обложки — берётся обложка альбома
    assert_eq!(p.tracks[0].cover_url, p.cover_url);
  }

  #[test]
  fn rejects_pages_without_data() {
    assert!(parse_page("<html><body>nothing</body></html>").is_err());
    let artist = r#"<script type="application/json" id="serialized-server-data">{"data":[{"intent":{"$kind":"ArtistDetailPageIntent"},"data":{"sections":[]}}]}</script>"#;
    assert!(parse_page(artist).unwrap_err().to_string().contains("не плейлист"));
  }

  #[tokio::test]
  #[ignore = "живая страница Apple Music"]
  async fn live_playlist() {
    let url = "https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd41149aaacabb233eb5eb";
    let p = fetch(&reqwest::Client::new(), url).await.unwrap();
    assert!(!p.tracks.is_empty());
  }
}
