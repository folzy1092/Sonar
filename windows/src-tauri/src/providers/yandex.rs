//! Яндекс Музыка: поиск, трек, ссылка на mp3. Заголовки и подпись — как в
//! server/tools/check_ym.py (проверено с ПК владельца 2026-11-12). Запросы — с IP компьютера
//! (вариант 3 из SPEC §3.7а), не чаще, чем просит пользователь.

use super::{http_error, Account, Album, AlbumRef, Artist, ArtistRef, ServicePlaylist, Source, Track};
use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;

const API: &str = "https://api.music.yandex.net";
/// Соль подписи ссылки на mp3 (как в yandex-music-api).
const SALT: &str = "XGRlBW9FXlekgbPrRHuSiA";
/// Ключ подписи `get-file-info` (как в yandex-music-api).
const SIGN_KEY: &[u8] = b"p93jhgh689SBReK6ghtw62";
/// «Без потерь» в настройке качества: FLAC, от 1411 кбит/с.
pub const LOSSLESS_KBPS: u32 = 1411;

fn hmac_sha256(key: &[u8], msg: &[u8]) -> [u8; 32] {
  use sha2::{Digest, Sha256};
  let mut k = [0u8; 64];
  if key.len() > 64 {
    k[..32].copy_from_slice(&Sha256::digest(key));
  } else {
    k[..key.len()].copy_from_slice(key);
  }
  let (mut ipad, mut opad) = ([0x36u8; 64], [0x5cu8; 64]);
  for i in 0..64 {
    ipad[i] ^= k[i];
    opad[i] ^= k[i];
  }
  let inner = Sha256::new().chain_update(ipad).chain_update(msg).finalize();
  Sha256::new().chain_update(opad).chain_update(inner).finalize().into()
}

/// Подпись `get-file-info`: base64(HMAC-SHA256(ts + trackId + quality + codecs без запятых + transports)) без последнего символа.
pub fn file_info_sign(ts: &str, id: &str, quality: &str, codecs: &str, transports: &str) -> String {
  use base64::Engine;
  let msg = format!("{ts}{id}{quality}{}{transports}", codecs.replace(',', ""));
  let mut s = base64::engine::general_purpose::STANDARD.encode(hmac_sha256(SIGN_KEY, msg.as_bytes()));
  s.pop();
  s
}

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
    self.with_headers(self.http.get(url))
  }

  fn with_headers(&self, rb: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
    rb
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
    Ok(Account { name, avatar_url: None, uid: id_str(&acc["uid"]) })
  }

  /// Исполнители, альбомы и плейлисты для вкладок поиска (один запрос `type=all`).
  pub async fn search_more(&self, q: &str, limit: u32) -> Result<(Vec<Artist>, Vec<Album>, Vec<ServicePlaylist>)> {
    let data = self
      .get(&format!("{API}/search"), &[("text", q), ("type", "all"), ("page", "0"), ("nocorrect", "false")])
      .await?;
    let list = |k: &str| data[k]["results"].as_array().cloned().unwrap_or_default();
    let n = limit as usize;
    Ok((
      list("artists").iter().filter_map(artist_from_json).take(n).collect(),
      list("albums").iter().filter_map(album_from_json).take(n).collect(),
      list("playlists").iter().filter_map(playlist_from_json).take(n).collect(),
    ))
  }

  /// Артист: шапка, популярные треки, альбомы (`brief-info`).
  pub async fn artist(&self, id: &str) -> Result<(Artist, Vec<Track>, Vec<Album>)> {
    let v = self.get(&format!("{API}/artists/{id}/brief-info"), &[]).await?;
    let artist = artist_from_json(&v["artist"]).ok_or_else(|| anyhow!("Яндекс Музыка: артист не найден"))?;
    let top = v["popularTracks"].as_array().map(|a| a.iter().filter_map(track_from_json).collect()).unwrap_or_default();
    let albums = v["albums"].as_array().map(|a| a.iter().filter_map(album_from_json).collect()).unwrap_or_default();
    Ok((artist, top, albums))
  }

  pub async fn album(&self, id: &str) -> Result<(Album, Vec<Track>)> {
    let v = self.get(&format!("{API}/albums/{id}/with-tracks"), &[]).await?;
    let album = album_from_json(&v).ok_or_else(|| anyhow!("Яндекс Музыка: альбом не найден"))?;
    let tracks = v["volumes"]
      .as_array()
      .map(|vols| vols.iter().flat_map(|vol| vol.as_array().cloned().unwrap_or_default()).filter_map(|t| track_from_json(&t)).collect())
      .unwrap_or_default();
    Ok((album, tracks))
  }

  pub async fn user_playlists(&self, uid: &str) -> Result<Vec<ServicePlaylist>> {
    let v = self.get(&format!("{API}/users/{uid}/playlists/list"), &[]).await?;
    Ok(v.as_array().map(|a| a.iter().filter_map(playlist_from_json).collect()).unwrap_or_default())
  }

  /// Плейлист целиком: шапка и треки. Если треки пришли без данных — дозапрашиваем по id.
  pub async fn playlist(&self, uid: &str, kind: &str) -> Result<(ServicePlaylist, Vec<Track>)> {
    let v = self.get(&format!("{API}/users/{uid}/playlists/{kind}"), &[("rich-tracks", "true")]).await?;
    let head = playlist_from_json(&v).ok_or_else(|| anyhow!("Яндекс Музыка: плейлист не найден"))?;
    let items = v["tracks"].as_array().cloned().unwrap_or_default();
    let tracks = if items.iter().all(|i| i["track"].is_object()) {
      items.iter().filter_map(|i| track_from_json(&i["track"])).collect()
    } else {
      let ids: Vec<String> = items.iter().filter_map(|i| id_str(&i["id"])).collect();
      self.tracks(&ids).await?
    };
    Ok((head, tracks))
  }

  /// Лайки в Яндексе (до `max`, новые первыми).
  pub async fn likes(&self, uid: &str, max: usize) -> Result<Vec<Track>> {
    let v = self.get(&format!("{API}/users/{uid}/likes/tracks"), &[]).await?;
    let ids: Vec<String> = v["library"]["tracks"]
      .as_array()
      .map(|a| {
        a.iter()
          .filter_map(|t| {
            let id = id_str(&t["id"])?;
            Some(match id_str(&t["albumId"]) {
              Some(alb) => format!("{id}:{alb}"),
              None => id,
            })
          })
          .take(max)
          .collect()
      })
      .unwrap_or_default();
    self.tracks(&ids).await
  }

  /// Похожие треки (`/tracks/{id}/similar`) — кандидаты своей волны (SPEC §3.7). rotor не трогаем.
  pub async fn similar(&self, id: &str) -> Result<Vec<Track>> {
    let v = self.get(&format!("{API}/tracks/{id}/similar"), &[]).await?;
    Ok(v["similarTracks"].as_array().map(|a| a.iter().filter_map(track_from_json).collect()).unwrap_or_default())
  }

  /// Новинки Яндекса (`landing3/new-releases` → альбомы по id) — запасной вариант «Релизов».
  pub async fn new_releases(&self, limit: usize) -> Result<Vec<Album>> {
    let v = self.get(&format!("{API}/landing3/new-releases"), &[]).await?;
    let ids: Vec<String> = v["newReleases"].as_array().map(|a| a.iter().filter_map(id_str).take(limit).collect()).unwrap_or_default();
    if ids.is_empty() {
      return Ok(vec![]);
    }
    let body = format!("album-ids={}", urlencoding::encode(&ids.join(",")));
    let r = self
      .with_headers(self.http.post(format!("{API}/albums")))
      .header("Content-Type", "application/x-www-form-urlencoded")
      .body(body)
      .send()
      .await?;
    if !r.status().is_success() {
      return Err(http_error("Яндекс Музыка", r.status()));
    }
    let v: Value = r.json().await?;
    Ok(v["result"].as_array().into_iter().flatten().filter_map(album_from_json).collect())
  }

  /// Треки по id (`POST /tracks`, порциями по 100), в том же порядке.
  async fn tracks(&self, ids: &[String]) -> Result<Vec<Track>> {
    let mut out = Vec::with_capacity(ids.len());
    for chunk in ids.chunks(100) {
      let body = format!("track-ids={}", urlencoding::encode(&chunk.join(",")));
      let r = self
        .with_headers(self.http.post(format!("{API}/tracks")))
        .header("Content-Type", "application/x-www-form-urlencoded")
        .body(body)
        .send()
        .await?;
      if !r.status().is_success() {
        return Err(http_error("Яндекс Музыка", r.status()));
      }
      let v: Value = r.json().await?;
      out.extend(v["result"].as_array().into_iter().flatten().filter_map(track_from_json));
    }
    Ok(out)
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

  /// Без потерь (`audio.quality = lossless`): `get-file-info` с `quality=lossless` → FLAC
  /// без шифрования (`transports=raw`). Подпись — HMAC-SHA256 параметров, как в yandex-music-api.
  /// Нет FLAC (нет Плюса, трек не в lossless) — None, дальше обычный mp3.
  pub async fn lossless_info(&self, id: &str) -> Result<Option<(String, String, u32)>> {
    let ts = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH)?.as_secs().to_string();
    let codecs = "flac,flac-mp4,aac,he-aac,mp3";
    let transports = "raw";
    let sign = file_info_sign(&ts, id, "lossless", codecs, transports);
    let data = self
      .get(
        &format!("{API}/get-file-info"),
        &[("ts", &ts), ("trackId", id), ("quality", "lossless"), ("codecs", codecs), ("transports", transports), ("sign", &sign)],
      )
      .await?;
    let info = &data["downloadInfo"];
    let codec = info["codec"].as_str().unwrap_or("").to_owned();
    let url = info["url"].as_str().or_else(|| info["urls"][0].as_str()).map(str::to_owned);
    let bitrate = info["bitrate"].as_u64().unwrap_or(0) as u32;
    Ok(match url {
      Some(u) if codec.starts_with("flac") && info["transport"] != "encraw" => Some((u, codec, bitrate)),
      _ => None,
    })
  }

  /// download-info → лучший mp3 не выше `max_kbps` → XML → подписанная ссылка на CDN.
  /// `max_kbps ≥ 1411` — сначала FLAC без потерь (`lossless_info`).
  pub async fn stream(&self, id: &str, max_kbps: u32) -> Result<Source> {
    if max_kbps >= LOSSLESS_KBPS {
      match self.lossless_info(id).await {
        Ok(Some((url, _, _))) => return Ok(Source::File { url, quality: "FLAC".into() }),
        Ok(None) => {}
        Err(e) => log::warn!("[yandex] lossless: {e}"),
      }
    }
    let infos = self.get(&format!("{API}/tracks/{id}/download-info"), &[]).await?;
    let info = pick_mp3(&infos, max_kbps).ok_or_else(|| anyhow!("Яндекс Музыка: нет mp3 для этого трека"))?;
    let xml_url = info["downloadInfoUrl"].as_str().ok_or_else(|| anyhow!("Яндекс Музыка: нет downloadInfoUrl"))?;
    let r = self.req(xml_url).send().await?;
    if !r.status().is_success() {
      return Err(http_error("Яндекс Музыка", r.status()));
    }
    let xml = r.text().await?;
    let url = signed_link(&xml).ok_or_else(|| anyhow!("Яндекс Музыка: не разобрал ссылку на файл"))?;
    let quality = format!("MP3 {}", info["bitrateInKbps"].as_u64().unwrap_or(0));
    Ok(Source::File { url, quality })
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

fn artist_refs(v: &Value) -> Vec<ArtistRef> {
  v.as_array()
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
    .unwrap_or_default()
}

pub fn artist_from_json(a: &Value) -> Option<Artist> {
  let id = id_str(&a["id"])?;
  Some(Artist {
    ref_: format!("yma:{id}"),
    name: a["name"].as_str()?.to_owned(),
    avatar_url: a["cover"]["uri"].as_str().or(a["ogImage"].as_str()).map(cover),
    followers: a["likesCount"].as_u64(),
    url: Some(format!("https://music.yandex.ru/artist/{id}")),
  })
}

pub fn album_from_json(a: &Value) -> Option<Album> {
  let id = id_str(&a["id"])?;
  let artists = artist_refs(&a["artists"]);
  Some(Album {
    ref_: format!("ymalb:{id}"),
    title: a["title"].as_str()?.to_owned(),
    artist: artists.iter().map(|x| x.name.as_str()).collect::<Vec<_>>().join(", "),
    artists,
    cover_url: a["coverUri"].as_str().or(a["ogImage"].as_str()).map(cover),
    year: a["year"].as_u64().map(|y| y as u32),
    released: a["releaseDate"].as_str().and_then(|d| d.get(..10)).map(str::to_owned),
    track_count: a["trackCount"].as_u64().unwrap_or(0) as u32,
    url: Some(format!("https://music.yandex.ru/album/{id}")),
  })
}

pub fn playlist_from_json(p: &Value) -> Option<ServicePlaylist> {
  let uid = id_str(&p["uid"]).or_else(|| id_str(&p["owner"]["uid"]))?;
  let kind = id_str(&p["kind"])?;
  let pic = p["cover"]["uri"].as_str().or(p["cover"]["itemsUri"][0].as_str()).or(p["ogImage"].as_str());
  Some(ServicePlaylist {
    ref_: format!("ympl:{uid}:{kind}"),
    title: p["title"].as_str()?.to_owned(),
    owner: p["owner"]["name"].as_str().or(p["owner"]["login"].as_str()).unwrap_or("").to_owned(),
    cover_url: pic.map(cover),
    track_count: p["trackCount"].as_u64().unwrap_or(0) as u32,
  })
}

pub fn track_from_json(j: &Value) -> Option<Track> {
  let id = id_str(&j["id"])?;
  let mut title = j["title"].as_str()?.to_owned();
  if let Some(v) = j["version"].as_str().filter(|v| !v.is_empty()) {
    title = format!("{title} ({v})");
  }
  let artists = artist_refs(&j["artists"]);
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
    plays: None,
    tags: j["albums"][0]["genre"].as_str().filter(|g| !g.is_empty()).map(|g| g.to_lowercase()),
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
  fn playlist_album_artist_json() {
    let p = json!({"uid": 42, "kind": 3, "title": "Мне нравится", "trackCount": 217,
      "owner": {"uid": 42, "login": "folzy", "name": "Folzy"}, "cover": {"itemsUri": ["avatars.yandex.net/a/%%"]}});
    let pl = playlist_from_json(&p).unwrap();
    assert_eq!(pl.ref_, "ympl:42:3");
    assert_eq!(pl.owner, "Folzy");
    assert_eq!(pl.cover_url.as_deref(), Some("https://avatars.yandex.net/a/400x400"));
    let a = album_from_json(&json!({"id": 9, "title": "Come Over", "year": 2016, "trackCount": 7,
      "artists": [{"id": 7, "name": "Lil Peep"}], "coverUri": "x/%%"}))
    .unwrap();
    assert_eq!((a.ref_.as_str(), a.artist.as_str(), a.year), ("ymalb:9", "Lil Peep", Some(2016)));
    let ar = artist_from_json(&json!({"id": 7, "name": "Lil Peep", "likesCount": 100})).unwrap();
    assert_eq!((ar.ref_.as_str(), ar.followers), ("yma:7", Some(100)));
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

  #[test]
  fn hmac_matches_rfc4231() {
    // RFC 4231, тест 2
    let mac = super::hmac_sha256(b"Jefe", b"what do ya want for nothing?");
    let hex: String = mac.iter().map(|b| format!("{b:02x}")).collect();
    assert_eq!(hex, "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");
  }

  #[tokio::test]
  #[ignore = "живой Яндекс на токене из keyring: печатает только форматы"]
  async fn live_quality_options() {
    let stored: crate::services::Stored<Creds> = crate::secrets::load("yandex").expect("Яндекс не подключён");
    let http = reqwest::Client::new();
    let ym = Yandex { http: &http, creds: &stored.creds };
    let q = std::env::var("YM_QUERY").unwrap_or_else(|_| "кизару дежавю".into());
    let found = ym.search(&q, 1).await.unwrap();
    let id = found[0].ref_.trim_start_matches("ym:").to_string();
    let infos = ym.get(&format!("{API}/tracks/{id}/download-info"), &[]).await.unwrap();
    let list: Vec<String> = infos.as_array().unwrap().iter().map(|i| format!("{} {}", i["codec"], i["bitrateInKbps"])).collect();
    println!("{} — {}: download-info {list:?}", found[0].artist, found[0].title);
    match ym.lossless_info(&id).await {
      Ok(Some((url, codec, br))) => {
        let r = http.get(&url).header("Range", "bytes=0-63").send().await.unwrap();
        let ct = r.headers().get("content-type").map(|v| v.to_str().unwrap_or("").to_owned());
        let len = r.headers().get("content-range").map(|v| v.to_str().unwrap_or("").to_owned());
        let b = r.bytes().await.unwrap();
        println!("lossless: {codec} {br} kbps, {ct:?} {len:?}, head {:?}", String::from_utf8_lossy(&b[4..12.min(b.len())]));
      }
      Ok(None) => println!("lossless: нет"),
      Err(e) => println!("lossless: ошибка {e}"),
    }
  }
}
