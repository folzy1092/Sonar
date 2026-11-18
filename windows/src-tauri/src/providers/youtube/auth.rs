//! Вход YouTube Music по cookie браузера: из cookie берём `SAPISID` (или `__Secure-3PAPISID`) и
//! подписываем каждый запрос заголовком `Authorization: SAPISIDHASH <ts>_<sha1>` — так делает сам
//! music.youtube.com. Cookie — секрет: живёт только в keyring, в логи и тексты ошибок не попадает.

use anyhow::{bail, Result};
use sha1::{Digest, Sha1};

/// Источник подписи — адрес сайта, с которого «пришёл» запрос.
pub const ORIGIN: &str = "https://music.youtube.com";

/// Cookie, по которым видно, что вход выполнен (любая из них годится для подписи).
const SAPISID_NAMES: [&str; 2] = ["SAPISID", "__Secure-3PAPISID"];

/// Значение cookie `name` из строки вида `a=1; b=2`.
pub fn cookie_value<'a>(cookie: &'a str, name: &str) -> Option<&'a str> {
  cookie
    .split(';')
    .filter_map(|part| part.trim().split_once('='))
    .find(|(k, _)| k.trim() == name)
    .map(|(_, v)| v.trim())
    .filter(|v| !v.is_empty())
}

/// `SAPISID` (или его безопасная пара `__Secure-3PAPISID`) — без него подписать запрос нельзя.
pub fn sapisid(cookie: &str) -> Option<&str> {
  SAPISID_NAMES.iter().find_map(|n| cookie_value(cookie, n))
}

/// `SAPISIDHASH <ts>_<sha1(ts + " " + SAPISID + " " + ORIGIN)>`.
pub fn sapisidhash(sapisid: &str, ts: u64) -> String {
  let digest = Sha1::digest(format!("{ts} {sapisid} {ORIGIN}").as_bytes());
  let hex: String = digest.iter().map(|b| format!("{b:02x}")).collect();
  format!("SAPISIDHASH {ts}_{hex}")
}

/// Вставленный пользователем cookie → одна строка `a=1; b=2`. Принимает заголовок целиком
/// (`Cookie: …`), переносы строк и лишние `;`. Без `SAPISID` — понятная ошибка (без самого cookie).
pub fn normalize_cookie(raw: &str) -> Result<String> {
  let body = raw.trim();
  let body = body.strip_prefix("Cookie:").or_else(|| body.strip_prefix("cookie:")).unwrap_or(body);
  let parts: Vec<String> = body
    .split(|c| c == ';' || c == '\n' || c == '\r')
    .map(str::trim)
    .filter(|p| p.contains('=') && !p.starts_with('='))
    .map(str::to_owned)
    .collect();
  let cookie = parts.join("; ");
  if cookie.is_empty() {
    bail!("Вставь cookie YouTube Music");
  }
  if sapisid(&cookie).is_none() {
    bail!("В cookie нет SAPISID — войди на music.youtube.com и скопируй cookie заново");
  }
  Ok(cookie)
}

/// Секунды Unix для подписи.
pub fn now_secs() -> u64 {
  std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn hash_matches_known_vector() {
    // Arrange: значения подобраны вручную, хэш посчитан sha1sum
    let ts = 1_700_000_000;
    // Act
    let h = sapisidhash("abcSAPISID", ts);
    // Assert
    assert_eq!(h, "SAPISIDHASH 1700000000_958be2d45afc2262a8777d73de623e5ba13eed75");
  }

  #[test]
  fn sapisid_prefers_plain_then_secure() {
    assert_eq!(sapisid("a=1; SAPISID=x; __Secure-3PAPISID=y"), Some("x"));
    assert_eq!(sapisid("a=1; __Secure-3PAPISID=y"), Some("y"));
    assert_eq!(sapisid("a=1; SAPISID="), None);
    assert_eq!(sapisid(""), None);
  }

  #[test]
  fn cookie_value_ignores_spaces_and_prefix_names() {
    assert_eq!(cookie_value(" HSID = h ;SID=s", "SID"), Some("s"));
    assert_eq!(cookie_value("APISID=a", "SAPISID"), None);
  }

  #[test]
  fn normalize_accepts_header_and_lines() {
    let got = normalize_cookie("Cookie: SID=1;\n SAPISID=abc ;;\r\nHSID=2").unwrap();
    assert_eq!(got, "SID=1; SAPISID=abc; HSID=2");
  }

  #[test]
  fn normalize_rejects_without_sapisid_and_hides_value() {
    let e = normalize_cookie("SID=secret-value").unwrap_err().to_string();
    assert!(e.contains("SAPISID"), "{e}");
    assert!(!e.contains("secret-value"), "{e}");
    assert_eq!(normalize_cookie("  ").unwrap_err().to_string(), "Вставь cookie YouTube Music");
  }
}
