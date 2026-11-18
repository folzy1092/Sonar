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
  // окно нужно только SMTC Windows; на других системах (тесты в Linux) — без него
  #[cfg(windows)]
  let hwnd = Some(window.hwnd().ok()?.0 as *mut _);
  #[cfg(not(windows))]
  let hwnd = {
    let _ = window;
    None
  };
  let config = PlatformConfig { display_name: "Sonar", dbus_name: "sonar", hwnd };
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

/// Обложка для SMTC: система не откроет адрес `sonarcover` из WebView — локальному файлу отдаём
/// путь к обложке в кэше (`file://…`, souvlaki читает его с диска); нет файла — без обложки.
fn smtc_cover(url: &str, cover_dir: Option<&std::path::Path>) -> Option<String> {
  let Some(name) = crate::local::cover_name_from_url(url) else { return Some(url.to_owned()) };
  let path = cover_dir?.join(name);
  path.is_file().then(|| format!("file://{}", path.display()))
}

pub fn update(media: &Media, info: &MediaInfo) {
  let mut guard = media.0.lock().unwrap();
  let Some(c) = guard.as_mut() else { return };
  if !info.active {
    let _ = c.set_playback(MediaPlayback::Stopped);
    return;
  }
  let cover = info.cover_url.as_deref().and_then(|u| smtc_cover(u, crate::stream::cover_dir().map(|d| d.as_path())));
  let _ = c.set_metadata(MediaMetadata {
    title: info.title.as_deref(),
    artist: info.artist.as_deref(),
    album: info.album.as_deref(),
    cover_url: cover.as_deref(),
    duration: info.duration_ms.map(Duration::from_millis),
  });
  let progress = info.position_ms.map(|p| MediaPosition(Duration::from_millis(p)));
  let _ = c.set_playback(if info.playing { MediaPlayback::Playing { progress } } else { MediaPlayback::Paused { progress } });
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn local_cover_goes_to_smtc_as_file_path() {
    let dir = crate::local::fixtures::temp_dir("smtc-cover");
    let name = format!("local-{}.png", "a".repeat(40));
    let url = crate::local::cover_url(&name);
    // обложки нет на диске — без обложки, а не битый адрес
    assert_eq!(smtc_cover(&url, Some(&dir)), None);
    std::fs::write(dir.join(&name), crate::local::fixtures::PNG).unwrap();
    assert_eq!(smtc_cover(&url, Some(&dir)), Some(format!("file://{}", dir.join(&name).display())));
    assert_eq!(smtc_cover(&url, None), None);
    // обложки сервисов — как были
    let web = "https://i1.sndcdn.com/artworks-1-t500x500.jpg";
    assert_eq!(smtc_cover(web, Some(&dir)).as_deref(), Some(web));
    let _ = std::fs::remove_dir_all(dir);
  }
}
