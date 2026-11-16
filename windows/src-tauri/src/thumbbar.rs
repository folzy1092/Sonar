//! Кнопки в превью окна на панели задач Windows (решение владельца 2026-11-16): навёл на Sonar в
//! панели задач — под миниатюрой «назад», «пауза / играть», «вперёд». Значки — наши же MingCute:
//! интерфейс рисует их в canvas 32×32 и присылает пиксели (`thumbbar_init`), поэтому стиль тот же,
//! что во всём приложении. Нажатие → событие `media-control` (как медиа-клавиши). Windows
//! пересоздаёт кнопку окна на панели задач (свернули в трей и вернули) — кнопки добавляются заново
//! по сообщению `TaskbarButtonCreated`.

use anyhow::{anyhow, Result};
use std::cell::RefCell;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::OnceLock;
use tauri::{AppHandle, Emitter, Manager};
use windows::core::w;
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::Graphics::Gdi::{CreateBitmap, DeleteObject, HGDIOBJ};
use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_INPROC_SERVER};
use windows::Win32::UI::Shell::{
  DefSubclassProc, ITaskbarList3, SetWindowSubclass, TaskbarList, THBF_ENABLED, THBN_CLICKED, THB_FLAGS, THB_ICON, THB_TOOLTIP,
  THUMBBUTTON,
};
use windows::Win32::UI::WindowsAndMessaging::{CreateIconIndirect, RegisterWindowMessageW, HICON, ICONINFO, WM_COMMAND};

const SIZE: i32 = 32;
const ID_PREV: u32 = 1;
const ID_PLAY: u32 = 2;
const ID_NEXT: u32 = 3;

static APP: OnceLock<AppHandle> = OnceLock::new();
static CREATED: AtomicU32 = AtomicU32::new(0);

struct Thumb {
  hwnd: HWND,
  list: ITaskbarList3,
  /// prev, play, pause, next
  icons: [HICON; 4],
  playing: bool,
  added: bool,
}

thread_local! {
  // всё — в потоке окна (COM и оконная процедура), поэтому без Mutex
  static TB: RefCell<Option<Thumb>> = const { RefCell::new(None) };
}

/// RGBA 32×32 (как из canvas) → значок Windows с прозрачностью.
fn icon(rgba: &[u8]) -> Result<HICON> {
  if rgba.len() != (SIZE * SIZE * 4) as usize {
    return Err(anyhow!("значок не 32×32"));
  }
  let bgra: Vec<u8> = rgba.chunks_exact(4).flat_map(|p| [p[2], p[1], p[0], p[3]]).collect();
  unsafe {
    let color = CreateBitmap(SIZE, SIZE, 1, 32, Some(bgra.as_ptr().cast()));
    let mask_bits = vec![0u8; (SIZE * SIZE / 8) as usize];
    let mask = CreateBitmap(SIZE, SIZE, 1, 1, Some(mask_bits.as_ptr().cast()));
    let info = ICONINFO { fIcon: true.into(), xHotspot: 0, yHotspot: 0, hbmMask: mask, hbmColor: color };
    let h = CreateIconIndirect(&info);
    let _ = DeleteObject(HGDIOBJ(color.0));
    let _ = DeleteObject(HGDIOBJ(mask.0));
    Ok(h?)
  }
}

fn tip(s: &str) -> [u16; 260] {
  let mut out = [0u16; 260];
  for (i, c) in s.encode_utf16().take(259).enumerate() {
    out[i] = c;
  }
  out
}

fn buttons(t: &Thumb) -> [THUMBBUTTON; 3] {
  let b = |id: u32, icon: HICON, text: &str| THUMBBUTTON {
    dwMask: THB_ICON | THB_TOOLTIP | THB_FLAGS,
    iId: id,
    iBitmap: 0,
    hIcon: icon,
    szTip: tip(text),
    dwFlags: THBF_ENABLED,
  };
  [
    b(ID_PREV, t.icons[0], "Назад"),
    if t.playing { b(ID_PLAY, t.icons[2], "Пауза") } else { b(ID_PLAY, t.icons[1], "Играть") },
    b(ID_NEXT, t.icons[3], "Вперёд"),
  ]
}

fn add(t: &mut Thumb) {
  let bs = buttons(t);
  // добавить можно только один раз на кнопку окна в панели задач; потом — обновлять
  let r = unsafe {
    if t.added {
      t.list.ThumbBarUpdateButtons(t.hwnd, &bs)
    } else {
      t.list.ThumbBarAddButtons(t.hwnd, &bs)
    }
  };
  match r {
    Ok(()) => t.added = true,
    Err(e) => log::warn!("кнопки в превью панели задач: {e}"),
  }
}

unsafe extern "system" fn proc(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM, _id: usize, _data: usize) -> LRESULT {
  if msg == WM_COMMAND && ((wp.0 >> 16) & 0xffff) as u32 == THBN_CLICKED {
    let action = match (wp.0 & 0xffff) as u32 {
      ID_PREV => Some("previous"),
      ID_PLAY => Some("toggle"),
      ID_NEXT => Some("next"),
      _ => None,
    };
    if let (Some(a), Some(app)) = (action, APP.get()) {
      let _ = app.emit("media-control", a);
      return LRESULT(0);
    }
  }
  let created = CREATED.load(Ordering::Relaxed);
  if created != 0 && msg == created {
    // Windows пересоздал кнопку окна в панели задач — кнопок под превью больше нет
    TB.with(|tb| {
      if let Some(t) = tb.borrow_mut().as_mut() {
        t.added = false;
        add(t);
      }
    });
  }
  unsafe { DefSubclassProc(hwnd, msg, wp, lp) }
}

/// Поставить кнопки (вызывать в потоке окна). `icons` — prev, play, pause, next, RGBA 32×32.
fn init_main(app: &AppHandle, icons: Vec<Vec<u8>>, playing: bool) -> Result<()> {
  let _ = APP.set(app.clone());
  let w = app.get_webview_window("main").ok_or_else(|| anyhow!("нет главного окна"))?;
  let hwnd = HWND(w.hwnd()?.0 as _);
  if icons.len() != 4 {
    return Err(anyhow!("нужно 4 значка"));
  }
  let made: Vec<HICON> = icons.iter().map(|i| icon(i)).collect::<Result<_>>()?;
  let fresh = TB.with(|tb| tb.borrow().is_none());
  let list: ITaskbarList3 = match TB.with(|tb| tb.borrow().as_ref().map(|t| t.list.clone())) {
    Some(l) => l,
    None => unsafe {
      let l: ITaskbarList3 = CoCreateInstance(&TaskbarList, None, CLSCTX_INPROC_SERVER)?;
      l.HrInit()?;
      l
    },
  };
  if fresh {
    CREATED.store(unsafe { RegisterWindowMessageW(w!("TaskbarButtonCreated")) }, Ordering::Relaxed);
    unsafe {
      let _ = SetWindowSubclass(hwnd, Some(proc), 0x50_4e_52, 0);
    }
  }
  TB.with(|tb| {
    let mut tb = tb.borrow_mut();
    let added = tb.as_ref().is_some_and(|t| t.added);
    let mut t = Thumb { hwnd, list, icons: [made[0], made[1], made[2], made[3]], playing, added };
    add(&mut t);
    *tb = Some(t);
  });
  Ok(())
}

pub fn init(app: &AppHandle, icons: Vec<Vec<u8>>, playing: bool) -> Result<()> {
  let a = app.clone();
  app.run_on_main_thread(move || {
    if let Err(e) = init_main(&a, icons, playing) {
      log::warn!("кнопки в превью панели задач: {e}");
    }
  })?;
  Ok(())
}

/// Играет / пауза — средняя кнопка меняет значок.
pub fn set_playing(app: &AppHandle, playing: bool) {
  let _ = app.run_on_main_thread(move || {
    TB.with(|tb| {
      if let Some(t) = tb.borrow_mut().as_mut() {
        if t.playing != playing {
          t.playing = playing;
          if t.added {
            add(t);
          }
        }
      }
    });
  });
}
