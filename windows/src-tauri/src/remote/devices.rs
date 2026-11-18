//! Привязанные телефоны и id этого ПК — в keyring (`remote`), рядом с токенами сервисов.
//! Ключей тут нет — только их SHA-256; в журнал и интерфейс не уходят даже хеши.
//! Правки — чистые функции, возвращают новый список (тесты ниже).

use super::pairing::{hash_key, key_matches, new_pc_id};
use super::protocol::DeviceHello;
use serde::{Deserialize, Serialize};

const SECRET: &str = "remote";
/// Больше телефонов к одному ПК не привязать (старые отвязываются в настройках).
pub const MAX_DEVICES: usize = 16;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Device {
  pub id: String,
  pub name: String,
  pub key_hash: String,
  pub paired_at: i64,
  #[serde(default)]
  pub last_seen: i64,
}

/// Что лежит в keyring.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Vault {
  #[serde(default)]
  pub pc_id: String,
  #[serde(default)]
  pub devices: Vec<Device>,
}

/// Устройство для настроек — без хеша ключа.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct DeviceView {
  pub id: String,
  pub name: String,
  pub paired_at: i64,
  pub last_seen: i64,
  pub online: bool,
}

impl Vault {
  /// Из keyring; id ПК создаётся при первом обращении.
  pub fn load() -> Self {
    let v: Vault = crate::secrets::load(SECRET).unwrap_or_default();
    v.with_pc_id()
  }

  pub fn save(&self) -> anyhow::Result<()> {
    crate::secrets::save(SECRET, self)
  }

  fn with_pc_id(self) -> Self {
    if self.pc_id.is_empty() {
      Self { pc_id: new_pc_id(), ..self }
    } else {
      self
    }
  }

  /// Привязать (или перепривязать тот же телефон с новым ключом).
  pub fn paired(&self, d: &DeviceHello, key: &str, now: i64) -> Self {
    let fresh = Device { id: d.id.clone(), name: d.name.clone(), key_hash: hash_key(key), paired_at: now, last_seen: now };
    let mut devices: Vec<Device> = self.devices.iter().filter(|x| x.id != d.id).cloned().collect();
    devices.push(fresh);
    // лишние — самые давно не появлявшиеся
    if devices.len() > MAX_DEVICES {
      devices.sort_by_key(|x| std::cmp::Reverse(x.last_seen));
      devices.truncate(MAX_DEVICES);
      devices.sort_by_key(|x| x.paired_at);
    }
    Self { devices, ..self.clone() }
  }

  pub fn without(&self, id: &str) -> Self {
    Self { devices: self.devices.iter().filter(|x| x.id != id).cloned().collect(), ..self.clone() }
  }

  /// Телефон с этим id и ключом привязан.
  pub fn verify(&self, id: &str, key: &str) -> bool {
    self.devices.iter().any(|x| x.id == id && key_matches(key, &x.key_hash))
  }

  /// Отметить вход: свежее имя телефона и время.
  pub fn seen(&self, d: &DeviceHello, now: i64) -> Self {
    let devices = self
      .devices
      .iter()
      .map(|x| if x.id == d.id { Device { name: d.name.clone(), last_seen: now, ..x.clone() } } else { x.clone() })
      .collect();
    Self { devices, ..self.clone() }
  }

  pub fn views(&self, online: &[String]) -> Vec<DeviceView> {
    self
      .devices
      .iter()
      .map(|x| DeviceView { id: x.id.clone(), name: x.name.clone(), paired_at: x.paired_at, last_seen: x.last_seen, online: online.contains(&x.id) })
      .collect()
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn phone(id: &str) -> DeviceHello {
    DeviceHello { id: id.into(), name: format!("iPhone {id}") }
  }

  #[test]
  fn pair_verify_unpair() {
    let v = Vault::default().with_pc_id();
    assert!(v.pc_id.starts_with("pc_"));
    let v = v.paired(&phone("a"), "key-a-0123456789", 10);
    assert!(v.verify("a", "key-a-0123456789"));
    assert!(!v.verify("a", "key-b-0123456789"));
    assert!(!v.verify("b", "key-a-0123456789"));
    assert!(!serde_json::to_string(&v).unwrap().contains("key-a"), "сам ключ не хранится");
    let v = v.without("a");
    assert!(!v.verify("a", "key-a-0123456789"));
  }

  #[test]
  fn repairing_replaces_key() {
    let v = Vault::default().paired(&phone("a"), "old-key-000000000", 1).paired(&phone("a"), "new-key-000000000", 2);
    assert_eq!(v.devices.len(), 1);
    assert!(!v.verify("a", "old-key-000000000"));
    assert!(v.verify("a", "new-key-000000000"));
  }

  #[test]
  fn seen_updates_name_and_time() {
    let v = Vault::default().paired(&phone("a"), "key-a-0123456789", 1);
    let v2 = v.seen(&DeviceHello { id: "a".into(), name: "Новое имя".into() }, 99);
    assert_eq!((v2.devices[0].name.as_str(), v2.devices[0].last_seen), ("Новое имя", 99));
    assert_eq!(v.devices[0].last_seen, 1, "старое значение не меняется");
    let views = v2.views(&["a".into()]);
    assert!(views[0].online);
    assert!(!serde_json::to_string(&views).unwrap().contains("key_hash"));
  }

  #[test]
  fn keeps_at_most_max_devices() {
    let mut v = Vault::default();
    for i in 0..(MAX_DEVICES + 3) {
      v = v.paired(&phone(&i.to_string()), "key-0000000000000", i as i64);
    }
    assert_eq!(v.devices.len(), MAX_DEVICES);
    assert!(v.devices.iter().all(|d| d.id != "0"), "выпал самый старый");
  }
}
