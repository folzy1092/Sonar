//! access_key треков VK на диске (`vk-keys.json` рядом с базой): без него `audio.getById` чужой
//! трек не отдаёт, а ref трека (`vk:<owner>_<id>`) ключа не несёт. Трек из Любимых, смешанного
//! плейлиста, очереди или волны после перезапуска играет с тем ключом, который VK отдал при показе.
//! Ключ трека — не секрет входа (без токена VK он ничего не открывает), но в журнал не пишем.
//! Переполнение — выкидываем самые давние, а не всё сразу.

use std::collections::HashMap;
use std::path::PathBuf;

/// Сколько ключей помнить.
const MAX_KEYS: usize = 20_000;
/// После переполнения оставляем столько самых свежих (чтобы не чистить на каждом треке).
const KEEP_AFTER_TRIM: usize = MAX_KEYS * 9 / 10;

pub struct VkKeys {
  file: Option<PathBuf>,
  /// ref → (access_key, когда видели последний раз — счётчик).
  keys: HashMap<String, (String, u64)>,
  tick: u64,
}

impl VkKeys {
  /// Только в памяти (тесты, пока путь не задан).
  pub fn memory() -> Self {
    Self { file: None, keys: HashMap::new(), tick: 0 }
  }

  /// С файла `[[ref, key], …]` от давних к свежим; нет файла или он битый — пусто.
  pub fn open(file: PathBuf) -> Self {
    let pairs: Vec<(String, String)> = match std::fs::read(&file) {
      Ok(bytes) => serde_json::from_slice(&bytes).unwrap_or_else(|e| {
        log::warn!("[vk] ключи треков не прочитались: {e}");
        Vec::new()
      }),
      Err(_) => Vec::new(),
    };
    let mut store = Self { file: Some(file), ..Self::memory() };
    for (r, k) in pairs {
      store.tick += 1;
      store.keys.insert(r, (k, store.tick));
    }
    store
  }

  pub fn get(&self, track_ref: &str) -> Option<String> {
    self.keys.get(track_ref).map(|(k, _)| k.clone())
  }

  #[cfg(test)]
  pub fn len(&self) -> usize {
    self.keys.len()
  }

  /// Запомнить пары ref → ключ; новые или сменившиеся сразу пишем на диск.
  pub fn remember(&mut self, pairs: impl IntoIterator<Item = (String, String)>) {
    let mut changed = false;
    for (r, k) in pairs {
      self.tick += 1;
      let tick = self.tick;
      match self.keys.get_mut(&r) {
        Some(entry) if entry.0 == k => entry.1 = tick,
        _ => {
          self.keys.insert(r, (k, tick));
          changed = true;
        }
      }
    }
    if self.keys.len() > MAX_KEYS {
      self.trim();
      changed = true;
    }
    if changed {
      self.save();
    }
  }

  /// Оставить `KEEP_AFTER_TRIM` самых свежих.
  fn trim(&mut self) {
    let mut ticks: Vec<u64> = self.keys.values().map(|(_, t)| *t).collect();
    ticks.sort_unstable_by(|a, b| b.cmp(a));
    let Some(&oldest_kept) = ticks.get(KEEP_AFTER_TRIM.saturating_sub(1)) else { return };
    self.keys.retain(|_, (_, t)| *t >= oldest_kept);
  }

  /// От давних к свежим; через временный файл, чтобы не оставить половину при сбое.
  fn save(&self) {
    let Some(file) = &self.file else { return };
    let mut list: Vec<(&String, &(String, u64))> = self.keys.iter().collect();
    list.sort_unstable_by_key(|(_, (_, t))| *t);
    let pairs: Vec<(&str, &str)> = list.iter().map(|(r, (k, _))| (r.as_str(), k.as_str())).collect();
    let tmp = file.with_extension("json.tmp");
    let written = serde_json::to_vec(&pairs)
      .map_err(std::io::Error::other)
      .and_then(|bytes| std::fs::write(&tmp, bytes))
      .and_then(|_| std::fs::rename(&tmp, file));
    if let Err(e) = written {
      log::warn!("[vk] ключи треков не сохранились: {e}");
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn temp_file(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("sonar-vkkeys-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir.join("vk-keys.json")
  }

  #[test]
  fn keys_survive_reopen() {
    let file = temp_file("reopen");
    let mut a = VkKeys::open(file.clone());
    a.remember([("vk:-1_2".to_owned(), "k1".to_owned()), ("vk:5_6".to_owned(), "k2".to_owned())]);
    let b = VkKeys::open(file.clone());
    assert_eq!(b.get("vk:-1_2").as_deref(), Some("k1"));
    assert_eq!(b.get("vk:5_6").as_deref(), Some("k2"));
    assert_eq!(b.get("vk:7_8"), None);
    let _ = std::fs::remove_dir_all(file.parent().unwrap());
  }

  #[test]
  fn broken_file_is_empty() {
    let file = temp_file("broken");
    std::fs::write(&file, b"{not json").unwrap();
    assert_eq!(VkKeys::open(file.clone()).len(), 0);
    let _ = std::fs::remove_dir_all(file.parent().unwrap());
  }

  /// Переполнение выкидывает самые давние, свежие и недавно виденные остаются.
  #[test]
  fn overflow_drops_oldest_only() {
    let mut keys = VkKeys::memory();
    keys.remember((0..MAX_KEYS).map(|i| (format!("vk:1_{i}"), "k".to_owned())));
    // самый первый снова попался на глаза — он теперь свежий
    keys.remember([("vk:1_0".to_owned(), "k".to_owned())]);
    keys.remember([("vk:2_1".to_owned(), "new".to_owned())]);
    assert_eq!(keys.len(), KEEP_AFTER_TRIM);
    assert_eq!(keys.get("vk:2_1").as_deref(), Some("new"));
    assert_eq!(keys.get("vk:1_0").as_deref(), Some("k"));
    assert_eq!(keys.get("vk:1_1"), None);
    assert_eq!(keys.get(&format!("vk:1_{}", MAX_KEYS - 1)).as_deref(), Some("k"));
  }
}
