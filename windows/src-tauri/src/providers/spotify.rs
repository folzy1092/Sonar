//! Spotify: ключ `sp_dc` (cookie open.spotify.com) → токен веб-плеера → Web API (поиск, лайки,
//! плейлисты, исполнитель, альбом). Рекомендаций не берём (их эндпоинты закрыты и не нужны волне).
//! Поток Spotify отдаёт только Premium через librespot (фича `spotify-playback`, docs/API.md
//! «Spotify»); без неё трек Spotify — «нужен резервный сервис» (резерв — этап 4).
//!
//! Токен: `GET open.spotify.com/api/token` с `totp`/`totpVer`. TOTP — HMAC-SHA1 от «шифра»
//! веб-плеера. Шифр Spotify меняет: свежий лежит в репо (`updates/spotify-totp.json`), Sonar читает
//! его при первом токене после запуска и при отказе «ключ устарел» (`TotpStore`), вшитый —
//! запасной. `sp_dc` не попадает ни в ошибки, ни в лог.

use super::{http_error, Account, Album, AlbumRef, Artist, ArtistRef, ServicePlaylist, Track, UA};
use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::Mutex;

const API: &str = "https://api.spotify.com/v1";
const TOKEN_URL: &str = "https://open.spotify.com/api/token";
/// Сколько треков отдаёт одна страница Web API.
const PAGE: usize = 50;
/// Предел страниц треков одного альбома (по `PAGE`): `next`, указывающий на себя, не крутит вечно.
const ALBUM_MAX_PAGES: usize = 40;
/// Токен обновляем за минуту до конца.
const TOKEN_MARGIN_MS: u64 = 60_000;
/// Шаг TOTP веб-плеера, секунд.
const TOTP_STEP: u64 = 30;

/// Трек Spotify без Premium (и всегда на iPhone) сам не играет — нужен резервный сервис (этап 4).
pub const NEEDS_FALLBACK: &str = "Spotify: нужен резервный сервис";
/// Шифр TOTP веб-плеера сменился, а свежего в репо ещё нет — Sonar перечитает его сам.
pub const TOTP_STALE: &str = "Spotify сменил защиту — Sonar подтянет новый ключ сам, попробуй через минуту";
/// Свежий шифр (docs/POLISH_PROMPT.md п. 3) — файл в репо, как `ios-update.json`.
const TOTP_REMOTE: &str = "https://raw.githubusercontent.com/folzy1092/Sonar/main/updates/spotify-totp.json";
/// Перечитывать файл шифра не чаще раза в минуту.
const TOTP_RECHECK: std::time::Duration = std::time::Duration::from_secs(60);
/// Байтов в шифре — с запасом: у Spotify их 17–32.
const TOTP_MAX_LEN: usize = 128;
/// Токен выдан анонимно: cookie `sp_dc` протух или чужой.
pub const SP_DC_BAD: &str = "Spotify: ключ sp_dc не подошёл — войди заново";
pub const NOT_CONNECTED: &str = "Spotify не подключён — открой Настройки → Сервисы";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Creds {
  pub sp_dc: String,
}

/// Шифр TOTP веб-плеера: версия (`totpVer`) и байты — формат `updates/spotify-totp.json`.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct TotpSecret {
  pub version: u32,
  pub cipher: Vec<u8>,
}

/// Вшитый запасной шифр: версия 61, проверена 2026-11-19 (v5 Spotify отвергает: `totpVerExpired`).
/// Сменится — сначала `updates/spotify-totp.json` (доходит без обновления), потом здесь.
pub fn default_totp() -> TotpSecret {
  TotpSecret {
    version: 61,
    cipher: vec![44, 55, 47, 42, 70, 40, 34, 114, 76, 74, 50, 111, 120, 97, 75, 76, 94, 102, 43, 69, 49, 120, 118, 80, 64, 78],
  }
}

/// Файл шифра из репо → шифр, если он годный и новее `current`. Чужое и битое — мимо.
pub fn parse_remote_totp(body: &str, current: u32) -> Option<TotpSecret> {
  let s: TotpSecret = serde_json::from_str(body).ok()?;
  let ok = s.version > current && !s.cipher.is_empty() && s.cipher.len() <= TOTP_MAX_LEN;
  ok.then_some(s)
}

/// Шифр ядра: вшитый, пока файл из репо не дал версию новее.
pub struct TotpStore {
  current: std::sync::RwLock<TotpSecret>,
  /// Когда последний раз читали файл; `None` — ещё ни разу после запуска.
  checked: Mutex<Option<std::time::Instant>>,
}

impl Default for TotpStore {
  fn default() -> Self {
    Self::new(default_totp())
  }
}

impl TotpStore {
  pub fn new(secret: TotpSecret) -> Self {
    Self { current: std::sync::RwLock::new(secret), checked: Mutex::new(None) }
  }

  pub fn current(&self) -> TotpSecret {
    self.current.read().unwrap_or_else(|e| e.into_inner()).clone()
  }

  fn adopt(&self, body: &str) -> bool {
    let mut cur = self.current.write().unwrap_or_else(|e| e.into_inner());
    let Some(fresh) = parse_remote_totp(body, cur.version) else { return false };
    crate::crashlog::write("info", &format!("Spotify: шифр веб-плеера из репо — версия {} (была {})", fresh.version, cur.version));
    *cur = fresh;
    true
  }

  /// Перечитать файл шифра (не чаще `TOTP_RECHECK`, а `force=false` — только первый раз после
  /// запуска). `true` — шифр сменился, токен стоит запросить снова.
  pub async fn refresh(&self, http: &reqwest::Client, force: bool) -> bool {
    let mut checked = self.checked.lock().await;
    let due = match *checked {
      None => true,
      Some(at) => force && at.elapsed() >= TOTP_RECHECK,
    };
    if !due {
      return false;
    }
    *checked = Some(std::time::Instant::now());
    let body = match http.get(TOTP_REMOTE).header("User-Agent", UA).send().await {
      Ok(r) if r.status().is_success() => r.text().await.unwrap_or_default(),
      Ok(r) => {
        crate::crashlog::write("warn", &format!("Spotify: файл шифра недоступен (HTTP {})", r.status().as_u16()));
        return false;
      }
      Err(_) => {
        crate::crashlog::write("warn", "Spotify: файл шифра недоступен (сеть)");
        return false;
      }
    };
    self.adopt(&body)
  }
}

/// Ключ HMAC из шифра: каждый байт XOR ((i % 33) + 9), числа подряд десятичной строкой.
pub fn totp_key(cipher: &[u8]) -> Vec<u8> {
  cipher.iter().enumerate().map(|(i, b)| (b ^ ((i % 33) as u8 + 9)).to_string()).collect::<String>().into_bytes()
}

fn hmac_sha1(key: &[u8], msg: &[u8]) -> [u8; 20] {
  use sha1::{Digest, Sha1};
  let mut k = [0u8; 64];
  if key.len() > 64 {
    k[..20].copy_from_slice(&Sha1::digest(key));
  } else {
    k[..key.len()].copy_from_slice(key);
  }
  let (ipad, opad): (Vec<u8>, Vec<u8>) = k.iter().map(|b| (b ^ 0x36, b ^ 0x5c)).unzip();
  let inner = Sha1::new().chain_update(&ipad).chain_update(msg).finalize();
  Sha1::new().chain_update(&opad).chain_update(inner).finalize().into()
}

/// HOTP (RFC 4226), 6 цифр.
pub fn hotp(key: &[u8], counter: u64) -> String {
  let h = hmac_sha1(key, &counter.to_be_bytes());
  let o = (h[19] & 0x0f) as usize;
  let v = u32::from_be_bytes([h[o] & 0x7f, h[o + 1], h[o + 2], h[o + 3]]) % 1_000_000;
  format!("{v:06}")
}

/// TOTP (RFC 6238) на момент `unix_secs`, шаг 30 с.
pub fn totp(key: &[u8], unix_secs: u64) -> String {
  hotp(key, unix_secs / TOTP_STEP)
}

/// `sp_dc` как его вставили: голое значение, `sp_dc=…`, `sp_dc=…;` или вся строка Cookie.
pub fn normalize_sp_dc(raw: &str) -> Option<String> {
  let raw = raw.trim();
  let value = raw
    .split(';')
    .map(str::trim)
    .find_map(|part| part.strip_prefix("sp_dc="))
    .unwrap_or_else(|| raw.trim_end_matches(';'))
    .trim()
    .trim_matches('"');
  let ok = value.len() >= 20 && value.chars().all(|c| c.is_ascii_alphanumeric() || "-_".contains(c));
  ok.then(|| value.to_owned())
}

/// Токен веб-плеера и когда он кончается.
#[derive(Debug, Clone, PartialEq)]
pub struct WebToken {
  pub access_token: String,
  pub expires_at_ms: u64,
}

impl WebToken {
  pub fn fresh_at(&self, now_ms: u64) -> bool {
    now_ms + TOKEN_MARGIN_MS < self.expires_at_ms
  }
}

fn now_ms() -> u64 {
  SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0)
}

/// Запрос токена: адрес с TOTP на момент `unix_secs`.
pub fn token_query(secret: &TotpSecret, unix_secs: u64) -> Vec<(&'static str, String)> {
  let code = totp(&totp_key(&secret.cipher), unix_secs);
  vec![
    ("reason", "init".into()),
    ("productType", "web-player".into()),
    ("totp", code.clone()),
    ("totpServer", code),
    ("totpVer", secret.version.to_string()),
  ]
}

/// Ответ `api/token` → токен или понятная ошибка (без `sp_dc` в тексте).
pub fn parse_token(status: u16, body: &str) -> Result<WebToken> {
  // «totp» ищем только в ответе с ошибкой: в удачном случайный accessToken может его содержать
  let failed = !(200..300).contains(&status);
  let stale = status == 400 || (failed && body.to_ascii_lowercase().contains("totp"));
  if stale {
    bail!(TOTP_STALE);
  }
  if failed {
    return Err(http_error("Spotify", reqwest::StatusCode::from_u16(status).unwrap_or(reqwest::StatusCode::BAD_GATEWAY)));
  }
  let v: Value = serde_json::from_str(body).map_err(|_| anyhow!("Spotify: непонятный ответ веб-плеера"))?;
  let token = v["accessToken"].as_str().filter(|t| !t.is_empty());
  match token {
    Some(t) if v["isAnonymous"].as_bool() != Some(true) => Ok(WebToken {
      access_token: t.to_owned(),
      expires_at_ms: v["accessTokenExpirationTimestampMs"].as_u64().unwrap_or_else(|| now_ms() + 30 * 60_000),
    }),
    _ => bail!(SP_DC_BAD),
  }
}

async fn fetch_token(http: &reqwest::Client, creds: &Creds, secret: &TotpSecret) -> Result<WebToken> {
  let r = http
    .get(TOKEN_URL)
    .query(&token_query(secret, now_ms() / 1000))
    .header("Cookie", format!("sp_dc={}", creds.sp_dc))
    .header("User-Agent", UA)
    .header("Accept", "application/json")
    .send()
    .await
    .map_err(|_| anyhow!("Spotify: open.spotify.com недоступен"))?;
  let status = r.status().as_u16();
  let body = r.text().await.unwrap_or_default();
  parse_token(status, &body)
}

/// Полный адрес Web API: путь от `API` или готовая ссылка (`next`), но только на api.spotify.com —
/// токен веб-плеера не уходит на чужие адреса из ответа.
pub fn api_url(path: &str) -> Option<String> {
  if path.starts_with('/') {
    return Some(format!("{API}{path}"));
  }
  path.starts_with(&format!("{API}/")).then(|| path.to_owned())
}

/// Ссылка на следующую страницу (`next`), если она ведёт в Web API.
fn next_url(page: &Value) -> Option<String> {
  page["next"].as_str().and_then(api_url)
}

// --- разбор JSON Web API ---

/// Самая крупная картинка (Spotify отдаёт по убыванию, но не обещает).
pub fn best_image(images: &Value) -> Option<String> {
  images
    .as_array()?
    .iter()
    .filter_map(|i| Some((i["width"].as_u64().unwrap_or(0), i["url"].as_str()?)))
    .max_by_key(|(w, _)| *w)
    .map(|(_, u)| u.to_owned())
}

fn spotify_url(v: &Value) -> Option<String> {
  v["external_urls"]["spotify"].as_str().map(str::to_owned)
}

fn artist_refs(v: &Value) -> Vec<ArtistRef> {
  v["artists"]
    .as_array()
    .map(|a| {
      a.iter()
        .filter_map(|x| Some(ArtistRef { ref_: format!("spa:{}", x["id"].as_str()?), name: x["name"].as_str()?.to_owned(), avatar_url: None }))
        .collect()
    })
    .unwrap_or_default()
}

fn joined(artists: &[ArtistRef]) -> String {
  artists.iter().map(|a| a.name.as_str()).collect::<Vec<_>>().join(", ")
}

/// Год из `release_date` («2021», «2021-03», «2021-03-05»).
fn year_of(date: Option<&str>) -> Option<u32> {
  date?.get(..4)?.parse().ok()
}

/// Трек; `album` — альбом снаружи (у треков альбома своего `album` нет). Локальные файлы
/// пользователя в плейлистах (`is_local`, без id) пропускаются.
pub fn track_from(v: &Value, album: Option<&Value>) -> Option<Track> {
  if v["is_local"].as_bool() == Some(true) || v["type"].as_str().is_some_and(|t| t != "track") {
    return None;
  }
  let id = v["id"].as_str()?;
  let alb = album.unwrap_or(&v["album"]);
  let artists = artist_refs(v);
  Some(Track {
    ref_: format!("sp:{id}"),
    title: v["name"].as_str()?.to_owned(),
    artist: joined(&artists),
    artists,
    album: alb["id"].as_str().map(|a| AlbumRef { ref_: format!("spalb:{a}"), title: alb["name"].as_str().unwrap_or("").to_owned() }),
    duration_ms: v["duration_ms"].as_u64().unwrap_or(0),
    cover_url: best_image(&alb["images"]),
    url: spotify_url(v),
    explicit: v["explicit"].as_bool().unwrap_or(false),
    // играет через резервный сервис — для очереди трек доступен
    available: true,
    plays: None,
    tags: None,
  })
}

pub fn album_from(v: &Value) -> Option<Album> {
  let artists = artist_refs(v);
  let date = v["release_date"].as_str();
  let full_date = date.filter(|d| d.len() == 10).map(str::to_owned);
  Some(Album {
    ref_: format!("spalb:{}", v["id"].as_str()?),
    title: v["name"].as_str()?.to_owned(),
    artist: joined(&artists),
    artists,
    cover_url: best_image(&v["images"]),
    year: year_of(date),
    released: full_date,
    track_count: v["total_tracks"].as_u64().unwrap_or(0) as u32,
    url: spotify_url(v),
  })
}

pub fn artist_from(v: &Value) -> Option<Artist> {
  Some(Artist {
    ref_: format!("spa:{}", v["id"].as_str()?),
    name: v["name"].as_str()?.to_owned(),
    avatar_url: best_image(&v["images"]),
    followers: v["followers"]["total"].as_u64(),
    url: spotify_url(v),
  })
}

/// Плейлист; число треков — в `tracks.total` (старый ответ) или `items.total` (новый).
pub fn playlist_from(v: &Value) -> Option<ServicePlaylist> {
  let total = v["tracks"]["total"].as_u64().or(v["items"]["total"].as_u64()).unwrap_or(0);
  Some(ServicePlaylist {
    ref_: format!("sppl:{}", v["id"].as_str()?),
    title: v["name"].as_str()?.to_owned(),
    owner: v["owner"]["display_name"].as_str().or(v["owner"]["id"].as_str()).unwrap_or("").to_owned(),
    cover_url: best_image(&v["images"]),
    track_count: total as u32,
  })
}

/// `GET /me`: имя, аватар, id и Premium (`product == "premium"`).
pub fn account_from(v: &Value) -> Account {
  Account {
    name: v["display_name"].as_str().or(v["id"].as_str()).map(str::to_owned),
    avatar_url: best_image(&v["images"]),
    uid: v["id"].as_str().map(str::to_owned),
    premium: v["product"].as_str().map(|p| p == "premium"),
  }
}

/// Строка плейлиста или «Любимых»: трек лежит в `track` (старый ответ) или `item` (новый).
pub fn item_track(row: &Value) -> Option<Track> {
  let t = if row["track"].is_object() { &row["track"] } else { &row["item"] };
  track_from(t, None)
}

fn list<T>(v: &Value, f: impl Fn(&Value) -> Option<T>) -> Vec<T> {
  v.as_array().map(|a| a.iter().filter_map(&f).collect()).unwrap_or_default()
}

/// Клиент Web API. Токен общий на ядро (`cache`), 401 — один повтор со свежим токеном.
pub struct Spotify<'a> {
  pub http: &'a reqwest::Client,
  pub creds: &'a Creds,
  pub secret: &'a TotpStore,
  pub cache: &'a Mutex<Option<WebToken>>,
}

impl Spotify<'_> {
  pub async fn token(&self, renew: bool) -> Result<String> {
    let mut cache = self.cache.lock().await;
    if !renew {
      if let Some(t) = cache.as_ref().filter(|t| t.fresh_at(now_ms())) {
        return Ok(t.access_token.clone());
      }
    }
    let t = self.fresh_token().await?;
    let access = t.access_token.clone();
    *cache = Some(t);
    Ok(access)
  }

  /// Токен с текущим шифром; шифр устарел — перечитать файл из репо и попробовать ещё раз.
  async fn fresh_token(&self) -> Result<WebToken> {
    self.secret.refresh(self.http, false).await;
    match fetch_token(self.http, self.creds, &self.secret.current()).await {
      Err(e) if e.to_string() == TOTP_STALE && self.secret.refresh(self.http, true).await => {
        fetch_token(self.http, self.creds, &self.secret.current()).await
      }
      other => other,
    }
  }

  async fn send(&self, url: &str, query: &[(&str, String)], token: &str) -> Result<reqwest::Response> {
    Ok(self.http.get(url).query(query).bearer_auth(token).header("Accept-Language", "ru").send().await?)
  }

  async fn get(&self, path: &str, query: &[(&str, String)]) -> Result<Value> {
    let url = api_url(path).ok_or_else(|| anyhow!("Spotify: непонятный ответ веб-плеера"))?;
    let mut r = self.send(&url, query, &self.token(false).await?).await?;
    if r.status() == reqwest::StatusCode::UNAUTHORIZED {
      r = self.send(&url, query, &self.token(true).await?).await?;
    }
    if !r.status().is_success() {
      return Err(http_error("Spotify", r.status()));
    }
    Ok(r.json().await?)
  }

  /// Все страницы списка (`next`) до `max` строк.
  async fn pages(&self, path: &str, max: usize) -> Result<Vec<Value>> {
    let mut out = Vec::new();
    let mut page = self.get(path, &[("limit", PAGE.to_string())]).await?;
    loop {
      out.extend(page["items"].as_array().cloned().unwrap_or_default());
      match next_url(&page) {
        Some(n) if out.len() < max => page = self.get(&n, &[]).await?,
        _ => break,
      }
    }
    out.truncate(max);
    Ok(out)
  }

  pub async fn account(&self) -> Result<Account> {
    Ok(account_from(&self.get("/me", &[]).await?))
  }

  pub async fn search(&self, q: &str, limit: u32) -> Result<Vec<Track>> {
    let v = self.search_raw(q, "track", limit).await?;
    Ok(list(&v["tracks"]["items"], |t| track_from(t, None)))
  }

  pub async fn search_more(&self, q: &str, limit: u32) -> Result<(Vec<Artist>, Vec<Album>, Vec<ServicePlaylist>)> {
    let v = self.search_raw(q, "artist,album,playlist", limit).await?;
    Ok((list(&v["artists"]["items"], artist_from), list(&v["albums"]["items"], album_from), list(&v["playlists"]["items"], playlist_from)))
  }

  async fn search_raw(&self, q: &str, types: &str, limit: u32) -> Result<Value> {
    let query = [("q", q.to_owned()), ("type", types.to_owned()), ("limit", limit.clamp(1, PAGE as u32).to_string()), ("market", "from_token".into())];
    self.get("/search", &query).await
  }

  /// «Любимые треки» аккаунта (`me/tracks`).
  pub async fn likes(&self, max: usize) -> Result<Vec<Track>> {
    Ok(self.pages("/me/tracks", max).await?.iter().filter_map(item_track).collect())
  }

  pub async fn playlists(&self) -> Result<Vec<ServicePlaylist>> {
    Ok(self.pages("/me/playlists", 500).await?.iter().filter_map(playlist_from).collect())
  }

  pub async fn playlist(&self, id: &str, max: usize) -> Result<(ServicePlaylist, Vec<Track>)> {
    let head = self.get(&format!("/playlists/{id}"), &[]).await?;
    let mut playlist = playlist_from(&head).ok_or_else(|| anyhow!("Spotify: плейлист не найден"))?;
    let rows = self.pages(&format!("/playlists/{id}/tracks"), max).await?;
    let tracks: Vec<Track> = rows.iter().filter_map(item_track).collect();
    playlist.track_count = playlist.track_count.max(tracks.len() as u32);
    Ok((playlist, tracks))
  }

  /// Шапка, популярные (`top-tracks`) и альбомы исполнителя.
  pub async fn artist(&self, id: &str) -> Result<(Artist, Vec<Track>, Vec<Album>)> {
    let artist = artist_from(&self.get(&format!("/artists/{id}"), &[]).await?).ok_or_else(|| anyhow!("Spotify: исполнитель не найден"))?;
    let top = self.get(&format!("/artists/{id}/top-tracks"), &[("market", "from_token".into())]).await?;
    let albums = self.artist_albums(id).await?;
    Ok((artist, list(&top["tracks"], |t| track_from(t, None)), albums))
  }

  pub async fn artist_albums(&self, id: &str) -> Result<Vec<Album>> {
    let rows = self.pages(&format!("/artists/{id}/albums?include_groups=album,single"), 200).await?;
    Ok(rows.iter().filter_map(album_from).collect())
  }

  /// Треки альбомов исполнителя (до 20 альбомов одним запросом) с датой выхода — вкладка «Треки».
  pub async fn artist_tracks(&self, id: &str, max: usize) -> Result<Vec<(Track, Option<String>)>> {
    let albums = self.artist_albums(id).await?;
    let ids: Vec<&str> = albums.iter().take(20).map(|a| a.ref_.trim_start_matches("spalb:")).collect();
    if ids.is_empty() {
      return Ok(vec![]);
    }
    let v = self.get("/albums", &[("ids", ids.join(","))]).await?;
    let mut out = Vec::new();
    for alb in v["albums"].as_array().into_iter().flatten() {
      let released = alb["release_date"].as_str().map(str::to_owned);
      let tracks = alb["tracks"]["items"].as_array().into_iter().flatten();
      out.extend(tracks.filter_map(|t| track_from(t, Some(alb))).map(|t| (t, released.clone())));
    }
    out.truncate(max);
    Ok(out)
  }

  pub async fn album(&self, id: &str) -> Result<(Album, Vec<Track>)> {
    let v = self.get(&format!("/albums/{id}"), &[]).await?;
    let album = album_from(&v).ok_or_else(|| anyhow!("Spotify: альбом не найден"))?;
    let mut tracks: Vec<Track> = list(&v["tracks"]["items"], |t| track_from(t, Some(&v)));
    // длинные альбомы: остальные страницы треков
    let mut next = next_url(&v["tracks"]);
    for _ in 0..ALBUM_MAX_PAGES {
      let Some(n) = next else { break };
      let page = self.get(&n, &[]).await?;
      tracks.extend(list(&page["items"], |t| track_from(t, Some(&v))));
      next = next_url(&page);
    }
    Ok((album, tracks))
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use serde_json::json;

  #[test]
  fn totp_rfc6238_vectors() {
    let key = b"12345678901234567890";
    assert_eq!(totp(key, 59), "287082");
    assert_eq!(totp(key, 1_111_111_109), "081804");
  }

  #[test]
  fn totp_key_from_cipher() {
    let key = totp_key(&default_totp().cipher);
    assert_eq!(String::from_utf8(key.clone()).unwrap(), "376136387538459893883312310911992847112448894410210511297108");
    assert_eq!(totp(&key, 1_700_000_000), "371599");
  }

  #[test]
  fn remote_totp_only_newer_and_sane() {
    let fresh = parse_remote_totp(r#"{"version":62,"cipher":[1,2,3]}"#, 61).unwrap();
    assert_eq!(fresh, TotpSecret { version: 62, cipher: vec![1, 2, 3] });
    assert_eq!(parse_remote_totp(r#"{"version":61,"cipher":[1]}"#, 61), None, "та же версия — мимо");
    assert_eq!(parse_remote_totp(r#"{"version":5,"cipher":[1]}"#, 61), None, "старая — мимо");
    assert_eq!(parse_remote_totp(r#"{"version":70,"cipher":[]}"#, 61), None, "пустой шифр");
    assert_eq!(parse_remote_totp(r#"{"version":70,"cipher":[300]}"#, 61), None, "не байт");
    assert_eq!(parse_remote_totp("<html>404</html>", 61), None);
    let long = format!(r#"{{"version":70,"cipher":{:?}}}"#, vec![1u8; 200]);
    assert_eq!(parse_remote_totp(&long, 61), None, "слишком длинный");
  }

  #[test]
  fn totp_store_adopts_newer_file() {
    let store = TotpStore::default();
    assert_eq!(store.current(), default_totp());
    assert!(!store.adopt(r#"{"version":61,"cipher":[9]}"#));
    assert!(store.adopt(r#"{"version":64,"cipher":[9,8]}"#));
    assert_eq!(store.current().version, 64);
    assert!(!store.adopt(r#"{"version":63,"cipher":[7]}"#), "назад не откатываемся");
  }

  #[test]
  fn repo_totp_file_matches_builtin() {
    let file: TotpSecret = serde_json::from_str(include_str!("../../../../updates/spotify-totp.json")).unwrap();
    assert!(file.version >= default_totp().version, "файл в репо не старше вшитого шифра");
  }

  #[test]
  fn token_query_shape() {
    let q = token_query(&default_totp(), 1_700_000_000);
    let get = |k: &str| q.iter().find(|(n, _)| *n == k).map(|(_, v)| v.as_str());
    assert_eq!(get("totp"), Some("371599"));
    assert_eq!(get("totpServer"), Some("371599"));
    assert_eq!(get("totpVer"), Some("61"));
    assert_eq!(get("productType"), Some("web-player"));
  }

  #[test]
  fn normalize_accepts_prefix_and_cookie_header() {
    let v = "AQBxyz-_0123456789abcdefABCDEF";
    assert_eq!(normalize_sp_dc(v).as_deref(), Some(v));
    assert_eq!(normalize_sp_dc(&format!("  sp_dc={v};  ")).as_deref(), Some(v));
    assert_eq!(normalize_sp_dc(&format!("sp_t=1; sp_dc={v}; sp_key=2")).as_deref(), Some(v));
    assert_eq!(normalize_sp_dc(&format!("\"{v}\"")).as_deref(), Some(v));
    assert_eq!(normalize_sp_dc(""), None);
    assert_eq!(normalize_sp_dc("short"), None);
    assert_eq!(normalize_sp_dc("has space inside the cookie value ok"), None);
  }

  #[test]
  fn api_url_only_spotify_web_api() {
    assert_eq!(api_url("/me").as_deref(), Some("https://api.spotify.com/v1/me"));
    let next = "https://api.spotify.com/v1/albums/1/tracks?offset=50&limit=50";
    assert_eq!(api_url(next).as_deref(), Some(next));
    assert_eq!(api_url("https://attacker.example/x"), None);
    assert_eq!(api_url("https://api.spotify.com.attacker.example/v1/x"), None);
    assert_eq!(api_url("http://api.spotify.com/v1/me"), None);
    assert_eq!(next_url(&json!({ "next": "https://evil.example/v1" })), None);
    assert_eq!(next_url(&json!({ "next": null })), None);
  }

  #[test]
  fn parse_token_ok_and_errors() {
    let ok = parse_token(200, r#"{"clientId":"c","accessToken":"BQ1","accessTokenExpirationTimestampMs":1700000000000,"isAnonymous":false}"#).unwrap();
    assert_eq!(ok, WebToken { access_token: "BQ1".into(), expires_at_ms: 1_700_000_000_000 });
    assert!(ok.fresh_at(1_700_000_000_000 - 61_000));
    assert!(!ok.fresh_at(1_700_000_000_000 - 59_000));
    let anon = parse_token(200, r#"{"accessToken":"BQ2","isAnonymous":true}"#).unwrap_err().to_string();
    assert_eq!(anon, SP_DC_BAD);
    assert_eq!(parse_token(400, "{}").unwrap_err().to_string(), TOTP_STALE);
    assert_eq!(parse_token(403, r#"{"error":"Invalid TOTP"}"#).unwrap_err().to_string(), TOTP_STALE);
    assert_eq!(parse_token(429, "").unwrap_err().to_string(), "Spotify: слишком много запросов, подожди минуту (HTTP 429)");
    assert_eq!(parse_token(200, "not json").unwrap_err().to_string(), "Spotify: непонятный ответ веб-плеера");
    // удачный ответ, где в случайном токене попалось «TOTP», — не «ключ устарел»
    let lucky = parse_token(200, r#"{"accessToken":"BQxTOTPy","accessTokenExpirationTimestampMs":1,"isAnonymous":false}"#).unwrap();
    assert_eq!(lucky.access_token, "BQxTOTPy");
  }

  fn track_json() -> Value {
    json!({
      "id": "t1", "type": "track", "name": "Song", "duration_ms": 201000, "explicit": true,
      "artists": [{"id": "a1", "name": "A"}, {"id": "a2", "name": "B"}],
      "album": {"id": "al1", "name": "LP", "images": [{"url": "https://i.scdn.co/image/small", "width": 64}, {"url": "https://i.scdn.co/image/big", "width": 640}]},
      "external_urls": {"spotify": "https://open.spotify.com/track/t1"}
    })
  }

  #[test]
  fn track_mapping() {
    let t = track_from(&track_json(), None).unwrap();
    assert_eq!(t.ref_, "sp:t1");
    assert_eq!(t.artist, "A, B");
    assert_eq!(t.artists[1].ref_, "spa:a2");
    assert_eq!(t.album.as_ref().map(|a| (a.ref_.as_str(), a.title.as_str())), Some(("spalb:al1", "LP")));
    assert_eq!(t.cover_url.as_deref(), Some("https://i.scdn.co/image/big"));
    assert!(t.explicit && t.available);
    assert_eq!(t.duration_ms, 201000);
    assert_eq!(t.url.as_deref(), Some("https://open.spotify.com/track/t1"));
  }

  #[test]
  fn local_files_and_episodes_skipped() {
    assert!(track_from(&json!({"id": null, "is_local": true, "name": "x"}), None).is_none());
    assert!(track_from(&json!({"id": "e", "type": "episode", "name": "x"}), None).is_none());
  }

  #[test]
  fn playlist_rows_track_or_item() {
    let page = json!({"items": [{"track": track_json()}, {"item": track_json()}, {"track": null}]});
    assert_eq!(list(&page["items"], item_track).len(), 2);
  }

  #[test]
  fn album_artist_playlist_account_mapping() {
    let a = album_from(&json!({"id": "al1", "name": "LP", "release_date": "2021-03-05", "total_tracks": 12, "artists": [{"id": "a1", "name": "A"}], "images": []})).unwrap();
    assert_eq!((a.ref_.as_str(), a.year, a.released.as_deref(), a.track_count), ("spalb:al1", Some(2021), Some("2021-03-05"), 12));
    let y = album_from(&json!({"id": "x", "name": "Y", "release_date": "1999"})).unwrap();
    assert_eq!((y.year, y.released), (Some(1999), None));
    let ar = artist_from(&json!({"id": "a1", "name": "A", "followers": {"total": 7}, "images": [{"url": "https://i.scdn.co/image/av", "width": 320}]})).unwrap();
    assert_eq!((ar.ref_.as_str(), ar.followers, ar.avatar_url.as_deref()), ("spa:a1", Some(7), Some("https://i.scdn.co/image/av")));
    let p = playlist_from(&json!({"id": "p1", "name": "Mix", "owner": {"id": "u", "display_name": "Folzy"}, "images": null, "tracks": {"total": 3}})).unwrap();
    assert_eq!((p.ref_.as_str(), p.owner.as_str(), p.track_count, p.cover_url), ("sppl:p1", "Folzy", 3, None));
    let p2 = playlist_from(&json!({"id": "p2", "name": "New", "owner": {"id": "u"}, "items": {"total": 9}})).unwrap();
    assert_eq!((p2.owner.as_str(), p2.track_count), ("u", 9));
    let me = account_from(&json!({"id": "u1", "display_name": "F", "product": "premium", "images": []}));
    assert_eq!((me.name.as_deref(), me.uid.as_deref(), me.premium), (Some("F"), Some("u1"), Some(true)));
    assert_eq!(account_from(&json!({"id": "u2", "product": "free"})).premium, Some(false));
  }

  #[test]
  fn album_tracks_take_outer_album() {
    let alb = json!({"id": "al9", "name": "EP", "images": [{"url": "https://i.scdn.co/image/c", "width": 300}]});
    let t = track_from(&json!({"id": "t9", "name": "N", "artists": []}), Some(&alb)).unwrap();
    assert_eq!(t.album.unwrap().ref_, "spalb:al9");
    assert_eq!(t.cover_url.as_deref(), Some("https://i.scdn.co/image/c"));
  }
}

/// Живые проверки: `SP_DC=… cargo test spotify -- --ignored`. Печатают только формат, не ключи.
#[cfg(test)]
mod live {
  use super::*;

  fn creds() -> Option<Creds> {
    std::env::var("SP_DC").ok().and_then(|v| normalize_sp_dc(&v)).map(|sp_dc| Creds { sp_dc })
  }

  #[tokio::test]
  #[ignore = "живой Spotify: нужен SP_DC в окружении"]
  async fn live_token_search_account() {
    let Some(creds) = creds() else { return eprintln!("SP_DC не задан — пропуск") };
    let http = reqwest::Client::new();
    let secret = TotpStore::default();
    let cache = Mutex::new(None);
    let sp = Spotify { http: &http, creds: &creds, secret: &secret, cache: &cache };
    let me = sp.account().await.unwrap();
    println!("аккаунт: premium={:?}", me.premium);
    let found = sp.search("Daft Punk One More Time", 5).await.unwrap();
    assert!(!found.is_empty());
    println!("поиск: {} треков, первый {}", found.len(), found[0].ref_);
    let likes = sp.likes(60).await.unwrap();
    println!("любимые: {}", likes.len());
    let lists = sp.playlists().await.unwrap();
    println!("плейлисты: {}", lists.len());
  }
}
