//! Офлайн-режим (`general.offline`, спека — `docs/OFFLINE.md`): Sonar не выходит в интернет.
//! Владелец флага — этот модуль; интерфейс его зеркалит (`lib/offline.svelte.ts`) по событию `offline-changed`.
//! Флаг читается из базы первым при запуске (`lib.rs`), до любой сетевой задачи; соединения режут ворота
//! `net::client`, сетевые команды — `guard()` первой строкой.
use std::sync::atomic::{AtomicBool, Ordering};

use tauri::{AppHandle, Emitter};

/// Ключ настройки (в синк не идёт — `store/sync.rs` `LOCAL_SETTINGS`).
pub const KEY: &str = "general.offline";
/// Событие для интерфейса: `bool` — включён ли режим.
pub const EVENT: &str = "offline-changed";
/// Текст ошибки любой сетевой команды в офлайне.
pub const MESSAGE: &str = "Нет доступа к сети: включён офлайн-режим";

static ON: AtomicBool = AtomicBool::new(false);

pub fn is_on() -> bool {
  ON.load(Ordering::SeqCst)
}

/// Поставить флаг без события — при запуске (значение уже в базе).
pub fn set_on(on: bool) {
  ON.store(on, Ordering::SeqCst);
}

/// Включить или выключить и сказать интерфейсу. Включение отменяет фоновую подкачку треков.
pub fn switch(app: &AppHandle, on: bool) {
  let was = ON.swap(on, Ordering::SeqCst);
  if on && !was {
    crate::stream::cancel_prefetch();
  }
  if let Err(e) = app.emit(EVENT, on) {
    eprintln!("офлайн: событие {EVENT} не ушло — {e}");
  }
}

/// Первая строка сетевой команды: в офлайне — ошибка `MESSAGE`, без единого запроса.
pub fn guard() -> Result<(), String> {
  if is_on() {
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
}
