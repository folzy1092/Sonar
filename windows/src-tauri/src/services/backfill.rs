//! Свежие карточки треков по ref — для дозаполнения обложки и длительности (docs/NOW_ACCURACY_PROMPT.md §2).
//! Спрашиваем тот же сервис, что играет трек: SoundCloud (`/tracks?ids=`) и Яндекс (`POST /tracks`), другие — нет.
//!
//! Какие ref берём и что делаем с ответом — общие правила: `windows/src/lib/track-backfill.ts` и
//! iPhone `ios/Sonar/Core/Library/TrackBackfill.swift`, **правила менять в обоих местах**.

use super::Core;
use crate::providers::{soundcloud, yandex, Track};

/// Что вернул сервис: найденные карточки (ref — как спрашивали) и ref, которые спросить не вышло (сеть,
/// ключи) — их можно спросить снова, в отличие от тех, что сервис просто не знает.
#[derive(Debug, Default, serde::Serialize)]
pub struct TrackMeta {
  pub tracks: Vec<Track>,
  pub failed: Vec<String>,
}

/// Префиксы, для которых умеем дозаполнять.
pub const BACKFILL_PREFIXES: [&str; 2] = ["sc:", "ym:"];

pub fn can_backfill(r: &str) -> bool {
  BACKFILL_PREFIXES.iter().any(|p| r.strip_prefix(p).is_some_and(|id| !id.is_empty()))
}

/// Первая часть id Яндекса: `ym:123:456` (трек:альбом) и `ym:123` — один трек.
fn ym_key(id: &str) -> &str {
  id.split(':').next().unwrap_or(id)
}

impl Core {
  pub async fn track_meta(&self, refs: &[String]) -> TrackMeta {
    let (sc, ym): (Vec<&String>, Vec<&String>) = refs.iter().filter(|r| can_backfill(r)).partition(|r| r.starts_with("sc:"));
    let mut out = TrackMeta::default();
    if !sc.is_empty() {
      match self.sc_meta(&sc).await {
        Ok(found) => out.tracks.extend(found),
        Err(e) => {
          log::warn!("дозаполнение SoundCloud: {e}");
          out.failed.extend(sc.into_iter().cloned());
        }
      }
    }
    if !ym.is_empty() {
      match self.ym_meta(&ym).await {
        Ok(found) => out.tracks.extend(found),
        Err(e) => {
          log::warn!("дозаполнение Яндекса: {e}");
          out.failed.extend(ym.into_iter().cloned());
        }
      }
    }
    out
  }

  async fn sc_meta(&self, refs: &[&String]) -> anyhow::Result<Vec<Track>> {
    let ids: Vec<String> = refs.iter().map(|r| r["sc:".len()..].to_owned()).collect();
    let http = &self.http();
    let ids = &ids;
    let raw = self.with_sc(|c| async move { soundcloud::SoundCloud { http, creds: &c }.tracks_by_ids(ids).await }).await?;
    Ok(self.sc_keep(raw).into_iter().filter(|t| refs.iter().any(|r| **r == t.ref_)).collect())
  }

  async fn ym_meta(&self, refs: &[&String]) -> anyhow::Result<Vec<Track>> {
    let ids: Vec<String> = refs.iter().map(|r| r["ym:".len()..].to_owned()).collect();
    let s = self.ym_creds().await?;
    let found = yandex::Yandex { http: &self.http(), creds: &s.creds }.tracks(&ids).await?;
    // Яндекс отвечает `ym:<id>` — возвращаем под тем ref, что спрашивали (может быть `ym:<id>:<альбом>`)
    Ok(
      refs
        .iter()
        .filter_map(|r| {
          let key = ym_key(&r["ym:".len()..]);
          found.iter().find(|t| ym_key(&t.ref_["ym:".len()..]) == key).map(|t| Track { ref_: (*r).clone(), ..t.clone() })
        })
        .collect(),
    )
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn only_soundcloud_and_yandex() {
    assert!(can_backfill("sc:123") && can_backfill("ym:5:77"));
    assert!(!can_backfill("sc:") && !can_backfill("yt:abc") && !can_backfill("local:1") && !can_backfill("vk:1_2"));
  }

  #[test]
  fn yandex_key_ignores_album() {
    assert_eq!(ym_key("123:456"), "123");
    assert_eq!(ym_key("123"), "123");
  }
}
