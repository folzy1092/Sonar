//! Подключение сервисов в один клик (SPEC §4.3а): Sonar открывает окно входа самого сервиса,
//! пользователь входит как обычно, а ключи Sonar забирает сам и окно закрывает.
//! - Яндекс: OAuth «токен в адресе» (`response_type=token`) с client_id приложения Яндекс Музыки —
//!   после входа страница уходит на адрес с `#access_token=y0_…`, его и перехватываем.
//! - SoundCloud: обычная страница входа; после входа сайт ставит cookie `oauth_token`, её читаем
//!   раз в секунду. client_id — публичный, с сайта (как в selfbot).
//! Окно закрыли, не войдя, — ошибка «Вход отменён». Ждём не больше 10 минут.

use crate::providers::{soundcloud, yandex};
use crate::services::{Core, ServiceStatus};
use anyhow::{anyhow, bail, Result};
use std::sync::Arc;
use std::time::Duration;
use tauri::{AppHandle, Manager, Url, WebviewUrl, WebviewWindow, WebviewWindowBuilder, WindowEvent};
use tokio::sync::mpsc;

/// client_id приложения Яндекс Музыки для OAuth (так входят официальный клиент и yandex-music-api).
const YM_CLIENT_ID: &str = "23cabbbdc6cd418abb4b39c32c41195d";
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
    .focused(true);
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

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn token_in_fragment() {
    let u = Url::parse("https://music.yandex.ru/#access_token=y0_AbC%2Bd&token_type=bearer&expires_in=31536000").unwrap();
    assert_eq!(token_from_url(&u).as_deref(), Some("y0_AbC+d"));
    assert_eq!(token_from_url(&Url::parse("https://music.yandex.ru/").unwrap()), None);
    assert_eq!(token_from_url(&Url::parse("https://x.ru/#access_token=").unwrap()), None);
  }
}
