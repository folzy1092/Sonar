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
