//! Масштаб интерфейса (pc/Screenshot_3): «в окне» и «на весь экран» — отдельно
//! (`appearance.scale_window`, `appearance.scale_fullscreen`, 75–125 %). Окно развернули или вернули —
//! зум WebView меняется сам.

use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use tauri::{Manager, WebviewWindow, WindowEvent};

static WINDOW: AtomicU32 = AtomicU32::new(100);
static FULL: AtomicU32 = AtomicU32::new(100);
static MAXIMIZED: AtomicBool = AtomicBool::new(false);

fn clamp(p: f64) -> u32 {
  p.clamp(50.0, 200.0).round() as u32
}

/// Применить подходящий масштаб к окну.
pub fn apply(w: &WebviewWindow) {
  let max = w.is_maximized().unwrap_or(false) || w.is_fullscreen().unwrap_or(false);
  MAXIMIZED.store(max, Ordering::Relaxed);
  let pct = if max { FULL.load(Ordering::Relaxed) } else { WINDOW.load(Ordering::Relaxed) };
  let _ = w.set_zoom(pct as f64 / 100.0);
}

/// Задать масштаб: `window` или `fullscreen`, в процентах.
pub fn set(w: &WebviewWindow, kind: &str, percent: f64) {
  match kind {
    "fullscreen" => FULL.store(clamp(percent), Ordering::Relaxed),
    _ => WINDOW.store(clamp(percent), Ordering::Relaxed),
  }
  apply(w);
}

/// При запуске: значения из настроек и слежение за разворачиванием окна.
pub fn setup(app: &tauri::App, window_pct: Option<f64>, full_pct: Option<f64>) {
  if let Some(p) = window_pct {
    WINDOW.store(clamp(p), Ordering::Relaxed);
  }
  if let Some(p) = full_pct {
    FULL.store(clamp(p), Ordering::Relaxed);
  }
  let Some(w) = app.get_webview_window("main") else { return };
  apply(&w);
  let win = w.clone();
  w.on_window_event(move |e| {
    if let WindowEvent::Resized(_) = e {
      let max = win.is_maximized().unwrap_or(false) || win.is_fullscreen().unwrap_or(false);
      if max != MAXIMIZED.load(Ordering::Relaxed) {
        apply(&win);
      }
    }
  });
}
