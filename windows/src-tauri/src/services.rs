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
      streams: Mutex::new(HashMap::new()),
      max_kbps: AtomicU32::new(320),
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
        let guard = self.sc.read().await;
        let s = guard.as_ref().ok_or_else(|| anyhow!("SoundCloud не подключён — открой Настройки → Сервисы"))?;
        let found = soundcloud::SoundCloud { http: &self.http, creds: &s.creds }.search(q, limit).await?;
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
        let guard = self.sc.read().await;
        let s = guard.as_ref().ok_or_else(|| anyhow!("SoundCloud не подключён"))?;
        let sc = soundcloud::SoundCloud { http: &self.http, creds: &s.creds };
        let cached = self.sc_raw.lock().unwrap().get(track_ref).cloned();
        let json = match cached {
          Some(j) if !fresh => j,
          _ => sc.track_json(id).await?,
        };
        let src = sc.stream(&json).await;
        if src.is_err() && !fresh {
          // в сохранённом JSON могла протухнуть track_authorization — берём трек заново
          let json = sc.track_json(id).await?;
          self.sc_raw.lock().unwrap().insert(track_ref.to_owned(), json.clone());
          sc.stream(&json).await?
        } else {
          src?
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
