//! Горячие клавиши по всей системе (Система → Горячие клавиши, решение владельца 2026-11-17).
//! Работают, даже когда Sonar свёрнут или спрятан в трей. Сочетания приходят из интерфейса
//! (`hotkeys.map` в настройках, вид `Ctrl+Alt+Space` — коды клавиш как у `KeyboardEvent.code`).
//! «Показать / скрыть окно» делает сам Rust, остальное — событие `hotkey` в интерфейс
//! (плеер слушает его так же, как медиа-клавиши).

use std::collections::HashMap;
use std::sync::Mutex;
use tauri::plugin::TauriPlugin;
use tauri::{AppHandle, Emitter, Manager, Runtime};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

/// Действия, которые можно повесить на клавиши.
pub const ACTIONS: &[&str] = &["toggle", "next", "prev", "like", "volume_up", "volume_down", "window"];

/// Зарегистрированные сейчас: id сочетания → действие.
static BOUND: Mutex<Vec<(u32, String)>> = Mutex::new(Vec::new());

pub fn plugin<R: Runtime>() -> TauriPlugin<R> {
  tauri_plugin_global_shortcut::Builder::new()
    .with_handler(|app, shortcut, event| {
      if event.state() != ShortcutState::Pressed {
        return;
      }
      let id = shortcut.id();
      let action = BOUND.lock().unwrap().iter().find(|(k, _)| *k == id).map(|(_, a)| a.clone());
      match action.as_deref() {
        Some("window") => toggle_window(app),
        Some(a) => {
          let _ = app.emit("hotkey", a);
        }
        None => {}
      }
    })
    .build()
}

fn toggle_window<R: Runtime>(app: &AppHandle<R>) {
  let Some(w) = app.get_webview_window("main") else { return };
  let shown = w.is_visible().unwrap_or(false) && !w.is_minimized().unwrap_or(false);
  if shown && w.is_focused().unwrap_or(false) {
    let _ = w.hide();
  } else {
    let _ = w.unminimize();
    let _ = w.show();
    let _ = w.set_focus();
  }
}

/// Разобрать сочетание из интерфейса. Без модификатора не берём: голая буква перехватила бы
/// набор текста во всех программах.
pub fn parse(accel: &str) -> Option<Shortcut> {
  let parts: Vec<&str> = accel.split('+').map(str::trim).filter(|p| !p.is_empty()).collect();
  let mods = ["ctrl", "control", "alt", "shift", "super", "win", "meta"];
  let has_mod = parts.iter().any(|p| mods.contains(&p.to_ascii_lowercase().as_str()));
  let key_ok = parts.last().is_some_and(|k| !mods.contains(&k.to_ascii_lowercase().as_str()));
  if !has_mod || !key_ok {
    return None;
  }
  let norm: Vec<String> = parts
    .iter()
    .map(|p| match p.to_ascii_lowercase().as_str() {
      "win" | "meta" => "Super".to_owned(),
      _ => (*p).to_owned(),
    })
    .collect();
  norm.join("+").parse().ok()
}

/// Перерегистрировать все сочетания. Вернёт действия, чьё сочетание не встало (неверное или
/// уже занято другой программой), — интерфейс подсветит их.
#[tauri::command]
pub fn set_hotkeys(app: AppHandle, keys: HashMap<String, String>) -> Vec<String> {
  let gs = app.global_shortcut();
  let _ = gs.unregister_all();
  let mut bound = BOUND.lock().unwrap();
  bound.clear();
  let mut failed = Vec::new();
  for action in ACTIONS {
    let Some(accel) = keys.get(*action).filter(|s| !s.is_empty()) else { continue };
    let Some(sc) = parse(accel) else {
      failed.push((*action).to_owned());
      continue;
    };
    // одно сочетание на два действия — второе не ставим
    if bound.iter().any(|(id, _)| *id == sc.id()) {
      failed.push((*action).to_owned());
      continue;
    }
    match gs.register(sc) {
      Ok(()) => bound.push((sc.id(), (*action).to_owned())),
      Err(e) => {
        log::info!("горячая клавиша {accel} ({action}) не встала: {e}");
        failed.push((*action).to_owned());
      }
    }
  }
  failed
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn parses_codes_and_needs_modifier() {
    assert!(parse("Ctrl+Alt+Space").is_some());
    assert!(parse("Ctrl+Alt+ArrowRight").is_some());
    assert!(parse("Ctrl+Shift+KeyL").is_some());
    assert!(parse("Alt+Equal").is_some());
    assert!(parse("Win+Digit1").is_some());
    assert!(parse("KeyL").is_none(), "без модификатора нельзя");
    assert!(parse("Ctrl+Alt").is_none(), "нужна клавиша, не только модификаторы");
    assert!(parse("").is_none());
    assert_eq!(parse("Ctrl+Alt+KeyL").map(|s| s.id()), parse("Control+Alt+KeyL").map(|s| s.id()));
  }
}
