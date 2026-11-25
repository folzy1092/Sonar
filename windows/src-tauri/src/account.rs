//! Аккаунт Sonar на ПК (API.md §1, SERVER_PROMPT этап 2): вход, регистрация, Telegram, быстрая ссылка,
//! профиль, пароль, устройства.
//!
//! Сессия — только в keyring (`sonar_session`, её же берёт синк `sync.rs`), последний `User` — рядом
//! (`sonar_user`, чтобы экран не мигал до ответа `/me`). Токен во фронт не отдаётся. Адрес API —
//! настройка устройства `sync.server`, без неё — [`DEFAULT_API`] (не зашит намертво: можно сменить).

use std::sync::Mutex;
use std::time::Duration;

use serde::Serialize;
use serde_json::{json, Value};
use tauri::State;

use crate::commands::Db;
use crate::services::Core;
use crate::store::Store;

pub const DEFAULT_API: &str = "https://try-sonar.ru/api";
const SESSION: &str = "sonar_session";
const USER: &str = "sonar_user";
const TIMEOUT: Duration = Duration::from_secs(15);

type Res<T> = Result<T, String>;

/// Ошибка сервера — `{"error": {"code", "message"}}`; во фронт уходит текст, а `signed_out` — когда сессии больше нет.
#[derive(Debug, PartialEq)]
pub struct ApiError {
  pub status: u16,
  pub code: String,
  pub message: String,
}

impl ApiError {
  fn to_front(&self) -> String {
    if self.status == 401 && self.code == "unauthorized" {
      return "signed_out".into();
    }
    self.message.clone()
  }
}

/// Разбор тела ошибки; не JSON (прокси хостера, 502) — общий текст по коду.
pub fn parse_error(status: u16, body: &str) -> ApiError {
  let v: Value = serde_json::from_str(body).unwrap_or(Value::Null);
  let e = &v["error"];
  let fallback = match status {
    429 => "Слишком много попыток — подожди немного",
    500..=599 => "Сервер Sonar не отвечает — попробуй позже",
    _ => "Сервер Sonar ответил ошибкой",
  };
  ApiError {
    status,
    code: e["code"].as_str().unwrap_or("error").to_owned(),
    message: e["message"].as_str().unwrap_or(fallback).to_owned(),
  }
}

/// Адрес API: `sync.server` (свой сервер для проверки) или основной.
pub fn base(db: &Mutex<Store>) -> String {
  let custom = db.lock().unwrap().setting("sync.server").ok().flatten();
  match custom.as_ref().and_then(Value::as_str).map(str::trim).filter(|s| !s.is_empty()) {
    Some(s) => s.trim_end_matches('/').to_owned(),
    None => DEFAULT_API.to_owned(),
  }
}

/// «Windows 10 (Folzy)» / «Windows 11 (Folzy)» — по номеру сборки, имя ПК в скобках (API.md §1).
pub fn device_name(build: u32, computer: &str) -> String {
  let os = if build >= 22000 { "Windows 11" } else { "Windows 10" };
  let pc = computer.trim();
  if pc.is_empty() { os.to_owned() } else { format!("{os} ({pc})") }
}

/// `device` из API.md §1. id — постоянный id установки (`sync_state.device_id`, он же в `op_id` синка).
pub fn device(db: &Mutex<Store>) -> Value {
  #[cfg(windows)]
  let build = windows_version::OsVersion::current().build;
  #[cfg(not(windows))]
  let build = 0; // клиент только под Windows; так крейт собирается для тестов на других системах
  let computer = std::env::var("COMPUTERNAME").unwrap_or_default();
  let id = db.lock().unwrap().device_id().unwrap_or_else(|_| "pc".into());
  let version = env!("CARGO_PKG_VERSION");
  json!({
    "id": id,
    "name": device_name(build, &computer),
    "platform": "windows",
    "os": format!("{} (сборка {build})", if build >= 22000 { "Windows 11" } else { "Windows 10" }),
    "app_version": version,
    "build": version.rsplit('.').next().and_then(|p| p.parse::<u32>().ok()),
  })
}

fn token() -> Option<String> {
  crate::secrets::load::<String>(SESSION).filter(|t| !t.is_empty())
}

fn signed_in(session: &str, user: &Value) -> Res<()> {
  crate::secrets::save(SESSION, &session.to_owned()).map_err(|e| e.to_string())?;
  crate::cred_sync::reset(); // другой аккаунт — прошлый обмен входами ни о чём не говорит
  let _ = crate::secrets::save(USER, user);
  Ok(())
}

fn forget() {
  let _ = crate::secrets::delete(SESSION);
  let _ = crate::secrets::delete(USER);
  crate::cred_sync::reset();
}

pub(crate) async fn call(core: &Core, db: &Mutex<Store>, method: reqwest::Method, path: &str, body: Option<Value>, auth: bool) -> Res<Value> {
  crate::offline::guard()?;
  let url = format!("{}/{}", base(db), path.trim_start_matches('/'));
  let mut req = core.http().request(method, &url).timeout(TIMEOUT);
  if auth {
    let Some(tok) = token() else { return Err("signed_out".into()) };
    req = req.bearer_auth(tok);
  }
  if let Some(b) = body {
    req = req.json(&b);
  }
  let r = req.send().await.map_err(|_| "Нет связи с сервером Sonar".to_string())?;
  let status = r.status().as_u16();
  let text = r.text().await.unwrap_or_default();
  if !(200..300).contains(&status) {
    let e = parse_error(status, &text);
    if auth && e.status == 401 {
      forget(); // сессию отозвали (выход на другом устройстве, бан) — локально тоже выходим
    }
    return Err(e.to_front());
  }
  if text.is_empty() {
    return Ok(Value::Null);
  }
  serde_json::from_str(&text).map_err(|_| "Сервер Sonar ответил не JSON".to_string())
}

#[derive(Serialize)]
pub struct AccountStatus {
  server: String,
  signed_in: bool,
  user: Option<Value>,
}

/// Что показать сразу при запуске: вошли ли и последний известный `User` (без сети).
#[tauri::command]
pub fn account_status(db: State<'_, Db>) -> AccountStatus {
  let signed = token().is_some();
  AccountStatus { server: base(&db.0), signed_in: signed, user: if signed { crate::secrets::load(USER) } else { None } }
}

/// Сервер отвечает? Ворота входа на ПК — только когда да (иначе пускаем как раньше).
#[tauri::command]
pub async fn account_ping(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>) -> Res<bool> {
  if crate::offline::is_on() {
    return Ok(false);
  }
  let url = format!("{}/health", base(&db.0));
  Ok(matches!(core.http().get(url).timeout(Duration::from_secs(5)).send().await, Ok(r) if r.status().is_success()))
}

async fn auth_with_password(core: &Core, db: &Mutex<Store>, path: &str, login: &str, password: &str) -> Res<Value> {
  let out = call(core, db, reqwest::Method::POST, path, Some(json!({"login": login, "password": password, "device": device(db)})), false).await?;
  let session = out["session"].as_str().ok_or("Сервер не прислал сессию")?;
  signed_in(session, &out["user"])?;
  Ok(out["user"].clone())
}

#[tauri::command]
pub async fn account_login(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>, login: String, password: String) -> Res<Value> {
  auth_with_password(&core, &db.0, "auth/login", &login, &password).await
}

#[tauri::command]
pub async fn account_register(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>, login: String, password: String) -> Res<Value> {
  auth_with_password(&core, &db.0, "auth/register", &login, &password).await
}

#[tauri::command]
pub async fn account_logout(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>) -> Res<()> {
  // Выйти локально нужно в любом случае — даже без сети; сервер забудет сессию, если дозвонимся.
  let _ = call(&core, &db.0, reqwest::Method::POST, "auth/logout", None, true).await;
  forget();
  Ok(())
}

#[tauri::command]
pub async fn account_me(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>) -> Res<Value> {
  let user = call(&core, &db.0, reqwest::Method::GET, "me", None, true).await?;
  let _ = crate::secrets::save(USER, &user);
  Ok(user)
}

#[tauri::command]
pub async fn account_update(
  core: State<'_, std::sync::Arc<Core>>,
  db: State<'_, Db>,
  username: Option<String>,
  display_name: Option<String>,
) -> Res<Value> {
  let mut body = serde_json::Map::new();
  if let Some(u) = username {
    body.insert("username".into(), u.into());
  }
  if let Some(n) = display_name {
    body.insert("display_name".into(), n.into());
  }
  let user = call(&core, &db.0, reqwest::Method::PATCH, "me", Some(Value::Object(body)), true).await?;
  let _ = crate::secrets::save(USER, &user);
  Ok(user)
}

#[tauri::command]
pub async fn account_password(
  core: State<'_, std::sync::Arc<Core>>,
  db: State<'_, Db>,
  old_password: Option<String>,
  new_password: String,
) -> Res<()> {
  call(&core, &db.0, reqwest::Method::PUT, "me/password", Some(json!({"old_password": old_password, "new_password": new_password})), true)
    .await
    .map(|_| ())
}

#[tauri::command]
pub async fn account_devices(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>) -> Res<Value> {
  call(&core, &db.0, reqwest::Method::GET, "me/devices", None, true).await
}

/// При запуске: имя, ОС и версия этого ПК (`PUT /me/device`).
#[tauri::command]
pub async fn account_report_device(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>) -> Res<Value> {
  let dev = device(&db.0);
  call(&core, &db.0, reqwest::Method::PUT, "me/device", Some(json!({"device": dev})), true).await
}

#[tauri::command]
pub async fn account_rename_device(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>, id: String, name: String) -> Res<Value> {
  call(&core, &db.0, reqwest::Method::PATCH, &format!("me/devices/{}", urlencoding::encode(&id)), Some(json!({"name": name})), true).await
}

#[tauri::command]
pub async fn account_revoke_device(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>, id: String) -> Res<()> {
  call(&core, &db.0, reqwest::Method::DELETE, &format!("me/devices/{}", urlencoding::encode(&id)), None, true).await.map(|_| ())
}

/// Ключ API для selfbot и своих скриптов (API.md §7, один на аккаунт, общий с ботом): `{key, created_at}`, ключа нет — `key: null`.
#[tauri::command]
pub async fn account_api_key(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>) -> Res<Value> {
  call(&core, &db.0, reqwest::Method::GET, "me/integration", None, true).await
}

/// Выпустить ключ заново — прежний перестаёт работать сразу.
#[tauri::command]
pub async fn account_api_key_new(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>) -> Res<Value> {
  call(&core, &db.0, reqwest::Method::POST, "integrations/api-key", None, true).await
}

#[tauri::command]
pub async fn account_api_key_delete(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>) -> Res<()> {
  call(&core, &db.0, reqwest::Method::DELETE, "integrations/api-key", None, true).await.map(|_| ())
}

/// Синк сразу после входа (не ждать фоновые 2 минуты): своё — на сервер, чужое — сюда; пришло — `sync-applied`.
#[tauri::command]
pub async fn account_sync(app: tauri::AppHandle, core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>) -> Res<usize> {
  use tauri::Emitter;
  crate::offline::guard()?;
  let r = crate::sync::sync_now(&core.http(), &db.0).await.map_err(|e| e.to_string())?;
  if r.pulled > 0 {
    let _ = app.emit("sync-applied", r.pulled);
  }
  // входы в сервисы — отдельно: их сбой не должен выдавать «синк не прошёл», когда Любимые уже приехали
  match crate::cred_sync::run(&core, &db.0).await {
    Ok(true) => {
      let _ = app.emit("services-changed", ());
    }
    Ok(false) => {}
    Err(e) => log::warn!("входы в сервисы: {e}"),
  }
  Ok(r.pulled)
}

// ——— Telegram и быстрая ссылка ———

/// `login` — войти через бота (без входа); `link` — привязать Telegram к своему аккаунту.
#[tauri::command]
pub async fn account_tg_start(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>, purpose: String) -> Res<Value> {
  let login = purpose == "login";
  let body = if login { json!({"purpose": "login", "device": device(&db.0)}) } else { json!({"purpose": "link"}) };
  call(&core, &db.0, reqwest::Method::POST, "auth/telegram/start", Some(body), !login).await
}

/// Отвязать Telegram (сервер разрешит, только если есть пароль).
#[tauri::command]
pub async fn account_tg_unlink(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>) -> Res<()> {
  call(&core, &db.0, reqwest::Method::DELETE, "auth/telegram", None, true).await.map(|_| ())
}

/// Ответ опроса: сессию (если пришла) кладём в keyring, во фронт — только статус и `User`.
fn take_session(out: Value) -> Res<Value> {
  if let Some(session) = out["session"].as_str() {
    signed_in(session, &out["user"])?;
  }
  Ok(json!({"status": out["status"], "user": out["user"]}))
}

#[tauri::command]
pub async fn account_tg_poll(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>, id: String) -> Res<Value> {
  let out = call(&core, &db.0, reqwest::Method::GET, &format!("auth/telegram/poll/{}", urlencoding::encode(&id)), None, token().is_some()).await?;
  take_session(out)
}

/// Войти с помощью другого устройства: ссылка + код (QR — на стороне фронта не нужен, ссылка и бот).
#[tauri::command]
pub async fn account_link_create(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>) -> Res<Value> {
  call(&core, &db.0, reqwest::Method::POST, "auth/link", Some(json!({"device": device(&db.0)})), false).await
}

#[tauri::command]
pub async fn account_link_poll(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>, code: String) -> Res<Value> {
  let out = call(&core, &db.0, reqwest::Method::GET, &format!("auth/link/{}/poll", urlencoding::encode(&code)), None, false).await?;
  take_session(out)
}

/// Код из ссылки `https://try-sonar.ru/auth/<код>`, `sonar://auth/<код>` или сам код.
pub fn link_code(raw: &str) -> Option<String> {
  let s = raw.trim().trim_end_matches('/');
  let code = s.rsplit('/').next().unwrap_or(s).trim();
  let ok = (16..=128).contains(&code.len()) && code.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
  ok.then(|| code.to_owned())
}

#[tauri::command]
pub async fn account_link_info(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>, link: String) -> Res<Value> {
  let code = link_code(&link).ok_or("Это не ссылка входа Sonar")?;
  let mut info = call(&core, &db.0, reqwest::Method::GET, &format!("auth/link/{code}"), None, true).await?;
  info["code"] = code.into();
  Ok(info)
}

#[tauri::command]
pub async fn account_link_decide(core: State<'_, std::sync::Arc<Core>>, db: State<'_, Db>, code: String, approve: bool) -> Res<()> {
  let code = link_code(&code).ok_or("Это не ссылка входа Sonar")?;
  let action = if approve { "approve" } else { "reject" };
  call(&core, &db.0, reqwest::Method::POST, &format!("auth/link/{code}/{action}"), None, true).await.map(|_| ())
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn names_windows_by_build() {
    assert_eq!(device_name(19045, "Folzy"), "Windows 10 (Folzy)");
    assert_eq!(device_name(22631, " DESKTOP-1 "), "Windows 11 (DESKTOP-1)");
    assert_eq!(device_name(19045, ""), "Windows 10");
  }

  #[test]
  fn parses_server_errors() {
    let e = parse_error(409, r#"{"error":{"code":"login_taken","message":"Логин уже занят"}}"#);
    assert_eq!(e, ApiError { status: 409, code: "login_taken".into(), message: "Логин уже занят".into() });
    assert_eq!(parse_error(502, "<html>").message, "Сервер Sonar не отвечает — попробуй позже");
    assert_eq!(parse_error(401, r#"{"error":{"code":"unauthorized","message":"x"}}"#).to_front(), "signed_out");
    // Неверный пароль — тоже 401, но это не «вышли»: показываем текст сервера.
    assert_eq!(parse_error(401, r#"{"error":{"code":"bad_credentials","message":"Неверный логин или пароль"}}"#).to_front(),
               "Неверный логин или пароль");
  }

  #[test]
  fn link_code_from_any_form() {
    let code = "AbC_def-0123456789xyz";
    assert_eq!(link_code(&format!("https://try-sonar.ru/auth/{code}")).as_deref(), Some(code));
    assert_eq!(link_code(&format!("sonar://auth/{code}/")).as_deref(), Some(code));
    assert_eq!(link_code(&format!("  {code} ")).as_deref(), Some(code));
    assert_eq!(link_code("https://evil/auth/../x"), None);
    assert_eq!(link_code("short"), None);
  }
}
