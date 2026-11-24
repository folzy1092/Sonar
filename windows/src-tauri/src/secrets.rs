//! Токены сервисов — в Диспетчере учётных данных Windows (keyring), не в базе и не в файлах.
//! Запись: служба `com.folzy.sonar`, имя `soundcloud` / `yandex` / …, значение — JSON ключей.
//!
//! У одной записи Диспетчера предел — 2560 байт (UTF-16), а cookie YouTube Music длиннее. Большой JSON
//! режется на части ≤ `PART_UNITS` UTF-16-символов: `<name>#1`, `<name>#2`…, а в `<name>` — заголовок
//! с числом частей. Короткие секреты, как и раньше, лежат одной записью — старые входы читаются как были.

use anyhow::Result;
use serde::{de::DeserializeOwned, Serialize};

const SERVICE: &str = "com.folzy.sonar";
/// Часть ≤ 1200 UTF-16-символов = ≤ 2400 байт — с запасом до предела 2560.
const PART_UNITS: usize = 1200;
/// Заголовок разбитой записи: `sonar-parts:<N>` (JSON с такого не начинается).
const HEADER: &str = "sonar-parts:";

/// Где лежат записи: keyring в приложении, словарь в тестах.
trait Vault {
  fn get(&self, name: &str) -> Option<String>;
  fn set(&self, name: &str, value: &str) -> Result<()>;
  fn remove(&self, name: &str) -> Result<()>;
}

struct Keyring;

impl Vault for Keyring {
  fn get(&self, name: &str) -> Option<String> {
    keyring::Entry::new(SERVICE, name).ok()?.get_password().ok()
  }
  fn set(&self, name: &str, value: &str) -> Result<()> {
    keyring::Entry::new(SERVICE, name)?.set_password(value)?;
    Ok(())
  }
  fn remove(&self, name: &str) -> Result<()> {
    match keyring::Entry::new(SERVICE, name)?.delete_credential() {
      Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
      Err(e) => Err(e.into()),
    }
  }
}

pub fn load<T: DeserializeOwned>(name: &str) -> Option<T> {
  serde_json::from_str(&read(&Keyring, name)?).ok()
}

pub fn save<T: Serialize>(name: &str, value: &T) -> Result<()> {
  write(&Keyring, name, &serde_json::to_string(value)?)
}

pub fn delete(name: &str) -> Result<()> {
  erase(&Keyring, name)
}

fn part_name(name: &str, i: usize) -> String {
  format!("{name}#{i}")
}

fn parts_in(head: &str) -> Option<usize> {
  head.strip_prefix(HEADER)?.parse().ok()
}

/// Разрезать строку на части не длиннее `max` UTF-16-символов, не разрывая символ.
fn split_utf16(text: &str, max: usize) -> Vec<&str> {
  let mut parts = Vec::new();
  let (mut start, mut units) = (0, 0);
  for (i, c) in text.char_indices() {
    if units + c.len_utf16() > max {
      parts.push(&text[start..i]);
      start = i;
      units = 0;
    }
    units += c.len_utf16();
  }
  if start < text.len() || parts.is_empty() {
    parts.push(&text[start..]);
  }
  parts
}

fn read(v: &impl Vault, name: &str) -> Option<String> {
  let head = v.get(name)?;
  let Some(n) = parts_in(&head) else { return Some(head) };
  (1..=n).map(|i| v.get(&part_name(name, i))).collect()
}

fn write(v: &impl Vault, name: &str, json: &str) -> Result<()> {
  let old = v.get(name).as_deref().and_then(parts_in).unwrap_or(0);
  let parts = split_utf16(json, PART_UNITS);
  let n = if parts.len() == 1 {
    v.set(name, json)?;
    0
  } else {
    for (i, p) in parts.iter().enumerate() {
      v.set(&part_name(name, i + 1), p)?;
    }
    // заголовок — последним: пока части не записаны, прежний вход остаётся целым
    v.set(name, &format!("{HEADER}{}", parts.len()))?;
    parts.len()
  };
  for i in n + 1..=old {
    v.remove(&part_name(name, i))?;
  }
  Ok(())
}

fn erase(v: &impl Vault, name: &str) -> Result<()> {
  let n = v.get(name).as_deref().and_then(parts_in).unwrap_or(0);
  for i in 1..=n {
    v.remove(&part_name(name, i))?;
  }
  v.remove(name)
}

/// Записи интеграций, которых больше нет (Last.fm — docs/LASTFM_EXIT.md). Стираются при запуске, если
/// остались: после первого раза записи уже нет, и это одно чтение keyring.
const RETIRED: [&str; 2] = ["lastfm", "vk"];

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

#[cfg(test)]
mod tests {
  use super::*;
  use std::{cell::RefCell, collections::BTreeMap};

  /// Как Диспетчер учётных данных: запись длиннее 2560 байт UTF-16 не принимается.
  #[derive(Default)]
  struct Memory(RefCell<BTreeMap<String, String>>);

  impl Vault for Memory {
    fn get(&self, name: &str) -> Option<String> {
      self.0.borrow().get(name).cloned()
    }
    fn set(&self, name: &str, value: &str) -> Result<()> {
      anyhow::ensure!(value.encode_utf16().count() * 2 <= 2560, "password encoded as UTF-16 is longer than 2560 chars");
      self.0.borrow_mut().insert(name.into(), value.into());
      Ok(())
    }
    fn remove(&self, name: &str) -> Result<()> {
      self.0.borrow_mut().remove(name);
      Ok(())
    }
  }

  fn cookie_json(bytes: usize) -> String {
    // cookie YouTube: латиница, `;`, `=`, плюс кириллица и эмодзи — проверка границ UTF-16
    let mut s = String::from(r#"{"cookie":""#);
    let alphabet = ["SAPISID=", "abcXYZ0123456789", ";", "ж", "🎵", "__Secure-3PSID="];
    let mut i = 0;
    while s.len() < bytes {
      s.push_str(alphabet[i % alphabet.len()]);
      i += 1;
    }
    s.push_str(r#""}"#);
    s
  }

  #[test]
  fn ten_kilobytes_round_trip_in_parts() {
    let v = Memory::default();
    let json = cookie_json(10 * 1024);
    write(&v, "youtube", &json).unwrap();
    assert_eq!(read(&v, "youtube").as_deref(), Some(json.as_str()));
    let n = parts_in(&v.get("youtube").unwrap()).unwrap();
    assert!(n > 1);
    assert!((1..=n).all(|i| v.get(&part_name("youtube", i)).unwrap().encode_utf16().count() <= PART_UNITS));
  }

  #[test]
  fn delete_removes_every_part() {
    let v = Memory::default();
    write(&v, "youtube", &cookie_json(10 * 1024)).unwrap();
    erase(&v, "youtube").unwrap();
    assert!(v.0.borrow().is_empty());
  }

  #[test]
  fn short_secret_stays_single_and_old_entries_read() {
    let v = Memory::default();
    // старая запись, сделанная до частей
    v.set("yandex", r#"{"token":"y0_abc"}"#).unwrap();
    assert_eq!(read(&v, "yandex").as_deref(), Some(r#"{"token":"y0_abc"}"#));
    write(&v, "soundcloud", r#"{"oauth":"x"}"#).unwrap();
    assert_eq!(v.0.borrow().len(), 2);
  }

  #[test]
  fn shrinking_secret_drops_leftover_parts() {
    let v = Memory::default();
    write(&v, "youtube", &cookie_json(10 * 1024)).unwrap();
    write(&v, "youtube", &cookie_json(3 * 1024)).unwrap();
    let n = parts_in(&v.get("youtube").unwrap()).unwrap();
    assert_eq!(v.0.borrow().len(), n + 1);
    write(&v, "youtube", r#"{"cookie":"short"}"#).unwrap();
    assert_eq!(v.0.borrow().len(), 1);
    assert_eq!(read(&v, "youtube").as_deref(), Some(r#"{"cookie":"short"}"#));
  }

  #[test]
  fn missing_part_reads_as_absent() {
    let v = Memory::default();
    write(&v, "youtube", &cookie_json(5 * 1024)).unwrap();
    v.remove(&part_name("youtube", 2)).unwrap();
    assert_eq!(read(&v, "youtube"), None);
  }

  #[test]
  fn split_keeps_surrogate_pairs_whole() {
    let s = "🎵".repeat(5);
    let parts = split_utf16(&s, 3);
    assert_eq!(parts.concat(), s);
    assert!(parts.iter().all(|p| p.encode_utf16().count() <= 3));
    assert_eq!(split_utf16("", 3), vec![""]);
  }
}
