//! Привязка телефона: одноразовый 6-значный код на экране ПК (5 минут, 5 попыток) → постоянный ключ
//! устройства. Ключ знает только телефон (Keychain), ПК хранит его SHA-256 (keyring, `devices.rs`).
//! Время передаётся снаружи — логика чистая и проверяется тестами.

use super::protocol::CODE_LEN;
use base64::Engine;
use sha2::{Digest, Sha256};

/// Сколько живёт код на экране.
pub const CODE_TTL_MS: u64 = 5 * 60 * 1000;
/// После стольких неверных вводов код сгорает — перебрать миллион за 5 попыток нельзя.
pub const MAX_ATTEMPTS: u32 = 5;
const KEY_BYTES: usize = 32;
const CODE_SPACE: u32 = 1_000_000;

/// Случайные байты из генератора ОС.
fn random_bytes<const N: usize>() -> [u8; N] {
  let mut buf = [0u8; N];
  getrandom::fill(&mut buf).expect("генератор случайных чисел ОС недоступен");
  buf
}

/// 6 цифр без перекоса: отбрасываем значения выше наибольшего кратного миллиону.
pub fn new_code() -> String {
  let limit = u32::MAX - (u32::MAX % CODE_SPACE);
  loop {
    let n = u32::from_le_bytes(random_bytes::<4>());
    if n < limit {
      return format!("{:0width$}", n % CODE_SPACE, width = CODE_LEN);
    }
  }
}

/// Постоянный ключ устройства: 32 случайных байта, base64url без `=` (43 знака).
pub fn new_key() -> String {
  base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(random_bytes::<KEY_BYTES>())
}

/// Постоянный id этого ПК для телефонов (по нему телефон находит свой ключ в Keychain).
pub fn new_pc_id() -> String {
  let bytes = random_bytes::<12>();
  format!("pc_{}", bytes.iter().map(|b| format!("{b:02x}")).collect::<String>())
}

/// Что хранится вместо ключа.
pub fn hash_key(key: &str) -> String {
  Sha256::digest(key.as_bytes()).iter().map(|b| format!("{b:02x}")).collect()
}

/// Сравнение без раннего выхода — время ответа не подсказывает, сколько знаков совпало.
pub fn same(a: &str, b: &str) -> bool {
  let (a, b) = (a.as_bytes(), b.as_bytes());
  if a.len() != b.len() {
    return false;
  }
  a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

/// Ключ подходит к сохранённому хешу.
pub fn key_matches(key: &str, stored_hash: &str) -> bool {
  same(&hash_key(key), stored_hash)
}

/// Код, который сейчас на экране ПК.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PairCode {
  pub code: String,
  pub expires_at_ms: u64,
  pub attempts: u32,
}

/// Чем закончилась попытка ввести код.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Check {
  /// Код верный — он больше не действует, можно выдавать ключ.
  Ok,
  /// Кода нет (не открыт или уже использован).
  NoCode,
  Expired,
  /// Неверно; `left` — сколько попыток осталось (0 — код сгорел).
  Wrong { left: u32 },
}

impl Check {
  /// Код ошибки для телефона.
  pub fn error_code(&self) -> &'static str {
    match self {
      Check::Ok => "",
      Check::NoCode => "no_code",
      Check::Expired => "code_expired",
      Check::Wrong { left: 0 } => "code_burned",
      Check::Wrong { .. } => "bad_code",
    }
  }
}

impl PairCode {
  pub fn new(now_ms: u64) -> Self {
    Self::with_code(new_code(), now_ms)
  }

  pub fn with_code(code: String, now_ms: u64) -> Self {
    Self { code, expires_at_ms: now_ms + CODE_TTL_MS, attempts: 0 }
  }
}

/// Проверить код и обновить состояние: верный и просроченный код убираются, неверный тратит попытку.
pub fn check(slot: &mut Option<PairCode>, entered: &str, now_ms: u64) -> Check {
  let Some(pc) = slot.as_mut() else { return Check::NoCode };
  if now_ms >= pc.expires_at_ms {
    *slot = None;
    return Check::Expired;
  }
  if same(&pc.code, entered) {
    *slot = None;
    return Check::Ok;
  }
  pc.attempts += 1;
  let left = MAX_ATTEMPTS.saturating_sub(pc.attempts);
  if left == 0 {
    *slot = None;
  }
  Check::Wrong { left }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::remote::protocol::{is_code, is_key};

  #[test]
  fn codes_and_keys_look_right() {
    for _ in 0..200 {
      assert!(is_code(&new_code()));
    }
    let k = new_key();
    assert_eq!(k.len(), 43);
    assert!(is_key(&k));
    assert_ne!(new_key(), k, "ключи случайные");
    let id = new_pc_id();
    assert!(id.starts_with("pc_") && id.len() == 27);
  }

  #[test]
  fn right_code_works_once() {
    let mut slot = Some(PairCode::with_code("123456".into(), 1_000));
    assert_eq!(check(&mut slot, "123456", 2_000), Check::Ok);
    assert_eq!(slot, None);
    assert_eq!(check(&mut slot, "123456", 2_001), Check::NoCode);
  }

  #[test]
  fn code_expires() {
    let mut slot = Some(PairCode::with_code("123456".into(), 0));
    assert_eq!(check(&mut slot, "123456", CODE_TTL_MS), Check::Expired);
    assert_eq!(slot, None);
  }

  #[test]
  fn wrong_codes_burn_it() {
    let mut slot = Some(PairCode::with_code("123456".into(), 0));
    for left in (1..MAX_ATTEMPTS).rev() {
      let r = check(&mut slot, "000000", 10);
      assert_eq!(r, Check::Wrong { left });
      assert_eq!(r.error_code(), "bad_code");
    }
    let last = check(&mut slot, "000000", 10);
    assert_eq!(last, Check::Wrong { left: 0 });
    assert_eq!(last.error_code(), "code_burned");
    // даже верный код после этого не проходит
    assert_eq!(check(&mut slot, "123456", 10), Check::NoCode);
  }

  #[test]
  fn key_hash_check() {
    let k = new_key();
    let h = hash_key(&k);
    assert_eq!(h.len(), 64);
    assert!(key_matches(&k, &h));
    assert!(!key_matches(&new_key(), &h));
    assert!(!same("abc", "abcd"));
    assert!(same("", ""));
  }
}
