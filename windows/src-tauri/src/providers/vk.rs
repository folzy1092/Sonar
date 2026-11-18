//! VK Музыка: поиск, «Моя музыка», плейлисты, альбомы, исполнители, похожие, ссылка на поток.
//! Ключ — токен Kate Mobile (`vk1.a.…`, вход на oauth.vk.com в `login.rs` или «Вставить ключ»):
//! методы `audio.*` VK отдаёт только «своим» клиентам, поэтому у каждого запроса — User-Agent
//! Kate Mobile. Запросы — POST с формой: токен в теле, не в адресе, и не попадает ни в ошибку
//! reqwest, ни в журнал. Проверка с компьютера владельца — `server/tools/check_vk.py`.
//!
//! ref: трек `vk:<owner>_<id>` (access_key трека — на диске, services/vk_keys.rs), альбом
//! `vkalb:<owner>_<id>[_<access_key>]`, плейлист `vkpl:<owner>_<id>[_<access_key>]` и `vkpl:likes`,
//! исполнитель `vka:<id>` (docs/API.md «Префиксы ref»).

use super::{http_error, Account, Album, AlbumRef, Artist, ArtistRef, ServicePlaylist, Source, Track};
use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::sync::Mutex;
use std::time::{Duration, Instant};

const API: &str = "https://api.vk.com/method";
/// Версия API, на которой проверены поля ответа.
pub const VERSION: &str = "5.131";
/// Приложение Kate Mobile: ему VK открывает `audio.*` (вход в один клик — `login.rs`).
pub const KATE_CLIENT_ID: &str = "2685278";
/// User-Agent Kate Mobile — на каждом запросе к API и к CDN VK (stream.rs).
pub const UA: &str = "KateMobileAndroid/56 lite-460 (Android 4.4.2; SDK 19; x86; unknown Android SDK built for x86; en)";
const NAME: &str = "VK Музыка";
/// Ключ отозван, устарел или без права `audio` (коды 5, 15, 25, 201, 1117).
pub const AUTH_EXPIRED: &str = "Ключ VK больше не работает — войди заново";
const TOO_MANY: &str = "VK Музыка: слишком много запросов, подожди минуту";
const CAPTCHA: &str = "VK Музыка: VK просит подтвердить вход — войди заново";
const FAILED: &str = "VK Музыка: сервис ответил ошибкой";
const OFFLINE: &str = "VK Музыка: нет связи с VK";
const NO_STREAM: &str = "VK Музыка: VK не отдал ссылку на трек";
/// VK пускает не больше 3 запросов в секунду с одного ключа.
const GAP: Duration = Duration::from_millis(350);
/// Сколько отдаёт за раз `audio.get` / `audio.getAudiosByArtist`.
const PAGE: usize = 200;

/// Когда можно сделать следующий запрос (общий для всех запросов к VK).
static NEXT_CALL: Mutex<Option<Instant>> = Mutex::new(None);

/// Сколько подождать перед запросом, чтобы между запросами было не меньше `GAP`;
/// `next` сдвигается на следующий свободный слот.
fn take_slot(next: &mut Option<Instant>, now: Instant) -> Duration {
  let at = next.map_or(now, |n| n.max(now));
  *next = Some(at + GAP);
  at - now
}

fn wait_turn() -> Duration {
  let mut next = NEXT_CALL.lock().unwrap_or_else(|p| p.into_inner());
  take_slot(&mut next, Instant::now())
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Creds {
  pub token: String,
}

/// Трек VK и то, что нужно для потока: access_key и ссылка (если VK отдал её сразу).
#[derive(Debug, Clone, PartialEq)]
pub struct VkAudio {
  pub track: Track,
  pub access_key: Option<String>,
  pub stream_url: Option<String>,
}

/// Ошибка API (`{"error": {...}}`) → текст для человека. Сообщение VK в текст не берём.
pub fn api_error(v: &Value) -> Option<anyhow::Error> {
  let e = v.get("error")?;
  let code = e["error_code"].as_i64().unwrap_or(0);
  let text = match code {
    5 | 15 | 25 | 201 | 1117 => AUTH_EXPIRED,
    6 | 9 | 29 => TOO_MANY,
    14 | 17 => CAPTCHA,
    _ => FAILED,
  };
  log::warn!("[vk] ошибка API, код {code}");
  Some(anyhow!(text))
}

pub struct Vk<'a> {
  pub http: &'a reqwest::Client,
  pub creds: &'a Creds,
}

impl Vk<'_> {
  /// Метод API: POST с формой (токен в теле), ответ — поле `response`. Код 6 — один повтор.
  async fn call(&self, method: &str, params: &[(&str, String)]) -> Result<Value> {
    match self.call_once(method, params).await {
      Err(e) if e.to_string() == TOO_MANY => {
        tokio::time::sleep(Duration::from_secs(1)).await;
        self.call_once(method, params).await
      }
      r => r,
    }
  }

  async fn call_once(&self, method: &str, params: &[(&str, String)]) -> Result<Value> {
    let wait = wait_turn();
    if !wait.is_zero() {
      tokio::time::sleep(wait).await;
    }
    let mut form: Vec<(&str, &str)> = params.iter().map(|(k, v)| (*k, v.as_str())).collect();
    form.push(("access_token", self.creds.token.as_str()));
    form.push(("v", VERSION));
    let r = self
      .http
      .post(format!("{API}/{method}"))
      .header("User-Agent", UA)
      .form(&form)
      .send()
      .await
      .map_err(|e| {
        log::warn!("[vk] {method}: {}", e.without_url());
        anyhow!(OFFLINE)
      })?;
    if !r.status().is_success() {
      return Err(http_error(NAME, r.status()));
    }
    let v: Value = r.json().await.map_err(|_| anyhow!(FAILED))?;
    if let Some(e) = api_error(&v) {
      return Err(e);
    }
    Ok(v["response"].clone())
  }

  /// Кто вошёл, и проверка, что ключу открыта музыка (иначе — «войди заново»).
  pub async fn account(&self) -> Result<Account> {
    let me = self.call("users.get", &[("fields", "photo_200".into())]).await?;
    let mut account = account_from_json(&me[0]).ok_or_else(|| anyhow!(AUTH_EXPIRED))?;
    let uid = account.uid.clone().unwrap_or_default();
    self.call("audio.get", &[("owner_id", uid), ("count", "1".into())]).await?;
    account.premium = None;
    Ok(account)
  }

  pub async fn search(&self, q: &str, limit: u32) -> Result<Vec<VkAudio>> {
    let v = self
      .call("audio.search", &[("q", q.into()), ("count", limit.min(300).to_string()), ("auto_complete", "1".into()), ("sort", "2".into())])
      .await?;
    Ok(audios(&v["items"]))
  }

  /// Исполнители, альбомы и плейлисты. Каждый из трёх запросов необязателен: упал один —
  /// остальные всё равно показываем; общей ошибкой — только протухший ключ.
  pub async fn search_more(&self, q: &str, limit: u32) -> Result<(Vec<Artist>, Vec<Album>, Vec<ServicePlaylist>)> {
    let n = limit.min(100).to_string();
    let params = [("q", q.to_owned()), ("count", n)];
    let artists = self.optional_items("audio.searchArtists", &params).await?;
    let albums = self.optional_items("audio.searchAlbums", &params).await?;
    let playlists = self.optional_items("audio.searchPlaylists", &params).await?;
    Ok((
      artists.iter().filter_map(artist_from_json).collect(),
      albums.iter().filter_map(album_from_json).collect(),
      playlists.iter().filter_map(playlist_from_json).collect(),
    ))
  }

  /// `items` метода; ошибка (кроме протухшего ключа) — пустой список и строка в журнал.
  async fn optional_items(&self, method: &str, params: &[(&str, String)]) -> Result<Vec<Value>> {
    match self.call(method, params).await {
      Ok(v) => Ok(items(&v)),
      Err(e) if e.to_string() == AUTH_EXPIRED => Err(e),
      Err(e) => {
        log::warn!("[vk] {method} пропущен: {e}");
        Ok(Vec::new())
      }
    }
  }

  /// Треки по `owner_id_id[_access_key]` (до 100 за раз).
  pub async fn by_id(&self, ids: &[String]) -> Result<Vec<VkAudio>> {
    let v = self.call("audio.getById", &[("audios", ids.join(","))]).await?;
    Ok(audios(&v))
  }

  /// «Моя музыка» аккаунта (до `max`), новые сверху.
  pub async fn likes(&self, uid: &str, max: usize) -> Result<Vec<VkAudio>> {
    self.pages("audio.get", &[("owner_id", uid.into())], max).await
  }

  /// Плейлисты аккаунта (свои и добавленные).
  pub async fn playlists(&self, uid: &str) -> Result<Vec<ServicePlaylist>> {
    let v = self.call("audio.getPlaylists", &[("owner_id", uid.into()), ("count", "100".into())]).await?;
    Ok(items(&v).iter().filter_map(playlist_from_json).collect())
  }

  /// Плейлист или альбом по `owner_id_id[_access_key]`: шапка и треки (до `max`).
  pub async fn playlist(&self, id: &str, max: usize) -> Result<(Value, Vec<VkAudio>)> {
    let p = PlaylistId::parse(id).ok_or_else(|| anyhow!("плохой ref плейлиста VK {id}"))?;
    let mut params = vec![("owner_id", p.owner.clone()), ("playlist_id", p.id.clone())];
    if let Some(k) = &p.key {
      params.push(("access_key", k.clone()));
    }
    let head = self.call("audio.getPlaylistById", &params).await?;
    let mut list = vec![("owner_id", p.owner), ("album_id", p.id)];
    if let Some(k) = p.key {
      list.push(("access_key", k));
    }
    let tracks = self.pages("audio.get", &list, max).await?;
    Ok((head, tracks))
  }

  pub async fn artist(&self, id: &str) -> Result<Artist> {
    let v = self.call("audio.getArtistById", &[("artist_id", id.into())]).await?;
    artist_from_json(&v).ok_or_else(|| anyhow!("VK Музыка: исполнитель не найден"))
  }

  /// Треки исполнителя (до `max`) в порядке популярности VK.
  pub async fn artist_tracks(&self, id: &str, max: usize) -> Result<Vec<VkAudio>> {
    self.pages("audio.getAudiosByArtist", &[("artist_id", id.into())], max).await
  }

  pub async fn artist_albums(&self, id: &str, limit: u32) -> Result<Vec<Album>> {
    let v = self.call("audio.getAlbumsByArtist", &[("artist_id", id.into()), ("count", limit.min(100).to_string())]).await?;
    Ok(items(&v).iter().filter_map(album_from_json).collect())
  }

  /// Похожие на трек `owner_id_id` — рекомендации VK от него.
  pub async fn similar(&self, id: &str, limit: u32) -> Result<Vec<VkAudio>> {
    let v = self.call("audio.getRecommendations", &[("target_audio", id.into()), ("count", limit.min(100).to_string())]).await?;
    Ok(audios(&v["items"]))
  }

  /// Метод со страницами `count`/`offset`: до `max` треков.
  async fn pages(&self, method: &str, params: &[(&str, String)], max: usize) -> Result<Vec<VkAudio>> {
    let mut out = Vec::new();
    let mut offset = 0;
    while out.len() < max {
      let asked = PAGE.min(max - out.len());
      let mut p = params.to_vec();
      p.push(("count", asked.to_string()));
      p.push(("offset", offset.to_string()));
      let v = self.call(method, &p).await?;
      let raw = items(&v);
      offset += raw.len();
      out.extend(audios(&Value::Array(raw.clone())));
      let total = v["count"].as_u64().map(|c| c as usize);
      if last_page(raw.len(), asked, offset, total) {
        break;
      }
    }
    out.truncate(max);
    Ok(out)
  }
}

/// Страниц больше нет: пустая страница; есть `count` — дошли до него; нет `count` (так бывает у
/// `audio.getAudiosByArtist`) — VK отдал меньше, чем просили.
fn last_page(got: usize, asked: usize, offset: usize, total: Option<usize>) -> bool {
  got == 0 || total.map_or(got < asked, |t| offset >= t)
}

/// `items` ответа-списка (или сам ответ, если это массив).
fn items(v: &Value) -> Vec<Value> {
  v["items"].as_array().or(v.as_array()).cloned().unwrap_or_default()
}

fn audios(v: &Value) -> Vec<VkAudio> {
  v.as_array().map(|a| a.iter().filter_map(audio_from_json).collect()).unwrap_or_default()
}

fn str_of(v: &Value) -> Option<String> {
  match v {
    Value::String(s) if !s.is_empty() => Some(s.clone()),
    Value::Number(n) => Some(n.to_string()),
    _ => None,
  }
}

/// Самая крупная обложка из `thumb` / `photo` (`photo_1200` → `photo_68`).
fn cover(thumb: &Value) -> Option<String> {
  ["photo_600", "photo_1200", "photo_300", "photo_270", "photo_135", "photo_68"]
    .iter()
    .find_map(|k| thumb[*k].as_str().filter(|s| !s.is_empty()).map(str::to_owned))
}

/// Картинка исполнителя: самый широкий кадр из `photo: [{url, width}]`.
fn widest(photos: &Value) -> Option<String> {
  photos
    .as_array()?
    .iter()
    .max_by_key(|p| p["width"].as_u64().unwrap_or(0))
    .and_then(|p| p["url"].as_str())
    .map(str::to_owned)
}

/// Жанр VK (`genre_id`) → тег для режимов волны.
fn genre(id: u64) -> Option<&'static str> {
  Some(match id {
    1 => "rock",
    2 => "pop",
    3 => "rap hip-hop",
    4 => "easy listening",
    5 => "house dance",
    6 => "instrumental",
    7 => "metal",
    8 => "dubstep",
    10 => "drum and bass",
    11 => "trance",
    12 => "chanson",
    13 => "ethnic",
    14 => "acoustic",
    15 => "reggae",
    16 => "classical",
    17 => "indie pop",
    21 => "alternative",
    22 => "electropop disco",
    1001 => "jazz blues",
    _ => return None,
  })
}

fn artist_refs(j: &Value) -> Vec<ArtistRef> {
  ["main_artists", "featured_artists"]
    .iter()
    .flat_map(|k| j[*k].as_array().cloned().unwrap_or_default())
    .filter_map(|a| {
      Some(ArtistRef { ref_: format!("vka:{}", str_of(&a["id"])?), name: a["name"].as_str()?.to_owned(), avatar_url: None })
    })
    .collect()
}

/// `owner_id`, `id`, `access_key` → `owner_id_id[_access_key]` (как ссылки vk.com/music/…).
fn full_id(owner: &Value, id: &Value, key: &Value) -> Option<String> {
  let (owner, id) = (owner.as_i64()?, id.as_i64()?);
  Some(match key.as_str().filter(|k| !k.is_empty()) {
    Some(k) => format!("{owner}_{id}_{k}"),
    None => format!("{owner}_{id}"),
  })
}

/// Аудиозапись VK → трек Sonar.
pub fn audio_from_json(j: &Value) -> Option<VkAudio> {
  let (owner, id) = (j["owner_id"].as_i64()?, j["id"].as_i64()?);
  let base = j["title"].as_str()?.trim();
  let title = match j["subtitle"].as_str().map(str::trim).filter(|s| !s.is_empty()) {
    Some(sub) => format!("{base} ({sub})"),
    None => base.to_owned(),
  };
  let artist = j["artist"].as_str().unwrap_or("").trim().to_owned();
  let album = &j["album"];
  let album_ref = full_id(&album["owner_id"], &album["id"], &album["access_key"])
    .map(|id| AlbumRef { ref_: format!("vkalb:{id}"), title: album["title"].as_str().unwrap_or("").to_owned() });
  let restricted = j["content_restricted"].as_u64().unwrap_or(0) != 0;
  let track = Track {
    ref_: format!("vk:{owner}_{id}"),
    title,
    artist,
    artists: artist_refs(j),
    album: album_ref,
    duration_ms: j["duration"].as_u64().unwrap_or(0) * 1000,
    cover_url: cover(&album["thumb"]),
    url: Some(format!("https://vk.com/audio{owner}_{id}")),
    explicit: j["is_explicit"].as_bool().unwrap_or(false),
    available: !restricted,
    plays: None,
    tags: j["genre_id"].as_u64().and_then(genre).map(str::to_owned),
  };
  Some(VkAudio {
    track,
    access_key: j["access_key"].as_str().filter(|k| !k.is_empty()).map(str::to_owned),
    stream_url: j["url"].as_str().filter(|u| !u.is_empty()).map(str::to_owned),
  })
}

/// Ссылка из ответа VK → откуда играть. Пустая или заглушка «audio_api_unavailable» — ошибка.
pub fn source_from_url(url: &str) -> Result<Source> {
  let u = url::Url::parse(url).map_err(|_| anyhow!(NO_STREAM))?;
  if u.path().contains("audio_api_unavailable") {
    return Err(anyhow!(NO_STREAM));
  }
  let quality = "MP3 320".to_owned();
  if u.path().ends_with(".m3u8") {
    Ok(Source::Hls { url: url.to_owned(), quality })
  } else {
    Ok(Source::File { url: url.to_owned(), quality })
  }
}

pub fn account_from_json(u: &Value) -> Option<Account> {
  let id = u["id"].as_i64()?;
  let name = [u["first_name"].as_str(), u["last_name"].as_str()].into_iter().flatten().collect::<Vec<_>>().join(" ");
  Some(Account {
    name: Some(name).filter(|n| !n.trim().is_empty()),
    avatar_url: u["photo_200"].as_str().map(str::to_owned),
    uid: Some(id.to_string()),
    premium: None,
  })
}

pub fn artist_from_json(a: &Value) -> Option<Artist> {
  let id = str_of(&a["id"])?;
  Some(Artist {
    url: a["domain"].as_str().map(|d| format!("https://vk.com/artist/{d}")),
    ref_: format!("vka:{id}"),
    name: a["name"].as_str()?.to_owned(),
    avatar_url: widest(&a["photo"]),
    followers: None,
  })
}

/// Обложка плейлиста: своя `photo` или первая из `thumbs` (коллаж из обложек альбомов).
fn playlist_cover(p: &Value) -> Option<String> {
  cover(&p["photo"]).or_else(|| p["thumbs"].as_array().and_then(|t| t.first()).and_then(cover))
}

/// id плейлиста для запросов: добавленный к себе чужой плейлист ведёт на оригинал.
fn playlist_full_id(p: &Value) -> Option<String> {
  let o = &p["original"];
  full_id(&o["owner_id"], &o["playlist_id"], &o["access_key"]).or_else(|| full_id(&p["owner_id"], &p["id"], &p["access_key"]))
}

pub fn album_from_json(p: &Value) -> Option<Album> {
  let id = playlist_full_id(p)?;
  let artists = artist_refs(p);
  let artist = artists.iter().map(|a| a.name.as_str()).collect::<Vec<_>>().join(", ");
  Some(Album {
    url: Some(format!("https://vk.com/music/album/{id}")),
    ref_: format!("vkalb:{id}"),
    title: p["title"].as_str()?.to_owned(),
    artist,
    artists,
    cover_url: playlist_cover(p),
    year: p["year"].as_u64().map(|y| y as u32),
    released: None,
    track_count: p["count"].as_u64().unwrap_or(0) as u32,
  })
}

pub fn playlist_from_json(p: &Value) -> Option<ServicePlaylist> {
  let id = playlist_full_id(p)?;
  let owner = artist_refs(p).into_iter().map(|a| a.name).collect::<Vec<_>>().join(", ");
  Some(ServicePlaylist {
    ref_: format!("vkpl:{id}"),
    title: p["title"].as_str()?.to_owned(),
    owner,
    cover_url: playlist_cover(p),
    track_count: p["count"].as_u64().unwrap_or(0) as u32,
  })
}

/// Разобранный `owner_id_id[_access_key]` (owner бывает отрицательным: `-2000123_456_abc`).
#[derive(Debug, PartialEq)]
pub struct PlaylistId {
  pub owner: String,
  pub id: String,
  pub key: Option<String>,
}

impl PlaylistId {
  pub fn parse(s: &str) -> Option<Self> {
    let mut it = s.splitn(3, '_');
    let owner = it.next()?.parse::<i64>().ok()?.to_string();
    let id = it.next()?.parse::<i64>().ok()?.to_string();
    let key = it.next().filter(|k| !k.is_empty() && k.chars().all(|c| c.is_ascii_alphanumeric())).map(str::to_owned);
    Some(Self { owner, id, key })
  }
}

/// id трека `owner_id_id` (часть ref после `vk:`) — проверка формы.
pub fn is_audio_id(s: &str) -> bool {
  PlaylistId::parse(s).is_some_and(|p| p.key.is_none() && s.matches('_').count() == 1)
}

#[cfg(test)]
mod tests {
  use super::*;
  use serde_json::json;

  fn audio_json() -> Value {
    json!({
      "artist": "Земфира",
      "id": 456239017,
      "owner_id": -2001234567,
      "title": "Хочешь?",
      "subtitle": "Live",
      "duration": 214,
      "access_key": "a1b2c3",
      "url": "https://cs1-2v4.vkuseraudio.net/s/v1/ac/abc/index.m3u8?siren=1",
      "is_explicit": true,
      "genre_id": 2,
      "album": {
        "id": 77, "title": "Прости меня моя любовь", "owner_id": -2000111, "access_key": "k9",
        "thumb": { "photo_300": "https://sun9-1.userapi.com/a300.jpg", "photo_600": "https://sun9-1.userapi.com/a600.jpg" }
      },
      "main_artists": [{ "name": "Земфира", "domain": "zemfira", "id": "123456789" }],
      "featured_artists": [{ "name": "Гость", "id": "42" }]
    })
  }

  /// Ответ без `count` не обрывает страницы на первой: идём дальше, пока страница полная.
  #[test]
  fn pages_without_count() {
    assert!(!last_page(200, 200, 200, None));
    assert!(last_page(37, 200, 237, None));
    assert!(last_page(0, 200, 400, None));
    // с count — по нему, даже если страница короче
    assert!(!last_page(150, 200, 150, Some(500)));
    assert!(last_page(200, 200, 500, Some(500)));
    assert!(last_page(0, 200, 0, Some(10)));
  }

  #[test]
  fn audio_fields() {
    let a = audio_from_json(&audio_json()).unwrap();
    let t = &a.track;
    assert_eq!(t.ref_, "vk:-2001234567_456239017");
    assert_eq!(t.title, "Хочешь? (Live)");
    assert_eq!(t.artist, "Земфира");
    assert_eq!(t.artists.iter().map(|r| r.ref_.as_str()).collect::<Vec<_>>(), ["vka:123456789", "vka:42"]);
    assert_eq!(t.album.as_ref().unwrap().ref_, "vkalb:-2000111_77_k9");
    assert_eq!(t.duration_ms, 214_000);
    assert_eq!(t.cover_url.as_deref(), Some("https://sun9-1.userapi.com/a600.jpg"));
    assert_eq!(t.url.as_deref(), Some("https://vk.com/audio-2001234567_456239017"));
    assert!(t.explicit && t.available);
    assert_eq!(t.tags.as_deref(), Some("pop"));
    assert_eq!(a.access_key.as_deref(), Some("a1b2c3"));
    assert!(a.stream_url.as_deref().unwrap().ends_with("index.m3u8?siren=1"));
  }

  #[test]
  fn audio_minimal_and_restricted() {
    let a = audio_from_json(&json!({"id": 1, "owner_id": 5, "title": "x", "url": "", "content_restricted": 1})).unwrap();
    assert_eq!(a.track.ref_, "vk:5_1");
    assert_eq!((a.track.album.clone(), a.track.cover_url.clone(), a.stream_url.clone(), a.access_key.clone()), (None, None, None, None));
    assert!(!a.track.available);
    assert!(a.track.artists.is_empty());
    assert!(audio_from_json(&json!({"id": 1, "title": "без владельца"})).is_none());
  }

  #[test]
  fn list_responses() {
    let v = json!({"count": 2, "items": [audio_json(), {"bad": 1}, audio_json()]});
    assert_eq!(audios(&v["items"]).len(), 2);
    // audio.getById отдаёт массив без items
    assert_eq!(audios(&json!([audio_json()])).len(), 1);
    assert_eq!(items(&json!([1, 2])).len(), 2);
    assert!(items(&json!({"count": 0})).is_empty());
  }

  #[test]
  fn stream_sources() {
    let hls = source_from_url("https://cs1.vkuseraudio.net/s/v1/ac/x/index.m3u8?siren=1").unwrap();
    assert!(matches!(hls, Source::Hls { .. }));
    let mp3 = source_from_url("https://cs1.vkuseraudio.net/s/v1/acmp3/x.mp3?extra=1").unwrap();
    assert!(matches!(mp3, Source::File { .. }));
    for bad in ["", "https://vk.com/mp3/audio_api_unavailable.mp3", "not a url"] {
      assert_eq!(source_from_url(bad).unwrap_err().to_string(), NO_STREAM, "{bad}");
    }
  }

  #[test]
  fn api_errors_are_friendly() {
    let e = |code: i64| {
      let v = json!({"error": {"error_code": code, "error_msg": "User authorization failed: access_token vk1.a.SECRET", "request_params": []}});
      api_error(&v).unwrap().to_string()
    };
    for code in [5, 15, 25, 201, 1117] {
      assert_eq!(e(code), AUTH_EXPIRED);
    }
    assert_eq!(e(6), TOO_MANY);
    assert_eq!(e(14), CAPTCHA);
    assert_eq!(e(100), FAILED);
    assert!(!e(5).contains("SECRET"));
    assert!(api_error(&json!({"response": []})).is_none());
  }

  #[test]
  fn account_fields() {
    let a = account_from_json(&json!({"id": 1, "first_name": "Иван", "last_name": "Петров", "photo_200": "https://sun9-2.userapi.com/p.jpg"})).unwrap();
    assert_eq!((a.name.as_deref(), a.uid.as_deref(), a.premium), (Some("Иван Петров"), Some("1"), None));
    assert_eq!(a.avatar_url.as_deref(), Some("https://sun9-2.userapi.com/p.jpg"));
    assert_eq!(account_from_json(&json!({"id": 2})).unwrap().name, None);
    assert!(account_from_json(&json!({})).is_none());
  }

  fn playlist_json() -> Value {
    json!({
      "id": 15, "owner_id": 1, "type": 0, "title": "Дорога", "count": 31, "access_key": "ff00",
      "thumbs": [{ "photo_300": "https://sun9-3.userapi.com/t300.jpg" }]
    })
  }

  #[test]
  fn playlists_and_albums() {
    let p = playlist_from_json(&playlist_json()).unwrap();
    assert_eq!((p.ref_.as_str(), p.title.as_str(), p.track_count), ("vkpl:1_15_ff00", "Дорога", 31));
    assert_eq!(p.cover_url.as_deref(), Some("https://sun9-3.userapi.com/t300.jpg"));
    // добавленный к себе чужой — по оригиналу
    let mut followed = playlist_json();
    followed["original"] = json!({"owner_id": -2000, "playlist_id": 9, "access_key": "zz"});
    assert_eq!(playlist_from_json(&followed).unwrap().ref_, "vkpl:-2000_9_zz");
    let album = json!({
      "id": 5, "owner_id": -2000222, "type": 1, "title": "Альбом", "count": 10, "year": 2004,
      "photo": { "photo_600": "https://sun9-4.userapi.com/c600.jpg" },
      "main_artists": [{ "name": "Земфира", "id": "123" }]
    });
    let a = album_from_json(&album).unwrap();
    assert_eq!((a.ref_.as_str(), a.artist.as_str(), a.year, a.track_count), ("vkalb:-2000222_5", "Земфира", Some(2004), 10));
    assert_eq!(a.url.as_deref(), Some("https://vk.com/music/album/-2000222_5"));
    assert_eq!(a.cover_url.as_deref(), Some("https://sun9-4.userapi.com/c600.jpg"));
  }

  #[test]
  fn artist_fields() {
    let a = artist_from_json(&json!({
      "id": "123", "name": "Земфира", "domain": "zemfira",
      "photo": [{"url": "https://sun9-5.userapi.com/s.jpg", "width": 100}, {"url": "https://sun9-5.userapi.com/l.jpg", "width": 1200}]
    }))
    .unwrap();
    assert_eq!((a.ref_.as_str(), a.name.as_str()), ("vka:123", "Земфира"));
    assert_eq!(a.avatar_url.as_deref(), Some("https://sun9-5.userapi.com/l.jpg"));
    assert_eq!(a.url.as_deref(), Some("https://vk.com/artist/zemfira"));
    assert!(artist_from_json(&json!({"name": "без id"})).is_none());
  }

  #[test]
  fn playlist_ids() {
    assert_eq!(PlaylistId::parse("-2000_9_ab12"), Some(PlaylistId { owner: "-2000".into(), id: "9".into(), key: Some("ab12".into()) }));
    assert_eq!(PlaylistId::parse("1_15").unwrap().key, None);
    assert!(PlaylistId::parse("x_1").is_none());
    assert!(PlaylistId::parse("1").is_none());
    assert_eq!(PlaylistId::parse("1_2_a&b").unwrap().key, None, "в ключе только буквы и цифры");
    assert!(is_audio_id("-1_2") && is_audio_id("5_1"));
    assert!(!is_audio_id("5_1_key") && !is_audio_id("likes") && !is_audio_id("5"));
  }

  #[test]
  fn throttle_spaces_calls() {
    let now = Instant::now();
    let mut next = None;
    assert_eq!(take_slot(&mut next, now), Duration::ZERO);
    assert_eq!(take_slot(&mut next, now), GAP);
    assert_eq!(take_slot(&mut next, now), GAP * 2);
    // после паузы ждать не нужно
    assert_eq!(take_slot(&mut next, now + GAP * 10), Duration::ZERO);
  }

  /// Живая проверка: `VK_TOKEN=vk1.a.… cargo test vk_live -- --ignored --nocapture`.
  #[tokio::test]
  #[ignore]
  async fn vk_live_search_and_stream() {
    let token = std::env::var("VK_TOKEN").expect("нужен VK_TOKEN");
    let http = reqwest::Client::new();
    let creds = Creds { token };
    let vk = Vk { http: &http, creds: &creds };
    let me = vk.account().await.expect("account");
    println!("аккаунт: {:?}", me.name);
    let found = vk.search("Земфира", 5).await.expect("search");
    assert!(!found.is_empty(), "поиск пуст");
    let first = &found[0];
    println!("первый: {} — {}", first.track.artist, first.track.title);
    let url = first.stream_url.clone().expect("VK не отдал ссылку");
    println!("поток: {:?}", source_from_url(&url).map(|s| matches!(s, Source::Hls { .. })));
    let id = first.track.ref_.trim_start_matches("vk:");
    let similar = vk.similar(id, 5).await.expect("similar");
    println!("похожих: {}", similar.len());
  }
}
