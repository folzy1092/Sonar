//! Память WebView2 (2026-11-27): окно спрятано в трей или свёрнуто — просим WebView2 держать поменьше памяти
//! (`MemoryUsageTargetLevel = Low`: сбрасывает кэши картинок и раскладки, скрипты и звук работают дальше).
//! Окно снова на экране — обычный уровень. Без Windows — ничего не делает.

use std::sync::atomic::{AtomicBool, Ordering};
use tauri::WebviewWindow;

/// Последний выставленный уровень: не дёргать WebView2 на каждое событие окна.
static LOW: AtomicBool = AtomicBool::new(false);

/// `low = true` — окно не видно (трей, свёрнуто), `false` — снова на экране.
pub fn set_low(w: &WebviewWindow, low: bool) {
  if LOW.swap(low, Ordering::Relaxed) == low {
    return;
  }
  #[cfg(windows)]
  {
    let _ = w.with_webview(move |wv| {
      use webview2_com::Microsoft::Web::WebView2::Win32::{
        ICoreWebView2_19, COREWEBVIEW2_MEMORY_USAGE_TARGET_LEVEL_LOW, COREWEBVIEW2_MEMORY_USAGE_TARGET_LEVEL_NORMAL,
      };
      use windows::core::Interface;
      let level = if low { COREWEBVIEW2_MEMORY_USAGE_TARGET_LEVEL_LOW } else { COREWEBVIEW2_MEMORY_USAGE_TARGET_LEVEL_NORMAL };
      // SAFETY: вызов COM на потоке WebView2 (with_webview), интерфейс 19 есть в WebView2 Runtime ≥ 114;
      // старее — cast не пройдёт, и уровень просто не меняется
      unsafe {
        if let Ok(core) = wv.controller().CoreWebView2() {
          if let Ok(core19) = core.cast::<ICoreWebView2_19>() {
            let _ = core19.SetMemoryUsageTargetLevel(level);
          }
        }
      }
    });
  }
  #[cfg(not(windows))]
  let _ = w;
}

/// Окно свернули или развернули — уровень по факту (событие `Resized` приходит и при сворачивании).
pub fn sync(w: &WebviewWindow) {
  let hidden = !w.is_visible().unwrap_or(true) || w.is_minimized().unwrap_or(false);
  set_low(w, hidden);
}
