//! «Тише во время звонков» (Аудио): пока другое приложение пишет с микрофона (звонок, голосовой
//! чат Discord / Telegram / Zoom / Teams), интерфейс плавно приглушает музыку. Признак — активный
//! сеанс записи на устройстве связи Windows от чужого процесса (тот же, по которому система
//! показывает значок «микрофон используется»). Опрос раз в 1,5 с, событие `call:active` — только
//! при смене состояния.

use std::time::Duration;
use tauri::{AppHandle, Emitter};

pub fn start(app: AppHandle) {
  std::thread::Builder::new()
    .name("calls".into())
    .spawn(move || {
      #[cfg(windows)]
      unsafe {
        use windows::Win32::System::Com::{CoInitializeEx, COINIT_MULTITHREADED};
        let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
      }
      let mut last = false;
      loop {
        let now = mic_busy().unwrap_or(false);
        if now != last {
          last = now;
          let _ = app.emit("call:active", now);
        }
        std::thread::sleep(Duration::from_millis(1500));
      }
    })
    .ok();
}

/// Пишет ли сейчас с микрофона связи (или с микрофона по умолчанию) другой процесс.
#[cfg(windows)]
fn mic_busy() -> windows::core::Result<bool> {
  use windows::core::Interface;
  use windows::Win32::Media::Audio::{
    eCapture, eCommunications, eConsole, AudioSessionStateActive, IAudioSessionControl2, IAudioSessionManager2, IMMDeviceEnumerator,
    MMDeviceEnumerator,
  };
  use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_ALL};

  let own = std::process::id();
  unsafe {
    let en: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
    let mut ids = Vec::new();
    for role in [eCommunications, eConsole] {
      let Ok(dev) = en.GetDefaultAudioEndpoint(eCapture, role) else { continue };
      let id = dev.GetId().ok().map(|p| p.to_string().unwrap_or_default());
      if ids.contains(&id) {
        continue;
      }
      ids.push(id);
      let mgr: IAudioSessionManager2 = dev.Activate(CLSCTX_ALL, None)?;
      let list = mgr.GetSessionEnumerator()?;
      for i in 0..list.GetCount()? {
        let Ok(ctl) = list.GetSession(i) else { continue };
        if ctl.GetState().ok() != Some(AudioSessionStateActive) {
          continue;
        }
        let Ok(c2) = ctl.cast::<IAudioSessionControl2>() else { continue };
        // системные звуки и наш собственный процесс не считаются
        if c2.IsSystemSoundsSession().0 == 0 {
          continue;
        }
        let pid = c2.GetProcessId().unwrap_or(0);
        if pid != 0 && pid != own {
          return Ok(true);
        }
      }
    }
  }
  Ok(false)
}

#[cfg(not(windows))]
fn mic_busy() -> Result<bool, ()> {
  Ok(false)
}
