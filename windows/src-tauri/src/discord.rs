//! Discord Rich Presence («Слушает …» в профиле Discord), `integrations.discord.*` (SETTINGS.md).
//! Работает в своём потоке: Discord может быть не запущен — тогда тихо пробуем подключиться раз
//! в 15 с. Данные — те же, что для плашки Windows (`media_update`).
//! ID приложения Discord пользователь **не вводит**: сейчас он вшит в сборку (`APP_ID`, это не
//! секрет — его видит любой RPC-клиент), с появлением сервера приходит оттуда (`GET /config` →
//! `discord_app_id`, API.md §7) и подменяется через `set_app_id`.

use crate::media::MediaInfo;
use discord_rich_presence::activity::{Activity, ActivityType, Assets, StatusDisplayType, Timestamps};
use discord_rich_presence::{DiscordIpc, DiscordIpcClient};
use discord_rich_presence::activity::Button;
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
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

/// Что в заголовке «Слушает …» (`integrations.discord.status_format`).
pub const FORMATS: [&str; 5] = ["artist", "title", "artist_title", "title_artist", "app"];

/// Сайт Sonar: страница трека по ссылке (BOT.md §2.11) и скачивание.
const SITE: &str = "https://sonar.folzy.ru";
const DOWNLOAD: &str = "https://github.com/folzy1092/Sonar/releases/latest";

pub struct Discord {
  tx: Mutex<Sender<Msg>>,
  pub enabled: AtomicBool,
  pub cover: AtomicBool,
  pub progress: AtomicBool,
  /// Индекс в `FORMATS`.
  pub format: AtomicU8,
  pub artist_photo: AtomicBool,
  pub show_paused: AtomicBool,
  pub button_listen: AtomicBool,
  pub button_download: AtomicBool,
  /// Discord запущен и принял подключение (для «Ожидание Discord…» в настройках).
  pub connected: AtomicBool,
}

/// Как показывать (снимок выключателей на момент отправки).
#[derive(Clone, Copy)]
struct Look {
  cover: bool,
  progress: bool,
  format: u8,
  artist_photo: bool,
  listen: bool,
  download: bool,
}

impl Discord {
  pub fn start() -> std::sync::Arc<Self> {
    let (tx, rx) = channel::<Msg>();
    let me = std::sync::Arc::new(Self {
      tx: Mutex::new(tx),
      enabled: AtomicBool::new(true),
      cover: AtomicBool::new(true),
      progress: AtomicBool::new(true),
      format: AtomicU8::new(0),
      artist_photo: AtomicBool::new(true),
      show_paused: AtomicBool::new(false),
      button_listen: AtomicBool::new(true),
      button_download: AtomicBool::new(true),
      connected: AtomicBool::new(false),
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
              // Discord могли запустить позже — пробуем ещё раз (и для статуса в настройках)
              if client.is_none() && state.enabled.load(Ordering::Relaxed) {
                dirty = true;
              }
            }
            Err(RecvTimeoutError::Disconnected) => break,
          }
          if !dirty {
            continue;
          }
          dirty = false;
          let enabled = state.enabled.load(Ordering::Relaxed) && !app_id.is_empty();
          if !enabled {
            if let Some(mut c) = client.take() {
              let _ = c.clear_activity();
              let _ = c.close();
            }
            state.connected.store(false, Ordering::Relaxed);
            continue;
          }
          // подключаемся, даже когда ничего не играет, — настройки показывают, видит ли нас Discord
          if client.is_none() {
            let mut c = DiscordIpcClient::new(&app_id);
            if c.connect().is_ok() {
              client = Some(c);
            }
          }
          state.connected.store(client.is_some(), Ordering::Relaxed);
          let Some(c) = client.as_mut() else { continue };
          let paused_ok = state.show_paused.load(Ordering::Relaxed);
          let shown = last.as_ref().filter(|l| l.active && (l.playing || paused_ok));
          let res = match shown {
            Some(info) => {
              let look = Look {
                cover: state.cover.load(Ordering::Relaxed),
                progress: state.progress.load(Ordering::Relaxed),
                format: state.format.load(Ordering::Relaxed),
                artist_photo: state.artist_photo.load(Ordering::Relaxed),
                listen: state.button_listen.load(Ordering::Relaxed),
                download: state.button_download.load(Ordering::Relaxed),
              };
              c.set_activity(activity(info, look))
            }
            None => c.clear_activity(),
          };
          if res.is_err() {
            // Discord закрыли — переподключимся при следующей попытке
            let _ = c.close();
            client = None;
            state.connected.store(false, Ordering::Relaxed);
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

fn activity(info: &MediaInfo, look: Look) -> Activity<'_> {
  // Discord требует 2–128 символов
  let clip = |s: &str| -> String {
    let s: String = s.chars().take(128).collect();
    if s.chars().count() < 2 { format!("{s}  ") } else { s }
  };
  let t = info.title.as_deref().unwrap_or("Sonar");
  let ar = info.artist.as_deref().unwrap_or("");
  // заголовок «Слушает …»: исполнитель (по умолчанию), трек, «исполнитель — трек», «трек — исполнитель», Sonar
  let (details, display) = match FORMATS.get(look.format as usize).copied().unwrap_or("artist") {
    "title" => (t.to_owned(), StatusDisplayType::Details),
    "artist_title" if !ar.is_empty() => (format!("{ar} — {t}"), StatusDisplayType::Details),
    "title_artist" if !ar.is_empty() => (format!("{t} — {ar}"), StatusDisplayType::Details),
    "app" => (t.to_owned(), StatusDisplayType::Name),
    _ if !ar.is_empty() => (t.to_owned(), StatusDisplayType::State),
    _ => (t.to_owned(), StatusDisplayType::Details),
  };
  let mut a = Activity::new()
    .activity_type(ActivityType::Listening)
    .status_display_type(display)
    .details(clip(&details))
    .state(clip(ar));
  // Ассет «sonar» загружен в Discord Developer Portal → Rich Presence → Art Assets (знак Sonar 1024×1024):
  // без обложки он большой картинкой; в углу — пауза, фото артиста или знак Sonar.
  let mut assets = Assets::new().large_text(clip(info.album.as_deref().unwrap_or("Sonar")));
  let cover_url = info.cover_url.as_deref().filter(|u| look.cover && u.starts_with("https://"));
  let avatar = info.artist_avatar.as_deref().filter(|u| look.artist_photo && u.starts_with("https://"));
  assets = match cover_url {
    Some(url) => assets.large_image(url.to_owned()),
    None => assets.large_image("sonar"),
  };
  assets = if !info.playing {
    assets.small_image("sonar").small_text("На паузе")
  } else if let Some(av) = avatar {
    assets.small_image(av.to_owned()).small_text(clip(ar))
  } else if cover_url.is_some() {
    assets.small_image("sonar").small_text("Sonar")
  } else {
    assets
  };
  a = a.assets(assets);
  if look.progress && info.playing {
    if let (Some(pos), Some(dur)) = (info.position_ms, info.duration_ms.filter(|d| *d > 0)) {
      let now = crate::store::now_ms();
      let start = now - pos as i64;
      a = a.timestamps(Timestamps::new().start(start).end(start + dur as i64));
    }
  }
  let mut buttons = Vec::new();
  if look.listen {
    if let Some(r) = info.track_ref.as_deref().filter(|r| r.starts_with("sc:") || r.starts_with("ym:")) {
      buttons.push(Button::new("Слушать в Sonar", format!("{SITE}/t/{r}")));
    }
  }
  if look.download {
    buttons.push(Button::new("Скачать Sonar", DOWNLOAD));
  }
  a.buttons(buttons)
}
