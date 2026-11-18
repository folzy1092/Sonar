//! Резервный сервис (docs/NEXT_PROMPT.md, этап 4): свой поток трека не играет — тот же трек ищется
//! в других сервисах по порядку `audio.fallback_order` и играет оттуда. Сверка строгая
//! (`providers/matching.rs`): не нашлось точно того же — лучше не играть ничего, чем чужой ремикс.
//! «SoundCloud через Яндекс» (`audio.sc_via_yandex`) — тот же механизм, только Яндекс пробуется
//! первым, даже когда SoundCloud играет.
//!
//! Найденные пары живут в памяти ядра; на диск (`track_alias`) их пишет команда `stream_url`.

use super::{Core, Provider};
use crate::providers::matching::Wanted;
use crate::providers::registry::{by_key, info, parse_ref, RefKind, ServiceId, REGISTRY};
use crate::providers::unplayable::{preview_of, reason_of, Reason};
use crate::providers::{soundcloud, Source, Track};
use crate::store::{now_ms, TrackAlias};
use anyhow::{anyhow, Result};
use serde::Serialize;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

/// Сколько результатов поиска сверять на каждый запрос.
const SEARCH_LIMIT: u32 = 8;

/// Трек играет не со своего сервиса: откуда, что и почему (поле `via` ответа `stream_url`).
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Via {
  #[serde(rename = "ref")]
  pub ref_: String,
  pub service: ServiceId,
  pub from: ServiceId,
  pub reason: Reason,
}

/// Что играть. `found` — трек замены из поиска (в кэш `tracks`), `searched` — новые строки `track_alias`.
#[derive(Debug)]
pub struct Played {
  pub source: Source,
  pub via: Option<Via>,
  pub found: Option<Track>,
  pub searched: Vec<TrackAlias>,
}

/// Настройки и память резервного сервиса.
pub struct Fallback {
  /// `audio.fallback` (по умолчанию включено).
  pub enabled: AtomicBool,
  order: Mutex<Vec<ServiceId>>,
  /// (исходный ref, сервис) → найденный ref; None — искали, не нашлось.
  aliases: Mutex<HashMap<(String, ServiceId), Option<String>>>,
  /// Что сейчас играет вместо исходного трека — `/file` и `/hls` берут поток замены.
  routed: Mutex<HashMap<String, Via>>,
}

impl Default for Fallback {
  fn default() -> Self {
    Self {
      enabled: AtomicBool::new(true),
      order: Mutex::new(default_order()),
      aliases: Mutex::new(HashMap::new()),
      routed: Mutex::new(HashMap::new()),
    }
  }
}

impl Fallback {
  pub fn set_order(&self, order: Vec<ServiceId>) {
    *self.order.lock().unwrap() = order;
  }

  pub fn order(&self) -> Vec<ServiceId> {
    self.order.lock().unwrap().clone()
  }

  /// Пары из `track_alias` (команда `stream_url` подкладывает их перед поиском).
  pub fn remember(&self, rows: &[TrackAlias]) {
    let mut map = self.aliases.lock().unwrap();
    for r in rows {
      if let Some(s) = by_key(&r.service) {
        map.insert((r.source_ref.clone(), s.id), r.alias_ref.clone());
      }
    }
  }

  fn known(&self, track_ref: &str, service: ServiceId) -> Option<Option<String>> {
    self.aliases.lock().unwrap().get(&(track_ref.to_owned(), service)).cloned()
  }

  fn put(&self, track_ref: &str, service: ServiceId, alias: Option<String>) {
    self.aliases.lock().unwrap().insert((track_ref.to_owned(), service), alias);
  }

  /// ref замены, если трек сейчас играет с другого сервиса.
  pub fn routed_ref(&self, track_ref: &str) -> Option<String> {
    self.routed.lock().unwrap().get(track_ref).map(|v| v.ref_.clone())
  }
}

/// Может быть резервом: работает в Sonar, ищет и отдаёт поток (по реестру; Spotify без потока — нет).
pub fn can_back_up(id: ServiceId) -> bool {
  let i = info(id);
  i.implemented && i.caps.search && i.caps.stream
}

/// Порядок по умолчанию — порядок реестра.
pub fn default_order() -> Vec<ServiceId> {
  REGISTRY.iter().map(|i| i.id).filter(|id| can_back_up(*id)).collect()
}

/// `audio.fallback_order` (массив id или ключей) → порядок: неизвестные и повторы — прочь,
/// забытые сервисы — в конец в порядке реестра (новый сервис сам встаёт в очередь).
pub fn parse_order(v: Option<&serde_json::Value>) -> Vec<ServiceId> {
  let mut out: Vec<ServiceId> = Vec::new();
  for s in v.and_then(|v| v.as_array()).into_iter().flatten().filter_map(|x| x.as_str()) {
    if let Some(i) = by_key(s).filter(|i| can_back_up(i.id) && !out.contains(&i.id)) {
      out.push(i.id);
    }
  }
  for id in default_order() {
    if !out.contains(&id) {
      out.push(id);
    }
  }
  out
}

/// Где искать замену: по порядку, без исходного сервиса и уже не сработавших.
pub fn candidates(order: &[ServiceId], from: ServiceId, skip: &[ServiceId]) -> Vec<ServiceId> {
  order.iter().copied().filter(|s| *s != from && !skip.contains(s)).collect()
}

/// Плашка качества: «MP3 320 · Яндекс Музыка».
fn labeled(src: Source, service: ServiceId) -> Source {
  let name = info(service).name;
  match src {
    Source::File { url, quality } => Source::File { url, quality: format!("{quality} · {name}") },
    Source::Hls { url, quality } => Source::Hls { url, quality: format!("{quality} · {name}") },
  }
}

impl Played {
  fn own(source: Source, searched: Vec<TrackAlias>) -> Self {
    Self { source, via: None, found: None, searched }
  }
}

impl Core {
  /// Поток трека с резервом: свой сервис, а не играет (нет трека, превью, нужна подписка, не открылся
  /// после повтора) — тот же трек в другом сервисе. `meta` — трек из интерфейса или кэша (по нему ищем);
  /// `broken` — свой поток открылся, но не играет (ошибка `<audio>`), сразу к замене.
  pub async fn resolve_playable(&self, track_ref: &str, meta: Option<&Track>, broken: bool) -> Result<Played> {
    let from = parse_ref(track_ref).filter(|(_, k)| *k == RefKind::Track).map(|(s, _)| s.id);
    let Some(from) = from.filter(|id| *id != ServiceId::Local) else {
      return Ok(Played::own(self.resolve(track_ref, false).await?, vec![]));
    };
    let mut skip = Vec::new();
    let routed = self.fallback.routed.lock().unwrap().remove(track_ref);
    if let Some(via) = routed {
      if !broken {
        if let Ok(src) = self.resolve_own_retrying(&via.ref_).await {
          self.fallback.routed.lock().unwrap().insert(track_ref.to_owned(), via.clone());
          return Ok(Played { source: labeled(src, via.service), via: Some(via), found: None, searched: vec![] });
        }
      }
      skip.push(via.service);
    }
    if broken {
      self.forget_stream(track_ref);
    }
    let mut searched = Vec::new();
    let mut wanted: Option<Option<Wanted>> = None;
    // «SoundCloud через Яндекс»: Яндекс первым, даже когда SoundCloud играет
    let preferred = from == ServiceId::Sc && self.sc_via_yandex.load(Ordering::Relaxed) && !skip.contains(&ServiceId::Ym);
    if !broken && preferred && self.can_search(ServiceId::Ym).await {
      let w = wanted.get_or_insert(self.wanted(track_ref, meta).await);
      if let Some(w) = w.as_ref() {
        if let Some(p) = self.try_alias(track_ref, w, ServiceId::Ym, from, Reason::Preferred, &mut searched).await {
          return Ok(Played { searched, ..p });
        }
      }
      skip.push(ServiceId::Ym);
    }
    let err = if broken {
      anyhow!("поток {} не открылся", info(from).name)
    } else {
      match self.resolve_own_retrying(track_ref).await {
        Ok(src) => return Ok(Played::own(src, searched)),
        Err(e) => e,
      }
    };
    if self.fallback.enabled.load(Ordering::Relaxed) {
      let reason = if broken { Reason::Failed } else { reason_of(&err) };
      if wanted.is_none() {
        wanted = Some(self.wanted(track_ref, meta).await);
      }
      if let Some(w) = wanted.flatten() {
        for svc in candidates(&self.fallback.order(), from, &skip) {
          if !self.can_search(svc).await {
            continue;
          }
          if let Some(p) = self.try_alias(track_ref, &w, svc, from, reason, &mut searched).await {
            log::info!("[fallback] {track_ref}: {} → {} ({reason:?})", info(from).name, info(svc).name);
            return Ok(Played { searched, ..p });
          }
        }
      }
    }
    // замены нет: отрывок — лучше, чем ничего (как раньше), иначе — исходная ошибка
    match preview_of(&err) {
      Some(src) => Ok(Played::own(src, searched)),
      None => Err(err),
    }
  }

  /// Сервис может искать замену прямо сейчас: SoundCloud (публичный client_id) и YouTube Music
  /// (гость) — всегда, остальные — когда подключены.
  async fn can_search(&self, id: ServiceId) -> bool {
    match id {
      ServiceId::Sc | ServiceId::Yt => true,
      ServiceId::Ym => self.ym.read().await.is_some(),
      ServiceId::Vk => self.vk.read().await.is_some(),
      ServiceId::Sp | ServiceId::Local => false,
    }
  }

  /// Что искать: у SoundCloud — по сырому JSON (артист из метаданных точнее ника), у остальных —
  /// по треку из интерфейса или кэша. Ничего нет — искать нечего.
  async fn wanted(&self, track_ref: &str, meta: Option<&Track>) -> Option<Wanted> {
    let sc_id = crate::providers::registry::is_kind(track_ref, ServiceId::Sc, RefKind::Track)
      .then(|| track_ref.split_once(':').map(|(_, id)| id.to_owned()))
      .flatten();
    let cached = self.sc_raw.lock().unwrap().get(track_ref).cloned();
    let json = match (cached, &sc_id, meta) {
      (Some(j), _, _) => Some(j),
      (None, Some(id), None) => {
        let creds = self.sc_creds(false).await.ok()?.0;
        soundcloud::SoundCloud { http: &self.http, creds: &creds }.track_json(id).await.ok()
      }
      _ => None,
    };
    if let Some(j) = json.filter(|_| sc_id.is_some()) {
      return Some(Wanted::soundcloud(
        j["user"]["username"].as_str().unwrap_or(""),
        j["publisher_metadata"]["artist"].as_str(),
        j["title"].as_str().unwrap_or(""),
        j["full_duration"].as_u64().or(j["duration"].as_u64()).unwrap_or(0),
      ));
    }
    meta.filter(|t| !t.title.trim().is_empty()).map(Wanted::from_track)
  }

  /// Замена в сервисе `svc`: пара из памяти или поиск (новая пара — в `searched`), потом поток.
  async fn try_alias(
    &self,
    track_ref: &str,
    wanted: &Wanted,
    svc: ServiceId,
    from: ServiceId,
    reason: Reason,
    searched: &mut Vec<TrackAlias>,
  ) -> Option<Played> {
    let (alias, found) = match self.fallback.known(track_ref, svc) {
      Some(alias) => (alias, None),
      None => {
        let t = match self.search_twin(wanted, svc).await {
          Ok(t) => t,
          // сеть или ключи — не «нет трека»: не запоминаем
          Err(e) => {
            log::warn!("[fallback] поиск {} для {track_ref}: {e}", info(svc).name);
            return None;
          }
        };
        let alias = t.as_ref().map(|t| t.ref_.clone());
        self.fallback.put(track_ref, svc, alias.clone());
        searched.push(TrackAlias {
          source_ref: track_ref.to_owned(),
          service: svc.as_str().to_owned(),
          alias_ref: alias.clone(),
          found_at: now_ms(),
        });
        (alias, t)
      }
    };
    let alias = alias?;
    match self.resolve_own_retrying(&alias).await {
      Ok(src) => {
        let via = Via { ref_: alias, service: svc, from, reason };
        self.fallback.routed.lock().unwrap().insert(track_ref.to_owned(), via.clone());
        Some(Played { source: labeled(src, svc), via: Some(via), found, searched: vec![] })
      }
      Err(e) => {
        log::warn!("[fallback] поток {alias}: {e}");
        None
      }
    }
  }

  /// Тот же трек в выдаче сервиса (не больше двух запросов).
  async fn search_twin(&self, wanted: &Wanted, svc: ServiceId) -> Result<Option<Track>> {
    let p = self.provider(svc)?;
    for q in wanted.queries() {
      let found = p.search(&q, SEARCH_LIMIT).await?;
      if let Some(t) = wanted.best(&found) {
        return Ok(Some(t.clone()));
      }
    }
    Ok(None)
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn default_order_follows_registry_and_skips_non_streaming() {
    assert_eq!(default_order(), vec![ServiceId::Sc, ServiceId::Ym, ServiceId::Yt, ServiceId::Vk]);
    assert!(!can_back_up(ServiceId::Sp));
    assert!(!can_back_up(ServiceId::Local));
  }

  #[test]
  fn parse_order_keeps_user_order_and_appends_missing() {
    let v = serde_json::json!(["yt", "yandex", "sp", "yt", "nope", 5]);
    assert_eq!(parse_order(Some(&v)), vec![ServiceId::Yt, ServiceId::Ym, ServiceId::Sc, ServiceId::Vk]);
    assert_eq!(parse_order(None), default_order());
    assert_eq!(parse_order(Some(&serde_json::json!("sc"))), default_order());
  }

  #[test]
  fn candidates_skip_source_and_failed() {
    let order = [ServiceId::Yt, ServiceId::Ym, ServiceId::Sc, ServiceId::Vk];
    assert_eq!(candidates(&order, ServiceId::Sc, &[ServiceId::Yt]), vec![ServiceId::Ym, ServiceId::Vk]);
    assert_eq!(candidates(&order, ServiceId::Sp, &[]), order.to_vec());
  }

  #[test]
  fn label_names_the_service() {
    let src = labeled(Source::Hls { url: "u".into(), quality: "Opus 160".into() }, ServiceId::Yt);
    assert_eq!(src, Source::Hls { url: "u".into(), quality: "Opus 160 · YouTube Music".into() });
  }

  #[test]
  fn remembers_rows_from_store() {
    let f = Fallback::default();
    f.remember(&[
      TrackAlias { source_ref: "sc:1".into(), service: "ym".into(), alias_ref: Some("ym:2".into()), found_at: 1 },
      TrackAlias { source_ref: "sc:1".into(), service: "youtube".into(), alias_ref: None, found_at: 1 },
      TrackAlias { source_ref: "sc:1".into(), service: "???".into(), alias_ref: None, found_at: 1 },
    ]);
    assert_eq!(f.known("sc:1", ServiceId::Ym), Some(Some("ym:2".into())));
    assert_eq!(f.known("sc:1", ServiceId::Yt), Some(None));
    assert_eq!(f.known("sc:1", ServiceId::Vk), None);
  }

  #[tokio::test]
  async fn spotify_without_fallback_match_keeps_error() {
    let core = Core::new_empty();
    core.fallback.set_order(vec![]);
    let e = core.resolve_playable("sp:4uLU6hMCjMI75M1A2tKUQC", None, false).await.unwrap_err();
    assert_eq!(e.to_string(), crate::providers::spotify::NEEDS_FALLBACK);
  }

  #[tokio::test]
  async fn routed_alias_feeds_plain_resolve() {
    let core = Core::new_empty();
    let via = Via { ref_: "local:x".into(), service: ServiceId::Ym, from: ServiceId::Sp, reason: Reason::Premium };
    core.fallback.routed.lock().unwrap().insert("sp:1".into(), via);
    assert_eq!(core.fallback.routed_ref("sp:1").as_deref(), Some("local:x"));
    // замена — несуществующий локальный файл: resolve идёт к ней, а не к Spotify
    let e = core.resolve("sp:1", false).await.unwrap_err().to_string();
    assert_ne!(e, crate::providers::spotify::NEEDS_FALLBACK);
  }
}
