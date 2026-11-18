//! Мини-окно (решение владельца 2026-11-16): маленькая плашка поверх всех окон — обложка, название,
//! артист, лайк, назад / пауза / вперёд; перетаскивается мышью, перемотки нет. Открывается только
//! кнопкой на странице плеера: Sonar сворачивается, плашка встаёт сверху по центру экрана;
//! закрыли плашку — Sonar возвращается. Звук остаётся в главном окне: мини-окно получает состояние событием
//! `mini:state` и шлёт команды `mini:cmd` (интерфейс — `src/app/MiniWindow.svelte`).
//!
//! Оверлей (решение владельца 2026-11-18, SETTINGS_NEXT «Оверлей») — то же окно-плашка, но отдельное
//! (`overlay`, `index.html#overlay`): режим Остров / Карточка / Полноэкранный, место на экране — сетка 3×3,
//! размер задаёт Интерфейс → Оверлей. Открывается горячей клавишей или само, когда Sonar свёрнут;
//! главное окно не трогает. Поверх игр в окне без рамки виден, поверх эксклюзивного полного экрана — нет.
//! Монитор — `overlay.monitor` (`monitors.rs`): основной или выбранный; плашка встаёт в рабочую область
//! этого монитора с его DPI, а подключили / отключили монитор, пока оверлей на экране, — переставляется.

use anyhow::Result;
use serde::Deserialize;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::Duration;
use tauri::{AppHandle, LogicalPosition, LogicalSize, Manager, Monitor, PhysicalPosition, PhysicalSize, WebviewUrl, WebviewWindow, WebviewWindowBuilder};

pub const LABEL: &str = "mini";
pub const OVERLAY: &str = "overlay";
const W: f64 = 340.0;
const H: f64 = 64.0;
/// Отступ плашки от края экрана.
const MARGIN: f64 = 20.0;
/// Как часто, пока оверлей открыт, проверять, не поменялись ли мониторы.
const WATCH_EVERY: Duration = Duration::from_secs(2);

/// Последняя раскладка оверлея — по ней переставляем, когда мониторы поменялись.
static LAST_LAYOUT: Mutex<Option<Layout>> = Mutex::new(None);
/// Слежение за мониторами уже идёт.
static WATCHING: AtomicBool = AtomicBool::new(false);

/// Размер и место оверлея (логические пиксели; масштаб уже учтён интерфейсом).
#[derive(Debug, Clone, Deserialize)]
pub struct Layout {
  pub width: f64,
  pub height: f64,
  /// Клетка сетки 3×3: строка `t` / `m` / `b` и столбец `l` / `c` / `r` — `tc`, `br`…
  pub anchor: String,
  /// Полноэкранный режим: окно на весь экран (затемнение и большая карточка рисует интерфейс).
  pub fullscreen: bool,
  /// `overlay.monitor`: `primary` или `monitorDevicePath`; нет — основной.
  #[serde(default)]
  pub monitor: Option<String>,
}

impl Default for Layout {
  /// Карточка по умолчанию: 340×58 сверху по центру.
  fn default() -> Self {
    Self { width: 340.0, height: 58.0, anchor: "tc".into(), fullscreen: false, monitor: None }
  }
}

/// Левый верхний угол плашки `w`×`h` в клетке `anchor` области `(x, y, ширина, высота)`.
pub fn anchor_pos(area: (f64, f64, f64, f64), w: f64, h: f64, anchor: &str) -> (f64, f64) {
  crate::monitors::anchor_in(area, w, h, anchor, MARGIN)
}

/// Логическая область монитора: `(x, y, ширина, высота)`.
fn area(m: &Monitor) -> (f64, f64, f64, f64) {
  let sc = m.scale_factor();
  let (pos, size) = (m.position(), m.size());
  (pos.x as f64 / sc, pos.y as f64 / sc, size.width as f64 / sc, size.height as f64 / sc)
}

/// Монитор главного окна; если его не узнать — тот, где окно `w`, или основной.
fn monitor(app: &AppHandle, w: &WebviewWindow) -> Option<Monitor> {
  app
    .get_webview_window("main")
    .and_then(|m| m.current_monitor().ok().flatten())
    .or_else(|| w.current_monitor().ok().flatten())
    .or_else(|| app.primary_monitor().ok().flatten())
}

/// Окно-плашка поверх всех окон: без рамки, прозрачное, не в панели задач.
fn build(app: &AppHandle, label: &str, hash: &str, title: &str, w: f64, h: f64, focused: bool) -> Result<WebviewWindow> {
  // у второго окна WebView2 те же флаги браузера, что у главного: иначе общая папка данных не откроется
  let args = app.config().app.windows.first().and_then(|w| w.additional_browser_args.clone());
  let mut b = WebviewWindowBuilder::new(app, label, WebviewUrl::App(format!("index.html#{hash}").into()))
    .title(title)
    .inner_size(w, h)
    .resizable(false)
    .maximizable(false)
    .minimizable(false)
    .decorations(false)
    .transparent(true)
    .shadow(false)
    .always_on_top(true)
    .skip_taskbar(true)
    .focused(focused);
  if let Some(a) = args {
    b = b.additional_browser_args(&a);
  }
  Ok(b.build()?)
}

/// Показать или закрыть мини-окно; вернёт, открыто ли оно теперь.
pub fn toggle(app: &AppHandle, show: bool) -> Result<bool> {
  if let Some(w) = app.get_webview_window(LABEL) {
    if show {
      let _ = w.show();
      let _ = w.set_focus();
      return Ok(true);
    }
    // destroy, а не close: закрывает окно, даже если его страница зависла или занята (иначе мог
    // остаться «фантом» — плашка «Ничего не играет», которую не закрыть и не сдвинуть)
    let _ = w.destroy();
    crate::tray::show_main(app);
    return Ok(false);
  }
  if !show {
    return Ok(false);
  }
  let w = build(app, LABEL, "mini", "Sonar — мини-плеер", W, H, false)?;
  // сверху по центру экрана, с отступом от края (решение владельца 2026-11-16)
  if let Some(m) = monitor(app, &w) {
    let (x, y) = anchor_pos(area(&m), W, H, "tc");
    let _ = w.set_position(LogicalPosition::new(x, y));
  }
  // большое окно уходит — вместо него мини-окно
  if let Some(main) = app.get_webview_window("main") {
    let _ = main.minimize();
  }
  Ok(true)
}

/// Поставить оверлей по `layout`: на выбранный монитор (отключён — на основной), в рабочую область, с его
/// DPI — физическими пикселями, иначе на мониторе с другим масштабом размер и место «поплывут».
fn place(app: &AppHandle, w: &WebviewWindow, layout: &Layout) {
  let list = crate::monitors::list(app);
  let wanted = layout.monitor.as_deref().unwrap_or(crate::monitors::PRIMARY);
  if let Some(m) = crate::monitors::pick(&list, wanted) {
    let (x, y, pw, ph) = crate::monitors::overlay_rect(m, layout.width, layout.height, &layout.anchor, MARGIN, layout.fullscreen);
    // сначала переезд (на мониторе с другим DPI Windows сама поменяет размер), потом размер, и ещё раз
    // место — у клеток справа и снизу оно зависит от размера
    let _ = w.set_position(PhysicalPosition::new(x, y));
    let _ = w.set_size(PhysicalSize::new(pw, ph));
    let _ = w.set_position(PhysicalPosition::new(x, y));
    return;
  }
  // Tauri не дал список мониторов — по-старому, у монитора главного окна
  if let Some(m) = monitor(app, w) {
    let a = area(&m);
    let (w_, h_, (x, y)) = if layout.fullscreen {
      (a.2, a.3, (a.0, a.1))
    } else {
      (layout.width, layout.height, anchor_pos(a, layout.width, layout.height, &layout.anchor))
    };
    let _ = w.set_size(LogicalSize::new(w_, h_));
    let _ = w.set_position(LogicalPosition::new(x, y));
  }
}

/// Пока оверлей открыт — раз в `WATCH_EVERY` сверять расстановку мониторов; поменялась (подключили,
/// отключили, сменили масштаб) — переставить по последней раскладке. Закрыли оверлей — слежение кончается.
fn watch(app: &AppHandle) {
  if WATCHING.swap(true, Ordering::SeqCst) {
    return;
  }
  let app = app.clone();
  std::thread::spawn(move || {
    let mut seen = crate::monitors::signature(&crate::monitors::list(&app));
    loop {
      std::thread::sleep(WATCH_EVERY);
      let Some(w) = app.get_webview_window(OVERLAY) else {
        WATCHING.store(false, Ordering::SeqCst);
        // оверлей могли открыть заново ровно между проверкой и сбросом — тогда следим дальше
        if app.get_webview_window(OVERLAY).is_none() || WATCHING.swap(true, Ordering::SeqCst) {
          return;
        }
        continue;
      };
      let now = crate::monitors::signature(&crate::monitors::list(&app));
      if now == seen {
        continue;
      }
      seen = now;
      let layout = LAST_LAYOUT.lock().ok().and_then(|g| g.clone());
      if let Some(layout) = layout {
        place(&app, &w, &layout);
      }
    }
  });
}

/// Показать (или переставить по новому `layout`) или закрыть оверлей; вернёт, открыт ли он.
pub fn overlay(app: &AppHandle, show: bool, layout: &Layout) -> Result<bool> {
  let existing = app.get_webview_window(OVERLAY);
  if !show {
    if let Some(w) = existing {
      let _ = w.destroy();
    }
    return Ok(false);
  }
  let w = match existing {
    Some(w) => w,
    None => build(app, OVERLAY, "overlay", "Sonar — оверлей", layout.width, layout.height, layout.fullscreen)?,
  };
  if let Ok(mut last) = LAST_LAYOUT.lock() {
    *last = Some(layout.clone());
  }
  place(app, &w, layout);
  let _ = w.show();
  // полноэкранный ловит Esc — ему нужен фокус; плашка фокус у игры не отбирает
  if layout.fullscreen {
    let _ = w.set_focus();
  }
  watch(app);
  Ok(true)
}

#[cfg(test)]
mod tests {
  use super::*;

  const SCREEN: (f64, f64, f64, f64) = (0.0, 0.0, 1920.0, 1080.0);

  #[test]
  fn corners_keep_margin() {
    assert_eq!(anchor_pos(SCREEN, 340.0, 58.0, "tl"), (20.0, 20.0));
    assert_eq!(anchor_pos(SCREEN, 340.0, 58.0, "br"), (1920.0 - 340.0 - 20.0, 1080.0 - 58.0 - 20.0));
  }

  #[test]
  fn center_and_middle() {
    assert_eq!(anchor_pos(SCREEN, 340.0, 58.0, "tc"), (790.0, 20.0));
    assert_eq!(anchor_pos(SCREEN, 340.0, 60.0, "mc"), (790.0, 510.0));
  }

  #[test]
  fn second_monitor_offset_and_unknown_anchor() {
    let right = (1920.0, 0.0, 1280.0, 720.0);
    assert_eq!(anchor_pos(right, 200.0, 50.0, "ml"), (1940.0, 335.0));
    // непонятная клетка — сверху по центру
    assert_eq!(anchor_pos(right, 200.0, 50.0, ""), (1920.0 + 540.0, 20.0));
  }
}
