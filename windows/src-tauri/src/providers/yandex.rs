//! Яндекс Музыка: поиск, трек, ссылка на mp3. Заголовки и подпись — как в
//! server/tools/check_ym.py (проверено с ПК владельца 2026-11-12). Запросы — с IP компьютера
//! (вариант 3 из SPEC §3.7а), не чаще, чем просит пользователь.

use super::{http_error, Account, AlbumRef, ArtistRef, Source, Track};
use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

const API: &str = "https://api.music.yandex.net";
/// Соль подписи ссылки на mp3 (как в yandex-music-api).
const SALT: &str = "XGRlBW9FXlekgbPrRHuSiA";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Creds {
  pub token: String,
}

pub struct Yandex<'a> {
  pub http: &'a reqwest::Client,
  pub creds: &'a Creds,
}

impl Yandex<'_> {
  fn req(&self, url: &str) -> reqwest::RequestBuilder {
    self
      .http
      .get(url)
      .header("X-Yandex-Music-Client", "YandexMusicAndroid/24023621")
      .header("User-Agent", "Yandex-Music-API")
      .header("Accept-Language", "ru")
      .header("Authorization", format!("OAuth {}", self.creds.token))
  }

  async fn get(&self, url: &str, query: &[(&str, &str)]) -> Result<Value> {
    let r = self.req(url).query(query).send().await?;
    if !r.status().is_success() {
      return Err(http_error("Яндекс Музыка", r.status()));
    }
    let v: Value = r.json().await?;
    Ok(v["result"].clone())
  }

  pub async fn account(&self) -> Result<Account> {
    let st = self.get(&format!("{API}/account/status"), &[]).await?;
    let acc = &st["account"];
    let name = acc["displayName"].as_str().or(acc["login"].as_str()).map(str::to_owned);
    if acc["uid"].is_null() {
      return Err(anyhow!("Яндекс Музыка: токен не подошёл"));
    }
    Ok(Account { name, avatar_url: None })
  }

  pub async fn search(&self, q: &str, limit: u32) -> Result<Vec<Track>> {
    let data = self
      .get(&format!("{API}/search"), &[("text", q), ("type", "track"), ("page", "0"), ("nocorrect", "false")])
      .await?;
    Ok(data["tracks"]["results"]
      .as_array()
      .map(|a| a.iter().filter_map(track_from_json).take(limit as usize).collect())
      .unwrap_or_default())
  }

  /// download-info → лучший mp3 не выше `max_kbps` → XML → подписанная ссылка на CDN.
  pub async fn stream(&self, id: &str, max_kbps: u32) -> Result<Source> {
    let infos = self.get(&format!("{API}/tracks/{id}/download-info"), &[]).await?;
    let info = pick_mp3(&infos, max_kbps).ok_or_else(|| anyhow!("Яндекс Музыка: нет mp3 для этого трека"))?;
    let xml_url = info["downloadInfoUrl"].as_str().ok_or_else(|| anyhow!("Яндекс Музыка: нет downloadInfoUrl"))?;
    let r = self.req(xml_url).send().await?;
    if !r.status().is_success() {
      return Err(http_error("Яндекс Музыка", r.status()));
    }
    let xml = r.text().await?;
    let url = signed_link(&xml).ok_or_else(|| anyhow!("Яндекс Музыка: не разобрал ссылку на файл"))?;
    Ok(Source::File { url })
  }
}

pub fn pick_mp3(infos: &Value, max_kbps: u32) -> Option<&Value> {
  let mp3: Vec<&Value> = infos.as_array()?.iter().filter(|i| i["codec"] == "mp3").collect();
  let kbps = |i: &Value| i["bitrateInKbps"].as_u64().unwrap_or(0) as u32;
  mp3
    .iter()
    .copied()
    .filter(|i| kbps(i) <= max_kbps)
    .max_by_key(|i| kbps(i))
    .or_else(|| mp3.iter().copied().min_by_key(|i| kbps(i)))
}

fn tag<'a>(xml: &'a str, name: &str) -> Option<&'a str> {
  let open = format!("<{name}>");
  let start = xml.find(&open)? + open.len();
  let end = xml[start..].find(&format!("</{name}>"))? + start;
  Some(&xml[start..end])
}

/// `https://{host}/get-mp3/{md5(SALT + path[1:] + s)}/{ts}{path}`.
pub fn signed_link(xml: &str) -> Option<String> {
  let (host, path, ts, s) = (tag(xml, "host")?, tag(xml, "path")?, tag(xml, "ts")?, tag(xml, "s")?);
  let sign = md5::compute(format!("{SALT}{}{s}", path.get(1..)?));
  Some(format!("https://{host}/get-mp3/{sign:x}/{ts}{path}"))
}

fn id_str(v: &Value) -> Option<String> {
  v.as_str().map(str::to_owned).or_else(|| v.as_u64().map(|n| n.to_string()))
}

/// `avatars.yandex.net/…/%%` → `https://avatars.yandex.net/…/400x400`.
pub fn cover(uri: &str) -> String {
  format!("https://{}", uri.replace("%%", "400x400"))
}

pub fn track_from_json(j: &Value) -> Option<Track> {
  let id = id_str(&j["id"])?;
  let mut title = j["title"].as_str()?.to_owned();
  if let Some(v) = j["version"].as_str().filter(|v| !v.is_empty()) {
    title = format!("{title} ({v})");
  }
  let artists: Vec<ArtistRef> = j["artists"]
    .as_array()
    .map(|a| {
      a.iter()
        .filter_map(|x| {
          Some(ArtistRef {
            ref_: format!("yma:{}", id_str(&x["id"])?),
            name: x["name"].as_str()?.to_owned(),
            avatar_url: x["cover"]["uri"].as_str().map(cover),
          })
        })
        .collect()
    })
    .unwrap_or_default();
  let album = &j["albums"][0];
  let album_id = id_str(&album["id"]);
  Some(Track {
    ref_: format!("ym:{id}"),
    title,
    artist: artists.iter().map(|a| a.name.as_str()).collect::<Vec<_>>().join(", "),
    album: album_id.as_ref().map(|a| AlbumRef {
      ref_: format!("ymalb:{a}"),
      title: album["title"].as_str().unwrap_or("").to_owned(),
    }),
    url: Some(match &album_id {
      Some(a) => format!("https://music.yandex.ru/album/{a}/track/{id}"),
      None => format!("https://music.yandex.ru/track/{id}"),
    }),
    artists,
    duration_ms: j["durationMs"].as_u64().unwrap_or(0),
    cover_url: j["coverUri"].as_str().or(album["coverUri"].as_str()).map(cover),
    explicit: j["contentWarning"].as_str() == Some("explicit"),
    available: j["available"].as_bool().unwrap_or(true),
  })
}

#[cfg(test)]
mod tests {
  use super::*;
  use serde_json::json;

  #[test]
  fn signs_link_like_library() {
    let xml = "<?xml version=\"1.0\"?><download-info><host>s1.storage.yandex.net</host>\
      <path>/rmusic/abc</path><ts>0005f</ts><region>-1</region><s>deadbeef</s></download-info>";
    let want = format!("{:x}", md5::compute(format!("{SALT}rmusic/abcdeadbeef")));
    assert_eq!(signed_link(xml).unwrap(), format!("https://s1.storage.yandex.net/get-mp3/{want}/0005f/rmusic/abc"));
  }

  #[test]
  fn picks_best_mp3_under_cap() {
    let infos = json!([
      {"codec": "mp3", "bitrateInKbps": 320}, {"codec": "mp3", "bitrateInKbps": 192},
      {"codec": "aac", "bitrateInKbps": 256}, {"codec": "mp3", "bitrateInKbps": 128}
    ]);
    assert_eq!(pick_mp3(&infos, 320).unwrap()["bitrateInKbps"], 320);
    assert_eq!(pick_mp3(&infos, 256).unwrap()["bitrateInKbps"], 192);
    assert_eq!(pick_mp3(&infos, 64).unwrap()["bitrateInKbps"], 128);
  }

  #[test]
  fn track_json_to_model() {
    let j = json!({"id": "123", "title": "Benz Truck", "version": "Remix", "durationMs": 160000,
      "coverUri": "avatars.yandex.net/get-music-content/1/%%", "available": true,
      "artists": [{"id": 7, "name": "Lil Peep"}], "albums": [{"id": 99, "title": "Come Over"}]});
    let t = track_from_json(&j).unwrap();
    assert_eq!(t.ref_, "ym:123");
    assert_eq!(t.title, "Benz Truck (Remix)");
    assert_eq!(t.artist, "Lil Peep");
    assert_eq!(t.cover_url.as_deref(), Some("https://avatars.yandex.net/get-music-content/1/400x400"));
    assert_eq!(t.url.as_deref(), Some("https://music.yandex.ru/album/99/track/123"));
  }
}
