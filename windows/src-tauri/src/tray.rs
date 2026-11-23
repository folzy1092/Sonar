//! Трей (решение владельца 2026-11-14, `system.tray`): крестик окна прячет Sonar в фон — музыка
//! играет дальше; выключено — крестик закрывает приложение. Значок в трее: левый клик — показать
//! окно, правый — «Открыть», «Играть / пауза», «Следующий», «Офлайн-режим» (галочка), «Выход».

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;
use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, WindowEvent};

/// `system.tray`: true — крестик прячет окно, false — закрывает Sonar.
pub static HIDE_ON_CLOSE: AtomicBool = AtomicBool::new(true);

/// Окно создаётся скрытым (`visible: false` в tauri.conf.json): иначе до старта WebView2 видна пустая
/// рамка. Первый показ — когда заставка из index.html нарисовала кадр (`first_paint`), страховка —
/// через 3 с из `setup`. Запуск с `--autostart` остаётся в трее.
static FIRST_SHOWN: AtomicBool = AtomicBool::new(false);
pub static START_HIDDEN: AtomicBool = AtomicBool::new(false);

/// Галочка «Офлайн-режим» в меню трея: режим переключили откуда угодно — `offline::switch` ставит её заново.
static OFFLINE_ITEM: OnceLock<CheckMenuItem<tauri::Wry>> = OnceLock::new();

/// Синхронизировать галочку с флагом (трея ещё нет — ничего).
pub fn set_offline_checked(on: bool) {
  if let Some(item) = OFFLINE_ITEM.get() {
    if let Err(e) = item.set_checked(on) {
      eprintln!("трей: галочка офлайн-режима не встала — {e}");
    }
  }
}

pub fn show_first(app: &AppHandle) {
  if START_HIDDEN.load(Ordering::Relaxed) || FIRST_SHOWN.swap(true, Ordering::Relaxed) {
    return;
  }
  show_main(app);
}

pub fn show_main(app: &AppHandle) {
  FIRST_SHOWN.store(true, Ordering::Relaxed);
  if let Some(w) = app.get_webview_window("main") {
    let _ = w.unminimize();
    let _ = w.show();
    let _ = w.set_focus();
  }
}

pub fn setup(app: &tauri::App) -> tauri::Result<()> {
  let open = MenuItem::with_id(app, "open", "Открыть", true, None::<&str>)?;
  let toggle = MenuItem::with_id(app, "toggle", "Играть / пауза", true, None::<&str>)?;
  let next = MenuItem::with_id(app, "next", "Следующий", true, None::<&str>)?;
  let sep = PredefinedMenuItem::separator(app)?;
  // флаг уже прочитан из базы (`lib.rs` — до трея), галочка сразу верная
  let offline = CheckMenuItem::with_id(app, "offline", "Офлайн-режим", true, crate::offline::is_on(), None::<&str>)?;
  let sep2 = PredefinedMenuItem::separator(app)?;
  let quit = MenuItem::with_id(app, "quit", "Выход", true, None::<&str>)?;
  let menu = Menu::with_items(app, &[&open, &toggle, &next, &sep, &offline, &sep2, &quit])?;
  let _ = OFFLINE_ITEM.set(offline);

  let mut tray = TrayIconBuilder::with_id("main")
    .tooltip("Sonar")
    .menu(&menu)
    .show_menu_on_left_click(false)
    .on_menu_event(|app, e| match e.id().as_ref() {
      "open" => show_main(app),
      // те же события, что медиа-клавиши (media.rs) — плеер в интерфейсе их уже слушает
      "toggle" => {
        let _ = app.emit("media-control", "toggle");
      }
      "next" => {
        let _ = app.emit("media-control", "next");
      }
      "offline" => crate::offline::toggle(app),
      "quit" => app.exit(0),
      _ => {}
    })
    .on_tray_icon_event(|tray, e| {
      if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = e {
        show_main(tray.app_handle());
      }
    });
  if let Some(icon) = app.default_window_icon() {
    tray = tray.icon(icon.clone());
  }
  tray.build(app)?;

  // Крестик (и Alt+F4): в трей или выход — по `system.tray`.
  if let Some(w) = app.get_webview_window("main") {
    let win = w.clone();
    let handle = app.handle().clone();
    w.on_window_event(move |e| {
      if let WindowEvent::CloseRequested { api, .. } = e {
        api.prevent_close();
        if HIDE_ON_CLOSE.load(Ordering::Relaxed) {
          let _ = win.hide();
        } else {
          handle.exit(0);
        }
      }
    });
  }
  Ok(())
}
