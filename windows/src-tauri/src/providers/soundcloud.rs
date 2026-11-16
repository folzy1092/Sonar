//! SoundCloud через api-v2: поиск, трек, ссылка на поток. Опыт — selfbot `sc_api.py`, `sc_audio.py`.

use super::{http_error, Account, Album, Artist, ArtistRef, ServicePlaylist, Source, Track, UA};
use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

const API: &str = "https://api-v2.soundcloud.com";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Creds {
  pub client_id: String,
  /// OAuth-токен необязателен: без него играют только открытые треки.
  pub oauth_token: Option<String>,
}

pub struct SoundCloud<'a> {
  pub http: &'a reqwest::Client,
  pub creds: &'a Creds,
}

impl SoundCloud<'_> {
  async fn get(&self, url: &str, query: &[(&str, &str)]) -> Result<Value> {
    let mut req = self
      .http
      .get(url)
      .header("User-Agent", UA)
      .query(&[("client_id", self.creds.client_id.as_str())])
      .query(query);
    if let Some(t) = self.creds.oauth_token.as_deref().filter(|t| !t.is_empty()) {
      req = req.header("Authorization", format!("OAuth {t}"));
    }
    let r = req.send().await?;
    if !r.status().is_success() {
      return Err(http_error("SoundCloud", r.status()));
    }
    Ok(r.json().await?)
  }

  /// Проверка ключей: с токеном — профиль, без — пробный поиск.
  pub async fn account(&self) -> Result<Account> {
    if self.creds.oauth_token.as_deref().is_some_and(|t| !t.is_empty()) {
      let me = self.get(&format!("{API}/me"), &[]).await?;
      return Ok(Account {
        name: me["username"].as_str().map(str::to_owned),
        avatar_url: me["avatar_url"].as_str().map(str::to_owned),
        uid: me["id"].as_u64().map(|n| n.to_string()),
      });
    }
    self.get(&format!("{API}/search/tracks"), &[("q", "a"), ("limit", "1")]).await?;
    Ok(Account::default())
  }

  /// Поиск треков. Вместе с моделью отдаём сырой JSON — в нём данные для потока.
  pub async fn search(&self, q: &str, limit: u32) -> Result<Vec<(Track, Value)>> {
    let limit = limit.to_string();
    let data = self.get(&format!("{API}/search/tracks"), &[("q", q), ("limit", &limit)]).await?;
    Ok(data["collection"]
      .as_array()
      .map(|items| items.iter().filter_map(|j| track_from_json(j).map(|t| (t, j.clone()))).collect())
      .unwrap_or_default())
  }

  /// Исполнители, альбомы и плейлисты для вкладок поиска.
  pub async fn search_more(&self, q: &str, limit: u32) -> Result<(Vec<Artist>, Vec<Album>, Vec<ServicePlaylist>)> {
    let limit = limit.to_string();
    let query = [("q", q), ("limit", limit.as_str())];
    let (u1, u2, u3) =
      (format!("{API}/search/users"), format!("{API}/search/albums"), format!("{API}/search/playlists_without_albums"));
    let (users, albums, lists) = futures_util::join!(self.get(&u1, &query), self.get(&u2, &query), self.get(&u3, &query));
    let coll = |r: Result<Value>| r.ok().and_then(|v| v["collection"].as_array().cloned()).unwrap_or_default();
    Ok((
      coll(users).iter().filter_map(artist_from_json).collect(),
      coll(albums).iter().filter_map(album_from_json).collect(),
      coll(lists).iter().filter_map(playlist_from_json).collect(),
    ))
  }

  pub async fn user(&self, id: &str) -> Result<Value> {
    self.get(&format!("{API}/users/{id}"), &[]).await
  }

  /// Популярные треки пользователя (сырой JSON треков).
  /// Все треки пользователя (до `max`), постранично по `next_href`.
  pub async fn user_tracks(&self, id: &str, max: usize) -> Result<Vec<Value>> {
    let mut out: Vec<Value> = Vec::new();
    let mut v = self.get(&format!("{API}/users/{id}/tracks"), &[("limit", "200"), ("linked_partitioning", "true")]).await?;
    loop {
      out.extend(v["collection"].as_array().cloned().unwrap_or_default());
      let Some(next) = v["next_href"].as_str().filter(|_| out.len() < max).map(str::to_owned) else { break };
      v = self.get(&next, &[]).await?;
    }
    out.truncate(max);
    Ok(out)
  }

  pub async fn top_tracks(&self, id: &str, limit: u32) -> Result<Vec<Value>> {
    let limit = limit.to_string();
    let v = self.get(&format!("{API}/users/{id}/toptracks"), &[("limit", &limit)]).await?;
    Ok(v["collection"].as_array().cloned().unwrap_or_default())
  }

  pub async fn user_albums(&self, id: &str) -> Result<Vec<Album>> {
    let v = self.get(&format!("{API}/users/{id}/albums"), &[("limit", "30")]).await?;
    Ok(v["collection"].as_array().map(|a| a.iter().filter_map(album_from_json).collect()).unwrap_or_default())
  }

  /// Свои плейлисты пользователя (без альбомов) — фантомные плейлисты в медиатеке.
  pub async fn user_playlists(&self, id: &str) -> Result<Vec<ServicePlaylist>> {
    let v = self.get(&format!("{API}/users/{id}/playlists_without_albums"), &[("limit", "50")]).await?;
    Ok(v["collection"].as_array().map(|a| a.iter().filter_map(playlist_from_json).collect()).unwrap_or_default())
  }

  /// Плейлист или альбом целиком: JSON шапки + сырой JSON всех треков по порядку.
  /// SoundCloud отдаёт полностью только первые треки, остальные — заглушки с id: дозапрашиваем по 50.
  pub async fn playlist(&self, id: &str) -> Result<(Value, Vec<Value>)> {
    let pl = self.get(&format!("{API}/playlists/{id}"), &[("representation", "full")]).await?;
    let items = pl["tracks"].as_array().cloned().unwrap_or_default();
    let tracks = self.fill_stubs(items).await?;
    Ok((pl, tracks))
  }

  /// Лайки пользователя в SoundCloud (до `max` треков, новые первыми).
  pub async fn user_likes(&self, id: &str, max: usize) -> Result<Vec<Value>> {
    let mut out = Vec::new();
    let mut url = format!("{API}/users/{id}/track_likes?limit=200&linked_partitioning=1");
    loop {
      let page = self.get(&url, &[]).await?;
      for it in page["collection"].as_array().into_iter().flatten() {
        if it["track"].is_object() {
          out.push(it["track"].clone());
        }
      }
      match page["next_href"].as_str() {
        Some(next) if out.len() < max => url = next.to_owned(),
        _ => break,
      }
    }
    out.truncate(max);
    Ok(out)
  }

  async fn fill_stubs(&self, items: Vec<Value>) -> Result<Vec<Value>> {
    let missing: Vec<String> = items
      .iter()
      .filter(|t| t["title"].is_null())
      .filter_map(|t| t["id"].as_u64().map(|n| n.to_string()))
      .collect();
    let mut full = std::collections::HashMap::new();
    for chunk in missing.chunks(50) {
      let ids = chunk.join(",");
      let v = self.get(&format!("{API}/tracks"), &[("ids", &ids)]).await?;
      for t in v.as_array().into_iter().flatten() {
        if let Some(n) = t["id"].as_u64() {
          full.insert(n, t.clone());
        }
      }
    }
    Ok(items
      .into_iter()
      .filter_map(|t| if t["title"].is_null() { t["id"].as_u64().and_then(|n| full.get(&n).cloned()) } else { Some(t) })
      .collect())
  }

  /// Похожие треки (`/tracks/{id}/related`) — кандидаты для своей волны и «Похожего» (SPEC §3.7).
  pub async fn related(&self, id: &str, limit: u32) -> Result<Vec<Value>> {
    let limit = limit.to_string();
    let v = self.get(&format!("{API}/tracks/{id}/related"), &[("limit", &limit)]).await?;
    Ok(v["collection"].as_array().cloned().unwrap_or_default())
  }

  /// Что за адресом soundcloud.com (трек, плейлист / альбом, пользователь) — `/resolve`.
  pub async fn resolve(&self, url: &str) -> Result<Value> {
    self.get(&format!("{API}/resolve"), &[("url", url)]).await
  }

  pub async fn track_json(&self, id: &str) -> Result<Value> {
    self.get(&format!("{API}/tracks/{id}"), &[]).await
  }

  /// JSON трека → ссылка на поток (вариант выбирает `pick_transcoding`).
  pub async fn stream(&self, track: &Value) -> Result<Source> {
    let t = pick_transcoding(track).ok_or_else(|| anyhow!("SoundCloud: у трека нет доступного потока"))?;
    let url = t["url"].as_str().ok_or_else(|| anyhow!("SoundCloud: пустая ссылка потока"))?;
    let auth = track["track_authorization"].as_str().unwrap_or("");
    let data = self.get(url, &[("track_authorization", auth)]).await?;
    let link = data["url"].as_str().ok_or_else(|| anyhow!("SoundCloud: поток без ссылки"))?.to_owned();
    let quality = quality_label(t);
    Ok(if t["format"]["protocol"] == "progressive" {
      Source::File { url: link, quality }
    } else {
      Source::Hls { url: link, quality }
    })
  }
}

/// Публичный client_id с soundcloud.com (как `_sc_refresh_client_id` в selfbot): страница →
/// скрипты `a-v2.sndcdn.com/assets/*.js` с конца → `client_id:"<32 символа>"`.
pub async fn public_client_id(http: &reqwest::Client) -> Result<String> {
  let get = |url: String| async move {
    let r = http.get(&url).header("User-Agent", UA).send().await?;
    if !r.status().is_success() {
      return Err(http_error("SoundCloud", r.status()));
    }
    Ok::<String, anyhow::Error>(r.text().await?)
  };
  let page = get("https://soundcloud.com/".into()).await?;
  for src in script_urls(&page).into_iter().rev() {
    if let Ok(js) = get(src).await {
      if let Some(id) = find_client_id(&js) {
        return Ok(id);
      }
    }
  }
  Err(anyhow!("SoundCloud: не нашёл client_id на сайте — вставь свой в Настройки → Сервисы"))
}

fn script_urls(html: &str) -> Vec<String> {
  const START: &str = "https://a-v2.sndcdn.com/assets/";
  let mut out = Vec::new();
  let mut rest = html;
  while let Some(i) = rest.find(START) {
    let tail = &rest[i..];
    let end = tail.find('"').unwrap_or(tail.len());
    if tail[..end].ends_with(".js") {
      out.push(tail[..end].to_owned());
    }
    rest = &tail[end..];
  }
  out
}

fn find_client_id(js: &str) -> Option<String> {
  for pat in ["client_id:\"", "client_id=\""] {
    let mut rest = js;
    while let Some(i) = rest.find(pat) {
      let after = &rest[i + pat.len()..];
      let id: String = after.chars().take_while(|c| c.is_ascii_alphanumeric()).collect();
      if id.len() == 32 && after[32..].starts_with('"') {
        return Some(id);
      }
      rest = after;
    }
  }
  None
}

/// Лучший вариант, который умеют `<audio>` и hls.js: AAC HLS (больший битрейт) → mp3 файлом → mp3 HLS.
/// Зашифрованные (DRM) и Opus пропускаем; превью 30 с — только если другого нет.
/// «aac_160k» → «AAC 160», mp3 → «MP3 128» (битрейт у mp3_* в пресете не пишут).
pub fn quality_label(t: &Value) -> String {
  let preset = t["preset"].as_str().unwrap_or("");
  let codec = if t["format"]["mime_type"].as_str().unwrap_or("").contains("mpeg") { "MP3" } else { "AAC" };
  let kbps = preset.split('_').find_map(|p| p.strip_suffix('k').and_then(|n| n.parse::<u32>().ok())).unwrap_or(128);
  format!("{codec} {kbps}")
}

pub fn pick_transcoding(track: &Value) -> Option<&Value> {
  let list = track["media"]["transcodings"].as_array()?;
  let score = |t: &Value| -> Option<i32> {
    let proto = t["format"]["protocol"].as_str()?;
    let mime = t["format"]["mime_type"].as_str()?;
    let preset = t["preset"].as_str().unwrap_or("");
    // битрейт из пресета: "aac_160k" → 160; у mp3_* его нет — 128
    let kbps: i32 = preset
      .split('_')
      .find_map(|p| p.strip_suffix('k').and_then(|n| n.parse().ok()))
      .unwrap_or(128);
    let base = match (proto, mime) {
      ("hls", m) if m.starts_with("audio/mp4") => 3000,
      ("progressive", "audio/mpeg") => 2000,
      ("hls", "audio/mpeg") => 1000,
      _ => return None,
    } + kbps;
    Some(if t["snipped"].as_bool() == Some(true) { base - 10_000 } else { base })
  };
  list.iter().filter_map(|t| score(t).map(|s| (s, t))).max_by_key(|(s, _)| *s).map(|(_, t)| t)
}

pub fn track_from_json(j: &Value) -> Option<Track> {
  let id = j["id"].as_u64()?;
  let user = &j["user"];
  let name = user["username"].as_str().unwrap_or("").to_owned();
  let cover = j["artwork_url"].as_str().or(user["avatar_url"].as_str()).map(big_artwork);
  Some(Track {
    ref_: format!("sc:{id}"),
    title: j["title"].as_str()?.to_owned(),
    artist: name.clone(),
    artists: vec![ArtistRef {
      ref_: format!("sca:{}", user["id"].as_u64().unwrap_or(0)),
      name,
      avatar_url: user["avatar_url"].as_str().map(str::to_owned),
    }],
    album: None,
    duration_ms: j["full_duration"].as_u64().or(j["duration"].as_u64()).unwrap_or(0),
    cover_url: cover,
    url: j["permalink_url"].as_str().map(str::to_owned),
    explicit: j["publisher_metadata"]["explicit"].as_bool().unwrap_or(false),
    available: j["policy"].as_str() != Some("BLOCK"),
    plays: j["playback_count"].as_u64(),
    tags: sc_tags(j),
  })
}

pub fn artist_from_json(u: &Value) -> Option<Artist> {
  Some(Artist {
    ref_: format!("sca:{}", u["id"].as_u64()?),
    name: u["username"].as_str()?.to_owned(),
    avatar_url: u["avatar_url"].as_str().map(big_artwork),
    followers: u["followers_count"].as_u64(),
    url: u["permalink_url"].as_str().map(str::to_owned),
  })
}

/// Обложка плейлиста: своя, иначе первого трека.
fn playlist_cover(p: &Value) -> Option<String> {
  p["artwork_url"].as_str().or(p["tracks"][0]["artwork_url"].as_str()).map(big_artwork)
}

/// Альбом SoundCloud — это плейлист с `set_type` album/ep; ref `scalb:<id>`.
pub fn album_from_json(p: &Value) -> Option<Album> {
  let user = &p["user"];
  let name = user["username"].as_str().unwrap_or("").to_owned();
  let date = p["release_date"].as_str().or(p["published_at"].as_str()).or(p["created_at"].as_str()).unwrap_or("");
  Some(Album {
    ref_: format!("scalb:{}", p["id"].as_u64()?),
    title: p["title"].as_str()?.to_owned(),
    artist: name.clone(),
    artists: user["id"]
      .as_u64()
      .map(|id| vec![ArtistRef { ref_: format!("sca:{id}"), name, avatar_url: user["avatar_url"].as_str().map(str::to_owned) }])
      .unwrap_or_default(),
    cover_url: playlist_cover(p),
    year: date.get(..4).and_then(|y| y.parse().ok()),
    released: date.get(..10).filter(|d| d.as_bytes().get(4) == Some(&b'-')).map(str::to_owned),
    track_count: p["track_count"].as_u64().unwrap_or(0) as u32,
    url: p["permalink_url"].as_str().map(str::to_owned),
  })
}

pub fn playlist_from_json(p: &Value) -> Option<ServicePlaylist> {
  Some(ServicePlaylist {
    ref_: format!("scpl:{}", p["id"].as_u64()?),
    title: p["title"].as_str()?.to_owned(),
    owner: p["user"]["username"].as_str().unwrap_or("").to_owned(),
    cover_url: playlist_cover(p),
    track_count: p["track_count"].as_u64().unwrap_or(0) as u32,
  })
}

/// `…-large.jpg` → `…-t500x500.jpg`.
pub fn big_artwork(url: &str) -> String {
  url.replace("-large.", "-t500x500.")
}

#[cfg(test)]
mod tests {
  use super::*;
  use serde_json::json;

  fn tc(proto: &str, mime: &str, preset: &str, snipped: bool) -> Value {
    json!({"url": format!("u-{proto}-{preset}"), "preset": preset, "snipped": snipped,
           "format": {"protocol": proto, "mime_type": mime}})
  }

  #[test]
  fn picks_aac_hls_and_skips_drm_and_opus() {
    let t = json!({"media": {"transcodings": [
      tc("hls", "audio/mpeg", "mp3_1_0", false),
      tc("progressive", "audio/mpeg", "mp3_1_0", false),
      tc("ctr-encrypted-hls", "audio/mpeg", "mp3_1_0", false),
      tc("hls", "audio/ogg; codecs=\"opus\"", "opus_0_0", false),
      tc("hls", "audio/mp4; codecs=\"mp4a.40.2\"", "aac_160k", false),
      tc("hls", "audio/mp4; codecs=\"mp4a.40.2\"", "aac_96k", false),
    ]}});
    assert_eq!(pick_transcoding(&t).unwrap()["preset"], "aac_160k");
  }

  #[test]
  fn finds_scripts_and_client_id() {
    let html = r#"<script crossorigin src="https://a-v2.sndcdn.com/assets/0-a.js"></script>
      <link href="https://a-v2.sndcdn.com/assets/x.css"><script src="https://a-v2.sndcdn.com/assets/49-b.js"></script>"#;
    assert_eq!(script_urls(html), ["https://a-v2.sndcdn.com/assets/0-a.js", "https://a-v2.sndcdn.com/assets/49-b.js"]);
    let js = r#"a={client_id:"short"},b={client_id:"AbCdEfGhIjKlMnOpQrStUvWxYz012345",env:"production"}"#;
    assert_eq!(find_client_id(js).as_deref(), Some("AbCdEfGhIjKlMnOpQrStUvWxYz012345"));
  }

  /// Публичный client_id с сайта (сеть): `cargo test live_public -- --ignored`.
  #[tokio::test]
  #[ignore]
  async fn live_public_client_id() {
    let id = public_client_id(&reqwest::Client::new()).await.unwrap();
    assert_eq!(id.len(), 32);
  }

  #[test]
  fn snipped_only_if_nothing_else() {
    let t = json!({"media": {"transcodings": [
      tc("hls", "audio/mp4; codecs=\"mp4a.40.2\"", "aac_160k", true),
      tc("hls", "audio/mpeg", "mp3_1_0", false),
    ]}});
    assert_eq!(pick_transcoding(&t).unwrap()["preset"], "mp3_1_0");
  }

  /// Живая проверка: `SC_CLIENT_ID=… cargo test live -- --ignored --nocapture`.
  #[tokio::test]
  #[ignore]
  async fn live_search_and_stream() {
    let http = reqwest::Client::new();
    let client_id = match std::env::var("SC_CLIENT_ID") {
      Ok(id) => id,
      Err(_) => public_client_id(&http).await.unwrap(),
    };
    let creds = Creds { client_id, oauth_token: None };
    let sc = SoundCloud { http: &http, creds: &creds };
    let q = std::env::var("SC_QUERY").unwrap_or_else(|_| "lil peep".into());
    let found = sc.search(&q, 5).await.unwrap();
    assert!(!found.is_empty());
    let (track, json) = &found[0];
    let src = sc.stream(json).await.unwrap();
    let presets: Vec<_> = json["media"]["transcodings"].as_array().unwrap().iter()
      .map(|t| format!("{} {}", t["preset"], t["format"]["protocol"])).collect();
    println!("{} — {}: {presets:?} → {:?}", track.artist, track.title, pick_transcoding(json).unwrap()["preset"]);
    if let Source::Hls { url, .. } = src {
      let text = http.get(&url).send().await.unwrap().text().await.unwrap();
      assert!(text.starts_with("#EXTM3U"));
      println!("{}", &text[..text.len().min(1500)]);
    }
  }

  #[test]
  fn playlist_json_to_album_and_phantom() {
    let p = json!({"id": 77, "title": "suffocate reality", "track_count": 9, "release_date": "2024-03-01T00:00:00Z",
      "artwork_url": null, "tracks": [{"id": 1, "artwork_url": "https://i1.sndcdn.com/a-large.jpg"}],
      "user": {"id": 5, "username": "extra"}, "permalink_url": "https://soundcloud.com/extra/sets/s"});
    let a = album_from_json(&p).unwrap();
    assert_eq!(a.ref_, "scalb:77");
    assert_eq!(a.year, Some(2024));
    assert_eq!(a.cover_url.as_deref(), Some("https://i1.sndcdn.com/a-t500x500.jpg"));
    assert_eq!(a.artists[0].ref_, "sca:5");
    let pl = playlist_from_json(&p).unwrap();
    assert_eq!((pl.ref_.as_str(), pl.owner.as_str(), pl.track_count), ("scpl:77", "extra", 9));
  }

  /// Живая проверка страниц (сеть): `cargo test live_pages -- --ignored --nocapture`.
  #[tokio::test]
  #[ignore]
  async fn live_resolve_links() {
    let http = reqwest::Client::new();
    let creds = Creds { client_id: public_client_id(&http).await.unwrap(), oauth_token: None };
    let sc = SoundCloud { http: &http, creds: &creds };
    // адрес берём из поиска — у треков он «имя-автора/имя-трека», угадывать нельзя
    let found = sc.search("lil peep", 1).await.unwrap();
    let link = found[0].1["permalink_url"].as_str().unwrap().to_owned();
    let t = sc.resolve(&link).await.unwrap();
    assert_eq!(t["kind"], "track", "{link}");
    assert!(track_from_json(&t).is_some());
    let user = link.rsplit_once('/').unwrap().0;
    let u = sc.resolve(user).await.unwrap();
    assert_eq!(u["kind"], "user", "{user}");
  }

  #[tokio::test]
  #[ignore]
  async fn live_pages() {
    let http = reqwest::Client::new();
    let creds = Creds { client_id: public_client_id(&http).await.unwrap(), oauth_token: None };
    let sc = SoundCloud { http: &http, creds: &creds };
    let (artists, albums, lists) = sc.search_more("lil peep", 5).await.unwrap();
    println!("{} артистов, {} альбомов, {} плейлистов", artists.len(), albums.len(), lists.len());
    let id = artists[0].ref_.trim_start_matches("sca:");
    let top = sc.top_tracks(id, 5).await.unwrap();
    assert!(top.iter().filter_map(track_from_json).count() > 0);
    if let Some(pl) = lists.first() {
      let (_, tracks) = sc.playlist(pl.ref_.trim_start_matches("scpl:")).await.unwrap();
      println!("{}: {} из {}", pl.title, tracks.len(), pl.track_count);
      assert!(tracks.iter().all(|t| !t["title"].is_null()));
    }
  }

  #[test]
  fn track_json_to_model() {
    let j = json!({"id": 2296053116u64, "title": "море стало моим домом.", "duration": 123000,
      "artwork_url": "https://i1.sndcdn.com/artworks-x-large.jpg", "permalink_url": "https://soundcloud.com/o/m",
      "policy": "ALLOW", "user": {"id": 5, "username": "одиссея", "avatar_url": "a"}});
    let t = track_from_json(&j).unwrap();
    assert_eq!(t.ref_, "sc:2296053116");
    assert_eq!(t.cover_url.as_deref(), Some("https://i1.sndcdn.com/artworks-x-t500x500.jpg"));
    assert_eq!(t.artists[0].ref_, "sca:5");
    assert!(t.available);
  }
}

/// Жанр и теги трека SoundCloud одной строкой в нижнем регистре — по ним волна понимает настроение.
fn sc_tags(j: &Value) -> Option<String> {
  let mut out = String::new();
  for k in ["genre", "tag_list"] {
    if let Some(v) = j[k].as_str().filter(|v| !v.trim().is_empty()) {
      if !out.is_empty() {
        out.push(' ');
      }
      out.push_str(&v.to_lowercase());
    }
  }
  (!out.is_empty()).then_some(out)
}
