//! Масштаб интерфейса (pc/Screenshot_3): «в окне» и «на весь экран» — отдельно
//! (`appearance.scale_window`, `appearance.scale_fullscreen`, 75–125 %). Окно развернули или вернули —
//! зум WebView меняется сам. «На весь экран» = 0 — «Авто»: как в окне.

use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use tauri::{Manager, WebviewWindow, WindowEvent};

static WINDOW: AtomicU32 = AtomicU32::new(100);
static FULL: AtomicU32 = AtomicU32::new(100);
static MAXIMIZED: AtomicBool = AtomicBool::new(false);

/// Значение из настроек → хранимое: `0` и меньше — «Авто», остальное — 50–200 %.
fn clamp(p: f64) -> u32 {
  if p <= 0.0 {
    return 0;
  }
  p.clamp(50.0, 200.0).round() as u32
}

/// Масштаб для состояния окна: развёрнутое без своего значения («Авто») берёт масштаб окна.
fn pick(maximized: bool, window: u32, full: u32) -> u32 {
  let window = if window == 0 { 100 } else { window };
  if maximized && full != 0 { full } else { window }
}

/// Применить подходящий масштаб к окну.
pub fn apply(w: &WebviewWindow) {
  let max = w.is_maximized().unwrap_or(false) || w.is_fullscreen().unwrap_or(false);
  MAXIMIZED.store(max, Ordering::Relaxed);
  let pct = pick(max, WINDOW.load(Ordering::Relaxed), FULL.load(Ordering::Relaxed));
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

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn auto_fullscreen_follows_window() {
    assert_eq!(pick(true, 110, 0), 110);
    assert_eq!(pick(true, 110, 125), 125);
    assert_eq!(pick(false, 90, 125), 90);
  }

  #[test]
  fn clamp_keeps_auto_and_bounds() {
    assert_eq!(clamp(0.0), 0);
    assert_eq!(clamp(-5.0), 0);
    assert_eq!(clamp(30.0), 50);
    assert_eq!(clamp(110.4), 110);
    assert_eq!(pick(false, 0, 0), 100);
  }
}
