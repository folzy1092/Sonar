//! SoundCloud ответил 401/403 на своих ключах (docs/POLISH_PROMPT.md п. 8). Ключи при входе — это
//! публичный client_id с soundcloud.com и cookie `oauth_token`; SoundCloud время от времени меняет
//! публичный client_id, и старый начинает отвечать 401. Порядок починки:
//! 1. взять публичный client_id заново и повторить запрос — помогло, сохраняем новый id;
//! 2. не помогло — тихо обновить вход: скрытое окно soundcloud.com с той же папкой WebView, где
//!    живёт вход, отдаёт свежий `oauth_token` (`login::soundcloud_silent`);
//! 3. и это не помогло — одна плашка «Войди в SoundCloud заново» (событие `soundcloud:relogin`).
//! Каждое обновление — строка в журнале сбоев, без значений ключей.

use crate::providers::soundcloud::Creds;
use anyhow::{anyhow, Result};
use std::future::Future;

/// Что обновили — для строки журнала.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Fix {
  ClientId,
  Token,
}

impl Fix {
  pub fn journal(self) -> &'static str {
    match self {
      Fix::ClientId => "SoundCloud: 401 — взял новый публичный client_id, запрос прошёл",
      Fix::Token => "SoundCloud: 401 — вход обновлён тихо (новый oauth_token), запрос прошёл",
    }
  }
}

pub const JOURNAL_RELOGIN: &str = "SoundCloud: 401 — ни новый client_id, ни тихий вход не помогли, нужен вход заново";

/// Текст ошибки, когда починить не вышло.
pub fn relogin_error() -> anyhow::Error {
  anyhow!("SoundCloud: вход устарел — войди в SoundCloud заново")
}

pub struct Repaired<T> {
  pub result: Result<T>,
  /// Новые ключи, которые сработали, — сохранить.
  pub save: Option<(Creds, Fix)>,
  /// Починить не вышло — показать плашку входа.
  pub relogin: bool,
}

/// Ключи сработали, если ответ — не 401/403 (404 и прочее — уже не про ключи).
fn passed<T>(r: &Result<T>) -> bool {
  !matches!(r, Err(e) if super::is_auth_error(e))
}

/// Починка после 401/403 на ключах `old`. `call` — сам запрос; `fresh_id` — публичный client_id
/// с сайта; `relogin` — тихий вход (свежий `oauth_token` или None).
pub async fn repair<T, F, Fut, I, IFut, R, RFut>(old: &Creds, err: anyhow::Error, call: &F, fresh_id: I, relogin: R) -> Repaired<T>
where
  F: Fn(Creds) -> Fut,
  Fut: Future<Output = Result<T>>,
  I: FnOnce() -> IFut,
  IFut: Future<Output = Result<String>>,
  R: FnOnce() -> RFut,
  RFut: Future<Output = Option<String>>,
{
  let id = fresh_id().await.unwrap_or_else(|_| old.client_id.clone());
  if id != old.client_id {
    let creds = Creds { client_id: id.clone(), oauth_token: old.oauth_token.clone() };
    let r = call(creds.clone()).await;
    if passed(&r) {
      return Repaired { result: r, save: Some((creds, Fix::ClientId)), relogin: false };
    }
  }
  let Some(old_token) = old.oauth_token.as_deref() else {
    // без токена входить нечем — ошибка как есть
    return Repaired { result: Err(err), save: None, relogin: false };
  };
  if let Some(token) = relogin().await.filter(|t| !t.is_empty() && t != old_token) {
    let creds = Creds { client_id: id, oauth_token: Some(token) };
    let r = call(creds.clone()).await;
    if passed(&r) {
      return Repaired { result: r, save: Some((creds, Fix::Token)), relogin: false };
    }
  }
  Repaired { result: Err(relogin_error()), save: None, relogin: true }
}

#[cfg(test)]
mod tests {
  use super::*;
  use std::sync::Mutex;

  fn creds(id: &str, token: Option<&str>) -> Creds {
    Creds { client_id: id.into(), oauth_token: token.map(Into::into) }
  }

  fn unauthorized() -> anyhow::Error {
    anyhow!("SoundCloud: HTTP 401")
  }

  /// Запрос проходит только с этими id и токеном; все попытки записываются.
  fn server<'a>(ok_id: &'static str, ok_token: &'static str, seen: &'a Mutex<Vec<String>>) -> impl Fn(Creds) -> std::future::Ready<Result<u32>> + 'a {
    move |c: Creds| {
      let token = c.oauth_token.clone().unwrap_or_default();
      seen.lock().unwrap().push(format!("{}/{token}", c.client_id));
      std::future::ready(if c.client_id == ok_id && token == ok_token { Ok(7) } else { Err(unauthorized()) })
    }
  }

  #[tokio::test]
  async fn new_client_id_is_enough() {
    let seen = Mutex::new(vec![]);
    let call = server("new", "tok", &seen);
    let r = repair(&creds("old", Some("tok")), unauthorized(), &call, || async { Ok("new".to_string()) }, || async {
      panic!("тихий вход не нужен")
    })
    .await;
    assert_eq!(r.result.unwrap(), 7);
    assert_eq!(r.save.map(|(c, f)| (c.client_id, f)), Some(("new".into(), Fix::ClientId)));
    assert!(!r.relogin);
    assert_eq!(*seen.lock().unwrap(), ["new/tok"]);
  }

  #[tokio::test]
  async fn falls_back_to_silent_relogin_with_new_id() {
    let seen = Mutex::new(vec![]);
    let call = server("new", "fresh", &seen);
    let r = repair(&creds("old", Some("tok")), unauthorized(), &call, || async { Ok("new".to_string()) }, || async {
      Some("fresh".to_string())
    })
    .await;
    assert_eq!(r.result.unwrap(), 7);
    let (c, fix) = r.save.unwrap();
    assert_eq!((c.client_id.as_str(), c.oauth_token.as_deref(), fix), ("new", Some("fresh"), Fix::Token));
    assert_eq!(*seen.lock().unwrap(), ["new/tok", "new/fresh"]);
  }

  #[tokio::test]
  async fn same_id_on_site_goes_straight_to_relogin() {
    let seen = Mutex::new(vec![]);
    let call = server("old", "fresh", &seen);
    let r = repair(&creds("old", Some("tok")), unauthorized(), &call, || async { Ok("old".to_string()) }, || async {
      Some("fresh".to_string())
    })
    .await;
    assert!(r.result.is_ok());
    assert_eq!(*seen.lock().unwrap(), ["old/fresh"]);
  }

  #[tokio::test]
  async fn nothing_helps_asks_to_log_in_again() {
    let seen = Mutex::new(vec![]);
    let call = server("x", "y", &seen);
    // тихий вход вернул тот же токен — повторять нечего
    let r = repair(&creds("old", Some("tok")), unauthorized(), &call, || async { Ok("new".to_string()) }, || async {
      Some("tok".to_string())
    })
    .await;
    assert!(r.relogin && r.save.is_none());
    assert!(r.result.unwrap_err().to_string().contains("войди в SoundCloud заново"));
    assert_eq!(*seen.lock().unwrap(), ["new/tok"]);
  }

  #[tokio::test]
  async fn site_unreachable_and_no_token_keeps_original_error() {
    let seen = Mutex::new(vec![]);
    let call = server("x", "y", &seen);
    let r = repair(&creds("own", None), unauthorized(), &call, || async { Err(anyhow!("нет сети")) }, || async {
      panic!("без токена входить нечем")
    })
    .await;
    assert!(!r.relogin && r.save.is_none());
    assert!(r.result.unwrap_err().to_string().contains("HTTP 401"));
    assert!(seen.lock().unwrap().is_empty());
  }

  #[tokio::test]
  async fn other_error_with_new_id_still_saves_it() {
    // 404 на новом id: ключ подошёл, просто трека нет — id сохраняем, ошибку отдаём
    let call = |c: Creds| std::future::ready(if c.client_id == "new" { Err::<u32, _>(anyhow!("SoundCloud: HTTP 404")) } else { Err(unauthorized()) });
    let r = repair(&creds("old", Some("tok")), unauthorized(), &call, || async { Ok("new".to_string()) }, || async { None }).await;
    assert!(r.result.unwrap_err().to_string().contains("404"));
    assert_eq!(r.save.map(|(_, f)| f), Some(Fix::ClientId));
  }

  #[test]
  fn journal_lines_carry_no_values() {
    for line in [Fix::ClientId.journal(), Fix::Token.journal(), JOURNAL_RELOGIN] {
      assert!(line.starts_with("SoundCloud: 401"));
    }
  }
}
