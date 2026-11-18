//! Подключение сервисов в один клик (SPEC §4.3а): Sonar открывает окно входа самого сервиса,
//! пользователь входит как обычно, а ключи Sonar забирает сам и окно закрывает.
//! - Яндекс: OAuth «токен в адресе» (`response_type=token`) с client_id приложения Яндекс Музыки —
//!   после входа страница уходит на адрес с `#access_token=y0_…`, его и перехватываем.
//! - SoundCloud: обычная страница входа; после входа сайт ставит cookie `oauth_token`, её читаем
//!   раз в секунду. client_id — публичный, с сайта (как в selfbot).
//! - YouTube Music: вход Google с возвратом на music.youtube.com; после входа у music.youtube.com
//!   появляется cookie `SAPISID` — весь набор cookie сайта уходит в keyring (подпись запросов —
//!   `providers/youtube/auth.rs`). Google может не пустить во встроенное окно — тогда cookie вставляют
//!   вручную в «Сервисах».
//! Окно закрыли, не войдя, — ошибка «Вход отменён». Ждём не больше 10 минут.
//!
//! Браузер по умолчанию (просьба владельца 2026-11-16): Яндекс — вход по коду (OAuth device flow того
//! же клиента Яндекс Музыки): Sonar показывает короткий код и открывает `ya.ru/device` в браузере,
//! который выбран в Windows, и сам забирает токен, когда код подтвердят. Last.fm — тоже в браузере
//! (`lastfm.rs`). SoundCloud так не умеет (своего OAuth-приложения с адресом возврата у нас нет, а
//! cookie чужого браузера не прочитать) — у него остаётся окно входа SoundCloud внутри Sonar.
//! «Отмена» (`cancel`) обрывает ожидание любого входа через браузер.

use crate::providers::{soundcloud, yandex, youtube};
use crate::services::{Core, ServiceStatus};
use anyhow::{anyhow, bail, Result};
use std::sync::Arc;
use std::time::Duration;
use tauri::webview::NewWindowResponse;
use std::sync::atomic::{AtomicU64, Ordering};
use tauri::{AppHandle, Emitter, Manager, Url, WebviewUrl, WebviewWindow, WebviewWindowBuilder, WindowEvent};
use tokio::sync::mpsc;

/// client_id приложения Яндекс Музыки для OAuth (так входят официальный клиент и yandex-music-api).
const YM_CLIENT_ID: &str = "23cabbbdc6cd418abb4b39c32c41195d";
/// Его публичный секрет (тот же, что в yandex-music-api) — нужен для обмена кода устройства на токен.
const YM_CLIENT_SECRET: &str = "53bc75238f0c4d08a118e51fe9203300";

/// Поколение входа через браузер: «Отмена» и новый вход его меняют — старое ожидание видит это и
/// заканчивается.
static LOGIN_GEN: AtomicU64 = AtomicU64::new(0);

/// Начать вход через браузер: вернёт номер, по которому ожидание поймёт, что его отменили.
pub fn begin() -> u64 {
  LOGIN_GEN.fetch_add(1, Ordering::SeqCst) + 1
}

pub fn cancelled(attempt: u64) -> bool {
  LOGIN_GEN.load(Ordering::SeqCst) != attempt
}

/// «Отмена» в настройках — ждать вход больше не нужно.
pub fn cancel() {
  LOGIN_GEN.fetch_add(1, Ordering::SeqCst);
}

/// Открыть адрес в браузере, который выбран в Windows по умолчанию.
pub fn open_in_browser(url: &str) -> Result<()> {
  if !url.starts_with("https://") {
    bail!("можно открыть только https-ссылку");
  }
  #[cfg(windows)]
  {
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    std::process::Command::new("rundll32").args(["url.dll,FileProtocolHandler", url]).creation_flags(CREATE_NO_WINDOW).spawn()?;
  }
  Ok(())
}

/// Код для входа на `ya.ru/device` — интерфейс показывает его, пока ждём (событие `login:code`).
#[derive(serde::Serialize, Clone)]
pub struct DeviceCode {
  pub service: &'static str,
  pub code: String,
  pub url: String,
  pub expires_in: u64,
}

/// Яндекс через браузер по умолчанию: код устройства → `ya.ru/device` → ждём подтверждения → токен.
/// Не удалось даже получить код (сеть, Яндекс отключил вход по коду) — `Ok(None)`, тогда вход
/// откроется прежним окном.
pub async fn yandex_device(app: &AppHandle, core: &Arc<Core>, device_id: &str) -> Result<Option<ServiceStatus>> {
  let attempt = begin();
  let started = core
    .http
    .post("https://oauth.yandex.ru/device/code")
    .form(&[("client_id", YM_CLIENT_ID), ("device_id", device_id), ("device_name", "Sonar (Windows)")])
    .send()
    .await;
  let Ok(r) = started else { return Ok(None) };
  let Ok(v) = r.json::<serde_json::Value>().await else { return Ok(None) };
  let (Some(device_code), Some(user_code)) = (v["device_code"].as_str(), v["user_code"].as_str()) else {
    log::warn!("Яндекс: вход по коду недоступен: {v}");
    return Ok(None);
  };
  let url = v["verification_url"].as_str().unwrap_or("https://ya.ru/device").to_owned();
  let expires = v["expires_in"].as_u64().unwrap_or(300);
  let mut interval = v["interval"].as_u64().unwrap_or(5).max(2);
  let _ = app.emit("login:code", DeviceCode { service: "yandex", code: user_code.to_owned(), url: url.clone(), expires_in: expires });
  let _ = open_in_browser(&url);
  let deadline = tokio::time::Instant::now() + Duration::from_secs(expires);
  let token = loop {
    tokio::time::sleep(Duration::from_secs(interval)).await;
    if cancelled(attempt) {
      bail!("Вход отменён");
    }
    if tokio::time::Instant::now() > deadline {
      bail!("Код устарел — нажми «Войти через Яндекс» ещё раз");
    }
    let r = core
      .http
      .post("https://oauth.yandex.ru/token")
      .form(&[("grant_type", "device_code"), ("code", device_code), ("client_id", YM_CLIENT_ID), ("client_secret", YM_CLIENT_SECRET)])
      .send()
      .await;
    let Ok(r) = r else { continue };
    let Ok(v) = r.json::<serde_json::Value>().await else { continue };
    if let Some(t) = v["access_token"].as_str().filter(|t| !t.is_empty()) {
      break t.to_owned();
    }
    match v["error"].as_str() {
      Some("authorization_pending") | None => {}
      Some("slow_down") => interval += 2,
      Some("expired_token") => bail!("Код устарел — нажми «Войти через Яндекс» ещё раз"),
      Some("access_denied") => bail!("Вход отменён"),
      Some(e) => bail!("Яндекс не пустил: {e}"),
    }
  };
  if cancelled(attempt) {
    bail!("Вход отменён");
  }
  core.connect_yandex(yandex::Creds { token }).await.map(Some)
}
const WAIT: Duration = Duration::from_secs(600);

/// `#access_token=…&…` → токен.
pub fn token_from_url(url: &Url) -> Option<String> {
  let frag = url.fragment()?;
  frag
    .split('&')
    .find_map(|kv| kv.strip_prefix("access_token="))
    .filter(|t| !t.is_empty())
    .map(|t| urlencoding::decode(t).map(|c| c.into_owned()).unwrap_or_else(|_| t.to_owned()))
}

fn window<'a>(app: &'a AppHandle, label: &str, title: &str, url: &str) -> Result<WebviewWindowBuilder<'a, tauri::Wry, AppHandle>> {
  if let Some(old) = app.get_webview_window(label) {
    let _ = old.close();
  }
  let url = Url::parse(url)?;
  // Своя папка данных WebView2: у главного окна свои флаги браузера, а два окна с разными флагами
  // на одной папке WebView2 не создаёт (HRESULT 0x8007139F). Вход сохраняется в этой папке.
  let dir = app.path().app_local_data_dir()?.join("login-webview");
  let b = WebviewWindowBuilder::new(app, label, WebviewUrl::External(url))
    .data_directory(dir)
    .title(title)
    .inner_size(480.0, 720.0)
    .min_inner_size(400.0, 560.0)
    .center()
    .focused(true)
    // Вход через Apple / Google / Facebook открывается всплывающим окном (`window.open`) и
    // возвращает результат через `window.opener`. Без обработчика WebView2 такие окна режет —
    // SoundCloud пишет «Please enable popup windows». Разрешаем: окно открывается в том же
    // окружении WebView2, а после входа закрывается само.
    .on_new_window(|_url, _features| NewWindowResponse::Allow);
  Ok(b)
}

/// Закрыли окно — сообщить ожидающему.
fn on_close(w: &WebviewWindow, tx: mpsc::UnboundedSender<Option<String>>) {
  w.on_window_event(move |e| {
    if matches!(e, WindowEvent::Destroyed) {
      let _ = tx.send(None);
    }
  });
}

async fn wait(rx: &mut mpsc::UnboundedReceiver<Option<String>>) -> Result<String> {
  match tokio::time::timeout(WAIT, rx.recv()).await {
    Ok(Some(Some(v))) => Ok(v),
    Ok(_) => bail!("Вход отменён — окно закрыто"),
    Err(_) => bail!("Вход не завершён за 10 минут"),
  }
}

pub async fn yandex(app: AppHandle, core: Arc<Core>) -> Result<ServiceStatus> {
  let (tx, mut rx) = mpsc::unbounded_channel::<Option<String>>();
  let url = format!("https://oauth.yandex.ru/authorize?response_type=token&client_id={YM_CLIENT_ID}");
  let nav_tx = tx.clone();
  let w = window(&app, "login-yandex", "Вход в Яндекс Музыку — Sonar", &url)?
    .on_navigation(move |u| {
      if let Some(t) = token_from_url(u) {
        let _ = nav_tx.send(Some(t));
        return false; // дальше на music.yandex.ru не идём
      }
      true
    })
    .build()?;
  on_close(&w, tx.clone());
  // на случай, если адрес с токеном пришёл без события навигации — проверяем текущий адрес
  let poll_tx = tx.clone();
  let poll_w = w.clone();
  let poll = tokio::spawn(async move {
    loop {
      tokio::time::sleep(Duration::from_millis(700)).await;
      match poll_w.url() {
        Ok(u) => {
          if let Some(t) = token_from_url(&u) {
            let _ = poll_tx.send(Some(t));
            break;
          }
        }
        Err(_) => break,
      }
    }
  });
  let token = wait(&mut rx).await;
  poll.abort();
  let _ = w.close();
  let token = token?;
  core.connect_yandex(yandex::Creds { token }).await
}

pub async fn soundcloud(app: AppHandle, core: Arc<Core>) -> Result<ServiceStatus> {
  let (tx, mut rx) = mpsc::unbounded_channel::<Option<String>>();
  let w = window(&app, "login-soundcloud", "Вход в SoundCloud — Sonar", "https://soundcloud.com/signin")?.build()?;
  on_close(&w, tx.clone());
  let poll_w = w.clone();
  let poll = tokio::spawn(async move {
    let sc = Url::parse("https://soundcloud.com/").expect("url");
    loop {
      tokio::time::sleep(Duration::from_secs(1)).await;
      match poll_w.cookies_for_url(sc.clone()) {
        Ok(cookies) => {
          if let Some(c) = cookies.iter().find(|c| c.name() == "oauth_token" && !c.value().is_empty()) {
            let _ = tx.send(Some(c.value().to_owned()));
            break;
          }
        }
        Err(_) => break,
      }
    }
  });
  let token = wait(&mut rx).await;
  poll.abort();
  let _ = w.close();
  let token = token?;
  let client_id = soundcloud::public_client_id(&core.http)
    .await
    .map_err(|e| anyhow!("Вошёл, но не нашёл client_id SoundCloud: {e}"))?;
  core.connect_soundcloud(soundcloud::Creds { client_id, oauth_token: Some(token) }).await
}

/// Страница входа Google, после неё — music.youtube.com.
const YT_LOGIN_URL: &str = "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fmusic.youtube.com%2F";

/// Cookie music.youtube.com одной строкой — только когда вход уже есть (`SAPISID` на месте).
fn yt_cookie_header<'a>(pairs: impl IntoIterator<Item = (&'a str, &'a str)>) -> Option<String> {
  let joined = pairs.into_iter().filter(|(k, v)| !k.is_empty() && !v.is_empty()).map(|(k, v)| format!("{k}={v}")).collect::<Vec<_>>().join("; ");
  youtube::auth::sapisid(&joined).map(|_| joined.clone())
}

/// Сколько раз подряд можно не прочитать cookie (окно как раз уходит на другую страницу),
/// прежде чем сдаться с понятной ошибкой.
const YT_COOKIE_READ_ATTEMPTS: u32 = 5;
const YT_COOKIE_READ_FAILED: &str = "Не удалось прочитать cookie YouTube Music — вставь cookie вручную в «Сервисах»";

pub async fn youtube(app: AppHandle, core: Arc<Core>) -> Result<ServiceStatus> {
  let (tx, mut rx) = mpsc::unbounded_channel::<Option<String>>();
  let w = window(&app, "login-youtube", "Вход в YouTube Music — Sonar", YT_LOGIN_URL)?.build()?;
  on_close(&w, tx.clone());
  let poll_w = w.clone();
  let read_failed = Arc::new(std::sync::atomic::AtomicBool::new(false));
  let poll_failed = read_failed.clone();
  let poll = tokio::spawn(async move {
    let site = Url::parse(youtube::auth::ORIGIN).expect("url");
    let mut errors = 0;
    loop {
      tokio::time::sleep(Duration::from_secs(1)).await;
      // ждём, пока окно вернётся на music.youtube.com: cookie там уже полные
      let on_site = poll_w.url().is_ok_and(|u| u.host_str() == site.host_str());
      if !on_site {
        continue;
      }
      match poll_w.cookies_for_url(site.clone()) {
        Ok(cookies) => {
          errors = 0;
          if let Some(c) = yt_cookie_header(cookies.iter().map(|c| (c.name(), c.value()))) {
            let _ = tx.send(Some(c));
            break;
          }
        }
        // в тексте ошибки WebView2 cookie нет, только причина
        Err(e) => {
          errors += 1;
          log::warn!("вход YouTube Music: cookie не прочитались ({errors}/{YT_COOKIE_READ_ATTEMPTS}): {e}");
          if errors >= YT_COOKIE_READ_ATTEMPTS {
            poll_failed.store(true, std::sync::atomic::Ordering::Relaxed);
            let _ = tx.send(None);
            break;
          }
        }
      }
    }
  });
  let cookie = wait(&mut rx).await;
  poll.abort();
  let _ = w.close();
  if read_failed.load(std::sync::atomic::Ordering::Relaxed) {
    bail!(YT_COOKIE_READ_FAILED);
  }
  core.connect_youtube(&cookie?).await
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn yt_cookie_needs_sapisid() {
    assert_eq!(yt_cookie_header([("SID", "1"), ("SAPISID", "a"), ("", "x"), ("HSID", "")]).as_deref(), Some("SID=1; SAPISID=a"));
    assert_eq!(yt_cookie_header([("__Secure-3PAPISID", "b")]).as_deref(), Some("__Secure-3PAPISID=b"));
    assert_eq!(yt_cookie_header([("SID", "1"), ("VISITOR_INFO1_LIVE", "v")]), None);
  }

  #[test]
  fn token_in_fragment() {
    let u = Url::parse("https://music.yandex.ru/#access_token=y0_AbC%2Bd&token_type=bearer&expires_in=31536000").unwrap();
    assert_eq!(token_from_url(&u).as_deref(), Some("y0_AbC+d"));
    assert_eq!(token_from_url(&Url::parse("https://music.yandex.ru/").unwrap()), None);
    assert_eq!(token_from_url(&Url::parse("https://x.ru/#access_token=").unwrap()), None);
  }
}
