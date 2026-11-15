//! Discord Rich Presence («Слушает …» в профиле Discord), `integrations.discord.*` (SETTINGS.md).
//! Работает в своём потоке: Discord может быть не запущен — тогда тихо пробуем подключиться раз
//! в 15 с. Данные — те же, что для плашки Windows (`media_update`).
//! ID приложения Discord пользователь **не вводит**: сейчас он вшит в сборку (`APP_ID`, это не
//! секрет — его видит любой RPC-клиент), с появлением сервера приходит оттуда (`GET /config` →
//! `discord_app_id`, API.md §7) и подменяется через `set_app_id`.

use crate::media::MediaInfo;
use discord_rich_presence::activity::{Activity, ActivityType, Assets, StatusDisplayType, Timestamps};
use discord_rich_presence::{DiscordIpc, DiscordIpcClient};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{channel, RecvTimeoutError, Sender};
use std::sync::Mutex;
use std::time::Duration;

/// ID приложения «Sonar» в Discord (discord.com/developers → Applications). Пусто — пока владелец
/// его не создал (ROADMAP): тогда статус просто не показывается.
pub const APP_ID: &str = "1571615944449466510";

enum Msg {
  Update(MediaInfo),
  AppId(String),
  Refresh,
}

pub struct Discord {
  tx: Mutex<Sender<Msg>>,
  pub enabled: AtomicBool,
  pub cover: AtomicBool,
  pub progress: AtomicBool,
}

impl Discord {
  pub fn start() -> std::sync::Arc<Self> {
    let (tx, rx) = channel::<Msg>();
    let me = std::sync::Arc::new(Self {
      tx: Mutex::new(tx),
      enabled: AtomicBool::new(true),
      cover: AtomicBool::new(true),
      progress: AtomicBool::new(true),
    });
    let state = me.clone();
    let mut app_id = APP_ID.to_owned();
    std::thread::Builder::new()
      .name("discord-rpc".into())
      .spawn(move || {
        let mut client: Option<DiscordIpcClient> = None;
        let mut last: Option<MediaInfo> = None;
        let mut dirty = false;
        loop {
          match rx.recv_timeout(Duration::from_secs(15)) {
            Ok(Msg::Update(info)) => {
              last = Some(info);
              dirty = true;
            }
            Ok(Msg::AppId(id)) => {
              if let Some(mut c) = client.take() {
                let _ = c.close();
              }
              app_id = if id.trim().is_empty() { APP_ID.to_owned() } else { id.trim().to_owned() };
              dirty = true;
            }
            Ok(Msg::Refresh) => dirty = true,
            Err(RecvTimeoutError::Timeout) => {
              // Discord могли запустить позже — пробуем ещё раз
              if client.is_none() && last.as_ref().is_some_and(|l| l.active) {
                dirty = true;
              }
            }
            Err(RecvTimeoutError::Disconnected) => break,
          }
          if !dirty {
            continue;
          }
          dirty = false;
          let show = state.enabled.load(Ordering::Relaxed) && !app_id.is_empty() && last.as_ref().is_some_and(|l| l.active && l.playing);
          if !show {
            if let Some(c) = client.as_mut() {
              if c.clear_activity().is_err() {
                client = None;
              }
            }
            continue;
          }
          if client.is_none() {
            let mut c = DiscordIpcClient::new(&app_id);
            if c.connect().is_ok() {
              client = Some(c);
            }
          }
          let (Some(c), Some(info)) = (client.as_mut(), last.as_ref()) else { continue };
          if c.set_activity(activity(info, state.cover.load(Ordering::Relaxed), state.progress.load(Ordering::Relaxed))).is_err() {
            // Discord закрыли — переподключимся при следующем обновлении
            let _ = c.close();
            client = None;
          }
        }
      })
      .ok();
    me
  }

  fn send(&self, m: Msg) {
    let _ = self.tx.lock().unwrap().send(m);
  }

  pub fn update(&self, info: &MediaInfo) {
    self.send(Msg::Update(info.clone()));
  }

  /// ID с сервера (`GET /config`) — когда сервер появится. Пустой — вернуть вшитый `APP_ID`.
  #[allow(dead_code)]
  pub fn set_app_id(&self, id: String) {
    self.send(Msg::AppId(id));
  }

  /// Поменялись выключатели — перерисовать статус.
  pub fn refresh(&self) {
    self.send(Msg::Refresh);
  }
}

fn activity(info: &MediaInfo, cover: bool, progress: bool) -> Activity<'_> {
  // Discord требует 2–128 символов
  let clip = |s: &str| -> String {
    let s: String = s.chars().take(128).collect();
    if s.chars().count() < 2 { format!("{s}  ") } else { s }
  };
  let title = clip(info.title.as_deref().unwrap_or("Sonar"));
  let artist = clip(info.artist.as_deref().unwrap_or(""));
  let mut a = Activity::new()
    .activity_type(ActivityType::Listening)
    .status_display_type(StatusDisplayType::Details)
    .details(title)
    .state(artist);
  let mut assets = Assets::new().large_text(clip(info.album.as_deref().unwrap_or("Sonar")));
  if cover {
    if let Some(url) = info.cover_url.as_deref().filter(|u| u.starts_with("https://")) {
      assets = assets.large_image(url.to_owned());
    }
  }
  a = a.assets(assets);
  if progress {
    if let (Some(pos), Some(dur)) = (info.position_ms, info.duration_ms.filter(|d| *d > 0)) {
      let now = crate::store::now_ms();
      let start = now - pos as i64;
      a = a.timestamps(Timestamps::new().start(start).end(start + dur as i64));
    }
  }
  a
}
