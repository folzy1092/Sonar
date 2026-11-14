//! Трей (решение владельца 2026-11-14): крестик окна прячет Sonar в фон — музыка из очереди
//! играет дальше; значок в трее: левый клик — показать окно, правый — «Открыть» и «Выход».
//! «Выход» завершает процесс целиком.

use tauri::menu::{Menu, MenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Manager, WindowEvent};

pub fn show_main(app: &AppHandle) {
  if let Some(w) = app.get_webview_window("main") {
    let _ = w.unminimize();
    let _ = w.show();
    let _ = w.set_focus();
  }
}

pub fn setup(app: &tauri::App) -> tauri::Result<()> {
  let open = MenuItem::with_id(app, "open", "Открыть", true, None::<&str>)?;
  let quit = MenuItem::with_id(app, "quit", "Выход", true, None::<&str>)?;
  let menu = Menu::with_items(app, &[&open, &quit])?;

  let mut tray = TrayIconBuilder::with_id("main")
    .tooltip("Sonar")
    .menu(&menu)
    .show_menu_on_left_click(false)
    .on_menu_event(|app, e| match e.id().as_ref() {
      "open" => show_main(app),
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

  // Крестик (и Alt+F4) не закрывает приложение, а прячет окно.
  if let Some(w) = app.get_webview_window("main") {
    let win = w.clone();
    w.on_window_event(move |e| {
      if let WindowEvent::CloseRequested { api, .. } = e {
        api.prevent_close();
        let _ = win.hide();
      }
    });
  }
  Ok(())
}
