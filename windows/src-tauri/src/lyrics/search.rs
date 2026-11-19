//! Порядок поиска текста (docs/TITLE_SPLIT.md «Порядок поиска текста», как в selfbot `fetch_any`):
//! 1. обычная пара в lrclib — как есть → ядро названия → ключевые слова;
//! 2. только если синхронного нет — варианты перезалива `reupload_variants` по очереди
//!    (у перезаливщика из правил — первыми); не нашлось ни по одному — промах на `VARIANT_RECHECK`,
//!    сетевой сбой — не промах;
//! 3. NetEase и Genius — по `search_pair` (настоящий артист + чистое название);
//! 4. нет синхронного нигде — простой текст из lrclib.
//!
//! Ручная пара из правил — вместо всех шагов; трек из «игнора» не ищется. Сеть — за `Source`, тесты подменяют её.

use super::rules::{same_pair, Rules, VariantMisses};
use super::title_split::{reupload_variants, search_pair, Pair};
use super::{clean_title, first_artist, genius, keyword_title, lrclib, netease, parse_lrc, plain_lines, Lyrics, Meta};
use anyhow::Result;
use std::sync::Mutex;
use std::time::Instant;

/// Откуда берутся тексты: настоящая сеть или подмена в тестах.
pub(crate) trait Source {
  async fn lrclib(&self, artist: &str, title: &str, duration: f64) -> Result<lrclib::Found>;
  async fn netease(&self, artist: &str, title: &str, duration: f64) -> Result<Option<Lyrics>>;
  async fn genius(&self, artist: &str, title: &str) -> Result<Option<String>>;
}

/// Настоящие lrclib, NetEase и Genius.
pub(crate) struct Net<'a>(pub &'a reqwest::Client);

impl Source for Net<'_> {
  async fn lrclib(&self, artist: &str, title: &str, duration: f64) -> Result<lrclib::Found> {
    lrclib::fetch(self.0, artist, title, duration).await
  }
  async fn netease(&self, artist: &str, title: &str, duration: f64) -> Result<Option<Lyrics>> {
    netease::fetch(self.0, artist, title, duration).await
  }
  async fn genius(&self, artist: &str, title: &str) -> Result<Option<String>> {
    genius::genius_text(self.0, artist, title).await
  }
}

/// Что ищем: метаданные и ключ трека (`ref`) для правил и памяти промахов; пустой ключ — без них.
pub(crate) struct Query<'a> {
  pub meta: &'a Meta,
  pub key: &'a str,
}

/// Пары для lrclib и одна пара для NetEase / Genius.
#[derive(Debug, PartialEq)]
struct Plan {
  normal: Vec<Pair>,
  variants: Vec<Pair>,
  variants_first: bool,
  other: Pair,
}

/// Как есть → ядро названия → ключевые слова, без повторов.
fn attempts(artist: &str, title: &str) -> Vec<Pair> {
  let (keywords, core, _) = keyword_title(title);
  let mut out: Vec<Pair> = Vec::new();
  for t in [title.to_string(), core, keywords] {
    let pair = (artist.to_string(), t);
    if !pair.1.trim().is_empty() && !out.iter().any(|p| same_pair(p, &pair)) {
      out.push(pair);
    }
  }
  out
}

fn plan(q: &Query, rules: &Rules, misses: &VariantMisses, now: Instant) -> Plan {
  if let Some(p) = rules.pair(q.key) {
    return Plan {
      normal: attempts(&p.artist, &p.title),
      variants: Vec::new(),
      variants_first: false,
      other: (p.artist.clone(), p.title.clone()),
    };
  }
  let Meta { artist, title, .. } = q.meta;
  let normal = attempts(artist, title);
  let variants = if !q.key.is_empty() && misses.is_fresh(q.key, now) {
    Vec::new()
  } else {
    reupload_variants(artist, title, &rules.dash).into_iter().filter(|v| !normal.iter().any(|n| same_pair(n, v))).collect()
  };
  Plan { normal, variants, variants_first: rules.is_reuploader(artist), other: search_pair(artist, title, &rules.dash) }
}

/// Что lrclib уже дал: простой текст про запас и сбой сети.
#[derive(Default)]
struct Lrc {
  plain: Option<String>,
  failed: Option<anyhow::Error>,
}

impl Lrc {
  /// Синхронный текст по первой подходящей паре и сама пара. Сбой сети — `failed`, дальше не спрашиваем.
  async fn try_pairs<'p>(&mut self, src: &impl Source, pairs: &'p [Pair], duration: f64) -> Option<(Lyrics, &'p Pair)> {
    for pair in pairs {
      match src.lrclib(&pair.0, &pair.1, duration).await {
        Ok(found) => {
          if let Some(synced) = found.synced {
            let lines = parse_lrc(&synced, duration);
            if !lines.is_empty() {
              return Some((Lyrics { is_synced: true, source: "lrclib".into(), lines }, pair));
            }
          }
          if self.plain.is_none() {
            self.plain = found.plain;
          }
        }
        Err(e) => {
          log::warn!("[lyrics] lrclib: {e}");
          self.failed = Some(e);
          return None; // lrclib лежит — дальше спрашивать бесполезно
        }
      }
    }
    None
  }
}

/// Найти текст. `Ok(None)` — текста нигде нет; `Err` — сеть не ответила (не кэшировать как «нет»).
pub(crate) async fn search(src: &impl Source, q: Query<'_>, rules: &Rules, misses: &Mutex<VariantMisses>, now: Instant) -> Result<Option<Lyrics>> {
  if !q.key.is_empty() && rules.is_ignored(q.key) {
    return Ok(None);
  }
  let plan = plan(&q, rules, &misses.lock().unwrap(), now);
  let duration = q.meta.duration;
  let stages = if plan.variants_first { [(&plan.variants, true), (&plan.normal, false)] } else { [(&plan.normal, false), (&plan.variants, true)] };

  let mut lrc = Lrc::default();
  for (pairs, is_variant) in stages {
    if let Some((found, pair)) = lrc.try_pairs(src, pairs, duration).await {
      if is_variant {
        crate::crashlog::write("info", &format!("тексты: текст нашёлся по названию перезалива «{}» — «{}»", pair.0, pair.1));
      }
      return Ok(Some(found));
    }
    if lrc.failed.is_some() {
      break;
    }
    if is_variant && !pairs.is_empty() && !q.key.is_empty() {
      misses.lock().unwrap().remember(q.key, now);
    }
  }

  let (artist, title) = &plan.other;
  // lrclib синхронного не нашёл — NetEase (пословный YRC или построчный LRC); не ответил — дальше Genius
  match src.netease(&first_artist(artist), &clean_title(title), duration).await {
    Ok(Some(l)) => return Ok(Some(l)),
    Ok(None) => {}
    Err(e) => log::warn!("[lyrics] NetEase: {e}"),
  }

  match src.genius(artist, title).await {
    Ok(Some(text)) => {
      let lines = plain_lines(&genius::strip_sections(&text));
      if !lines.is_empty() {
        return Ok(Some(Lyrics { is_synced: false, source: "genius".into(), lines }));
      }
    }
    Ok(None) => {}
    Err(e) => {
      log::warn!("[lyrics] Genius: {e}");
      if lrc.failed.is_none() && lrc.plain.is_none() {
        lrc.failed = Some(e);
      }
    }
  }

  if let Some(p) = lrc.plain {
    let lines = plain_lines(&p);
    if !lines.is_empty() {
      return Ok(Some(Lyrics { is_synced: false, source: "lrclib".into(), lines }));
    }
  }
  match lrc.failed {
    Some(e) => Err(e),
    None => Ok(None),
  }
}

#[cfg(test)]
#[path = "search_tests.rs"]
mod tests;
