//! Офлайн-индекс (`docs/OFFLINE.md` §7.1): кэш треков докладывает, что лёг и что ушло (`track_cache::Change`),
//! здесь это ложится в `offline_tracks`, а интерфейс получает `offline-index-changed` и перечитывает `offline_refs`.
//! Изменения идут через свой поток по очереди: кэш дёргают и под замком базы (`clear_storage`) — прямо из хука
//! брать замок нельзя, а порядок «лёг → вытеснен» терять нельзя.
use std::sync::mpsc;

use tauri::{AppHandle, Emitter, Manager};

use crate::commands::Db;
use crate::store::{Store, OFFLINE_KIND_CACHE, OFFLINE_KIND_PINNED};
use crate::track_cache::{self, Change};

/// Событие для интерфейса: набор доступного офлайн поменялся.
pub const EVENT: &str = "offline-index-changed";

/// Сверить индекс с диском и подписаться на кэш. Вызывать после `app.manage(Db)`.
pub fn init(app: &AppHandle) {
  {
    let db = app.state::<Db>();
    let store = db.0.lock().unwrap();
    for (pinned, kind) in [(false, OFFLINE_KIND_CACHE), (true, OFFLINE_KIND_PINNED)] {
      if let Err(e) = store.offline_reconcile(&track_cache::disk_files(pinned), track_cache::key, kind) {
        log::warn!("офлайн-индекс: сверка с диском ({kind}) не прошла — {e}");
      }
    }
    match store.offline_pinned_covers() {
      Ok(urls) => crate::stream::prune_pinned_covers(&urls),
      Err(e) => log::warn!("офлайн-индекс: обложки скачанного не прочитаны — {e}"),
    }
  }
  let (tx, rx) = mpsc::channel::<Change>();
  track_cache::on_change(move |c| {
    let _ = tx.send(c);
  });
  let app = app.clone();
  std::thread::spawn(move || {
    while let Ok(first) = rx.recv() {
      // пачкой: вытеснение сыплет десятком изменений — интерфейсу хватит одного события
      {
        let db = app.state::<Db>();
        let store = db.0.lock().unwrap();
        for c in std::iter::once(first).chain(rx.try_iter()) {
          if let Err(e) = apply(&store, c) {
            log::warn!("офлайн-индекс: запись не прошла — {e}");
          }
        }
      }
      if let Err(e) = app.emit(EVENT, ()) {
        log::warn!("офлайн-индекс: событие не ушло — {e}");
      }
    }
  });
}

fn apply(store: &Store, c: Change) -> anyhow::Result<()> {
  match c {
    Change::Added { track_ref, file, mime, bytes, pinned } => store.offline_put(&track_ref, &file, &mime, bytes, kind(pinned)),
    Change::Removed { file, pinned } => store.offline_drop_file(&file, kind(pinned)),
    Change::Cleared { pinned } => store.offline_drop_kind(kind(pinned)),
  }
}

fn kind(pinned: bool) -> &'static str {
  if pinned {
    OFFLINE_KIND_PINNED
  } else {
    OFFLINE_KIND_CACHE
  }
}
