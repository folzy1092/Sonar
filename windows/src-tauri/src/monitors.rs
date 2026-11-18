//! Мониторы для оверлея (Интерфейс → Оверлей → «Положение на экране», решение владельца 2026-11-18):
//! все экраны так, как они расставлены, с настоящим названием модели, разрешением и частотой; выбор
//! экрана по `overlay.monitor` (`primary` или `monitorDevicePath`) с откатом на основной и место
//! плашки в рабочей области (без панели задач) с учётом DPI монитора.
//!
//! Расстановку, рабочую область и масштаб даёт Tauri (`available_monitors`). На Windows Tauri зовёт
//! монитор именем GDI (`\\.\DISPLAY1`) — по нему подмешиваем то, что знает DisplayConfig: название
//! модели (`monitorFriendlyDeviceName`), постоянный путь устройства (`monitorDevicePath`, им и
//! запоминаем выбор) и частоту. На других ОС название — то, что сказал Tauri, частоты нет.

use serde::Serialize;
use tauri::{AppHandle, Monitor};

/// `overlay.monitor` по умолчанию: основной монитор, какой бы он ни был.
pub const PRIMARY: &str = "primary";

/// Монитор для интерфейса (`list_monitors`). Координаты и размеры — физические пиксели.
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct MonitorInfo {
  /// Постоянный id: `monitorDevicePath` на Windows, иначе имя или координаты.
  pub id: String,
  /// Имя GDI (`\\.\DISPLAY1`) — пусто, если ОС его не дала.
  pub gdi_name: String,
  /// Название модели; пусто — интерфейс пишет «Монитор N».
  pub name: String,
  /// Номер как у Windows (из `\\.\DISPLAYn`), иначе порядковый.
  pub number: u32,
  pub x: i32,
  pub y: i32,
  pub width: u32,
  pub height: u32,
  /// Рабочая область — экран без панели задач.
  pub work_x: i32,
  pub work_y: i32,
  pub work_w: u32,
  pub work_h: u32,
  /// Масштаб (DPI / 96): 1.0, 1.25, 1.5…
  pub scale: f64,
  /// Частота, Гц; 0 — неизвестна.
  pub refresh_hz: f64,
  pub primary: bool,
}

/// Что Tauri знает о мониторе — без `tauri::Monitor`, чтобы сборку списка можно было проверить тестом.
#[derive(Debug, Clone, Default)]
pub struct RawMonitor {
  pub name: Option<String>,
  pub x: i32,
  pub y: i32,
  pub width: u32,
  pub height: u32,
  pub work_x: i32,
  pub work_y: i32,
  pub work_w: u32,
  pub work_h: u32,
  pub scale: f64,
}

/// Что знает DisplayConfig об активном выходе (только Windows).
#[derive(Debug, Clone, Default)]
pub struct Target {
  /// `\\.\DISPLAY1` — по нему сводим с монитором Tauri.
  pub gdi: String,
  pub friendly: String,
  pub path: String,
  pub hz: f64,
}

/// Названия, которые ничего не говорят о модели: Windows пишет их, когда монитор не прислал EDID.
const GENERIC_NAMES: [&str; 4] = ["generic pnp monitor", "generic non-pnp monitor", "универсальный монитор pnp", "универсальный монитор не pnp"];

/// Имя GDI начинается так — это не название модели.
const GDI_PREFIX: &str = r"\\.\";

/// Название модели или пусто, если его нет или оно «Generic PnP Monitor».
pub fn clean_friendly(raw: &str) -> String {
  let s = raw.trim();
  if s.is_empty() || s.starts_with(GDI_PREFIX) || GENERIC_NAMES.contains(&s.to_lowercase().as_str()) {
    return String::new();
  }
  s.to_string()
}

/// Номер из имени GDI: `\\.\DISPLAY3` → 3.
pub fn gdi_number(gdi: &str) -> Option<u32> {
  let at = gdi.to_ascii_uppercase().rfind("DISPLAY")?;
  let digits: String = gdi[at + "DISPLAY".len()..].chars().take_while(|c| c.is_ascii_digit()).collect();
  digits.parse().ok().filter(|n| *n > 0)
}

/// Свести мониторы Tauri с данными DisplayConfig. `primary` — индекс основного в `raws`, если узнали.
pub fn build(raws: &[RawMonitor], primary: Option<usize>, targets: &[Target]) -> Vec<MonitorInfo> {
  // не узнали основной — тот, что в начале координат (так у Windows), иначе первый
  let primary = primary.or_else(|| raws.iter().position(|r| r.x == 0 && r.y == 0)).unwrap_or(0);
  let mut list: Vec<MonitorInfo> = raws
    .iter()
    .enumerate()
    .map(|(i, r)| {
      let gdi = r.name.clone().unwrap_or_default();
      let target = targets.iter().find(|t| !gdi.is_empty() && t.gdi.eq_ignore_ascii_case(&gdi));
      let is_gdi = gdi.starts_with(GDI_PREFIX);
      let id = match target.map(|t| t.path.as_str()).filter(|p| !p.is_empty()) {
        Some(p) => p.to_string(),
        None if !gdi.is_empty() => gdi.clone(),
        None => format!("{},{}", r.x, r.y),
      };
      let name = clean_friendly(target.map_or(if is_gdi { "" } else { gdi.as_str() }, |t| t.friendly.as_str()));
      MonitorInfo {
        id,
        gdi_name: if is_gdi { gdi.clone() } else { String::new() },
        name,
        number: gdi_number(&gdi).unwrap_or(i as u32 + 1),
        x: r.x,
        y: r.y,
        width: r.width,
        height: r.height,
        work_x: r.work_x,
        work_y: r.work_y,
        work_w: r.work_w,
        work_h: r.work_h,
        scale: if r.scale > 0.0 { r.scale } else { 1.0 },
        refresh_hz: target.map_or(0.0, |t| t.hz),
        primary: i == primary,
      }
    })
    .collect();
  list.sort_by_key(|m| m.number);
  list
}

/// Монитор для оверлея: сохранённый по id, а если его нет (отключили) или выбран «Основной» — основной.
pub fn pick<'a>(list: &'a [MonitorInfo], wanted: &str) -> Option<&'a MonitorInfo> {
  let exact = (wanted != PRIMARY).then(|| list.iter().find(|m| m.id == wanted)).flatten();
  exact.or_else(|| list.iter().find(|m| m.primary)).or_else(|| list.first())
}

/// Левый верхний угол плашки `w`×`h` в клетке `anchor` (`tl` … `br`) области `(x, y, ширина, высота)`
/// с отступом `margin` от краёв. Не влезает — прижимается к левому / верхнему краю области.
pub fn anchor_in(area: (f64, f64, f64, f64), w: f64, h: f64, anchor: &str, margin: f64) -> (f64, f64) {
  let (ax, ay, aw, ah) = area;
  let mut chars = anchor.chars();
  let row = chars.next().unwrap_or('t');
  let col = chars.next().unwrap_or('c');
  let x = match col {
    'l' => ax + margin,
    'r' => ax + aw - w - margin,
    _ => ax + (aw - w) / 2.0,
  };
  let y = match row {
    'm' => ay + (ah - h) / 2.0,
    'b' => ay + ah - h - margin,
    _ => ay + margin,
  };
  (x.max(ax), y.max(ay))
}

/// Место и размер окна оверлея на мониторе `m`, физические пиксели: `(x, y, ширина, высота)`.
/// `w`×`h` и `margin` — логические (как в настройках), переводятся масштабом этого монитора;
/// плашка стоит в рабочей области, полноэкранный — на весь монитор.
pub fn overlay_rect(m: &MonitorInfo, w: f64, h: f64, anchor: &str, margin: f64, fullscreen: bool) -> (i32, i32, u32, u32) {
  if fullscreen {
    return (m.x, m.y, m.width, m.height);
  }
  let k = m.scale;
  let (pw, ph) = ((w * k).round().min(m.work_w as f64), (h * k).round().min(m.work_h as f64));
  let area = (m.work_x as f64, m.work_y as f64, m.work_w as f64, m.work_h as f64);
  let (x, y) = anchor_in(area, pw, ph, anchor, (margin * k).round());
  (x.round() as i32, y.round() as i32, pw.max(1.0) as u32, ph.max(1.0) as u32)
}

/// Отпечаток расстановки — поменялся, значит монитор подключили, отключили или передвинули.
pub fn signature(list: &[MonitorInfo]) -> String {
  list
    .iter()
    .map(|m| format!("{}@{},{} {}x{} w{},{} {}x{} s{}", m.id, m.x, m.y, m.width, m.height, m.work_x, m.work_y, m.work_w, m.work_h, m.scale))
    .collect::<Vec<_>>()
    .join("|")
}

fn raw(m: &Monitor) -> RawMonitor {
  let (pos, size, work) = (m.position(), m.size(), m.work_area());
  RawMonitor {
    name: m.name().cloned(),
    x: pos.x,
    y: pos.y,
    width: size.width,
    height: size.height,
    work_x: work.position.x,
    work_y: work.position.y,
    work_w: work.size.width,
    work_h: work.size.height,
    scale: m.scale_factor(),
  }
}

/// Все мониторы сейчас; Tauri не ответил — пустой список (тогда оверлей ставится по-старому).
pub fn list(app: &AppHandle) -> Vec<MonitorInfo> {
  let all = app.available_monitors().unwrap_or_default();
  let primary = app.primary_monitor().ok().flatten();
  let primary_idx = primary.as_ref().and_then(|p| all.iter().position(|m| m.name() == p.name() && m.position() == p.position()));
  let raws: Vec<RawMonitor> = all.iter().map(raw).collect();
  build(&raws, primary_idx, &targets())
}

#[cfg(windows)]
fn targets() -> Vec<Target> {
  win::targets()
}

#[cfg(not(windows))]
fn targets() -> Vec<Target> {
  Vec::new()
}

#[cfg(windows)]
mod win {
  //! DisplayConfig: активные пути «источник → монитор», для каждого — имя GDI источника и название,
  //! путь и частота монитора.
  use super::Target;
  use windows::Win32::Devices::Display::{
    DisplayConfigGetDeviceInfo, GetDisplayConfigBufferSizes, QueryDisplayConfig, DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME,
    DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME, DISPLAYCONFIG_DEVICE_INFO_HEADER, DISPLAYCONFIG_MODE_INFO, DISPLAYCONFIG_PATH_INFO,
    DISPLAYCONFIG_SOURCE_DEVICE_NAME, DISPLAYCONFIG_TARGET_DEVICE_NAME, QDC_ONLY_ACTIVE_PATHS,
  };
  use windows::Win32::Foundation::{ERROR_INSUFFICIENT_BUFFER, ERROR_SUCCESS};

  /// Сколько раз переспросить, если между «сколько путей» и «дай пути» мониторы поменялись.
  const ATTEMPTS: usize = 3;

  fn wide(buf: &[u16]) -> String {
    let end = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
    String::from_utf16_lossy(&buf[..end])
  }

  fn active_paths() -> Vec<DISPLAYCONFIG_PATH_INFO> {
    for _ in 0..ATTEMPTS {
      let (mut np, mut nm) = (0u32, 0u32);
      // SAFETY: указатели на локальные u32, живут весь вызов
      if unsafe { GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &mut np, &mut nm) } != ERROR_SUCCESS {
        return Vec::new();
      }
      let mut paths = vec![DISPLAYCONFIG_PATH_INFO::default(); np as usize];
      let mut modes = vec![DISPLAYCONFIG_MODE_INFO::default(); nm as usize];
      // SAFETY: буферы ровно той длины, что передаём в np / nm
      let res = unsafe { QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &mut np, paths.as_mut_ptr(), &mut nm, modes.as_mut_ptr(), None) };
      if res == ERROR_SUCCESS {
        paths.truncate(np as usize);
        return paths;
      }
      if res != ERROR_INSUFFICIENT_BUFFER {
        return Vec::new();
      }
    }
    Vec::new()
  }

  fn target(p: &DISPLAYCONFIG_PATH_INFO) -> Option<Target> {
    let mut src = DISPLAYCONFIG_SOURCE_DEVICE_NAME {
      header: DISPLAYCONFIG_DEVICE_INFO_HEADER {
        r#type: DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME,
        size: std::mem::size_of::<DISPLAYCONFIG_SOURCE_DEVICE_NAME>() as u32,
        adapterId: p.sourceInfo.adapterId,
        id: p.sourceInfo.id,
      },
      ..Default::default()
    };
    // SAFETY: заголовок — первое поле структуры, размер в нём — размер всей структуры
    if unsafe { DisplayConfigGetDeviceInfo(&mut src.header) } != 0 {
      return None;
    }
    let mut tgt = DISPLAYCONFIG_TARGET_DEVICE_NAME {
      header: DISPLAYCONFIG_DEVICE_INFO_HEADER {
        r#type: DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME,
        size: std::mem::size_of::<DISPLAYCONFIG_TARGET_DEVICE_NAME>() as u32,
        adapterId: p.targetInfo.adapterId,
        id: p.targetInfo.id,
      },
      ..Default::default()
    };
    // SAFETY: как выше; не ответил — монитор всё равно покажем, только без названия и пути
    let named = unsafe { DisplayConfigGetDeviceInfo(&mut tgt.header) } == 0;
    let rate = p.targetInfo.refreshRate;
    let hz = if rate.Denominator > 0 { rate.Numerator as f64 / rate.Denominator as f64 } else { 0.0 };
    Some(Target {
      gdi: wide(&src.viewGdiDeviceName),
      friendly: if named { wide(&tgt.monitorFriendlyDeviceName) } else { String::new() },
      path: if named { wide(&tgt.monitorDevicePath) } else { String::new() },
      hz,
    })
  }

  /// Активные мониторы; в режиме «Дублировать» на одном источнике два монитора — берём первый.
  pub fn targets() -> Vec<Target> {
    let mut out: Vec<Target> = Vec::new();
    for t in active_paths().iter().filter_map(target) {
      if !out.iter().any(|o| o.gdi.eq_ignore_ascii_case(&t.gdi)) {
        out.push(t);
      }
    }
    out
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn raw(name: &str, x: i32, y: i32, w: u32, h: u32, scale: f64) -> RawMonitor {
    RawMonitor { name: Some(name.into()), x, y, width: w, height: h, work_x: x, work_y: y, work_w: w, work_h: h - 48, scale }
  }

  fn target(gdi: &str, friendly: &str, path: &str, hz: f64) -> Target {
    Target { gdi: gdi.into(), friendly: friendly.into(), path: path.into(), hz }
  }

  #[test]
  fn generic_and_empty_names_are_dropped() {
    assert_eq!(clean_friendly("DELL U2720Q"), "DELL U2720Q");
    assert_eq!(clean_friendly("  LG ULTRAGEAR "), "LG ULTRAGEAR");
    assert_eq!(clean_friendly(""), "");
    assert_eq!(clean_friendly("Generic PnP Monitor"), "");
    assert_eq!(clean_friendly("generic non-pnp monitor"), "");
    assert_eq!(clean_friendly("Универсальный монитор PnP"), "");
    assert_eq!(clean_friendly(r"\\.\DISPLAY1"), "");
  }

  #[test]
  fn number_from_gdi_name() {
    assert_eq!(gdi_number(r"\\.\DISPLAY1"), Some(1));
    assert_eq!(gdi_number(r"\\.\DISPLAY12"), Some(12));
    assert_eq!(gdi_number(r"\\.\display3"), Some(3));
    assert_eq!(gdi_number("Built-in Retina Display"), None);
    assert_eq!(gdi_number(""), None);
  }

  #[test]
  fn windows_names_paths_and_rates_are_merged() {
    let raws = [raw(r"\\.\DISPLAY2", 2560, 0, 1920, 1080, 1.0), raw(r"\\.\DISPLAY1", 0, 0, 2560, 1440, 1.25)];
    let targets = [target(r"\\.\DISPLAY1", "DELL U2720Q", r"\\?\DISPLAY#DEL1#1", 143.999), target(r"\\.\DISPLAY2", "Generic PnP Monitor", r"\\?\DISPLAY#GSM#2", 60.0)];
    let list = build(&raws, Some(1), &targets);
    // по номеру Windows
    assert_eq!(list[0].number, 1);
    assert_eq!(list[0].name, "DELL U2720Q");
    assert_eq!(list[0].id, r"\\?\DISPLAY#DEL1#1");
    assert!(list[0].primary);
    assert!((list[0].refresh_hz - 143.999).abs() < 1e-9);
    assert_eq!(list[1].number, 2);
    assert_eq!(list[1].name, "", "Generic PnP Monitor — интерфейс напишет «Монитор 2»");
    assert_eq!(list[1].gdi_name, r"\\.\DISPLAY2");
    assert!(!list[1].primary);
  }

  #[test]
  fn other_os_uses_tauri_name_and_order() {
    let raws = [raw("Built-in Retina Display", 0, 0, 3024, 1964, 2.0), raw("LG HDR 4K", 3024, 0, 3840, 2160, 1.0)];
    let list = build(&raws, None, &[]);
    assert_eq!(list[0].id, "Built-in Retina Display");
    assert_eq!(list[0].name, "Built-in Retina Display");
    assert_eq!(list[0].gdi_name, "");
    assert_eq!(list[0].number, 1);
    assert!(list[0].primary, "не узнали основной — тот, что в начале координат");
    assert_eq!(list[1].number, 2);
    assert_eq!(list[1].refresh_hz, 0.0);
  }

  #[test]
  fn nameless_monitor_gets_coordinate_id_and_sane_scale() {
    let r = RawMonitor { x: -1920, y: 0, width: 1920, height: 1080, scale: 0.0, ..Default::default() };
    let list = build(&[r], None, &[]);
    assert_eq!(list[0].id, "-1920,0");
    assert_eq!(list[0].scale, 1.0);
    assert!(list[0].primary, "единственный монитор — основной");
  }

  #[test]
  fn pick_saved_or_falls_back_to_primary() {
    let list = build(
      &[raw(r"\\.\DISPLAY1", 0, 0, 1920, 1080, 1.0), raw(r"\\.\DISPLAY2", 1920, 0, 1920, 1080, 1.0)],
      Some(0),
      &[target(r"\\.\DISPLAY1", "A", "path-a", 60.0), target(r"\\.\DISPLAY2", "B", "path-b", 60.0)],
    );
    assert_eq!(pick(&list, "path-b").unwrap().id, "path-b");
    assert_eq!(pick(&list, PRIMARY).unwrap().id, "path-a");
    // отключили — на основном, а настройка остаётся как была
    assert_eq!(pick(&list, "path-gone").unwrap().id, "path-a");
    assert!(pick(&[], PRIMARY).is_none());
  }

  #[test]
  fn plaque_sits_in_work_area_with_dpi() {
    let m = MonitorInfo {
      id: "a".into(),
      gdi_name: String::new(),
      name: String::new(),
      number: 2,
      x: 2560,
      y: 0,
      width: 3840,
      height: 2160,
      work_x: 2560,
      work_y: 0,
      work_w: 3840,
      work_h: 2088,
      scale: 1.5,
      refresh_hz: 60.0,
      primary: false,
    };
    // 340×58 логических при 150 % — 510×87 физических, отступ 20 → 30
    assert_eq!(overlay_rect(&m, 340.0, 58.0, "tl", 20.0, false), (2590, 30, 510, 87));
    // снизу справа — над панелью задач (рабочая область кончается на 2088)
    assert_eq!(overlay_rect(&m, 340.0, 58.0, "br", 20.0, false), (2560 + 3840 - 510 - 30, 2088 - 87 - 30, 510, 87));
    assert_eq!(overlay_rect(&m, 340.0, 58.0, "mc", 20.0, true), (2560, 0, 3840, 2160));
  }

  #[test]
  fn anchor_in_clamps_oversized_plaque() {
    assert_eq!(anchor_in((0.0, 0.0, 100.0, 100.0), 300.0, 50.0, "tr", 10.0), (0.0, 10.0));
    assert_eq!(anchor_in((0.0, 0.0, 1920.0, 1080.0), 340.0, 60.0, "mc", 20.0), (790.0, 510.0));
  }

  #[test]
  fn signature_changes_when_layout_changes() {
    let a = build(&[raw("x", 0, 0, 1920, 1080, 1.0)], None, &[]);
    let b = build(&[raw("x", 0, 0, 1920, 1080, 1.0), raw("y", 1920, 0, 1280, 720, 1.0)], None, &[]);
    assert_ne!(signature(&a), signature(&b));
    assert_eq!(signature(&a), signature(&a.clone()));
  }
}
