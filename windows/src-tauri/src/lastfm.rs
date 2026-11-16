//! Last.fm (решение владельца 2026-11-16): вход в один клик и скробблинг прямо из клиента.
//!
//! Вход — веб-авторизация Last.fm для десктопа: `auth.getToken` → страница `last.fm/api/auth` в браузере по умолчанию (как вход
//! в сервисы, `login.rs`) → пользователь жмёт «Yes, allow access» → `auth.getSession` даёт ключ
//! сессии; он и имя хранятся в keyring (`lastfm`). Дальше «Сейчас играет»
//! (`track.updateNowPlaying`) на смену трека и скроббл (`track.scrobble`) на каждое засчитанное
//! прослушивание (`record_play`: ≥ 30 с или половина трека — правило Last.fm).
//! Ключ и секрет приложения Last.fm вшивает CI (`SONAR_LASTFM_KEY`, `SONAR_LASTFM_SECRET`); без них
//! вход честно говорит, что в этой сборке Last.fm ещё нет.

use anyhow::{anyhow, bail, Result};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::time::Duration;
use tauri::AppHandle;

const API: &str = "https://ws.audioscrobbler.com/2.0/";
const SECRET_NAME: &str = "lastfm";

/// Сохранённый вход.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Session {
  pub name: String,
  pub key: String,
  #[serde(default)]
  pub avatar_url: Option<String>,
}

/// Что видит интерфейс.
#[derive(Debug, Clone, Serialize)]
pub struct Status {
  /// Ключ приложения вшит в сборку — вход возможен.
  pub available: bool,
  pub name: Option<String>,
  pub avatar_url: Option<String>,
}

fn keys() -> Option<(&'static str, &'static str)> {
  match (option_env!("SONAR_LASTFM_KEY"), option_env!("SONAR_LASTFM_SECRET")) {
    (Some(k), Some(s)) if !k.is_empty() && !s.is_empty() => Some((k, s)),
    _ => None,
  }
}

/// Подпись запроса Last.fm: параметры по алфавиту «имязначение» подряд + секрет → md5.
pub fn sign(params: &BTreeMap<&str, String>, secret: &str) -> String {
  let mut s = String::new();
  for (k, v) in params {
    if *k != "format" && *k != "callback" {
      s.push_str(k);
      s.push_str(v);
    }
  }
  s.push_str(secret);
  format!("{:x}", md5::compute(s.as_bytes()))
}

pub fn session() -> Option<Session> {
  crate::secrets::load(SECRET_NAME)
}

pub fn status() -> Status {
  let s = session();
  Status { available: keys().is_some(), name: s.as_ref().map(|s| s.name.clone()), avatar_url: s.and_then(|s| s.avatar_url) }
}

pub fn logout() -> Result<()> {
  crate::secrets::delete(SECRET_NAME)
}

async fn call(http: &reqwest::Client, mut params: BTreeMap<&str, String>, signed: bool, post: bool) -> Result<serde_json::Value> {
  let (key, secret) = keys().ok_or_else(|| anyhow!("Last.fm появится в следующей сборке — ключ приложения ещё не добавлен"))?;
  params.insert("api_key", key.to_owned());
  if signed {
    let sig = sign(&params, secret);
    params.insert("api_sig", sig);
  }
  params.insert("format", "json".into());
  let req = if post { http.post(API).form(&params) } else { http.get(API).query(&params) };
  let v: serde_json::Value = req.send().await?.json().await?;
  if let Some(code) = v["error"].as_i64() {
    bail!("Last.fm: {} ({code})", v["message"].as_str().unwrap_or("ошибка"));
  }
  Ok(v)
}

/// Вход: страница Last.fm «Разрешить доступ» открывается в браузере, выбранном в Windows; ждём
/// подтверждения (до 10 минут, «Отмена» в настройках обрывает), сохраняем сессию.
pub async fn login(_app: AppHandle, http: reqwest::Client) -> Result<Status> {
  let v = call(&http, BTreeMap::from([("method", "auth.getToken".to_owned())]), true, false).await?;
  let token = v["token"].as_str().ok_or_else(|| anyhow!("Last.fm не выдал токен"))?.to_owned();
  let (key, _) = keys().ok_or_else(|| anyhow!("нет ключа Last.fm"))?;
  let url = format!("https://www.last.fm/api/auth/?api_key={key}&token={token}");
  let attempt = crate::login::begin();
  crate::login::open_in_browser(&url)?;
  // после «Yes, allow access» токен становится сессией — спрашиваем раз в 2 с
  let deadline = tokio::time::Instant::now() + Duration::from_secs(600);
  let got = loop {
    tokio::time::sleep(Duration::from_secs(2)).await;
    if crate::login::cancelled(attempt) || tokio::time::Instant::now() > deadline {
      break None;
    }
    let p = BTreeMap::from([("method", "auth.getSession".to_owned()), ("token", token.clone())]);
    if let Ok(v) = call(&http, p, true, false).await {
      if let (Some(name), Some(sk)) = (v["session"]["name"].as_str(), v["session"]["key"].as_str()) {
        break Some((name.to_owned(), sk.to_owned()));
      }
    }
  };
  let (name, key) = got.ok_or_else(|| anyhow!("Вход в Last.fm отменён"))?;
  // аватар — для карточки в настройках
  let info = call(&http, BTreeMap::from([("method", "user.getInfo".to_owned()), ("user", name.clone())]), false, false).await.ok();
  let avatar_url = info.and_then(|v| {
    v["user"]["image"].as_array().and_then(|imgs| imgs.iter().rev().find_map(|i| i["#text"].as_str().filter(|u| !u.is_empty()).map(str::to_owned)))
  });
  crate::secrets::save(SECRET_NAME, &Session { name, key, avatar_url })?;
  Ok(status())
}

/// Трек для Last.fm.
pub struct Scrobble {
  pub artist: String,
  pub title: String,
  pub album: Option<String>,
  pub duration_s: Option<u64>,
  /// Начало прослушивания, секунды Unix (только для скроббла).
  pub started_at: Option<i64>,
}

fn track_params(t: &Scrobble, method: &str, sk: &str) -> BTreeMap<&'static str, String> {
  let mut p = BTreeMap::from([
    ("method", method.to_owned()),
    ("artist", t.artist.clone()),
    ("track", t.title.clone()),
    ("sk", sk.to_owned()),
  ]);
  if let Some(a) = t.album.as_ref().filter(|a| !a.is_empty()) {
    p.insert("album", a.clone());
  }
  if let Some(d) = t.duration_s.filter(|d| *d > 0) {
    p.insert("duration", d.to_string());
  }
  if let Some(ts) = t.started_at {
    p.insert("timestamp", ts.to_string());
  }
  p
}

/// «Сейчас играет» (если вошёл и в сборке есть ключ). Ошибки — только в журнал.
pub async fn now_playing(http: &reqwest::Client, t: Scrobble) {
  let Some(s) = session() else { return };
  if keys().is_none() {
    return;
  }
  if let Err(e) = call(http, track_params(&t, "track.updateNowPlaying", &s.key), true, true).await {
    log::warn!("Last.fm сейчас играет: {e}");
  }
}

/// Скроббл засчитанного прослушивания.
pub async fn scrobble(http: &reqwest::Client, t: Scrobble) {
  let Some(s) = session() else { return };
  if keys().is_none() {
    return;
  }
  if let Err(e) = call(http, track_params(&t, "track.scrobble", &s.key), true, true).await {
    log::warn!("Last.fm скроббл: {e}");
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn signature_sorts_params_and_skips_format() {
    // пример из документации Last.fm: md5("api_keyxxxxmethodauth.getSessiontokenyyyyyysecret")
    let p = BTreeMap::from([
      ("method", "auth.getSession".to_owned()),
      ("token", "yyyyyy".to_owned()),
      ("api_key", "xxxx".to_owned()),
      ("format", "json".to_owned()),
    ]);
    let want = format!("{:x}", md5::compute(b"api_keyxxxxmethodauth.getSessiontokenyyyyyysecret"));
    assert_eq!(sign(&p, "secret"), want);
  }
}
