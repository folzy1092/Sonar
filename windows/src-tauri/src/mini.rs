//! Мини-окно (решение владельца 2026-11-16): маленькая плашка поверх всех окон — обложка, название,
//! артист, лайк, назад / пауза / вперёд; перетаскивается мышью, перемотки нет. Открывается только
//! кнопкой на странице плеера: Sonar сворачивается, плашка встаёт сверху по центру экрана;
//! закрыли плашку — Sonar возвращается. Звук остаётся в главном окне: мини-окно получает состояние событием
//! `mini:state` и шлёт команды `mini:cmd` (интерфейс — `src/app/MiniWindow.svelte`).

use anyhow::Result;
use tauri::{AppHandle, LogicalPosition, Manager, WebviewUrl, WebviewWindowBuilder};

pub const LABEL: &str = "mini";
const W: f64 = 340.0;
const H: f64 = 64.0;

/// Показать или закрыть мини-окно; вернёт, открыто ли оно теперь.
pub fn toggle(app: &AppHandle, show: bool) -> Result<bool> {
  if let Some(w) = app.get_webview_window(LABEL) {
    if show {
      let _ = w.show();
      let _ = w.set_focus();
      return Ok(true);
    }
    let _ = w.close();
    crate::tray::show_main(app);
    return Ok(false);
  }
  if !show {
    return Ok(false);
  }
  // у второго окна WebView2 те же флаги браузера, что у главного: иначе общая папка данных не откроется
  let args = app.config().app.windows.first().and_then(|w| w.additional_browser_args.clone());
  let mut b = WebviewWindowBuilder::new(app, LABEL, WebviewUrl::App("index.html#mini".into()))
    .title("Sonar — мини-плеер")
    .inner_size(W, H)
    .resizable(false)
    .maximizable(false)
    .minimizable(false)
    .decorations(false)
    .transparent(true)
    .shadow(false)
    .always_on_top(true)
    .skip_taskbar(true)
    .focused(false);
  if let Some(a) = args {
    b = b.additional_browser_args(&a);
  }
  let w = b.build()?;
  // сверху по центру экрана, с отступом от края (решение владельца 2026-11-16)
  let monitor = app.get_webview_window("main").and_then(|m| m.current_monitor().ok().flatten()).or_else(|| w.current_monitor().ok().flatten());
  if let Some(m) = monitor {
    let sc = m.scale_factor();
    let size = m.size();
    let pos = m.position();
    let x = pos.x as f64 / sc + (size.width as f64 / sc - W) / 2.0;
    let y = pos.y as f64 / sc + 20.0;
    let _ = w.set_position(LogicalPosition::new(x, y));
  }
  // большое окно уходит — вместо него мини-окно
  if let Some(main) = app.get_webview_window("main") {
    let _ = main.minimize();
  }
  Ok(true)
}
