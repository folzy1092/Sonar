//! Сведение (`docs/BLEND.md` §4.1, §5): файл трека целиком для анализа и хранение результатов.
//!
//! Анализ считает фронт (`player/blend/analysis.ts` в воркере); Rust только отдаёт трек одним файлом
//! с локального аудио-сервера и кладёт результат в базу. Трек уже на диске (кэш, скачанное, свой
//! файл) — адрес на него. Нет — качаем целиком тем же кодом, что кэш: при включённом кэше файл ложится
//! в кэш как обычно, при выключенном — во временный `<кэш>/blend-tmp` (`blend_release` после анализа,
//! остатки чистятся при запуске).

use crate::commands::{Db, StreamPort};
use crate::services::Core;
use crate::store::BlendRow;
use crate::stream::{self, Target};
use crate::track_cache;
use serde::Serialize;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tauri::State;

/// Трек больше — анализа нет, будет кроссфейд (решение 5).
pub const FETCH_CAP_BYTES: u64 = 60 * 1024 * 1024;
/// Дольше качать не ждём.
pub const FETCH_DEADLINE: Duration = Duration::from_secs(30);
/// Как часто смотрим, не докачал ли трек плеер (он уже взял его в работу).
const WAIT_STEP: Duration = Duration::from_millis(250);

#[derive(Serialize, Debug, PartialEq)]
pub struct BlendSource {
  pub url: String,
  /// Временный файл: после анализа — `blend_release`.
  pub temp: bool,
}

type Res<T> = Result<T, String>;

/// Где взять трек целиком, не качая: свой файл, кэш, скачанное, уже лежащий временный.
pub fn on_disk(port: u16, track_ref: &str) -> Option<BlendSource> {
  if crate::local::is_local_ref(track_ref) || track_cache::lookup(track_ref).is_some() {
    return Some(BlendSource { url: stream::track_url(port, "file", track_ref), temp: false });
  }
  track_cache::blend_lookup(track_ref).map(|_| BlendSource { url: blend_url(port, track_ref), temp: true })
}

fn blend_url(port: u16, track_ref: &str) -> String {
  stream::track_url(port, "blend", track_ref)
}

#[tauri::command]
pub async fn blend_source(core: State<'_, Arc<Core>>, port: State<'_, StreamPort>, track_ref: String) -> Res<BlendSource> {
  if track_ref.is_empty() {
    return Err("пустой ref".into());
  }
  if let Some(hit) = on_disk(port.0, &track_ref) {
    return Ok(hit);
  }
  crate::offline::guard()?;
  let started = Instant::now();
  let stop = move || crate::offline::is_on() || started.elapsed() > FETCH_DEADLINE;
  if !track_cache::enabled() {
    fetch(&core, &track_ref, Target::Blend, &stop).await?;
    return Ok(BlendSource { url: blend_url(port.0, &track_ref), temp: true });
  }
  if track_cache::claim(&track_ref) {
    let got = fetch(&core, &track_ref, Target::Cache, &stop).await;
    track_cache::release(&track_ref);
    got?;
  } else {
    // трек уже качает плеер (HLS) или подкачка — ждём его файл
    while track_cache::lookup(&track_ref).is_none() {
      if stop() {
        return Err("трек не скачался за 30 с".into());
      }
      tokio::time::sleep(WAIT_STEP).await;
    }
  }
  on_disk(port.0, &track_ref).ok_or_else(|| "файл не лёг в кэш".into())
}

async fn fetch(core: &Core, track_ref: &str, to: Target, stop: &(dyn Fn() -> bool + Send + Sync)) -> Res<()> {
  let work = stream::fetch_into(core, track_ref, to, Some(FETCH_CAP_BYTES), stop);
  match tokio::time::timeout(FETCH_DEADLINE, work).await {
    Ok(r) => r.map_err(|e| format!("сведение: {track_ref} не скачался — {e}")),
    Err(_) => Err(format!("сведение: {track_ref} не скачался за 30 с")),
  }
}

/// Анализ закончен — временный файл больше не нужен (файлы кэша не трогает).
#[tauri::command]
pub fn blend_release(track_ref: String) {
  track_cache::blend_drop(&track_ref);
}

#[tauri::command]
pub fn blend_get(db: State<'_, Db>, refs: Vec<String>) -> Res<HashMap<String, BlendRow>> {
  db.0.lock().unwrap().blend_get(&refs).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn blend_put(db: State<'_, Db>, track_ref: String, version: i64, json: String) -> Res<()> {
  db.0.lock().unwrap().blend_put(&track_ref, version, &json).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn blend_rate(db: State<'_, Db>, from: String, to: String, kind: String, score: i64) -> Res<()> {
  db.0.lock().unwrap().blend_rate(&from, &to, &kind, score).map_err(|e| e.to_string())
}

/// Перевес 👍/👎 по видам перехода с `since_ms` — его учитывает «Авто» (§8.6).
#[tauri::command]
pub fn blend_balance(db: State<'_, Db>, since_ms: i64) -> Res<HashMap<String, f64>> {
  db.0.lock().unwrap().blend_balance(since_ms).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn local_file_is_served_as_is() {
    let r = crate::local::local_ref(std::path::Path::new("/music/a.flac"));
    let got = on_disk(4000, &r).unwrap();
    assert!(!got.temp);
    assert!(got.url.starts_with("http://127.0.0.1:4000/file?ref="));
  }

  #[test]
  fn unknown_track_is_not_on_disk() {
    assert_eq!(on_disk(4000, "sc:нет-такого-трека-blend"), None);
  }
}
