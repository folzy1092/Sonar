//! Медиа-клавиши и системная плашка Windows (SMTC) через `souvlaki`.
//! WebView2 свои медиа-клавиши не ловит (флаги в tauri.conf.json) — их ведёт Rust:
//! нажатие → событие `media-control` в интерфейс; интерфейс → `media_update` с названием и статусом.

use serde::Deserialize;
use souvlaki::{MediaControlEvent, MediaControls, MediaMetadata, MediaPlayback, MediaPosition, PlatformConfig};
use std::sync::Mutex;
use std::time::Duration;
use tauri::{AppHandle, Emitter, WebviewWindow};

pub struct Media(pub Mutex<Option<MediaControls>>);

// SMTC-объекты Windows «agile» — ими можно пользоваться из любого потока.
unsafe impl Send for Media {}
unsafe impl Sync for Media {}

pub fn attach(app: &AppHandle, window: &WebviewWindow) -> Option<MediaControls> {
  let hwnd = window.hwnd().ok()?;
  let config = PlatformConfig { display_name: "Sonar", dbus_name: "sonar", hwnd: Some(hwnd.0 as *mut _) };
  let mut controls = MediaControls::new(config).ok()?;
  let app = app.clone();
  controls
    .attach(move |e| {
      let payload = match e {
        MediaControlEvent::Play => "play".to_owned(),
        MediaControlEvent::Pause => "pause".to_owned(),
        MediaControlEvent::Toggle => "toggle".to_owned(),
        MediaControlEvent::Next => "next".to_owned(),
        MediaControlEvent::Previous => "previous".to_owned(),
        MediaControlEvent::Stop => "stop".to_owned(),
        MediaControlEvent::SetPosition(MediaPosition(d)) => format!("seek:{}", d.as_millis()),
        _ => return,
      };
      let _ = app.emit("media-control", payload);
    })
    .ok()?;
  Some(controls)
}

#[derive(Deserialize, Clone, Debug)]
pub struct MediaInfo {
  pub title: Option<String>,
  pub artist: Option<String>,
  pub album: Option<String>,
  pub cover_url: Option<String>,
  pub duration_ms: Option<u64>,
  pub playing: bool,
  pub position_ms: Option<u64>,
  /// false — ничего не играет (плашка скрывается).
  pub active: bool,
  /// ref трека (`sc:…` / `ym:…`) — для кнопки «Слушать в Sonar» в Discord.
  #[serde(default)]
  pub track_ref: Option<String>,
  /// Фото главного артиста — мини-значок в углу обложки в Discord.
  #[serde(default)]
  pub artist_avatar: Option<String>,
}

pub fn update(media: &Media, info: &MediaInfo) {
  let mut guard = media.0.lock().unwrap();
  let Some(c) = guard.as_mut() else { return };
  if !info.active {
    let _ = c.set_playback(MediaPlayback::Stopped);
    return;
  }
  let _ = c.set_metadata(MediaMetadata {
    title: info.title.as_deref(),
    artist: info.artist.as_deref(),
    album: info.album.as_deref(),
    cover_url: info.cover_url.as_deref(),
    duration: info.duration_ms.map(Duration::from_millis),
  });
  let progress = info.position_ms.map(|p| MediaPosition(Duration::from_millis(p)));
  let _ = c.set_playback(if info.playing { MediaPlayback::Playing { progress } } else { MediaPlayback::Paused { progress } });
}
