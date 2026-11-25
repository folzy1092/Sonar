//! «Поделиться» треком (docs/SPACE_SHARE_PROMPT.md §3): тот же трек в других сервисах — для ссылки
//! `try-sonar.ru/t/#…`. Сервера нет, поэтому ищет приложение в момент шеринга: пары из `track_alias`
//! (резерв уже находил) или поиск теми же клиентами, что и резерв. Всё параллельно и с общим таймаутом:
//! не успели — делимся тем, что есть.
use super::Core;
use crate::providers::registry::{parse_ref, RefKind, ServiceId};
use crate::providers::{soundcloud, Track};
use serde::Serialize;
use std::collections::BTreeMap;
use std::time::Duration;

/// Дольше пользователь ждать не станет.
pub const SHARE_TIMEOUT: Duration = Duration::from_secs(4);

/// Где ищем двойников: что сайт может сыграть целиком (YouTube, SoundCloud) и Яндекс для кнопки.
const LOOK_IN: [ServiceId; 3] = [ServiceId::Yt, ServiceId::Sc, ServiceId::Ym];

#[derive(Debug, Default, Serialize, PartialEq)]
pub struct ShareTwins {
  /// Ключ сервиса (`yt`, `sc`, `ym`) → ref найденного трека.
  pub refs: BTreeMap<String, String>,
  /// Ключ сервиса → ссылка на трек (нужна для пути SoundCloud «user/slug»).
  pub urls: BTreeMap<String, String>,
  /// Трек SoundCloud (свой или двойник) играется целиком, а не Go+-отрывком.
  pub sc_full: bool,
}

impl Core {
  pub async fn share_twins(&self, track_ref: &str, meta: Option<&Track>) -> ShareTwins {
    let mut out = ShareTwins::default();
    let Some(from) = parse_ref(track_ref).filter(|(_, k)| *k == RefKind::Track).map(|(s, _)| s.id) else {
      return out;
    };
    if from == ServiceId::Local {
      return out;
    }
    let work = async {
      let wanted = self.wanted(track_ref, meta).await;
      let twins = futures_util::future::join_all(
        LOOK_IN.into_iter().filter(|s| *s != from).map(|svc| self.share_twin(track_ref, wanted.as_ref(), svc)),
      )
      .await;
      let mut out = ShareTwins::default();
      for (svc, twin) in LOOK_IN.into_iter().filter(|s| *s != from).zip(twins) {
        if let Some((r, url)) = twin {
          out.refs.insert(svc.as_str().to_owned(), r);
          if let Some(u) = url {
            out.urls.insert(svc.as_str().to_owned(), u);
          }
        }
      }
      let sc = if from == ServiceId::Sc { Some(track_ref.to_owned()) } else { out.refs.get("sc").cloned() };
      if let Some(sc) = sc {
        out.sc_full = self.sc_is_full(&sc).await;
      }
      out
    };
    match tokio::time::timeout(SHARE_TIMEOUT, work).await {
      Ok(found) => out = found,
      Err(_) => log::info!("[share] {track_ref}: двойники не успели за {SHARE_TIMEOUT:?}"),
    }
    out
  }

  /// Двойник в `svc`: известная пара или поиск (найденное — в `track_alias`, как у резерва).
  async fn share_twin(
    &self,
    track_ref: &str,
    wanted: Option<&crate::providers::matching::Wanted>,
    svc: ServiceId,
  ) -> Option<(String, Option<String>)> {
    if let Some(known) = self.fallback.known(track_ref, svc) {
      // ссылки у пары из памяти нет — путь SoundCloud тогда возьмём из кэша треков, если есть
      return known.map(|r| (r, None));
    }
    if !self.can_search(svc).await {
      return None;
    }
    match self.search_twin(wanted?, svc).await {
      Ok(t) => {
        self.fallback.put(track_ref, svc, t.as_ref().map(|t| t.ref_.clone()));
        t.map(|t| (t.ref_, t.url))
      }
      Err(e) => {
        log::warn!("[share] поиск {svc:?} для {track_ref}: {e}");
        None
      }
    }
  }

  /// SoundCloud отдаёт трек целиком (не `policy: SNIP` и не обрезанный поток). Не узнали — «нет»:
  /// лучше честная кнопка, чем 30 секунд на сайте.
  async fn sc_is_full(&self, sc_ref: &str) -> bool {
    let Some(id) = sc_ref.strip_prefix("sc:") else { return false };
    let cached = self.sc_raw.lock().unwrap().get(sc_ref).cloned();
    let json = match cached {
      Some(j) => j,
      None => {
        let Ok((creds, _)) = self.sc_creds(false).await else { return false };
        match (soundcloud::SoundCloud { http: &self.http(), creds: &creds }).track_json(id).await {
          Ok(j) => j,
          Err(_) => return false,
        }
      }
    };
    json["policy"].as_str() != Some("BLOCK") && !soundcloud::is_snippet(&json)
  }
}
