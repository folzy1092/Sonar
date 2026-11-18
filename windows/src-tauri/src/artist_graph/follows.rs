//! Фоновая подкачка для карты исполнителей: лайки подключённых сервисов (фантомные, раз в сутки)
//! и подписки исполнителей SoundCloud — пачками по 5 с паузой, не больше 60 за проход, кэш на 7 дней.
//! Граф по фитам виден сразу, подписки дорисовывают связи по мере загрузки. 429 — пауза на
//! 30 минут, 404 — пустой список (страницы нет). Базу не держим, пока ждём сеть.

use std::sync::atomic::{AtomicBool, AtomicI64, Ordering};
use std::sync::Arc;
use std::time::Duration;

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};

use super::Graph;
use crate::commands::Db;
use crate::providers::registry::{likes_ref, ServiceId};
use crate::providers::{Artist, Track};
use crate::services::Core;
use crate::store::{now_ms, Store};

const FIRST_RUN_DELAY: Duration = Duration::from_secs(90);
const RERUN_EVERY: Duration = Duration::from_secs(6 * 60 * 60);
const DAY_MS: i64 = 24 * 60 * 60 * 1000;
const FOLLOWS_TTL_MS: i64 = 7 * DAY_MS;
const PHANTOM_TTL_MS: i64 = DAY_MS;
const RATE_PAUSE_MS: i64 = 30 * 60 * 1000;
const MAX_PER_RUN: usize = 60;
const BATCH: usize = 5;
const BATCH_PAUSE: Duration = Duration::from_secs(3);
/// Подписок одного исполнителя хватит и 600 (три страницы): связи рисуются только с теми, кто есть на карте.
const MAX_FOLLOWINGS: usize = 600;

const EVENT_PROGRESS: &str = "artist-graph-progress";
const EVENT_UPDATED: &str = "artist-graph-updated";

static RUNNING: AtomicBool = AtomicBool::new(false);
/// До какого времени (мс) SoundCloud не трогаем после 429.
static RETRY_AFTER: AtomicI64 = AtomicI64::new(0);

/// Ход подкачки подписок для строки внизу карты.
#[derive(Debug, Clone, Serialize)]
struct Progress {
  done: usize,
  total: usize,
  /// `running` · `done` · `paused` (SoundCloud просит подождать) · `stopped` (ошибка сети)
  state: &'static str,
}

#[derive(Debug, PartialEq)]
enum Failure {
  RateLimited,
  NotFound,
  Other,
}

/// Ошибки провайдеров — текст `providers::http_error` с кодом в конце.
fn classify(e: &anyhow::Error) -> Failure {
  let text = e.to_string();
  if text.contains("HTTP 429") {
    Failure::RateLimited
  } else if text.contains("HTTP 404") {
    Failure::NotFound
  } else {
    Failure::Other
  }
}

/// Чьи подписки качать: исполнители медиатеки с `sca:`, самые весомые первыми, без свежего кэша.
fn pick_targets(g: &Graph, fetched_at: impl Fn(&str) -> Option<i64>, now: i64, max: usize) -> Vec<String> {
  g.nodes
    .iter()
    .filter(|n| n.discovered)
    .filter_map(|n| n.refs.iter().find(|r| r.starts_with("sca:")))
    .filter(|r| fetched_at(r).map_or(true, |at| now - at >= FOLLOWS_TTL_MS))
    .take(max)
    .cloned()
    .collect()
}

/// Цикл с запуска приложения: первый проход через полторы минуты, дальше раз в 6 часов.
pub async fn background(app: AppHandle) {
  tokio::time::sleep(FIRST_RUN_DELAY).await;
  loop {
    run(&app).await;
    tokio::time::sleep(RERUN_EVERY).await;
  }
}

/// Один проход; если уже идёт — ничего не делаем.
pub async fn run(app: &AppHandle) {
  if RUNNING.swap(true, Ordering::AcqRel) {
    return;
  }
  let res = pass(app).await;
  RUNNING.store(false, Ordering::Release);
  if let Err(e) = res {
    log::warn!("карта исполнителей: {e}");
  }
}

async fn pass(app: &AppHandle) -> anyhow::Result<()> {
  let (Some(core), Some(db)) = (app.try_state::<Arc<Core>>(), app.try_state::<Db>()) else {
    return Ok(());
  };
  if refresh_phantoms(&core, &db).await {
    super::invalidate();
    let _ = app.emit(EVENT_UPDATED, ());
  }
  fetch_follows(app, &core, &db).await
}

/// Лайки подключённых сервисов → фантомные треки карты. `true` — что-то обновили.
async fn refresh_phantoms(core: &Core, db: &Db) -> bool {
  let st = core.status().await;
  let services = [
    (ServiceId::Sc, st.soundcloud.connected),
    (ServiceId::Ym, st.yandex.connected),
    (ServiceId::Yt, st.youtube.connected),
    (ServiceId::Vk, st.vk.connected),
    (ServiceId::Sp, st.spotify.connected),
  ];
  let mut changed = false;
  for (id, connected) in services {
    let Some(source) = likes_ref(id).filter(|_| connected) else { continue };
    let fetched = db.0.lock().unwrap().phantom_fetched_at(&source).ok().flatten();
    if fetched.is_some_and(|at| now_ms() - at < PHANTOM_TTL_MS) {
      continue;
    }
    let page = match core.service_playlist(&source).await {
      Ok(page) => page,
      Err(e) => {
        log::warn!("карта исполнителей: лайки {source}: {e}");
        continue;
      }
    };
    match save_phantom(&mut db.0.lock().unwrap(), &source, &page.tracks) {
      Ok(()) => changed = true,
      Err(e) => log::warn!("карта исполнителей: сохранить лайки {source}: {e}"),
    }
  }
  changed
}

fn save_phantom(store: &mut Store, source: &str, tracks: &[Track]) -> anyhow::Result<()> {
  store.upsert_tracks(tracks)?;
  let refs: Vec<String> = tracks.iter().map(|t| t.ref_.clone()).collect();
  store.put_phantom(source, &refs)
}

fn save_follows(db: &Db, artist_ref: &str, follows: &[Artist]) {
  if let Err(e) = db.0.lock().unwrap().put_follows(artist_ref, follows) {
    log::warn!("карта исполнителей: сохранить подписки {artist_ref}: {e}");
  }
}

fn report(app: &AppHandle, done: usize, total: usize, state: &'static str) {
  let _ = app.emit(EVENT_PROGRESS, Progress { done, total, state });
  if done > 0 && state != "running" {
    super::invalidate();
    let _ = app.emit(EVENT_UPDATED, ());
  }
}

async fn fetch_follows(app: &AppHandle, core: &Core, db: &Db) -> anyhow::Result<()> {
  if now_ms() < RETRY_AFTER.load(Ordering::Acquire) {
    return Ok(());
  }
  let targets = {
    let store = db.0.lock().unwrap();
    let g = super::graph_for(&store)?;
    pick_targets(&g, |r| store.follows_fetched_at(r).ok().flatten(), now_ms(), MAX_PER_RUN)
  };
  let total = targets.len();
  if total == 0 {
    return Ok(());
  }
  let mut done = 0;
  report(app, done, total, "running");
  for (i, batch) in targets.chunks(BATCH).enumerate() {
    if i > 0 {
      tokio::time::sleep(BATCH_PAUSE).await;
    }
    for artist_ref in batch {
      match core.sc_followings(artist_ref, MAX_FOLLOWINGS).await {
        Ok(list) => save_follows(db, artist_ref, &list),
        Err(e) => match classify(&e) {
          Failure::NotFound => save_follows(db, artist_ref, &[]),
          Failure::RateLimited => {
            RETRY_AFTER.store(now_ms() + RATE_PAUSE_MS, Ordering::Release);
            report(app, done, total, "paused");
            return Ok(());
          }
          Failure::Other => {
            report(app, done, total, "stopped");
            return Err(e);
          }
        },
      }
      done += 1;
    }
    report(app, done, total, "running");
  }
  report(app, done, total, "done");
  Ok(())
}

// ——— команда ———

/// Подкачать сейчас (карта открылась). Ход — событиями `artist-graph-progress`, готово — `artist-graph-updated`.
#[tauri::command]
pub fn artist_graph_refresh(app: AppHandle) {
  tauri::async_runtime::spawn(async move { run(&app).await });
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::artist_graph::build::Node;

  fn node(key: &str, refs: &[&str], discovered: bool) -> Node {
    Node {
      key: key.into(),
      name: key.into(),
      refs: refs.iter().map(|r| r.to_string()).collect(),
      avatar_url: None,
      tracks: 1,
      plays: 0,
      weight: 1.0,
      discovered,
    }
  }

  #[test]
  fn targets_skip_fresh_cache_other_services_and_undiscovered() {
    let g = Graph {
      nodes: vec![
        node("a", &["ymar:1", "sca:1"], true),
        node("b", &["sca:2"], true),
        node("c", &["ymar:3"], true),
        node("d", &["sca:4"], false),
        node("e", &["sca:5"], true),
      ],
      edges: Vec::new(),
    };
    let now = 100 * DAY_MS;
    let fetched = |r: &str| match r {
      "sca:2" => Some(now - DAY_MS),
      "sca:5" => Some(now - 8 * DAY_MS),
      _ => None,
    };
    assert_eq!(pick_targets(&g, fetched, now, 10), vec!["sca:1", "sca:5"]);
    assert_eq!(pick_targets(&g, fetched, now, 1), vec!["sca:1"]);
  }

  #[test]
  fn classify_reads_http_code() {
    assert_eq!(classify(&crate::providers::http_error("SoundCloud", reqwest::StatusCode::TOO_MANY_REQUESTS)), Failure::RateLimited);
    assert_eq!(classify(&crate::providers::http_error("SoundCloud", reqwest::StatusCode::NOT_FOUND)), Failure::NotFound);
    assert_eq!(classify(&anyhow::anyhow!("timeout")), Failure::Other);
  }
}
