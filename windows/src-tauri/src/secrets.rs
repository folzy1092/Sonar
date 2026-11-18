//! Токены сервисов — в Диспетчере учётных данных Windows (keyring), не в базе и не в файлах.
//! Запись: служба `com.folzy.sonar`, имя `soundcloud` / `yandex`, значение — JSON ключей.

use anyhow::Result;
use serde::{de::DeserializeOwned, Serialize};

const SERVICE: &str = "com.folzy.sonar";

pub fn load<T: DeserializeOwned>(name: &str) -> Option<T> {
  let entry = keyring::Entry::new(SERVICE, name).ok()?;
  serde_json::from_str(&entry.get_password().ok()?).ok()
}

pub fn save<T: Serialize>(name: &str, value: &T) -> Result<()> {
  keyring::Entry::new(SERVICE, name)?.set_password(&serde_json::to_string(value)?)?;
  Ok(())
}

pub fn delete(name: &str) -> Result<()> {
  match keyring::Entry::new(SERVICE, name)?.delete_credential() {
    Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
    Err(e) => Err(e.into()),
  }
}

/// Записи интеграций, которых больше нет (Last.fm — docs/LASTFM_EXIT.md). Стираются при запуске, если
/// остались: после первого раза записи уже нет, и это одно чтение keyring.
const RETIRED: [&str; 1] = ["lastfm"];

pub fn forget_retired() {
  for name in RETIRED {
    if load::<serde_json::Value>(name).is_none() {
      continue;
    }
    match delete(name) {
      Ok(()) => log::info!("keyring: стёрта старая запись {name}"),
      Err(e) => log::warn!("keyring: не удалось стереть {name}: {e}"),
    }
  }
}
