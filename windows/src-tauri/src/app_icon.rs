//! Значок приложения (`appearance.app_icon`, Интерфейс → Вид → «Значок приложения», решение владельца
//! 2026-11-24): основной — «Стекло», остальные на выбор. Меняется на лету: малый значок окна и значок в
//! трее — средствами Tauri, большой значок окна (панель задач, Alt+Tab) — сообщением `WM_SETICON`, потому
//! что `Window::set_icon` ставит только малый (tao `set_window_icon`).
//!
//! Ярлыки и сам exe остаются с основным значком: его Windows берёт из ресурса exe, при запущенном Sonar
//! этого не поменять; закреплённая на панели задач кнопка тоже. Файлы — `icons/app/<id>-64|32.png`
//! (`brand/app-icons/build.mjs`); список id — `lib/app-icons.ts` (оба сверяют тесты).

use tauri::image::Image;
use tauri::{AppHandle, Manager};

/// Ключ настройки.
pub const KEY: &str = "appearance.app_icon";
/// Основной значок: тот, что вшит в exe.
pub const DEFAULT: &str = "glass";

/// id, значок 64 px (большой значок окна), значок 32 px (заголовок и трей).
type Entry = (&'static str, &'static [u8], &'static [u8]);

macro_rules! icon {
  ($id:literal) => {
    (
      $id,
      include_bytes!(concat!("../icons/app/", $id, "-64.png")) as &[u8],
      include_bytes!(concat!("../icons/app/", $id, "-32.png")) as &[u8],
    )
  };
}

const ICONS: &[Entry] = &[
  icon!("glass"),
  icon!("flat"),
  icon!("bevel"),
  icon!("puff"),
  icon!("block"),
  icon!("echo"),
  icon!("well"),
  icon!("chrome"),
  icon!("carved"),
  icon!("light"),
];

/// Значок по id; незнакомый (настройка из другой сборки) — основной.
fn find(id: &str) -> &'static Entry {
  ICONS.iter().find(|i| i.0 == id).unwrap_or(&ICONS[0])
}

/// Поставить значок всем окнам и в трей (из потока команды — она идёт в главном потоке).
pub fn apply(app: &AppHandle, id: &str) {
  let (name, big, small) = find(id);
  let (Ok(big), Ok(small)) = (Image::from_bytes(big), Image::from_bytes(small)) else {
    eprintln!("значок приложения «{name}»: файл не читается");
    return;
  };
  for w in app.webview_windows().values() {
    if let Err(e) = w.set_icon(small.clone()) {
      eprintln!("значок окна «{}»: {e}", w.label());
    }
    #[cfg(windows)]
    win::set_big(w, &big);
  }
  #[cfg(not(windows))]
  let _ = &big;
  if let Some(tray) = app.tray_by_id("main") {
    if let Err(e) = tray.set_icon(Some(small)) {
      eprintln!("значок в трее: {e}");
    }
  }
}

/// Значок из сохранённой настройки при запуске: основной уже в exe, трогаем только другой.
pub fn apply_saved(app: &AppHandle, saved: Option<&serde_json::Value>) {
  if let Some(id) = saved.and_then(|v| v.as_str()).filter(|id| *id != DEFAULT) {
    apply(app, id);
  }
}

#[cfg(windows)]
mod win {
  use super::Image;
  use std::sync::Mutex;
  use tauri::WebviewWindow;
  use windows::Win32::Foundation::{HWND, LPARAM, WPARAM};
  use windows::Win32::Graphics::Gdi::{CreateBitmap, DeleteObject, HGDIOBJ};
  use windows::Win32::UI::WindowsAndMessaging::{CreateIconIndirect, DestroyIcon, SendMessageW, HICON, ICONINFO, ICON_BIG, WM_SETICON};

  /// Свои большие значки окон (hwnd → HICON): прошлый при замене уничтожаем, чужие (от tao) не трогаем.
  static MINE: Mutex<Vec<(isize, isize)>> = Mutex::new(Vec::new());

  /// RGBA (прозрачность сохраняется) → значок Windows.
  fn hicon(img: &Image<'_>) -> Option<HICON> {
    let (w, h) = (img.width() as i32, img.height() as i32);
    let bgra: Vec<u8> = img.rgba().chunks_exact(4).flat_map(|p| [p[2], p[1], p[0], p[3]]).collect();
    unsafe {
      let color = CreateBitmap(w, h, 1, 32, Some(bgra.as_ptr().cast()));
      let mask_bits = vec![0u8; (w as usize).div_ceil(16) * 2 * h as usize];
      let mask = CreateBitmap(w, h, 1, 1, Some(mask_bits.as_ptr().cast()));
      let info = ICONINFO { fIcon: true.into(), xHotspot: 0, yHotspot: 0, hbmMask: mask, hbmColor: color };
      let made = CreateIconIndirect(&info);
      let _ = DeleteObject(HGDIOBJ(color.0));
      let _ = DeleteObject(HGDIOBJ(mask.0));
      made.ok()
    }
  }

  pub fn set_big(window: &WebviewWindow, img: &Image<'_>) {
    let Ok(raw) = window.hwnd() else { return };
    let Some(icon) = hicon(img) else {
      eprintln!("значок окна «{}»: не собрался HICON", window.label());
      return;
    };
    let hwnd = HWND(raw.0 as _);
    unsafe {
      SendMessageW(hwnd, WM_SETICON, Some(WPARAM(ICON_BIG as usize)), Some(LPARAM(icon.0 as isize)));
    }
    let mut mine = MINE.lock().unwrap();
    let key = raw.0 as isize;
    if let Some(slot) = mine.iter_mut().find(|m| m.0 == key) {
      let old = HICON(slot.1 as _);
      slot.1 = icon.0 as isize;
      unsafe {
        let _ = DestroyIcon(old);
      }
    } else {
      mine.push((key, icon.0 as isize));
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn primary_is_first() {
    assert_eq!(ICONS[0].0, DEFAULT);
    assert_eq!(find("нет-такого").0, DEFAULT);
  }

  #[test]
  fn ids_are_unique() {
    let mut ids: Vec<_> = ICONS.iter().map(|i| i.0).collect();
    ids.sort_unstable();
    ids.dedup();
    assert_eq!(ids.len(), ICONS.len());
  }

  #[test]
  fn files_are_png_of_the_right_size() {
    for (id, big, small) in ICONS {
      let (b, s) = (Image::from_bytes(big).unwrap(), Image::from_bytes(small).unwrap());
      assert_eq!((b.width(), b.height()), (64, 64), "{id}-64.png");
      assert_eq!((s.width(), s.height()), (32, 32), "{id}-32.png");
    }
  }

  /// Список в `lib/app-icons.ts` — те же id в том же порядке (порядок плиток в настройках).
  #[test]
  fn same_ids_as_the_frontend_catalog() {
    let ts = include_str!("../../src/lib/app-icons.ts");
    let listed: Vec<&str> = ts.split("id: '").skip(1).filter_map(|s| s.split('\'').next()).collect();
    let ours: Vec<&str> = ICONS.iter().map(|i| i.0).collect();
    assert_eq!(listed, ours);
  }
}
