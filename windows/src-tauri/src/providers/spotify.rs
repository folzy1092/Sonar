//! Spotify: ключ `sp_dc` (cookie open.spotify.com) → токен веб-плеера → внутренний GraphQL веб-плеера
//! (`spotify_gql.rs`: поиск, лайки, плейлисты, исполнитель, альбом). Открытый Web API (`api.spotify.com/v1`)
//! с декабря 2025 отвечает на такой токен 429 на любой запрос — им больше не пользуемся (проверено
//! 2026-11-24). Рекомендаций не берём (не нужны волне).
//! Поток Spotify отдаёт только Premium через librespot (фича `spotify-playback`, docs/API.md
//! «Spotify»); без неё трек Spotify — «нужен резервный сервис» (резерв — этап 4).
//!
//! Токен: `GET open.spotify.com/api/token` с `totp`/`totpVer`. TOTP — HMAC-SHA1 от «шифра»
//! веб-плеера. Шифр Spotify меняет: свежий лежит в репо (`updates/spotify-totp.json`), Sonar читает
//! его при первом токене после запуска и при отказе «ключ устарел» (`TotpStore`), вшитый —
//! запасной. `sp_dc` не попадает ни в ошибки, ни в лог.

use super::spotify_gql::{self as gql, Op};
use super::{http_error, Account, Album, Artist, ArtistRef, ServicePlaylist, Track, UA};
use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::Mutex;

const TOKEN_URL: &str = "https://open.spotify.com/api/token";
/// Предел страниц одного списка: сервер, который не даёт `totalCount`, не крутит вечно.
const MAX_PAGES: usize = 60;
/// Треков в одном альбоме (сборники на сотни треков).
const ALBUM_MAX_TRACKS: usize = 2000;
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
/// Хэш запроса веб-плеера устарел, а свежий из веб-плеера не вынулся.
pub const GQL_STALE: &str = "Spotify обновил веб-плеер — Sonar не смог подхватить новые запросы, попробуй позже";
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

/// Клиент: токен веб-плеера общий на ядро (`cache`), запросы — внутренний GraphQL веб-плеера
/// (`spotify_gql.rs`): 401 — один повтор со свежим токеном, 412 «хэш устарел» — перечитать хэши из
/// веб-плеера и повторить.
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

  async fn send(&self, op: Op, variables: &Value, token: &str) -> Result<reqwest::Response> {
    let body = gql::body(op, &gql::HASHES.get(op), variables.clone());
    let r = self
      .http
      .post(gql::ENDPOINT)
      .bearer_auth(token)
      .header("App-Platform", "WebPlayer")
      .header("Accept", "application/json")
      .header("Accept-Language", "ru")
      .header("User-Agent", UA)
      .json(&body)
      .send()
      .await
      .map_err(|_| anyhow!("Spotify: api-partner.spotify.com недоступен"))?;
    Ok(r)
  }

  /// Операция → `data` ответа.
  async fn query(&self, op: Op, variables: Value) -> Result<Value> {
    let mut r = self.send(op, &variables, &self.token(false).await?).await?;
    if r.status() == reqwest::StatusCode::UNAUTHORIZED {
      r = self.send(op, &variables, &self.token(true).await?).await?;
    }
    if r.status() == reqwest::StatusCode::PRECONDITION_FAILED && gql::HASHES.refresh(self.http, op).await {
      r = self.send(op, &variables, &self.token(false).await?).await?;
    }
    match r.status() {
      s if s.is_success() => {}
      reqwest::StatusCode::PRECONDITION_FAILED => bail!(GQL_STALE),
      s => return Err(http_error("Spotify", s)),
    }
    let v: Value = r.json().await.map_err(|_| anyhow!("Spotify: непонятный ответ веб-плеера"))?;
    gql_data(v)
  }

  /// Страницы списка по `offset`, пока не кончатся или не наберётся `max` строк. `parse` → (строки,
  /// сколько элементов было на странице, всего).
  async fn paged<T>(&self, op: Op, max: usize, vars: impl Fn(u32) -> Value, parse: impl Fn(&Value) -> (Vec<T>, usize, Option<u64>)) -> Result<Vec<T>> {
    let mut out = Vec::new();
    let mut offset = 0u32;
    for _ in 0..MAX_PAGES {
      let (rows, seen, total) = parse(&self.query(op, vars(offset)).await?);
      out.extend(rows);
      offset += seen as u32;
      let done = seen == 0 || total.is_some_and(|t| u64::from(offset) >= t) || out.len() >= max;
      if done {
        break;
      }
    }
    out.truncate(max);
    Ok(out)
  }

  /// Профиль и подписка (подписка не пришла — `premium: None`, вход всё равно удался).
  pub async fn account(&self) -> Result<Account> {
    let profile = self.query(Op::Profile, json!({})).await?;
    if profile["me"]["profile"].is_null() {
      bail!(SP_DC_BAD);
    }
    let acc = self.query(Op::Account, json!({})).await.ok();
    Ok(gql::account(&profile, acc.as_ref()))
  }

  pub async fn search(&self, q: &str, limit: u32) -> Result<Vec<Track>> {
    let vars = json!({
      "searchTerm": q, "offset": 0, "limit": limit.clamp(1, gql::PAGE), "numberOfTopResults": 5,
      "includeAudiobooks": false, "includePreReleases": false, "includeAuthors": false,
    });
    Ok(gql::search_tracks(&self.query(Op::SearchTracks, vars).await?))
  }

  pub async fn search_more(&self, q: &str, limit: u32) -> Result<(Vec<Artist>, Vec<Album>, Vec<ServicePlaylist>)> {
    let vars = json!({
      "searchTerm": q, "offset": 0, "limit": limit.clamp(1, gql::PAGE), "numberOfTopResults": 5,
      "includeAudiobooks": false, "includeArtistHasConcertsField": false, "includePreReleases": false,
      "includeAlbumPreReleases": false, "includeAuthors": false, "includeEpisodeContentRatingsV2": false,
      "isPrefix": null, "sectionFilters": ["GENERIC"],
    });
    Ok(gql::search_more(&self.query(Op::SearchDesktop, vars).await?))
  }

  /// «Любимые треки» аккаунта.
  pub async fn likes(&self, max: usize) -> Result<Vec<Track>> {
    self.paged(Op::LibraryTracks, max, |offset| json!({ "offset": offset, "limit": gql::PAGE }), gql::library_tracks).await
  }

  /// Плейлисты библиотеки (папки раскрыты).
  pub async fn playlists(&self) -> Result<Vec<ServicePlaylist>> {
    let vars = |offset: u32| {
      json!({
        "filters": ["Playlists"], "order": null, "textFilter": null, "features": [], "limit": gql::PAGE, "offset": offset,
        "flatten": true, "expandedFolders": [], "folderUri": null, "includeFoldersWhenFlattening": false,
      })
    };
    self.paged(Op::LibraryV3, 500, vars, gql::library_playlists).await
  }

  pub async fn playlist(&self, id: &str, max: usize) -> Result<(ServicePlaylist, Vec<Track>)> {
    let uri = format!("spotify:playlist:{id}");
    let vars = |offset: u32| {
      json!({ "uri": uri, "offset": offset, "limit": gql::PAGE, "enableWatchFeedEntrypoint": false, "includeEpisodeContentRatingsV2": false })
    };
    let head = std::sync::Mutex::new(None);
    let tracks = self
      .paged(Op::Playlist, max, vars, |data| {
        let (p, tracks, seen, total) = gql::playlist_page(data);
        let mut h = head.lock().unwrap_or_else(|e| e.into_inner());
        if h.is_none() {
          *h = p;
        }
        (tracks, seen, total)
      })
      .await?;
    let mut playlist = head.into_inner().unwrap_or_else(|e| e.into_inner()).ok_or_else(|| anyhow!("Spotify: плейлист не найден"))?;
    playlist.track_count = playlist.track_count.max(tracks.len() as u32);
    Ok((playlist, tracks))
  }

  /// Шапка, популярные и альбомы исполнителя.
  pub async fn artist(&self, id: &str) -> Result<(Artist, Vec<Track>, Vec<Album>)> {
    let vars = json!({ "uri": format!("spotify:artist:{id}"), "locale": "", "preReleaseV2": false, "includeMusicVideoPreviews": false });
    let (artist, top) = gql::artist_overview(&self.query(Op::ArtistOverview, vars).await?).ok_or_else(|| anyhow!("Spotify: исполнитель не найден"))?;
    let by = ArtistRef { ref_: artist.ref_.clone(), name: artist.name.clone(), avatar_url: None };
    let albums = self.discography(id, Some(&by)).await?;
    Ok((artist, top, albums))
  }

  pub async fn artist_albums(&self, id: &str) -> Result<Vec<Album>> {
    self.discography(id, None).await
  }

  async fn discography(&self, id: &str, by: Option<&ArtistRef>) -> Result<Vec<Album>> {
    let uri = format!("spotify:artist:{id}");
    let vars = |offset: u32| json!({ "uri": uri, "offset": offset, "limit": gql::PAGE, "order": "DATE_DESC" });
    self.paged(Op::Discography, 200, vars, |d| gql::discography(d, by)).await
  }

  /// Треки альбомов исполнителя (до 20 альбомов, по 4 запроса разом) с датой выхода — вкладка «Треки».
  pub async fn artist_tracks(&self, id: &str, max: usize) -> Result<Vec<(Track, Option<String>)>> {
    let albums = self.artist_albums(id).await?;
    let ids: Vec<&str> = albums.iter().take(20).map(|a| a.ref_.trim_start_matches("spalb:")).collect();
    let mut pages: Vec<(Album, Vec<Track>)> = Vec::new();
    for batch in ids.chunks(4) {
      pages.extend(futures_util::future::try_join_all(batch.iter().map(|id| self.album(id))).await?);
    }
    let mut out: Vec<(Track, Option<String>)> =
      pages.into_iter().flat_map(|(album, tracks)| tracks.into_iter().map(move |t| (t, album.released.clone()))).collect();
    out.truncate(max);
    Ok(out)
  }

  pub async fn album(&self, id: &str) -> Result<(Album, Vec<Track>)> {
    let uri = format!("spotify:album:{id}");
    let vars = |offset: u32| json!({ "uri": uri, "locale": "", "offset": offset, "limit": gql::PAGE });
    let head = std::sync::Mutex::new(None);
    let tracks = self
      .paged(Op::Album, ALBUM_MAX_TRACKS, vars, |data| match gql::album_page(data) {
        Some((album, tracks, seen, total)) => {
          head.lock().unwrap_or_else(|e| e.into_inner()).get_or_insert(album);
          (tracks, seen, total)
        }
        None => (vec![], 0, None),
      })
      .await?;
    let album = head.into_inner().unwrap_or_else(|e| e.into_inner()).ok_or_else(|| anyhow!("Spotify: альбом не найден"))?;
    Ok((album, tracks))
  }
}

/// Ответ GraphQL → `data`; ошибки без данных — понятным текстом (без ключей и адресов).
pub fn gql_data(mut v: Value) -> Result<Value> {
  let data = v.get_mut("data").map(Value::take).unwrap_or(Value::Null);
  if data.is_object() {
    return Ok(data);
  }
  let msg = v["errors"][0]["message"].as_str().unwrap_or("");
  if msg.contains("not authorized") {
    bail!(SP_DC_BAD);
  }
  bail!("Spotify: непонятный ответ веб-плеера")
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

  #[test]
  fn gql_data_or_clear_error() {
    assert_eq!(gql_data(json!({ "data": { "me": null } })).unwrap(), json!({ "me": null }));
    let unauthorized = json!({ "data": null, "errors": [{ "message": "Exception while fetching data (/me) : User is not authorized" }] });
    assert_eq!(gql_data(unauthorized).unwrap_err().to_string(), SP_DC_BAD);
    assert_eq!(gql_data(json!("Invalid query hash")).unwrap_err().to_string(), "Spotify: непонятный ответ веб-плеера");
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
    if let Some(p) = lists.first() {
      let (head, rows) = sp.playlist(p.ref_.trim_start_matches("sppl:"), 120).await.unwrap();
      println!("плейлист: {} строк из {}", rows.len(), head.track_count);
    }
    let (artist, top, albums) = sp.artist("7dGJo4pcD2V6oG8kP0tJRR").await.unwrap();
    println!("исполнитель {}: популярных {}, альбомов {}", artist.name, top.len(), albums.len());
    let (album, tracks) = sp.album("6t7956yu5zYf5A829XRiHC").await.unwrap();
    println!("альбом {}: {} треков", album.title, tracks.len());
  }
}
