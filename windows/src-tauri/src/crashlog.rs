//! Журнал ошибок и отчёт после сбоя (решение владельца 2026-11-16).
//!
//! Каждый запуск пишет свой `session.log` в папку логов приложения: предупреждения и ошибки Rust
//! (`log::warn!` / `log::error!`), ошибки интерфейса (`log_frontend`) и падения (panic-хук).
//! При следующем запуске прошлый журнал смотрится: было падение или ошибки — он становится
//! отчётом `report.log`, и интерфейс показывает плашку с кнопкой «Отправить лог». Отправка — в
//! Telegram ботом отчётов (токен, чат и тему вшивает CI из секретов: `SONAR_REPORT_BOT_TOKEN`,
//! `SONAR_REPORT_CHAT`, `SONAR_REPORT_THREAD`; в репозитории их нет). Сборка без них сохраняет лог
//! в «Загрузки» и показывает его в Проводнике — прислать вручную.

use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Mutex, OnceLock};

/// Журнал сессии не растёт больше этого — старое не нужно, нужна причина.
const MAX_LOG: u64 = 1_048_576;
/// Ошибок интерфейса за сессию пишем не больше — одна ошибка в цикле не должна забить диск.
const MAX_FRONT_ERRORS: usize = 60;

static DIR: OnceLock<PathBuf> = OnceLock::new();
static FILE: Mutex<Option<std::fs::File>> = Mutex::new(None);
static FRONT_ERRORS: AtomicUsize = AtomicUsize::new(0);

fn path(name: &str) -> Option<PathBuf> {
  DIR.get().map(|d| d.join(name))
}

fn stamp() -> String {
  let ms = crate::store::now_ms();
  let s = ms / 1000;
  format!("{:02}:{:02}:{:02}.{:03}", (s / 3600) % 24, (s / 60) % 60, s % 60, ms % 1000)
}

/// Дописать строку в журнал сессии (UTC-время, уровень, текст).
pub fn write(level: &str, msg: &str) {
  let mut g = FILE.lock().unwrap_or_else(|e| e.into_inner());
  let Some(f) = g.as_mut() else { return };
  if f.metadata().map(|m| m.len()).unwrap_or(0) > MAX_LOG {
    return;
  }
  let _ = writeln!(f, "{} {level:<5} {}", stamp(), msg.replace('\n', "\n      "));
}

/// `log` → журнал сессии: предупреждения и ошибки (информационное не нужно).
struct FileLogger;

impl log::Log for FileLogger {
  fn enabled(&self, m: &log::Metadata) -> bool {
    m.level() <= log::Level::Warn
  }
  fn log(&self, r: &log::Record) {
    if self.enabled(r.metadata()) {
      let level = if r.level() == log::Level::Error { "ERROR" } else { "WARN" };
      write(level, &format!("[{}] {}", r.target(), r.args()));
    }
  }
  fn flush(&self) {}
}

/// Что показать в плашке при запуске.
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Pending {
  /// Прошлый запуск упал (panic), а не просто ловил ошибки.
  pub crashed: bool,
  pub errors: usize,
  /// Последняя ошибка — одной строкой, для подписи в плашке.
  pub last: String,
}

/// Безвредные «ошибки» браузера: не сбой, а предупреждение движка (ResizeObserver не успел
/// разослать все уведомления за кадр). В журнал не пишем, в отчётах прошлых версий не считаем.
const BENIGN_UI: [&str; 2] = ["ResizeObserver loop completed with undelivered notifications", "ResizeObserver loop limit exceeded"];

fn is_benign(msg: &str) -> bool {
  BENIGN_UI.iter().any(|b| msg.contains(b))
}

/// Разобрать прошлый журнал: сколько ошибок, было ли падение, последняя ошибка.
pub fn summarize(log: &str) -> Pending {
  let crashed = log.contains(" PANIC ");
  let errors: Vec<&str> =
    log.lines().filter(|l| (l.contains(" ERROR ") || l.contains(" PANIC ")) && !is_benign(l)).collect();
  let last = errors.last().map(|l| l.get(13..).unwrap_or(l).trim().chars().take(140).collect()).unwrap_or_default();
  Pending { crashed, errors: errors.len(), last }
}

/// Запустить журнал: прошлую сессию с ошибками — в отчёт, новую — с чистого листа, panic-хук и логгер.
/// `with_logger = false` — в отладке логгер уже ставит tauri-plugin-log.
pub fn init(dir: &Path, with_logger: bool) {
  let _ = std::fs::create_dir_all(dir);
  let _ = DIR.set(dir.to_path_buf());
  let session = dir.join("session.log");
  if let Ok(prev) = std::fs::read_to_string(&session) {
    if summarize(&prev).errors > 0 {
      let _ = std::fs::write(dir.join("report.log"), prev);
    }
  }
  if let Ok(f) = std::fs::File::create(&session) {
    *FILE.lock().unwrap_or_else(|e| e.into_inner()) = Some(f);
  }
  write("INFO", &format!("Sonar {} · {}", env!("CARGO_PKG_VERSION"), os_line()));

  let default = std::panic::take_hook();
  std::panic::set_hook(Box::new(move |info| {
    let place = info.location().map(|l| format!(" ({}:{})", l.file(), l.line())).unwrap_or_default();
    let msg = info
      .payload()
      .downcast_ref::<&str>()
      .map(|s| s.to_string())
      .or_else(|| info.payload().downcast_ref::<String>().cloned())
      .unwrap_or_else(|| "неизвестная ошибка".into());
    write("PANIC", &format!("{msg}{place}\n{}", std::backtrace::Backtrace::force_capture()));
    default(info);
  }));
  if with_logger && log::set_boxed_logger(Box::new(FileLogger)).is_ok() {
    log::set_max_level(log::LevelFilter::Warn);
  }
}

fn os_line() -> String {
  format!("{} {}", std::env::consts::OS, std::env::consts::ARCH)
}

/// Ошибка из интерфейса (необработанное исключение, отказ промиса).
pub fn frontend(level: &str, msg: &str) {
  if is_benign(msg) {
    return;
  }
  let level = if level == "error" { "ERROR" } else { "WARN" };
  if level == "ERROR" && FRONT_ERRORS.fetch_add(1, Ordering::Relaxed) >= MAX_FRONT_ERRORS {
    return;
  }
  write(level, &format!("[ui] {msg}"));
}

/// Отчёт прошлой сессии, если он есть.
pub fn pending() -> Option<Pending> {
  let raw = std::fs::read_to_string(path("report.log")?).ok()?;
  let p = summarize(&raw);
  (p.errors > 0).then_some(p)
}

/// Закрыть плашку без отправки.
pub fn dismiss() {
  if let Some(p) = path("report.log") {
    let _ = std::fs::remove_file(p);
  }
}

/// Куда ушёл отчёт.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "snake_case", tag = "kind")]
pub enum Sent {
  Telegram,
  /// Бот отчётов не вшит в эту сборку — лог сохранён, путь показан в Проводнике.
  Saved { path: String },
}

/// Что было в интерфейсе в момент отправки — помогает повторить ошибку.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct Context {
  /// Стиль интерфейса (`appearance.style`).
  pub style: Option<String>,
  /// Сколько треков в очереди.
  pub queue: Option<usize>,
}

/// Длина строки стиля в подписи — защита от мусора из интерфейса.
const STYLE_MAX: usize = 32;

/// Подпись к отчёту: что случилось, версия, система, устройство, стиль и очередь.
fn caption(p: &Pending, device: &str, ctx: &Context) -> String {
  let style: String = ctx.style.as_deref().unwrap_or("?").chars().take(STYLE_MAX).collect();
  let queue = ctx.queue.map_or_else(|| "?".to_owned(), |n| n.to_string());
  format!(
    "{} Sonar {} · {}\nустройство {device}\nстиль {style} · очередь {queue}\nошибок: {}\n{}",
    if p.crashed { "💥 Падение" } else { "⚠️ Ошибки" },
    env!("CARGO_PKG_VERSION"),
    os_line(),
    p.errors,
    p.last
  )
}

/// Бот отчётов из сборки. Секреты CI чистим от пробелов и переводов строк: chat_id с хвостовым
/// `\n` Telegram не узнаёт и отвечает 400 (на iPhone так же — `ReportBot.from`).
struct ReportBot {
  token: &'static str,
  chat: &'static str,
  thread: Option<&'static str>,
}

fn clean(v: Option<&'static str>) -> Option<&'static str> {
  v.map(str::trim).filter(|s| !s.is_empty())
}

fn report_bot() -> Option<ReportBot> {
  Some(ReportBot {
    token: clean(option_env!("SONAR_REPORT_BOT_TOKEN"))?,
    chat: clean(option_env!("SONAR_REPORT_CHAT"))?,
    thread: clean(option_env!("SONAR_REPORT_THREAD")),
  })
}

/// Отказ Telegram: код и описание из ответа (`{"ok":false,"description":"Bad Request: …"}`).
#[derive(Debug)]
struct Rejected {
  status: u16,
  description: Option<String>,
}

impl Rejected {
  /// Тема удалена, закрыта или id темы не тот — можно отправить в общий чат.
  fn thread_problem(&self) -> bool {
    self.description.as_deref().is_some_and(|d| {
      let d = d.to_lowercase();
      d.contains("thread") || d.contains("topic")
    })
  }

  fn message(&self) -> String {
    match &self.description {
      Some(d) => format!("Telegram не принял отчёт: {d} ({})", self.status),
      None => format!("Telegram не принял отчёт ({})", self.status),
    }
  }
}

fn telegram_description(body: &str) -> Option<String> {
  serde_json::from_str::<serde_json::Value>(body).ok()?.get("description")?.as_str().map(str::to_owned)
}

async fn send_document(
  http: &reqwest::Client,
  bot: &ReportBot,
  thread: Option<&str>,
  caption: &str,
  name: &str,
  body: &[u8],
) -> Result<std::result::Result<(), Rejected>> {
  let mut form = reqwest::multipart::Form::new()
    .text("chat_id", bot.chat.to_owned())
    .text("caption", caption.chars().take(1000).collect::<String>())
    .part("document", reqwest::multipart::Part::bytes(body.to_vec()).file_name(name.to_owned()).mime_str("text/plain")?);
  if let Some(thread) = thread {
    form = form.text("message_thread_id", thread.to_owned());
  }
  let r = http.post(format!("https://api.telegram.org/bot{}/sendDocument", bot.token)).multipart(form).send().await?;
  let status = r.status();
  if status.is_success() {
    return Ok(Ok(()));
  }
  let description = telegram_description(&r.text().await.unwrap_or_default());
  write("WARN", &format!("отчёт: Telegram {} — {}", status.as_u16(), description.as_deref().unwrap_or("без описания")));
  Ok(Err(Rejected { status: status.as_u16(), description }))
}

/// Отправить отчёт: в Telegram ботом отчётов, а в сборке без него — сохранить в «Загрузки».
pub async fn send(http: &reqwest::Client, device: &str, ctx: &Context) -> Result<Sent> {
  let report = path("report.log").ok_or_else(|| anyhow!("журнал не запущен"))?;
  let body = std::fs::read(&report).map_err(|_| anyhow!("Отчёт уже отправлен или удалён"))?;
  let p = summarize(&String::from_utf8_lossy(&body));
  let caption = caption(&p, device, ctx);
  let name = format!("sonar-{}-{}.log", env!("CARGO_PKG_VERSION"), crate::store::now_ms());
  match report_bot() {
    Some(bot) => {
      let mut sent = send_document(http, &bot, bot.thread, &caption, &name, &body).await?;
      // тема сломалась — лучше отчёт в общем чате, чем никакого
      if matches!(&sent, Err(e) if bot.thread.is_some() && e.thread_problem()) {
        sent = send_document(http, &bot, None, &caption, &name, &body).await?;
      }
      sent.map_err(|e| anyhow!(e.message()))?;
      dismiss();
      Ok(Sent::Telegram)
    }
    None => {
      let dir = std::env::var_os("USERPROFILE").map(|h| PathBuf::from(h).join("Downloads")).filter(|d| d.is_dir());
      let dir = dir.or_else(|| DIR.get().cloned()).ok_or_else(|| anyhow!("некуда сохранить"))?;
      let out = dir.join(name);
      std::fs::write(&out, [caption.as_bytes(), b"\n\n", &body].concat())?;
      dismiss();
      Ok(Sent::Saved { path: out.to_string_lossy().into_owned() })
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn caption_has_version_style_and_queue() {
    let p = Pending { crashed: true, errors: 2, last: "PANIC x".into() };
    let ctx = Context { style: Some("classic".into()), queue: Some(412) };
    let c = caption(&p, "dev1", &ctx);
    assert!(c.contains(env!("CARGO_PKG_VERSION")));
    assert!(c.contains("стиль classic · очередь 412"));
    assert!(c.contains("устройство dev1"));
    let blank = caption(&p, "dev1", &Context { style: Some("x".repeat(500)), queue: None });
    assert!(blank.contains(&format!("стиль {} · очередь ?", "x".repeat(STYLE_MAX))));
  }

  #[test]
  fn summary_counts_errors_and_panics() {
    let log = "12:00:00.000 INFO  Sonar 0.1.1\n12:00:01.000 WARN  [ui] медленно\n12:00:02.000 ERROR [ui] TypeError: x is undefined\n12:00:03.000 PANIC called `unwrap()` on None (src/a.rs:1)\n      stack";
    let p = summarize(log);
    assert!(p.crashed);
    assert_eq!(p.errors, 2);
    assert!(p.last.starts_with("PANIC called"), "{}", p.last);
    let calm = summarize("12:00:00.000 INFO  Sonar\n12:00:01.000 WARN  [x] y");
    assert_eq!(calm, Pending { crashed: false, errors: 0, last: String::new() });
  }

  #[test]
  fn resize_observer_noise_is_not_an_error() {
    let log = "12:00:00.000 INFO  Sonar\n12:00:01.000 ERROR [ui] ResizeObserver loop completed with undelivered notifications. @ :0\n12:00:02.000 ERROR [ui] ResizeObserver loop limit exceeded";
    assert_eq!(summarize(log).errors, 0);
    assert!(is_benign("ResizeObserver loop completed with undelivered notifications."));
    assert!(!is_benign("TypeError: x is undefined"));
  }

  #[test]
  fn secrets_are_trimmed() {
    assert_eq!(clean(Some(" -1002276939424\n")), Some("-1002276939424"));
    assert_eq!(clean(Some("  \n")), None);
    assert_eq!(clean(None), None);
  }

  #[test]
  fn telegram_rejection_reads_description() {
    let d = telegram_description(r#"{"ok":false,"error_code":400,"description":"Bad Request: message thread not found"}"#);
    let e = Rejected { status: 400, description: d };
    assert!(e.thread_problem());
    assert_eq!(e.message(), "Telegram не принял отчёт: Bad Request: message thread not found (400)");
    let chat = Rejected { status: 400, description: Some("Bad Request: chat not found".into()) };
    assert!(!chat.thread_problem());
    assert_eq!(Rejected { status: 502, description: telegram_description("<html>") }.message(), "Telegram не принял отчёт (502)");
  }
}
