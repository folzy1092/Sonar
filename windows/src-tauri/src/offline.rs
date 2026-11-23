//! Офлайн-режим (`general.offline`, спека — `docs/OFFLINE.md`): Sonar не выходит в интернет.
//! Владелец флага — этот модуль; интерфейс его зеркалит (`lib/offline.svelte.ts`) по событию `offline-changed`.
//! Флаг читается из базы первым при запуске (`lib.rs`), до любой сетевой задачи; соединения режут ворота
//! `net::client`, сетевые команды — `guard()` первой строкой.
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};

use tauri::{AppHandle, Emitter, Manager};

/// Ключ настройки (в синк не идёт — `store/sync.rs` `LOCAL_SETTINGS`).
pub const KEY: &str = "general.offline";
/// Событие для интерфейса: `bool` — включён ли режим.
pub const EVENT: &str = "offline-changed";
/// Текст ошибки любой сетевой команды в офлайне.
pub const MESSAGE: &str = "Нет доступа к сети: включён офлайн-режим";

static ON: AtomicBool = AtomicBool::new(false);
/// Сколько попыток выйти в сеть отбито с последнего включения (ворота `net.rs` и `guard()`); «Сеть» в настройках.
static BLOCKED: AtomicU64 = AtomicU64::new(0);

pub fn is_on() -> bool {
  ON.load(Ordering::SeqCst)
}

/// Поставить флаг без события — при запуске (значение уже в базе).
pub fn set_on(on: bool) {
  ON.store(on, Ordering::SeqCst);
}

/// Включить или выключить и сказать интерфейсу. Включение отменяет фоновую подкачку, выключение будит очередь скачивания.
pub fn switch(app: &AppHandle, on: bool) {
  let was = ON.swap(on, Ordering::SeqCst);
  if on && !was {
    BLOCKED.store(0, Ordering::SeqCst);
    crate::stream::cancel_prefetch();
  }
  // очередь скачивания в офлайне стоит (начатое оборвалось само) — при выходе продолжаем
  if !on && was {
    crate::downloads::pump(app);
  }
  crate::tray::set_offline_checked(on);
  if let Err(e) = app.emit(EVENT, on) {
    eprintln!("офлайн: событие {EVENT} не ушло — {e}");
  }
}

/// Переключить из трея: как `set_setting` — сначала база, потом флаг. Запись упала — флаг и галочка прежние.
pub fn toggle(app: &AppHandle) {
  let on = !is_on();
  let db = app.state::<crate::commands::Db>();
  let saved = match db.0.lock() {
    Ok(store) => store.set_setting(KEY, &serde_json::json!(on)).map_err(|e| e.to_string()),
    Err(e) => Err(e.to_string()),
  };
  match saved {
    Ok(()) => switch(app, on),
    Err(e) => {
      eprintln!("офлайн: переключение из трея не записалось — {e}");
      crate::tray::set_offline_checked(is_on());
    }
  }
}

/// Попытка выйти в сеть отбита (ворота соединений или `guard()`).
pub fn note_blocked() {
  BLOCKED.fetch_add(1, Ordering::Relaxed);
}

/// Сколько попыток отбито с последнего включения режима.
pub fn blocked() -> u64 {
  BLOCKED.load(Ordering::Relaxed)
}

/// Первая строка сетевой команды: в офлайне — ошибка `MESSAGE`, без единого запроса.
pub fn guard() -> Result<(), String> {
  if is_on() {
    note_blocked();
    Err(MESSAGE.to_owned())
  } else {
    Ok(())
  }
}

/// Значение из базы: всё, кроме явного `false`, при ошибке чтения считается «включено» — лучше тишина, чем трафик в роуминге.
pub fn from_setting<E: std::fmt::Display>(value: Result<Option<serde_json::Value>, E>) -> bool {
  match value {
    Ok(None) => false,
    Ok(Some(v)) => v.as_bool().unwrap_or(true),
    Err(e) => {
      eprintln!("офлайн: настройка не прочиталась, считаю режим включённым — {e}");
      true
    }
  }
}

#[cfg(test)]
pub(crate) mod tests {
  use super::*;
  use std::sync::Mutex;

  /// Флаг общий на процесс, а тесты идут параллельно — кто трогает флаг, держит этот замок.
  pub static FLAG: Mutex<()> = Mutex::new(());

  #[test]
  fn unreadable_setting_means_offline() {
    assert!(!from_setting::<&str>(Ok(None)));
    assert!(!from_setting::<&str>(Ok(Some(serde_json::json!(false)))));
    assert!(from_setting::<&str>(Ok(Some(serde_json::json!(true)))));
    assert!(from_setting::<&str>(Ok(Some(serde_json::json!("мусор")))));
    assert!(from_setting::<&str>(Err("база заперта")));
  }

  #[test]
  fn guard_follows_flag() {
    let _lock = FLAG.lock().unwrap_or_else(|p| p.into_inner());
    set_on(true);
    assert_eq!(guard(), Err(MESSAGE.to_owned()));
    set_on(false);
    assert_eq!(guard(), Ok(()));
  }

  #[test]
  fn guard_counts_refusals_only_in_offline() {
    let _lock = FLAG.lock().unwrap_or_else(|p| p.into_inner());
    BLOCKED.store(0, Ordering::SeqCst);
    set_on(false);
    let _ = guard();
    assert_eq!(blocked(), 0, "в сети отказов нет — и счёт стоит");
    set_on(true);
    let _ = guard();
    let _ = guard();
    note_blocked();
    assert_eq!(blocked(), 3);
    set_on(false);
  }
}
