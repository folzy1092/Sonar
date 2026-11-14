//! SoundCloud через api-v2: поиск, трек, ссылка на поток. Опыт — selfbot `sc_api.py`, `sc_audio.py`.

use super::{http_error, Account, ArtistRef, Source, Track, UA};
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
    Ok(if t["format"]["protocol"] == "progressive" { Source::File { url: link } } else { Source::Hls { url: link } })
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
    let creds = Creds { client_id: std::env::var("SC_CLIENT_ID").unwrap(), oauth_token: None };
    let http = reqwest::Client::new();
    let sc = SoundCloud { http: &http, creds: &creds };
    let found = sc.search("lil peep", 5).await.unwrap();
    assert!(!found.is_empty());
    let (track, json) = &found[0];
    let src = sc.stream(json).await.unwrap();
    let presets: Vec<_> = json["media"]["transcodings"].as_array().unwrap().iter()
      .map(|t| format!("{} {}", t["preset"], t["format"]["protocol"])).collect();
    println!("{} — {}: {presets:?} → {:?}", track.artist, track.title, pick_transcoding(json).unwrap()["preset"]);
    if let Source::Hls { url } = src {
      let text = http.get(&url).send().await.unwrap().text().await.unwrap();
      assert!(text.starts_with("#EXTM3U"));
      println!("{}", &text[..text.len().min(400)]);
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
