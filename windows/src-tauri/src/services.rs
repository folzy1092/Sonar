//! Общее ядро: HTTP-клиент, ключи сервисов, кэш ссылок на поток.
//! Команды интерфейса и локальный аудио-сервер ходят в сервисы только через него.

use crate::providers::{soundcloud, yandex, Account, Source, Track};
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
