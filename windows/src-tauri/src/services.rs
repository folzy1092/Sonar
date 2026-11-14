//! Общее ядро: HTTP-клиент, ключи сервисов, кэш ссылок на поток.
//! Команды интерфейса и локальный аудио-сервер ходят в сервисы только через него.

use crate::providers::{
  soundcloud, yandex, Account, AlbumPage, ArtistPage, SearchResults, ServicePlaylist, Source, Track,
};
use crate::secrets;
use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

/// Ссылки SoundCloud и Яндекса живут минуты — держим чуть меньше, при 403 берём заново.
const STREAM_TTL: Duration = Duration::from_secs(240);

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Stored<C> {
  pub creds: C,
  pub account: Account,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ServiceStatus {
  pub connected: bool,
  pub name: Option<String>,
  pub avatar_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ServicesStatus {
  pub soundcloud: ServiceStatus,
  pub yandex: ServiceStatus,
}

/// Плейлист сервиса с треками.
#[derive(Debug, Clone, Serialize)]
pub struct PlaylistPage {
  pub playlist: ServicePlaylist,
  pub tracks: Vec<Track>,
}

pub struct Core {
  pub http: reqwest::Client,
  sc: RwLock<Option<Stored<soundcloud::Creds>>>,
  ym: RwLock<Option<Stored<yandex::Creds>>>,
  /// Сырой JSON треков SoundCloud из поиска — в нём `transcodings` для потока.
  sc_raw: Mutex<HashMap<String, Value>>,
  /// Публичный client_id с soundcloud.com — когда своих ключей нет (поиск и открытые треки).
  sc_auto: RwLock<Option<String>>,
  streams: Mutex<HashMap<String, (Source, Instant)>>,
  /// Потолок битрейта Яндекса (`audio.quality`): 192 / 256 / 320.
  pub max_kbps: AtomicU32,
}

fn status<C>(s: &Option<Stored<C>>) -> ServiceStatus {
  match s {
    Some(s) => ServiceStatus { connected: true, name: s.account.name.clone(), avatar_url: s.account.avatar_url.clone() },
    None => ServiceStatus::default(),
  }
}

impl Core {
  pub fn new() -> Self {
    let http = reqwest::Client::builder()
      .connect_timeout(Duration::from_secs(10))
      .gzip(true)
      .build()
      .expect("http client");
    Self {
      http,
      sc: RwLock::new(secrets::load("soundcloud")),
      ym: RwLock::new(secrets::load("yandex")),
      sc_raw: Mutex::new(HashMap::new()),
      sc_auto: RwLock::new(None),
      streams: Mutex::new(HashMap::new()),
      max_kbps: AtomicU32::new(320),
    }
  }

  /// Ключи SoundCloud: свои из «Сервисов», иначе публичный client_id с сайта.
  /// Второе значение — true, если ключи публичные (их можно взять заново при 401/403).
  /// `renew` — выбросить старый публичный client_id и найти свежий.
  async fn sc_creds(&self, renew: bool) -> Result<(soundcloud::Creds, bool)> {
    if let Some(s) = self.sc.read().await.as_ref() {
      return Ok((s.creds.clone(), false));
    }
    if !renew {
      if let Some(id) = self.sc_auto.read().await.clone() {
        return Ok((soundcloud::Creds { client_id: id, oauth_token: None }, true));
      }
    }
    let id = soundcloud::public_client_id(&self.http).await?;
    *self.sc_auto.write().await = Some(id.clone());
    Ok((soundcloud::Creds { client_id: id, oauth_token: None }, true))
  }

  async fn sc_search(&self, creds: &soundcloud::Creds, q: &str, limit: u32) -> Result<Vec<(Track, Value)>> {
    soundcloud::SoundCloud { http: &self.http, creds }.search(q, limit).await
  }

  async fn sc_stream(&self, creds: &soundcloud::Creds, track_ref: &str, id: &str, fresh: bool) -> Result<Source> {
    let sc = soundcloud::SoundCloud { http: &self.http, creds };
    let cached = self.sc_raw.lock().unwrap().get(track_ref).cloned();
    let json = match cached {
      Some(j) if !fresh => j,
      _ => sc.track_json(id).await?,
    };
    match sc.stream(&json).await {
      Ok(src) => Ok(src),
      // в сохранённом JSON могла протухнуть track_authorization — берём трек заново
      Err(_) if !fresh => {
        let json = sc.track_json(id).await?;
        self.sc_raw.lock().unwrap().insert(track_ref.to_owned(), json.clone());
        sc.stream(&json).await
      }
      Err(e) => Err(e),
    }
  }

  /// Для тестов: ядро с ключами SoundCloud, без Диспетчера учётных данных.
  #[cfg(test)]
  pub fn with_soundcloud(creds: soundcloud::Creds) -> Self {
    let core = Self::new_empty();
    *core.sc.try_write().unwrap() = Some(Stored { creds, account: Account::default() });
    core
  }

  #[cfg(test)]
  fn new_empty() -> Self {
    Self {
      http: reqwest::Client::new(),
      sc: RwLock::new(None),
      ym: RwLock::new(None),
      sc_raw: Mutex::new(HashMap::new()),
      sc_auto: RwLock::new(None),
      streams: Mutex::new(HashMap::new()),
      max_kbps: AtomicU32::new(320),
    }
  }

  pub async fn status(&self) -> ServicesStatus {
    ServicesStatus { soundcloud: status(&*self.sc.read().await), yandex: status(&*self.ym.read().await) }
  }

  pub async fn connect_soundcloud(&self, creds: soundcloud::Creds) -> Result<ServiceStatus> {
    if creds.client_id.trim().len() < 20 {
      bail!("client_id SoundCloud — строка из 32 символов");
    }
    let account = soundcloud::SoundCloud { http: &self.http, creds: &creds }.account().await?;
    let stored = Stored { creds, account };
    secrets::save("soundcloud", &stored)?;
    *self.sc.write().await = Some(stored.clone());
    self.streams.lock().unwrap().clear();
    Ok(status(&Some(stored)))
  }

  pub async fn connect_yandex(&self, creds: yandex::Creds) -> Result<ServiceStatus> {
    if creds.token.trim().is_empty() {
      bail!("Вставь токен Яндекс Музыки");
    }
    let account = yandex::Yandex { http: &self.http, creds: &creds }.account().await?;
    let stored = Stored { creds, account };
    secrets::save("yandex", &stored)?;
    *self.ym.write().await = Some(stored.clone());
    self.streams.lock().unwrap().clear();
    Ok(status(&Some(stored)))
  }

  pub async fn disconnect(&self, service: &str) -> Result<()> {
    match service {
      "soundcloud" => *self.sc.write().await = None,
      "yandex" => *self.ym.write().await = None,
      _ => bail!("неизвестный сервис {service}"),
    }
    secrets::delete(service)
  }

  pub async fn search(&self, q: &str, src: &str, limit: u32) -> Result<Vec<Track>> {
    match src {
      "sc" => {
        let (creds, public) = self.sc_creds(false).await?;
        let found = match self.sc_search(&creds, q, limit).await {
          Err(e) if public && is_auth_error(&e) => self.sc_search(&self.sc_creds(true).await?.0, q, limit).await?,
          r => r?,
        };
        let mut raw = self.sc_raw.lock().unwrap();
        if raw.len() > 2000 {
          raw.clear();
        }
        Ok(found
          .into_iter()
          .map(|(t, j)| {
            raw.insert(t.ref_.clone(), j);
            t
          })
          .collect())
      }
      "ym" => {
        let guard = self.ym.read().await;
        let s = guard.as_ref().ok_or_else(|| anyhow!("Яндекс Музыка не подключена — открой Настройки → Сервисы"))?;
        yandex::Yandex { http: &self.http, creds: &s.creds }.search(q, limit).await
      }
      _ => bail!("неизвестный источник {src}"),
    }
  }

  /// Сырой JSON треков SoundCloud → модели; JSON запоминаем для потока.
  fn sc_keep(&self, raw: Vec<Value>) -> Vec<Track> {
    let mut cache = self.sc_raw.lock().unwrap();
    if cache.len() > 5000 {
      cache.clear();
    }
    raw
      .into_iter()
      .filter_map(|j| {
        let t = soundcloud::track_from_json(&j)?;
        cache.insert(t.ref_.clone(), j);
        Some(t)
      })
      .collect()
  }

  /// Вызов SoundCloud с повтором на свежем публичном client_id при 401/403.
  async fn with_sc<T, F, Fut>(&self, f: F) -> Result<T>
  where
    F: Fn(soundcloud::Creds) -> Fut,
    Fut: std::future::Future<Output = Result<T>>,
  {
    let (creds, public) = self.sc_creds(false).await?;
    match f(creds).await {
      Err(e) if public && is_auth_error(&e) => f(self.sc_creds(true).await?.0).await,
      r => r,
    }
  }

  async fn ym_creds(&self) -> Result<Stored<yandex::Creds>> {
    self.ym.read().await.clone().ok_or_else(|| anyhow!("Яндекс Музыка не подключена — открой Настройки → Сервисы"))
  }

  /// Исполнители, альбомы, плейлисты для вкладок поиска.
  pub async fn search_more(&self, q: &str, src: &str, limit: u32) -> Result<SearchResults> {
    let (artists, albums, playlists) = match src {
      "sc" => {
        let http = &self.http;
        self.with_sc(|c| async move { soundcloud::SoundCloud { http, creds: &c }.search_more(q, limit).await }).await?
      }
      "ym" => {
        let s = self.ym_creds().await?;
        yandex::Yandex { http: &self.http, creds: &s.creds }.search_more(q, limit).await?
      }
      _ => bail!("неизвестный источник {src}"),
    };
    Ok(SearchResults { tracks: vec![], artists, albums, playlists })
  }

  pub async fn artist_page(&self, artist_ref: &str) -> Result<ArtistPage> {
    let (kind, id) = artist_ref.split_once(':').ok_or_else(|| anyhow!("плохой ref {artist_ref}"))?;
    match kind {
      "sca" => {
        let http = &self.http;
        let (user, top, albums) = self
          .with_sc(|c| async move {
            let sc = soundcloud::SoundCloud { http, creds: &c };
            let (user, top, albums) = futures_util::join!(sc.user(id), sc.top_tracks(id, 10), sc.user_albums(id));
            Ok((user?, top.unwrap_or_default(), albums.unwrap_or_default()))
          })
          .await?;
        let artist = soundcloud::artist_from_json(&user).ok_or_else(|| anyhow!("SoundCloud: исполнитель не найден"))?;
        Ok(ArtistPage { artist, top: self.sc_keep(top), albums })
      }
      "yma" => {
        let s = self.ym_creds().await?;
        let (artist, top, albums) = yandex::Yandex { http: &self.http, creds: &s.creds }.artist(id).await?;
        Ok(ArtistPage { artist, top, albums })
      }
      _ => bail!("неизвестный исполнитель {artist_ref}"),
    }
  }

  pub async fn album_page(&self, album_ref: &str) -> Result<AlbumPage> {
    let (kind, id) = album_ref.split_once(':').ok_or_else(|| anyhow!("плохой ref {album_ref}"))?;
    match kind {
      "scalb" => {
        let http = &self.http;
        let (head, raw) =
          self.with_sc(|c| async move { soundcloud::SoundCloud { http, creds: &c }.playlist(id).await }).await?;
        let album = soundcloud::album_from_json(&head).ok_or_else(|| anyhow!("SoundCloud: альбом не найден"))?;
        Ok(AlbumPage { album, tracks: self.sc_keep(raw) })
      }
      "ymalb" => {
        let s = self.ym_creds().await?;
        let (album, tracks) = yandex::Yandex { http: &self.http, creds: &s.creds }.album(id).await?;
        Ok(AlbumPage { album, tracks })
      }
      _ => bail!("неизвестный альбом {album_ref}"),
    }
  }

  /// id своего аккаунта в сервисе: из сохранённого, иначе спросить у сервиса.
  async fn sc_uid(&self) -> Result<Option<(soundcloud::Creds, String)>> {
    let Some(s) = self.sc.read().await.clone() else { return Ok(None) };
    if s.creds.oauth_token.is_none() {
      return Ok(None);
    }
    let uid = match s.account.uid.clone() {
      Some(u) => u,
      None => soundcloud::SoundCloud { http: &self.http, creds: &s.creds }
        .account()
        .await?
        .uid
        .ok_or_else(|| anyhow!("SoundCloud: не узнал id аккаунта"))?,
    };
    Ok(Some((s.creds, uid)))
  }

  async fn ym_uid(&self) -> Result<Option<(yandex::Creds, String)>> {
    let Some(s) = self.ym.read().await.clone() else { return Ok(None) };
    let uid = match s.account.uid.clone() {
      Some(u) => u,
      None => yandex::Yandex { http: &self.http, creds: &s.creds }
        .account()
        .await?
        .uid
        .ok_or_else(|| anyhow!("Яндекс Музыка: не узнал id аккаунта"))?,
    };
    Ok(Some((s.creds, uid)))
  }

  /// Фантомные плейлисты подключённых аккаунтов: сначала «Лайки» сервиса, потом свои плейлисты.
  pub async fn service_playlists(&self, service: &str) -> Result<Vec<ServicePlaylist>> {
    match service {
      "soundcloud" => {
        let Some((creds, uid)) = self.sc_uid().await? else { return Ok(vec![]) };
        let mut out = vec![ServicePlaylist {
          ref_: "scpl:likes".into(),
          title: "Лайки SoundCloud".into(),
          owner: self.sc.read().await.as_ref().and_then(|s| s.account.name.clone()).unwrap_or_default(),
          cover_url: None,
          track_count: 0,
        }];
        out.extend(soundcloud::SoundCloud { http: &self.http, creds: &creds }.user_playlists(&uid).await?);
        Ok(out)
      }
      "yandex" => {
        let Some((creds, uid)) = self.ym_uid().await? else { return Ok(vec![]) };
        let mut out = vec![ServicePlaylist {
          ref_: "ympl:likes".into(),
          title: "Мне нравится".into(),
          owner: self.ym.read().await.as_ref().and_then(|s| s.account.name.clone()).unwrap_or_default(),
          cover_url: None,
          track_count: 0,
        }];
        let lists = yandex::Yandex { http: &self.http, creds: &creds }.user_playlists(&uid).await?;
        // «Мне нравится» в Яндексе — kind 3, он уже есть первой строкой
        out.extend(lists.into_iter().filter(|p| !p.ref_.ends_with(":3")));
        Ok(out)
      }
      _ => bail!("неизвестный сервис {service}"),
    }
  }

  /// Плейлист сервиса с треками (`scpl:<id>`, `scpl:likes`, `ympl:<uid>:<kind>`, `ympl:likes`).
  pub async fn service_playlist(&self, pl_ref: &str) -> Result<PlaylistPage> {
    const MAX_LIKES: usize = 2000;
    let (kind, id) = pl_ref.split_once(':').ok_or_else(|| anyhow!("плохой ref {pl_ref}"))?;
    match (kind, id) {
      ("scpl", "likes") => {
        let (creds, uid) = self.sc_uid().await?.ok_or_else(|| anyhow!("Нужен OAuth-токен SoundCloud"))?;
        let raw = soundcloud::SoundCloud { http: &self.http, creds: &creds }.user_likes(&uid, MAX_LIKES).await?;
        let tracks = self.sc_keep(raw);
        let mut head = self.service_playlists("soundcloud").await.ok().and_then(|l| l.into_iter().next()).unwrap_or(ServicePlaylist {
          ref_: pl_ref.into(),
          title: "Лайки SoundCloud".into(),
          owner: String::new(),
          cover_url: None,
          track_count: 0,
        });
        head.track_count = tracks.len() as u32;
        head.cover_url = tracks.first().and_then(|t| t.cover_url.clone());
        Ok(PlaylistPage { playlist: head, tracks })
      }
      ("scpl", id) => {
        let http = &self.http;
        let (head, raw) =
          self.with_sc(|c| async move { soundcloud::SoundCloud { http, creds: &c }.playlist(id).await }).await?;
        let playlist = soundcloud::playlist_from_json(&head).ok_or_else(|| anyhow!("SoundCloud: плейлист не найден"))?;
        Ok(PlaylistPage { playlist, tracks: self.sc_keep(raw) })
      }
      ("ympl", "likes") => {
        let (creds, uid) = self.ym_uid().await?.ok_or_else(|| anyhow!("Яндекс Музыка не подключена"))?;
        let tracks = yandex::Yandex { http: &self.http, creds: &creds }.likes(&uid, MAX_LIKES).await?;
        let owner = self.ym.read().await.as_ref().and_then(|s| s.account.name.clone()).unwrap_or_default();
        let playlist = ServicePlaylist {
          ref_: pl_ref.into(),
          title: "Мне нравится".into(),
          owner,
          cover_url: tracks.first().and_then(|t| t.cover_url.clone()),
          track_count: tracks.len() as u32,
        };
        Ok(PlaylistPage { playlist, tracks })
      }
      ("ympl", rest) => {
        let (uid, kind) = rest.split_once(':').ok_or_else(|| anyhow!("плохой ref {pl_ref}"))?;
        let s = self.ym_creds().await?;
        let (playlist, tracks) = yandex::Yandex { http: &self.http, creds: &s.creds }.playlist(uid, kind).await?;
        Ok(PlaylistPage { playlist, tracks })
      }
      _ => bail!("неизвестный плейлист {pl_ref}"),
    }
  }

  /// Ссылка на поток для `sc:123` / `ym:456`. `fresh` — не брать из кэша (ссылка протухла).
  pub async fn resolve(&self, track_ref: &str, fresh: bool) -> Result<Source> {
    if !fresh {
      if let Some((src, at)) = self.streams.lock().unwrap().get(track_ref) {
        if at.elapsed() < STREAM_TTL {
          return Ok(src.clone());
        }
      }
    }
    let (kind, id) = track_ref.split_once(':').ok_or_else(|| anyhow!("плохой ref {track_ref}"))?;
    let src = match kind {
      "sc" => {
        let (creds, public) = self.sc_creds(false).await?;
        match self.sc_stream(&creds, track_ref, id, fresh).await {
          Err(e) if public && is_auth_error(&e) => {
            self.sc_stream(&self.sc_creds(true).await?.0, track_ref, id, true).await?
          }
          r => r?,
        }
      }
      "ym" => {
        let guard = self.ym.read().await;
        let s = guard.as_ref().ok_or_else(|| anyhow!("Яндекс Музыка не подключена"))?;
        yandex::Yandex { http: &self.http, creds: &s.creds }.stream(id, self.max_kbps.load(Ordering::Relaxed)).await?
      }
      _ => bail!("неизвестный источник в {track_ref}"),
    };
    self.streams.lock().unwrap().insert(track_ref.to_owned(), (src.clone(), Instant::now()));
    Ok(src)
  }
}

/// 401/403 от сервиса — ключ не подошёл (публичный client_id SoundCloud время от времени меняется).
fn is_auth_error(e: &anyhow::Error) -> bool {
  let t = e.to_string();
  t.contains("HTTP 401") || t.contains("HTTP 403")
}
