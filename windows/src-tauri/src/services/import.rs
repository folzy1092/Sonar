//! Импорт плейлиста по любой ссылке (docs/NEXT_PROMPT.md, этап 5): Spotify, YouTube / YouTube Music,
//! VK, Яндекс, SoundCloud и Apple Music. Прочитать список треков → каждому найти пару в подключённых
//! сервисах (той же сверкой, что и резервный сервис: `Core::search_twin`, этап 4) → итог «нашлось
//! N из M». Трек сервиса, который сам играет в Sonar, остаётся как есть; Spotify (без потока) и
//! Apple Music (своего сервиса нет) ищутся в сервисах по порядку `audio.fallback_order`.
//!
//! Прогресс — шагами через `on_step` (команда шлёт их событием `import:progress`), отмена — по id
//! задачи (`cancel`): «Остановить» или новый импорт не тратят запросы на остальные треки.

use super::fallback::{can_back_up, candidates};
use super::Core;
use crate::providers::apple;
use crate::providers::links::{parse, Link};
use crate::providers::matching::Wanted;
use crate::providers::registry::{parse_ref, RefKind, ServiceId};
use crate::providers::Track;
use anyhow::{anyhow, bail, Result};
use futures_util::stream::{self, StreamExt};
use serde::Serialize;
use std::collections::HashSet;
use std::sync::{LazyLock, Mutex};

/// Сколько треков ищется одновременно: быстрее, но без лишней нагрузки на поиск сервисов.
const PARALLEL: usize = 4;
/// Сервис источника — для значка на экране импорта (Apple Music нет в реестре).
const APPLE: &str = "am";

/// Отменённые задачи импорта (id задачи придумывает интерфейс).
static CANCELLED: LazyLock<Mutex<HashSet<String>>> = LazyLock::new(|| Mutex::new(HashSet::new()));

/// Откуда переносим: шапка экрана импорта.
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ImportHead {
  /// Короткий id сервиса (`sp`, `yt`, …) или `am` для Apple Music.
  pub service: String,
  pub album: bool,
  pub title: String,
  pub owner: String,
  pub cover_url: Option<String>,
  /// Сколько треков в источнике (Apple отдаёт со страницы не больше ~100 — тогда `total` больше).
  pub total: u32,
  /// ref плейлиста или альбома сервиса либо адрес страницы Apple Music — `source_ref` нового плейлиста.
  pub source: String,
}

/// Прочитанный источник: шапка и треки по порядку.
#[derive(Debug, Clone)]
pub struct ImportSource {
  pub head: ImportHead,
  pub tracks: Vec<Track>,
}

/// Что вышло с треком.
#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum StepStatus {
  /// Трек сервиса, который сам играет в Sonar, — без поиска.
  Kept,
  /// Нашлась пара в другом сервисе.
  Found,
  /// Пары нет ни в одном подключённом сервисе.
  Missing,
}

/// Шаг сверки: трек `index` источника и что с ним.
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ImportStep {
  pub index: usize,
  pub status: StepStatus,
  /// Что попадёт в плейлист: сам трек (`kept`) или найденная пара (`found`).
  pub track: Option<Track>,
}

/// Остановить задачу: оставшиеся треки не ищутся.
pub fn cancel(job: &str) {
  CANCELLED.lock().unwrap().insert(job.to_owned());
}

fn cancelled(job: &str) -> bool {
  CANCELLED.lock().unwrap().contains(job)
}

/// Забыть задачу: она кончилась (или не началась — источник не прочитался).
pub fn forget_job(job: &str) {
  CANCELLED.lock().unwrap().remove(job);
}

/// Играет ли трек в Sonar сам (его сервис ищет и отдаёт поток) — тогда пару искать не нужно.
pub fn keeps_own(track_ref: &str) -> bool {
  parse_ref(track_ref).is_some_and(|(s, kind)| kind == RefKind::Track && s.id != ServiceId::Local && can_back_up(s.id))
}

/// Сервис трека-источника (Apple и неизвестные — None): в нём пару не ищем.
fn own_service(track_ref: &str) -> Option<ServiceId> {
  parse_ref(track_ref).filter(|(_, k)| *k == RefKind::Track).map(|(s, _)| s.id)
}

impl Core {
  /// Прочитать источник по ссылке (или по готовому ref плейлиста / альбома сервиса).
  pub async fn import_source(&self, raw: &str) -> Result<ImportSource> {
    let raw = raw.trim();
    let collection = parse_ref(raw).filter(|(_, k)| matches!(k, RefKind::Playlist | RefKind::Album)).map(|_| raw.to_owned());
    let pl_ref = match collection {
      Some(r) => r,
      None => match parse(raw).ok_or_else(|| anyhow!("Это не ссылка на плейлист или альбом"))? {
        Link::Apple(url) => return self.apple_source(&url).await,
        Link::Ref(r) => r,
        Link::SoundCloud(_) => match self.resolve_link(raw).await? {
          super::LinkItem::Playlist { playlist } => playlist.ref_,
          super::LinkItem::Album { album } => album.ref_,
          _ => bail!("Перенести можно только плейлист или альбом"),
        },
      },
    };
    self.collection_source(&pl_ref).await
  }

  pub(super) async fn apple_source(&self, url: &str) -> Result<ImportSource> {
    let p = apple::fetch(&self.http(), url).await?;
    let head = ImportHead {
      service: APPLE.into(),
      album: p.album,
      title: p.title,
      owner: p.owner,
      cover_url: p.cover_url,
      total: p.track_count.max(p.tracks.len() as u32),
      source: url.to_owned(),
    };
    Ok(ImportSource { head, tracks: p.tracks })
  }

  /// Плейлист или альбом сервиса по ref.
  async fn collection_source(&self, r: &str) -> Result<ImportSource> {
    let (svc, kind) = parse_ref(r).ok_or_else(|| anyhow!("плохая ссылка"))?;
    let service = svc.id.as_str().to_owned();
    match kind {
      RefKind::Playlist => {
        let p = self.service_playlist(r).await?;
        let total = p.tracks.len() as u32;
        let pl = p.playlist;
        let head =
          ImportHead { service, album: false, title: pl.title, owner: pl.owner, cover_url: pl.cover_url, total, source: r.to_owned() };
        Ok(ImportSource { head, tracks: p.tracks })
      }
      RefKind::Album => {
        let p = self.album_page(r).await?;
        let total = p.tracks.len() as u32;
        let a = p.album;
        let head = ImportHead { service, album: true, title: a.title, owner: a.artist, cover_url: a.cover_url, total, source: r.to_owned() };
        Ok(ImportSource { head, tracks: p.tracks })
      }
      _ => bail!("Перенести можно только плейлист или альбом"),
    }
  }

  /// Где искать пары: порядок `audio.fallback_order`, только сервисы, которые могут искать сейчас.
  pub async fn import_order(&self) -> Vec<ServiceId> {
    let mut out = Vec::new();
    for svc in self.fallback.order() {
      if self.can_search(svc).await {
        out.push(svc);
      }
    }
    out
  }

  /// Пара одного трека: свой сервис играет — он сам; иначе первый найденный в `order`.
  pub async fn import_match(&self, t: &Track, order: &[ServiceId]) -> ImportStep {
    if keeps_own(&t.ref_) {
      return ImportStep { index: 0, status: StepStatus::Kept, track: Some(t.clone()) };
    }
    let wanted = Wanted::from_track(t);
    let from = own_service(&t.ref_);
    let services = match from {
      Some(from) => candidates(order, from, &[]),
      None => order.to_vec(),
    };
    for svc in services {
      match self.search_twin(&wanted, svc).await {
        Ok(Some(found)) => return ImportStep { index: 0, status: StepStatus::Found, track: Some(found) },
        Ok(None) => {}
        // сеть или ключи одного сервиса — пробуем следующий
        Err(e) => log::warn!("[import] поиск в {}: {e}", svc.as_str()),
      }
    }
    ImportStep { index: 0, status: StepStatus::Missing, track: None }
  }

  /// Сверить все треки (по `PARALLEL` сразу), каждый шаг — в `on_step` по мере готовности.
  /// Отменённая задача (`cancel`) больше не ищет; вернутся только готовые шаги, по порядку треков.
  pub async fn import_match_all(&self, job: &str, tracks: &[Track], on_step: impl Fn(&ImportStep)) -> Vec<ImportStep> {
    let order = self.import_order().await;
    let order = &order;
    // треки — копиями: ссылки в замыканиях потока не проходят проверку Send у команды Tauri
    let mut pending = stream::iter(tracks.to_vec().into_iter().enumerate())
      .map(|(index, t)| async move {
        if cancelled(job) {
          return None;
        }
        Some(ImportStep { index, ..self.import_match(&t, order).await })
      })
      .buffer_unordered(PARALLEL);
    let mut steps = Vec::with_capacity(tracks.len());
    while let Some(next) = pending.next().await {
      if let Some(step) = next {
        on_step(&step);
        steps.push(step);
      }
    }
    forget_job(job);
    steps.sort_by_key(|s| s.index);
    steps
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use std::sync::atomic::{AtomicUsize, Ordering};

  fn track(r: &str, artist: &str, title: &str) -> Track {
    Track {
      ref_: r.into(),
      title: title.into(),
      artist: artist.into(),
      artists: vec![],
      album: None,
      duration_ms: 200_000,
      cover_url: None,
      url: None,
      explicit: false,
      available: true,
      plays: None,
      tags: None,
    }
  }

  #[test]
  fn playable_services_keep_their_tracks() {
    assert!(keeps_own("sc:1"));
    assert!(keeps_own("ym:2"));
    assert!(keeps_own("yt:dQw4w9WgXcQ"));
    assert!(keeps_own("vk:1_2"));
    // Spotify без потока и Apple Music без сервиса — ищутся
    assert!(!keeps_own("sp:4uLU6hMCjMI75M1A2tKUQC"));
    assert!(!keeps_own("am:6822497774"));
    assert!(!keeps_own("local:abc"));
    assert!(!keeps_own("scpl:1"));
  }

  #[tokio::test]
  async fn matches_in_source_order_and_reports_every_step() {
    let core = Core::new_empty();
    // искать негде: всё, что не играет само, — «не нашлось», без сети
    core.fallback.set_order(vec![]);
    let tracks = vec![track("sc:1", "A", "One"), track("sp:4uLU6hMCjMI75M1A2tKUQC", "B", "Two"), track("am:3", "C", "Three")];
    let seen = AtomicUsize::new(0);
    let steps = core.import_match_all("t1", &tracks, |_| {
      seen.fetch_add(1, Ordering::Relaxed);
    })
    .await;
    assert_eq!(seen.load(Ordering::Relaxed), 3);
    let got: Vec<(usize, StepStatus)> = steps.iter().map(|s| (s.index, s.status)).collect();
    assert_eq!(got, vec![(0, StepStatus::Kept), (1, StepStatus::Missing), (2, StepStatus::Missing)]);
    assert_eq!(steps[0].track.as_ref().map(|t| t.ref_.as_str()), Some("sc:1"));
  }

  #[tokio::test]
  async fn cancelled_job_stops_matching() {
    let core = Core::new_empty();
    core.fallback.set_order(vec![]);
    cancel("t2");
    let steps = core.import_match_all("t2", &[track("sc:1", "A", "One")], |_| {}).await;
    assert!(steps.is_empty());
    // задача забыта — тот же id можно запустить снова
    assert!(!cancelled("t2"));
  }

  #[tokio::test]
  async fn rejects_links_that_are_not_collections() {
    let core = Core::new_empty();
    let e = core.import_source("просто текст").await.unwrap_err().to_string();
    assert!(e.contains("не ссылка"));
    let e = core.import_source("https://music.yandex.ru/artist/42").await.unwrap_err().to_string();
    assert!(e.contains("только плейлист или альбом"));
  }

  #[tokio::test]
  async fn apple_head_counts_whole_playlist() {
    let p = apple::parse_page(include_str!("../providers/fixtures/apple-playlist.html")).unwrap();
    assert!(p.track_count as usize > p.tracks.len());
    // Apple-трек ищется во всех сервисах порядка: своего сервиса у него нет
    assert_eq!(own_service(&p.tracks[0].ref_), None);
  }
}
