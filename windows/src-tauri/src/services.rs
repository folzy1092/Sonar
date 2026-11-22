//! Общее ядро: HTTP-клиент, ключи сервисов, кэш ссылок на поток.
//! Команды интерфейса и локальный аудио-сервер ходят в сервисы только через него.

use crate::providers::registry::{by_key, parse_ref, split_ref, RefKind, ServiceId, ServiceInfo, REGISTRY};
use crate::providers::{
  soundcloud, spotify, vk as vk_api, yandex, youtube, Account, Album, AlbumPage, Artist, ArtistPage, ArtistTrack, SearchResults, ServicePlaylist, Source, Track,
};
use crate::providers::unplayable::{preview_of, Unplayable};
use crate::secrets;
use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

pub mod fallback;
pub mod import;
mod local;
mod provider;
mod sc;
mod sc_repair;
mod sp;
mod vk;
mod vk_keys;
mod ym;
mod yt;
pub use provider::{AnyProvider, Provider};

/// Ссылки SoundCloud, Яндекса и VK живут минуты — держим чуть меньше, при 403 берём заново.
const STREAM_TTL: Duration = Duration::from_secs(240);

/// Что нашлось по ссылке из строки поиска.
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum LinkItem {
  Track { track: Track },
  Album { album: Album },
  Artist { artist: Artist },
  Playlist { playlist: ServicePlaylist },
  /// Плейлист или альбом, который можно только перенести с подбором пар (Apple Music).
  Import { head: import::ImportHead },
}

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
  /// Платная подписка сервиса (Яндекс Плюс); None — сервис не говорит.
  pub premium: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ServicesStatus {
  pub soundcloud: ServiceStatus,
  pub yandex: ServiceStatus,
  pub youtube: ServiceStatus,
  pub vk: ServiceStatus,
  pub spotify: ServiceStatus,
}

/// Сервис из реестра и состояние его подключения (команда `services_list`).
#[derive(Debug, Serialize)]
pub struct ServiceEntry {
  #[serde(flatten)]
  pub info: &'static ServiceInfo,
  pub connected: bool,
  pub account_name: Option<String>,
  pub avatar_url: Option<String>,
  pub premium: Option<bool>,
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
  /// Cookie входа YouTube Music (каталог и поток работают и без него).
  yt: RwLock<Option<Stored<youtube::Creds>>>,
  /// `visitorData` гостя YouTube Music для `player` — одна на сессию.
  yt_visitor: RwLock<Option<String>>,
  /// «YouTube Music: Высокое» (`audio.yt_quality`, по умолчанию): Opus вместо AAC 128.
  pub yt_high: AtomicBool,
  vk: RwLock<Option<Stored<vk_api::Creds>>>,
  /// Ссылки на поток, которые VK отдал вместе с треками, и когда (services/vk.rs).
  vk_seen: Mutex<HashMap<String, (String, Instant)>>,
  /// access_key треков VK — на диске, переживают перезапуск (services/vk_keys.rs).
  vk_keys: Mutex<vk_keys::VkKeys>,
  sp: RwLock<Option<Stored<spotify::Creds>>>,
  /// Токен веб-плеера Spotify (живёт около часа) — общий для всех запросов.
  sp_token: tokio::sync::Mutex<Option<spotify::WebToken>>,
  /// Шифр TOTP для токена Spotify; потом — с сервера (`GET /config`).
  sp_totp: spotify::TotpStore,
  /// Сырой JSON треков SoundCloud из поиска — в нём `transcodings` для потока.
  sc_raw: Mutex<HashMap<String, Value>>,
  /// Публичный client_id с soundcloud.com — когда своих ключей нет (поиск и открытые треки).
  sc_auto: RwLock<Option<String>>,
  /// Тихий вход SoundCloud (скрытое окно, `login::soundcloud_silent`) и плашка «Войди заново» —
  /// ставит `lib.rs`, у ядра нет окна (services/sc_repair.rs).
  pub sc_hooks: std::sync::OnceLock<ScHooks>,
  /// Чинится один запрос за раз: остальные 401 ждут и берут уже новые ключи.
  sc_repair: tokio::sync::Mutex<()>,
  /// Починить не вышло — до нового входа плашку не повторяем и окно не открываем.
  sc_stale: AtomicBool,
  streams: Mutex<HashMap<String, (Source, Instant)>>,
  /// Потолок битрейта Яндекса (`audio.quality`): 192 / 256 / 320 / 1411 (FLAC без потерь).
  pub max_kbps: AtomicU32,
  /// Трек SoundCloud играть с Яндекса, если там есть тот же (`audio.sc_via_yandex`) — через резерв.
  pub sc_via_yandex: AtomicBool,
  /// Резервный сервис: порядок, найденные пары, что играет вместо чего (services/fallback.rs).
  pub fallback: fallback::Fallback,
  /// Локальные файлы: ref → путь (Хранилище → «Папки с музыкой»).
  pub local: crate::local::Index,
}

/// Тихий вход SoundCloud: на вход — прежний `oauth_token`, на выход — новый или None.
pub type ScRelogin = Box<dyn Fn(Option<String>) -> futures_util::future::BoxFuture<'static, Option<String>> + Send + Sync>;

pub struct ScHooks {
  pub relogin: ScRelogin,
  /// Показать плашку «Войди в SoundCloud заново».
  pub notice: Box<dyn Fn() + Send + Sync>,
}

fn status<C>(s: &Option<Stored<C>>) -> ServiceStatus {
  match s {
    Some(s) => ServiceStatus {
      connected: true,
      name: s.account.name.clone(),
      avatar_url: s.account.avatar_url.clone(),
      premium: s.account.premium,
    },
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
      sc: RwLock::new(secrets::load(ServiceId::Sc.key())),
      ym: RwLock::new(secrets::load(ServiceId::Ym.key())),
      yt: RwLock::new(secrets::load(ServiceId::Yt.key())),
      yt_visitor: RwLock::new(None),
      yt_high: AtomicBool::new(yt_high(None)),
      vk: RwLock::new(secrets::load(ServiceId::Vk.key())),
      vk_seen: Mutex::new(HashMap::new()),
      vk_keys: Mutex::new(vk_keys::VkKeys::memory()),
      sp: RwLock::new(secrets::load(ServiceId::Sp.key())),
      sp_token: tokio::sync::Mutex::new(None),
      sp_totp: spotify::TotpStore::default(),
      sc_raw: Mutex::new(HashMap::new()),
      sc_auto: RwLock::new(None),
      sc_hooks: std::sync::OnceLock::new(),
      sc_repair: tokio::sync::Mutex::new(()),
      sc_stale: AtomicBool::new(false),
      streams: Mutex::new(HashMap::new()),
      max_kbps: AtomicU32::new(crate::providers::yandex::LOSSLESS_KBPS),
      // по умолчанию выключено (решение владельца 2026-11-17): на Яндексе треки бывают заблюрены
      sc_via_yandex: AtomicBool::new(false),
      fallback: fallback::Fallback::default(),
      local: crate::local::Index::default(),
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
    let (src, json) = match sc.stream(&json).await {
      Ok(src) => (src, json),
      // в сохранённом JSON могла протухнуть track_authorization — берём трек заново
      Err(_) if !fresh => {
        let json = sc.track_json(id).await?;
        self.sc_raw.lock().unwrap().insert(track_ref.to_owned(), json.clone());
        (sc.stream(&json).await?, json)
      }
      Err(e) => return Err(e),
    };
    // только отрывок (без Go+): сыграет, если тот же трек больше нигде не нашёлся
    if soundcloud::is_snippet(&json) {
      return Err(Unplayable::preview("SoundCloud: доступен только отрывок", src).into());
    }
    Ok(src)
  }

  /// Для тестов: ядро с ключами SoundCloud, без Диспетчера учётных данных.
  #[cfg(test)]
  pub fn with_soundcloud(creds: soundcloud::Creds) -> Self {
    let core = Self::new_empty();
    *core.sc.try_write().unwrap() = Some(Stored { creds, account: Account::default() });
    core
  }

  /// Для тестов других модулей: пустое ядро без keyring.
  #[cfg(test)]
  pub fn new_empty_for_tests() -> Self {
    Self::new_empty()
  }

  #[cfg(test)]
  fn new_empty() -> Self {
    Self {
      http: reqwest::Client::new(),
      sc: RwLock::new(None),
      ym: RwLock::new(None),
      yt: RwLock::new(None),
      yt_visitor: RwLock::new(None),
      yt_high: AtomicBool::new(yt_high(None)),
      vk: RwLock::new(None),
      vk_seen: Mutex::new(HashMap::new()),
      vk_keys: Mutex::new(vk_keys::VkKeys::memory()),
      sp: RwLock::new(None),
      sp_token: tokio::sync::Mutex::new(None),
      sp_totp: spotify::TotpStore::default(),
      sc_raw: Mutex::new(HashMap::new()),
      sc_auto: RwLock::new(None),
      sc_hooks: std::sync::OnceLock::new(),
      sc_repair: tokio::sync::Mutex::new(()),
      sc_stale: AtomicBool::new(false),
      streams: Mutex::new(HashMap::new()),
      max_kbps: AtomicU32::new(crate::providers::yandex::LOSSLESS_KBPS),
      sc_via_yandex: AtomicBool::new(false),
      fallback: fallback::Fallback::default(),
      local: crate::local::Index::default(),
    }
  }

  pub async fn status(&self) -> ServicesStatus {
    ServicesStatus {
      soundcloud: status(&*self.sc.read().await),
      yandex: status(&*self.ym.read().await),
      youtube: status(&*self.yt.read().await),
      vk: status(&*self.vk.read().await),
      spotify: status(&*self.sp.read().await),
    }
  }

  /// Все сервисы реестра по порядку; у работающих — подключён ли и чей аккаунт.
  pub async fn list(&self) -> Vec<ServiceEntry> {
    let ServicesStatus { soundcloud, yandex, youtube, vk, spotify } = self.status().await;
    REGISTRY
      .iter()
      .map(|info| {
        let st = match info.id {
          ServiceId::Sc => soundcloud.clone(),
          ServiceId::Ym => yandex.clone(),
          ServiceId::Yt => youtube.clone(),
          ServiceId::Vk => vk.clone(),
          ServiceId::Sp => spotify.clone(),
          _ => ServiceStatus::default(),
        };
        ServiceEntry { info, connected: st.connected, account_name: st.name, avatar_url: st.avatar_url, premium: st.premium }
      })
      .collect()
  }

  pub async fn connect_soundcloud(&self, creds: soundcloud::Creds) -> Result<ServiceStatus> {
    if creds.client_id.trim().len() < 20 {
      bail!("client_id SoundCloud — строка из 32 символов");
    }
    let account = soundcloud::SoundCloud { http: &self.http, creds: &creds }.account().await?;
    let stored = Stored { creds, account };
    secrets::save(ServiceId::Sc.key(), &stored)?;
    *self.sc.write().await = Some(stored.clone());
    self.sc_stale.store(false, Ordering::Relaxed);
    self.streams.lock().unwrap().clear();
    Ok(status(&Some(stored)))
  }

  pub async fn connect_yandex(&self, creds: yandex::Creds) -> Result<ServiceStatus> {
    if creds.token.trim().is_empty() {
      bail!("Вставь токен Яндекс Музыки");
    }
    let account = yandex::Yandex { http: &self.http, creds: &creds }.account().await?;
    let stored = Stored { creds, account };
    secrets::save(ServiceId::Ym.key(), &stored)?;
    *self.ym.write().await = Some(stored.clone());
    self.streams.lock().unwrap().clear();
    Ok(status(&Some(stored)))
  }

  /// YouTube Music по cookie браузера: проверить вход (`account_menu`) и сохранить в keyring.
  pub async fn connect_youtube(&self, cookie: &str) -> Result<ServiceStatus> {
    let creds = youtube::Creds { cookie: youtube::auth::normalize_cookie(cookie)? };
    let account = youtube::YouTube { http: &self.http, creds: Some(&creds) }.account().await?;
    let stored = Stored { creds, account };
    secrets::save(ServiceId::Yt.key(), &stored)?;
    *self.yt.write().await = Some(stored.clone());
    Ok(status(&Some(stored)))
  }

  /// Сменилось качество потока — старые ссылки больше не годятся.
  pub fn forget_streams(&self) {
    self.streams.lock().unwrap().clear();
  }

  /// Токен VK (`vk1.a.…`): проверяем, что он живой и что ему открыта музыка, и кладём в keyring.
  pub async fn connect_vk(&self, creds: vk_api::Creds) -> Result<ServiceStatus> {
    let creds = vk_api::Creds { token: creds.token.trim().to_owned() };
    if creds.token.is_empty() {
      bail!("Вставь токен VK");
    }
    let account = vk_api::Vk { http: &self.http, creds: &creds }.account().await?;
    let stored = Stored { creds, account };
    secrets::save(ServiceId::Vk.key(), &stored)?;
    *self.vk.write().await = Some(stored.clone());
    self.streams.lock().unwrap().clear();
    self.vk_seen.lock().unwrap().clear();
    Ok(status(&Some(stored)))
  }

  pub async fn disconnect(&self, service: &str) -> Result<()> {
    let Some(info) = by_key(service) else { bail!("неизвестный сервис {service}") };
    match info.id {
      ServiceId::Sc => *self.sc.write().await = None,
      ServiceId::Ym => *self.ym.write().await = None,
      ServiceId::Yt => *self.yt.write().await = None,
      ServiceId::Vk => {
        *self.vk.write().await = None;
        self.vk_seen.lock().unwrap().clear();
      }
      ServiceId::Sp => self.forget_spotify().await,
      _ => bail!("неизвестный сервис {service}"),
    }
    secrets::delete(info.key)
  }

  /// Клиент сервиса по id (реализованы все сервисы реестра).
  pub fn provider(&self, id: ServiceId) -> Result<AnyProvider<'_>> {
    match id {
      ServiceId::Sc => Ok(AnyProvider::Sc(sc::ScProvider { core: self })),
      ServiceId::Ym => Ok(AnyProvider::Ym(ym::YmProvider { core: self })),
      ServiceId::Yt => Ok(AnyProvider::Yt(yt::YtProvider { core: self })),
      ServiceId::Vk => Ok(AnyProvider::Vk(vk::VkProvider { core: self })),
      ServiceId::Local => Ok(AnyProvider::Local(local::LocalProvider { core: self })),
      ServiceId::Sp => Ok(AnyProvider::Sp(sp::SpProvider { core: self })),
    }
  }

  /// Сервис по `src` поиска — только короткий id (`sc`, `ym`), как и раньше.
  fn source(&self, src: &str) -> Result<AnyProvider<'_>> {
    let info = by_key(src).filter(|s| s.id.as_str() == src).ok_or_else(|| anyhow!("неизвестный источник {src}"))?;
    self.provider(info.id)
  }

  /// Сервис и id объекта по ref вида `kind`. Без `:` — «плохой ref», чужой вид или
  /// неработающий сервис — `{unknown} {ref}`.
  fn route<'r>(&self, r: &'r str, kind: RefKind, unknown: &str) -> Result<(AnyProvider<'_>, &'r str)> {
    let (_, id) = split_ref(r).ok_or_else(|| anyhow!("плохой ref {r}"))?;
    match parse_ref(r) {
      Some((s, k)) if k == kind && s.implemented => Ok((self.provider(s.id)?, id)),
      _ => bail!("{unknown} {r}"),
    }
  }

  pub async fn search(&self, q: &str, src: &str, limit: u32) -> Result<Vec<Track>> {
    self.source(src)?.search(q, limit).await
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

  /// Вызов SoundCloud с починкой ключей при 401/403: публичный client_id — берём свежий; свои
  /// ключи — свежий client_id, тихий вход, иначе плашка (services/sc_repair.rs).
  async fn with_sc<T, F, Fut>(&self, f: F) -> Result<T>
  where
    F: Fn(soundcloud::Creds) -> Fut,
    Fut: std::future::Future<Output = Result<T>>,
  {
    let (creds, public) = self.sc_creds(false).await?;
    let err = match f(creds.clone()).await {
      Err(e) if is_auth_error(&e) => e,
      r => return r,
    };
    if public {
      return f(self.sc_creds(true).await?.0).await;
    }
    self.sc_fix(creds, err, &f).await
  }

  async fn sc_fix<T, F, Fut>(&self, failed: soundcloud::Creds, err: anyhow::Error, f: &F) -> Result<T>
  where
    F: Fn(soundcloud::Creds) -> Fut,
    Fut: std::future::Future<Output = Result<T>>,
  {
    let _one = self.sc_repair.lock().await;
    let Some(current) = self.sc.read().await.as_ref().map(|s| s.creds.clone()) else { return Err(err) };
    // пока ждали очереди, ключи уже починил другой запрос
    if current.client_id != failed.client_id || current.oauth_token != failed.oauth_token {
      return f(current).await;
    }
    if self.sc_stale.load(Ordering::Relaxed) {
      return Err(sc_repair::relogin_error());
    }
    let hooks = self.sc_hooks.get();
    let old_token = failed.oauth_token.clone();
    let out = sc_repair::repair(&failed, err, f, || soundcloud::public_client_id(&self.http), || async move {
      match hooks {
        Some(h) => (h.relogin)(old_token).await,
        None => None,
      }
    })
    .await;
    if let Some((creds, fix)) = out.save {
      crate::crashlog::write("info", fix.journal());
      if let Err(e) = self.save_sc_creds(creds).await {
        log::warn!("SoundCloud: новые ключи не сохранились: {e}");
      }
    }
    if out.relogin {
      crate::crashlog::write("warn", sc_repair::JOURNAL_RELOGIN);
      self.sc_stale.store(true, Ordering::Relaxed);
      if let Some(h) = hooks {
        (h.notice)();
      }
    }
    out.result
  }

  /// Обновлённые ключи SoundCloud — в keyring и в ядро (аккаунт прежний).
  async fn save_sc_creds(&self, creds: soundcloud::Creds) -> Result<()> {
    let mut guard = self.sc.write().await;
    let Some(stored) = guard.as_mut() else { return Ok(()) };
    let next = Stored { creds, account: stored.account.clone() };
    secrets::save(ServiceId::Sc.key(), &next)?;
    *guard = Some(next);
    self.streams.lock().unwrap().clear();
    Ok(())
  }

  async fn ym_creds(&self) -> Result<Stored<yandex::Creds>> {
    self.ym.read().await.clone().ok_or_else(|| anyhow!("Яндекс Музыка не подключена — открой Настройки → Сервисы"))
  }

  /// Исполнители, альбомы, плейлисты для вкладок поиска.
  pub async fn search_more(&self, q: &str, src: &str, limit: u32) -> Result<SearchResults> {
    self.source(src)?.search_more(q, limit).await
  }

  pub async fn artist_page(&self, artist_ref: &str) -> Result<ArtistPage> {
    let (p, id) = self.route(artist_ref, RefKind::Artist, "неизвестный исполнитель")?;
    p.artist_page(id).await
  }

  /// Все треки исполнителя для вкладки «Треки» (до 1000), сначала самые прослушиваемые.
  pub async fn artist_tracks(&self, artist_ref: &str) -> Result<Vec<ArtistTrack>> {
    let (p, id) = self.route(artist_ref, RefKind::Artist, "неизвестный исполнитель")?;
    p.artist_tracks(id).await
  }

  /// Репосты исполнителя (раздел «Репосты»): у SoundCloud — что он репостнул, у остальных сервисов
  /// репостов нет — пусто.
  pub async fn artist_reposts(&self, artist_ref: &str, limit: u32) -> Result<Vec<Track>> {
    let (p, id) = self.route(artist_ref, RefKind::Artist, "неизвестный исполнитель")?;
    match p {
      AnyProvider::Sc(sc) => sc.artist_reposts(id, limit).await,
      _ => Ok(Vec::new()),
    }
  }

  pub async fn album_page(&self, album_ref: &str) -> Result<AlbumPage> {
    let (p, id) = self.route(album_ref, RefKind::Album, "неизвестный альбом")?;
    p.album_page(id).await
  }

  /// Похожие на трек (`sc:` — related SoundCloud, `ym:` — similar Яндекса). Для волны и «Похожего».
  pub async fn similar(&self, track_ref: &str, limit: u32) -> Result<Vec<Track>> {
    let (p, id) = self.route(track_ref, RefKind::Track, "неизвестный трек")?;
    p.similar(id, limit).await
  }

  /// Популярные треки исполнителя — «знакомое» для своей волны (одна просьба к сервису).
  pub async fn artist_top(&self, artist_ref: &str, limit: u32) -> Result<Vec<Track>> {
    let (p, id) = self.route(artist_ref, RefKind::Artist, "неизвестный исполнитель")?;
    p.artist_top(id, limit).await
  }

  /// На кого подписан исполнитель SoundCloud (`sca:<id>`) — связи карты исполнителей.
  pub async fn sc_followings(&self, artist_ref: &str, max: usize) -> Result<Vec<Artist>> {
    let id = artist_ref.strip_prefix("sca:").ok_or_else(|| anyhow!("не исполнитель SoundCloud: {artist_ref}"))?;
    let http = &self.http;
    self.with_sc(|c| async move { soundcloud::SoundCloud { http, creds: &c }.followings(id, max).await }).await
  }

  /// Свежие треки исполнителя SoundCloud (`sca:<id>`) с датой выхода — для «Новинок» (на SoundCloud
  /// новое выходит треками, а не альбомами). Новые первыми.
  pub async fn sc_recent_tracks(&self, artist_ref: &str, limit: usize) -> Result<Vec<ArtistTrack>> {
    let id = artist_ref.strip_prefix("sca:").ok_or_else(|| anyhow!("не исполнитель SoundCloud: {artist_ref}"))?;
    let http = &self.http;
    let raw = self.with_sc(|c| async move { soundcloud::SoundCloud { http, creds: &c }.user_tracks(id, limit).await }).await?;
    let dates: HashMap<String, String> = raw
      .iter()
      .filter_map(|j| {
        let date = j["release_date"].as_str().or(j["display_date"].as_str()).or(j["created_at"].as_str())?;
        Some((format!("sc:{}", j["id"].as_u64()?), date.chars().take(10).collect()))
      })
      .collect();
    let mut out: Vec<ArtistTrack> = self
      .sc_keep(raw)
      .into_iter()
      .map(|t| {
        let released = dates.get(&t.ref_).cloned();
        ArtistTrack { track: t, likes: None, released }
      })
      .collect();
    out.sort_by(|a, b| b.released.cmp(&a.released));
    Ok(out)
  }

  /// Яндекс подключён — можно брать его похожие и новинки.
  pub async fn has_yandex(&self) -> bool {
    self.ym.read().await.is_some()
  }

  /// VK подключён — его лайки и треки годятся для волны.
  pub async fn has_vk(&self) -> bool {
    self.vk.read().await.is_some()
  }

  /// Альбомы исполнителя (для «Релизов» на главной).
  pub async fn artist_albums(&self, artist_ref: &str) -> Result<Vec<Album>> {
    let (p, id) = self.route(artist_ref, RefKind::Artist, "неизвестный исполнитель")?;
    p.artist_albums(id).await
  }

  /// Новинки Яндекса — когда у любимых исполнителей свежего нет.
  pub async fn yandex_new_releases(&self, limit: usize) -> Result<Vec<Album>> {
    let s = self.ym_creds().await?;
    yandex::Yandex { http: &self.http, creds: &s.creds }.new_releases(limit).await
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
  /// `service` — короткий id (`sc`) или ключ (`soundcloud`).
  pub async fn service_playlists(&self, service: &str) -> Result<Vec<ServicePlaylist>> {
    let info = by_key(service).ok_or_else(|| anyhow!("неизвестный сервис {service}"))?;
    self.provider(info.id)?.playlists().await
  }

  /// Плейлист сервиса с треками (`scpl:<id>`, `scpl:likes`, `ympl:<uid>:<kind>`, `ympl:likes`).
  pub async fn service_playlist(&self, pl_ref: &str) -> Result<PlaylistPage> {
    let (p, id) = self.route(pl_ref, RefKind::Playlist, "неизвестный плейлист")?;
    p.playlist(id).await
  }

  /// Ссылка из строки поиска → трек, альбом, артист или плейлист (providers/links.rs).
  pub async fn resolve_link(&self, raw: &str) -> Result<LinkItem> {
    use crate::providers::links::{parse, Link};
    let link = parse(raw).ok_or_else(|| anyhow!("Это не ссылка на трек, альбом, артиста или плейлист музыкального сервиса"))?;
    match link {
      Link::Ref(r) => {
        let (svc, kind) = parse_ref(&r).ok_or_else(|| anyhow!("плохая ссылка"))?;
        match kind {
          RefKind::Album => Ok(LinkItem::Album { album: self.album_page(&r).await?.album }),
          RefKind::Artist => Ok(LinkItem::Artist { artist: self.artist_page(&r).await?.artist }),
          RefKind::Playlist => Ok(LinkItem::Playlist { playlist: self.service_playlist(&r).await?.playlist }),
          RefKind::Track if svc.id == ServiceId::Ym => {
            let (_, id) = split_ref(&r).ok_or_else(|| anyhow!("плохая ссылка"))?;
            let s = self.ym_creds().await?;
            let t = yandex::Yandex { http: &self.http, creds: &s.creds }.tracks(&[id.to_owned()]).await?;
            let track = t.into_iter().next().ok_or_else(|| anyhow!("Яндекс Музыка: трек не найден"))?;
            Ok(LinkItem::Track { track })
          }
          RefKind::Track => bail!("{}: ссылки на отдельные треки пока не открываются — вставь ссылку на плейлист или альбом", svc.name),
        }
      }
      Link::Apple(url) => Ok(LinkItem::Import { head: self.apple_source(&url).await?.head }),
      Link::SoundCloud(url) => {
        let http = &self.http;
        let url = &url;
        let v = self.with_sc(|c| async move { soundcloud::SoundCloud { http, creds: &c }.resolve(url).await }).await?;
        let none = || anyhow!("SoundCloud: по ссылке ничего не нашлось");
        match v["kind"].as_str() {
          Some("track") => Ok(LinkItem::Track { track: self.sc_keep(vec![v]).into_iter().next().ok_or_else(none)? }),
          Some("playlist") => {
            let album = matches!(v["set_type"].as_str(), Some("album" | "ep" | "single" | "compilation")) || v["is_album"].as_bool() == Some(true);
            if album {
              Ok(LinkItem::Album { album: soundcloud::album_from_json(&v).ok_or_else(none)? })
            } else {
              Ok(LinkItem::Playlist { playlist: soundcloud::playlist_from_json(&v).ok_or_else(none)? })
            }
          }
          Some("user") => Ok(LinkItem::Artist { artist: soundcloud::artist_from_json(&v).ok_or_else(none)? }),
          _ => Err(none()),
        }
      }
    }
  }

  /// Ссылка на поток для `sc:123` / `ym:456` (`/file`, `/hls`, предзагрузка). `fresh` — не брать из
  /// кэша (ссылка протухла). Трек сейчас играет с резервного сервиса (`resolve_playable`) — поток
  /// замены; свой сервис отдаёт только отрывок — отрывок.
  pub async fn resolve(&self, track_ref: &str, fresh: bool) -> Result<Source> {
    if let Some(alias) = self.fallback.routed_ref(track_ref) {
      return self.resolve_own(&alias, fresh).await;
    }
    match self.resolve_own(track_ref, fresh).await {
      Err(e) => preview_of(&e).ok_or(e),
      ok => ok,
    }
  }

  /// Поток со своего сервиса трека, без резерва.
  async fn resolve_own(&self, track_ref: &str, fresh: bool) -> Result<Source> {
    if !fresh {
      if let Some((src, at)) = self.streams.lock().unwrap().get(track_ref) {
        if at.elapsed() < STREAM_TTL {
          return Ok(src.clone());
        }
      }
    }
    let (p, id) = self.route(track_ref, RefKind::Track, "неизвестный источник в")?;
    let src = p.stream(id, fresh).await?;
    // путь к файлу не протухает, а файл могли переместить — локальные не кэшируем
    if p.id() != ServiceId::Local {
      self.streams.lock().unwrap().insert(track_ref.to_owned(), (src.clone(), Instant::now()));
    }
    Ok(src)
  }

  /// Свой поток не играет — ссылку из кэша больше не отдаём.
  fn forget_stream(&self, track_ref: &str) {
    self.streams.lock().unwrap().remove(track_ref);
  }

  /// Как `resolve_own`, но YouTube Music, не открывшийся с первого раза, пробует ещё раз с новой
  /// visitorData; не помогло — причина в журнал ошибок. У остальных сервисов ошибки не временные
  /// (нет входа, нет трека) — повтор ничего не даст. В тексте ошибок нет ни cookie, ни подписанных ссылок.
  async fn resolve_own_retrying(&self, track_ref: &str) -> Result<Source> {
    match self.resolve_own(track_ref, false).await {
      Err(e) if retries_resolve(track_ref) => {
        log::warn!("поток {track_ref}: {e}; пробую ещё раз");
        self.resolve_own(track_ref, true).await.inspect_err(|e| log::error!("поток {track_ref}: {e}"))
      }
      r => r,
    }
  }

  /// Поток SoundCloud как есть (публичный client_id обновляется при 401/403).
  async fn sc_resolve(&self, track_ref: &str, id: &str, fresh: bool) -> Result<Source> {
    // повтор после 401 — с только что взятым JSON трека (в старом — подпись прежних ключей)
    let again = AtomicBool::new(false);
    self
      .with_sc(|c| {
        let fresh = fresh || again.swap(true, Ordering::Relaxed);
        async move { self.sc_stream(&c, track_ref, id, fresh).await }
      })
      .await
  }
}

/// 401/403 от сервиса — ключ не подошёл (публичный client_id SoundCloud время от времени меняется).
fn is_auth_error(e: &anyhow::Error) -> bool {
  let t = e.to_string();
  t.contains("HTTP 401") || t.contains("HTTP 403")
}

/// Ошибку потока стоит повторить с `fresh`: только YouTube Music (протухшая или помеченная
/// visitorData, временный LOGIN_REQUIRED плеера).
pub fn retries_resolve(track_ref: &str) -> bool {
  crate::providers::registry::is_kind(track_ref, ServiceId::Yt, RefKind::Track)
}

/// `audio.quality` → потолок битрейта Яндекса. По умолчанию — максимум (FLAC, если есть).
pub fn quality_kbps(v: Option<&str>) -> u32 {
  match v {
    Some("low") => 192,
    Some("medium") => 256,
    Some("high") => 320,
    _ => crate::providers::yandex::LOSSLESS_KBPS,
  }
}

/// `audio.yt_quality`: «high» (по умолчанию) — Opus, «normal» — AAC 128.
pub fn yt_high(v: Option<&str>) -> bool {
  v != Some("normal")
}

#[cfg(test)]
mod tests {
  use super::*;

  fn err_text<T>(r: Result<T>) -> String {
    match r {
      Ok(_) => panic!("ожидалась ошибка"),
      Err(e) => e.to_string(),
    }
  }

  #[test]
  fn provider_dispatch_by_id() {
    let core = Core::new_empty();
    assert_eq!(core.provider(ServiceId::Sc).unwrap().id(), ServiceId::Sc);
    assert_eq!(core.provider(ServiceId::Ym).unwrap().id(), ServiceId::Ym);
    assert_eq!(core.provider(ServiceId::Yt).unwrap().id(), ServiceId::Yt);
    assert_eq!(core.provider(ServiceId::Vk).unwrap().id(), ServiceId::Vk);
    assert_eq!(core.provider(ServiceId::Local).unwrap().id(), ServiceId::Local);
    assert_eq!(core.provider(ServiceId::Sp).unwrap().id(), ServiceId::Sp);
  }

  #[tokio::test]
  async fn local_stream_only_from_index() {
    use crate::local::fixtures::{temp_dir, write_wav};
    let core = Core::new_empty();
    let dir = temp_dir("svc-local");
    let path = dir.join("a.flac");
    write_wav(&path, 100);
    let r = crate::local::local_ref(&path);
    // не в индексе — «Файл не найден», путь из ref не читается
    assert_eq!(err_text(core.resolve(&r, false).await), local::NOT_FOUND);
    let f = crate::store::LocalFile {
      ref_: r.clone(),
      path: path.to_string_lossy().into_owned(),
      mtime: 0,
      size: 0,
      title: "T".into(),
      artist: String::new(),
      album: None,
      duration_ms: 0,
      cover_path: None,
    };
    core.local.replace(&[f]);
    match core.resolve(&r, false).await.unwrap() {
      Source::File { url, quality } => {
        assert_eq!(url, path.to_string_lossy());
        assert_eq!(quality, "FLAC · файл");
      }
      other => panic!("{other:?}"),
    }
    // файл удалили — сразу «не найден», без кэша
    std::fs::remove_file(&path).unwrap();
    assert_eq!(err_text(core.resolve(&r, false).await), local::NOT_FOUND);
    // у локальных нет страниц и похожих
    assert!(core.similar(&r, 5).await.unwrap().is_empty());
    assert!(core.search("x", "local", 5).await.unwrap().is_empty());
    let _ = std::fs::remove_dir_all(dir);
  }

  #[tokio::test]
  async fn search_unknown_src_text() {
    let core = Core::new_empty();
    assert_eq!(err_text(core.search("x", "zz", 5).await), "неизвестный источник zz");
    // как и раньше, поиск принимает только короткий id
    assert_eq!(err_text(core.search("x", "soundcloud", 5).await), "неизвестный источник soundcloud");
    assert_eq!(err_text(core.search_more("x", "", 5).await), "неизвестный источник ");
  }

  #[tokio::test]
  async fn ref_dispatch_errors_unchanged() {
    let core = Core::new_empty();
    assert_eq!(err_text(core.artist_page("nocolon").await), "плохой ref nocolon");
    assert_eq!(err_text(core.artist_page("xx:1").await), "неизвестный исполнитель xx:1");
    assert_eq!(err_text(core.artist_tracks("sc:1").await), "неизвестный исполнитель sc:1");
    assert_eq!(err_text(core.artist_reposts("scalb:1", 20).await), "неизвестный исполнитель scalb:1");
    assert_eq!(err_text(core.artist_top("spalb:1", 5).await), "неизвестный исполнитель spalb:1");
    assert_eq!(err_text(core.artist_albums("scalb:1").await), "неизвестный исполнитель scalb:1");
    assert_eq!(err_text(core.album_page("sca:1").await), "неизвестный альбом sca:1");
    assert_eq!(err_text(core.album_page("spa:1").await), "неизвестный альбом spa:1");
    assert_eq!(err_text(core.similar("scpl:1", 5).await), "неизвестный трек scpl:1");
    assert_eq!(err_text(core.similar("sppl:1", 5).await), "неизвестный трек sppl:1");
    assert_eq!(err_text(core.service_playlist("pl_x").await), "плохой ref pl_x");
    assert_eq!(err_text(core.service_playlist("sc:1").await), "неизвестный плейлист sc:1");
    assert_eq!(err_text(core.service_playlist("sp:1").await), "неизвестный плейлист sp:1");
    assert_eq!(err_text(core.resolve("nocolon", false).await), "плохой ref nocolon");
    assert_eq!(err_text(core.resolve("scalb:1", false).await), "неизвестный источник в scalb:1");
    assert_eq!(err_text(core.resolve("spalb:1", false).await), "неизвестный источник в spalb:1");
  }

  /// Без Яндекса ветки ym доходят до своего провайдера и отвечают прежними текстами — без сети.
  #[tokio::test]
  async fn ym_dispatch_without_account() {
    let core = Core::new_empty();
    let not_connected = "Яндекс Музыка не подключена — открой Настройки → Сервисы";
    assert_eq!(err_text(core.search("x", "ym", 5).await), not_connected);
    assert_eq!(err_text(core.search_more("x", "ym", 5).await), not_connected);
    assert_eq!(err_text(core.artist_page("yma:1").await), not_connected);
    assert_eq!(err_text(core.artist_tracks("yma:1").await), not_connected);
    assert_eq!(err_text(core.artist_top("yma:1", 5).await), not_connected);
    assert_eq!(err_text(core.artist_albums("yma:1").await), not_connected);
    assert_eq!(err_text(core.album_page("ymalb:1").await), not_connected);
    assert_eq!(err_text(core.similar("ym:1", 5).await), not_connected);
    assert_eq!(err_text(core.service_playlist("ympl:42:1003").await), not_connected);
    assert_eq!(err_text(core.service_playlist("ympl:likes").await), "Яндекс Музыка не подключена");
    assert_eq!(err_text(core.service_playlist("ympl:42").await), "плохой ref ympl:42");
    assert_eq!(err_text(core.resolve("ym:1", false).await), "Яндекс Музыка не подключена");
    assert_eq!(err_text(core.resolve("ym:1", true).await), "Яндекс Музыка не подключена");
  }

  /// Без VK ветки vk доходят до своего провайдера и отвечают без сети.
  #[tokio::test]
  async fn vk_dispatch_without_account() {
    let core = Core::new_empty();
    let not_connected = "VK Музыка не подключена — открой Настройки → Сервисы";
    assert_eq!(err_text(core.search("x", "vk", 5).await), not_connected);
    assert_eq!(err_text(core.search_more("x", "vk", 5).await), not_connected);
    assert_eq!(err_text(core.artist_page("vka:1").await), not_connected);
    assert_eq!(err_text(core.artist_tracks("vka:1").await), not_connected);
    assert_eq!(err_text(core.artist_albums("vka:1").await), not_connected);
    assert_eq!(err_text(core.album_page("vkalb:-1_2_ab").await), not_connected);
    assert_eq!(err_text(core.similar("vk:1_2", 5).await), not_connected);
    assert_eq!(err_text(core.service_playlist("vkpl:1_2").await), not_connected);
    assert_eq!(err_text(core.service_playlist("vkpl:likes").await), "VK Музыка не подключена");
    assert_eq!(err_text(core.service_playlist("vkpl:x").await), "плохой ref vkpl:x");
    assert_eq!(err_text(core.resolve("vk:1_2", false).await), "VK Музыка не подключена");
    assert_eq!(err_text(core.resolve("vk:1_2_key", true).await), "плохой ref vk:1_2_key");
    assert!(core.service_playlists("vk").await.unwrap().is_empty());
    assert_eq!(core.status().await.vk.connected, false);
  }

  /// Ссылка из поиска играет без второго запроса к VK; протухла (`fresh`) — идём в VK.
  #[tokio::test]
  async fn vk_stream_uses_seen_url() {
    let core = Core::new_empty();
    let audio = |url: &str| vk_api::audio_from_json(&serde_json::json!({
      "id": 2, "owner_id": -1, "title": "t", "artist": "a", "access_key": "k", "url": url
    })).unwrap();
    let tracks = core.vk_keep(vec![audio("https://cs1.vkuseraudio.net/s/v1/ac/x/index.m3u8")]);
    assert_eq!(tracks[0].ref_, "vk:-1_2");
    assert!(matches!(core.resolve("vk:-1_2", false).await.unwrap(), Source::Hls { .. }));
    // fresh — к VK, а он не подключён
    assert_eq!(err_text(core.resolve("vk:-1_2", true).await), "VK Музыка не подключена");
    core.vk_keep(vec![audio("https://vk.com/mp3/audio_api_unavailable.mp3")]);
    core.streams.lock().unwrap().clear();
    assert_eq!(err_text(core.resolve("vk:-1_2", false).await), "VK Музыка: VK не отдал ссылку на трек");
  }

  /// Ссылка старше `STREAM_TTL` не берётся — идём в VK.
  #[tokio::test]
  async fn vk_seen_url_expires() {
    let core = Core::new_empty();
    let Some(old) = Instant::now().checked_sub(STREAM_TTL + Duration::from_secs(1)) else { return };
    core.vk_seen.lock().unwrap().insert("vk:-1_2".into(), ("https://cs1.vkuseraudio.net/s/v1/ac/x/index.m3u8".into(), old));
    assert_eq!(err_text(core.resolve("vk:-1_2", false).await), "VK Музыка не подключена");
  }

  /// После перезапуска (пустой `vk_seen`, новое ядро) access_key трека берётся с диска.
  #[test]
  fn vk_key_survives_restart() {
    let dir = std::env::temp_dir().join(format!("sonar-vkrestart-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join("vk-keys.json");
    let before = Core::new_empty();
    before.open_vk_keys(file.clone());
    let audio = vk_api::audio_from_json(&serde_json::json!({
      "id": 2, "owner_id": -1, "title": "t", "artist": "a", "access_key": "k7", "url": "https://cs1.vkuseraudio.net/a.mp3"
    }))
    .unwrap();
    before.vk_keep(vec![audio]);
    drop(before);

    let after = Core::new_empty();
    after.open_vk_keys(file);
    assert!(after.vk_seen.lock().unwrap().is_empty());
    assert_eq!(after.vk_full_id("-1_2"), "-1_2_k7");
    assert_eq!(after.vk_full_id("-1_3"), "-1_3");
    let _ = std::fs::remove_dir_all(&dir);
  }

  #[tokio::test]
  async fn connect_vk_rejects_empty_token() {
    let core = Core::new_empty();
    let e = err_text(core.connect_vk(vk_api::Creds { token: "  ".into() }).await);
    assert_eq!(e, "Вставь токен VK");
    assert!(!core.status().await.vk.connected);
  }

  #[tokio::test]
  async fn service_playlists_accepts_short_id_and_key() {
    let core = Core::new_empty();
    for s in ["sc", "soundcloud", "ym", "yandex", "yt", "youtube", "vk"] {
      assert!(core.service_playlists(s).await.unwrap().is_empty(), "{s}");
    }
    assert_eq!(err_text(core.service_playlists("zz").await), "неизвестный сервис zz");
    // лайки SoundCloud без OAuth-токена — прежний текст
    assert_eq!(err_text(core.service_playlist("scpl:likes").await), "Нужен OAuth-токен SoundCloud");
  }

  #[tokio::test]
  async fn list_shape_empty() {
    let list = Core::new_empty().list().await;
    let ids: Vec<ServiceId> = list.iter().map(|e| e.info.id).collect();
    assert_eq!(ids, [ServiceId::Sc, ServiceId::Ym, ServiceId::Yt, ServiceId::Vk, ServiceId::Sp, ServiceId::Local]);
    assert!(list.iter().all(|e| !e.connected && e.account_name.is_none() && e.avatar_url.is_none() && e.premium.is_none()));
    let json = serde_json::to_value(&list).unwrap();
    let keys = [
      "id", "key", "name", "color", "icon", "icon_mono", "prefixes", "caps", "implemented", "connected", "account_name",
      "avatar_url", "premium",
    ];
    for entry in json.as_array().unwrap() {
      let obj = entry.as_object().unwrap();
      let mut got: Vec<&str> = obj.keys().map(String::as_str).collect();
      let mut want = keys.to_vec();
      got.sort_unstable();
      want.sort_unstable();
      assert_eq!(got, want);
    }
    assert_eq!(json[0]["id"], "sc");
    assert_eq!(json[0]["key"], "soundcloud");
    assert_eq!(json[0]["prefixes"]["playlist"], "scpl");
    assert_eq!(json[2]["caps"]["key"], true);
    assert_eq!(json[2]["implemented"], true);
    assert_eq!(json[3]["implemented"], true);
    assert_eq!(json[4]["implemented"], true);
    assert_eq!(json[5]["icon"], Value::Null);
    assert_eq!(json[5]["prefixes"]["album"], Value::Null);
  }

  #[tokio::test]
  async fn list_with_soundcloud() {
    let creds = soundcloud::Creds { client_id: "id".into(), oauth_token: None };
    let core = Core::with_soundcloud(creds);
    *core.sc.write().await = Some(Stored {
      creds: soundcloud::Creds { client_id: "id".into(), oauth_token: None },
      account: Account { name: Some("dj".into()), ..Account::default() },
    });
    let list = core.list().await;
    assert!(list[0].connected);
    assert_eq!(list[0].account_name.as_deref(), Some("dj"));
    assert!(!list[1].connected);
    assert!(list[2..].iter().all(|e| !e.connected));
    let st = core.status().await;
    assert!(st.soundcloud.connected && st.soundcloud.premium.is_none());
  }

  #[test]
  fn status_carries_premium() {
    let stored = Some(Stored { creds: (), account: Account { premium: Some(true), ..Account::default() } });
    assert_eq!(status(&stored).premium, Some(true));
    assert_eq!(status::<()>(&None).premium, None);
  }

  /// Без ключа Spotify ветки sp доходят до провайдера и отвечают «не подключён» — без сети.
  #[tokio::test]
  async fn sp_dispatch_without_account() {
    let core = Core::new_empty();
    let nc = spotify::NOT_CONNECTED;
    assert_eq!(err_text(core.search("x", "sp", 5).await), nc);
    assert_eq!(err_text(core.search_more("x", "sp", 5).await), nc);
    assert_eq!(err_text(core.artist_page("spa:1").await), nc);
    assert_eq!(err_text(core.artist_tracks("spa:1").await), nc);
    assert_eq!(err_text(core.album_page("spalb:1").await), nc);
    assert_eq!(err_text(core.service_playlist("sppl:1").await), nc);
    assert_eq!(err_text(core.service_playlist("sppl:likes").await), nc);
    // плейлисты аккаунта без ключа — пусто, похожих у Spotify нет
    assert!(core.service_playlists("spotify").await.unwrap().is_empty());
    assert!(core.similar("sp:1", 5).await.unwrap().is_empty());
  }

  /// Трек Spotify без Premium-сборки не играет, а просит резервный сервис — без паники и сети.
  #[cfg(not(feature = "spotify-playback"))]
  #[tokio::test]
  async fn sp_stream_needs_fallback() {
    let core = Core::new_empty();
    assert_eq!(err_text(core.resolve("sp:4uLU6hMCjMI75M1A2tKUQC", false).await), spotify::NEEDS_FALLBACK);
    *core.sp.write().await = Some(Stored {
      creds: spotify::Creds { sp_dc: "x".repeat(40) },
      account: Account { premium: Some(true), ..Account::default() },
    });
    assert_eq!(err_text(core.resolve("sp:4uLU6hMCjMI75M1A2tKUQC", true).await), spotify::NEEDS_FALLBACK);
  }

  #[tokio::test]
  async fn connect_spotify_rejects_garbage_without_network() {
    let core = Core::new_empty();
    assert_eq!(err_text(core.connect_spotify("  ").await), "Вставь значение cookie sp_dc с open.spotify.com");
    assert_eq!(err_text(core.connect_spotify("sp_dc=a b").await), "Вставь значение cookie sp_dc с open.spotify.com");
  }

  #[tokio::test]
  async fn status_and_list_show_spotify() {
    let core = Core::new_empty();
    *core.sp.write().await = Some(Stored {
      creds: spotify::Creds { sp_dc: "x".repeat(40) },
      account: Account { name: Some("F".into()), premium: Some(false), ..Account::default() },
    });
    let st = core.status().await;
    assert!(st.spotify.connected && st.spotify.premium == Some(false));
    let list = core.list().await;
    let sp = list.iter().find(|e| e.info.id == ServiceId::Sp).unwrap();
    assert!(sp.connected && sp.account_name.as_deref() == Some("F"));
    let json = serde_json::to_value(&st).unwrap();
    assert_eq!(json["spotify"]["name"], "F");
  }

  #[tokio::test]
  async fn disconnect_accepts_short_id() {
    let core = Core::new_empty();
    assert_eq!(err_text(core.disconnect("zz").await), "неизвестный сервис zz");
    assert_eq!(err_text(core.disconnect("").await), "неизвестный сервис ");
  }

  /// Без входа в YouTube Music библиотека пуста, «Лайки» просят подключить — без сети.
  #[tokio::test]
  async fn yt_library_without_account() {
    let core = Core::new_empty();
    assert!(core.service_playlists("youtube").await.unwrap().is_empty());
    assert_eq!(err_text(core.service_playlist("ytpl:likes").await), "YouTube Music не подключён — открой Настройки → Сервисы");
    assert!(!core.status().await.youtube.connected);
  }

  #[test]
  fn yt_quality_values() {
    assert!(yt_high(None));
    assert!(yt_high(Some("high")));
    assert!(!yt_high(Some("normal")));
  }

  #[test]
  fn only_youtube_stream_is_retried() {
    assert!(retries_resolve("yt:q7mwXbOw58g"));
    for r in ["sc:1", "ym:2", "ytalb:MPREb_x", "ytpl:likes", "", "yt"] {
      assert!(!retries_resolve(r), "{r}");
    }
  }
}

#[cfg(test)]
mod live_twin {
  use super::*;

  #[tokio::test]
  #[ignore = "живые SoundCloud и Яндекс на ключах из keyring: печатает только формат"]
  async fn sc_tracks_play_from_yandex() {
    let core = Core::new();
    for q in ["EsDeeKid 4 Raws", "ONDA ANDAR FIRE", "kizaru дежавю", "lil peep star shopping"] {
      let found = core.search(q, "sc", 3).await.unwrap();
      let Some(t) = found.first() else { continue };
      let src = core.resolve(&t.ref_, false).await.unwrap();
      let quality = match src {
        Source::File { quality, .. } | Source::Hls { quality, .. } => quality,
      };
      println!("{q}: SC «{} — {}» → {quality}", t.artist, t.title);
    }
  }
}
