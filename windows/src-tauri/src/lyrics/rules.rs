//! Правила поиска текста (docs/POLISH_PROMPT.md п. 7, docs/TITLE_SPLIT.md): словарь «артист-трек»,
//! перезаливщики, ручные пары на трек и игнор. До сервера — файл `updates/lyrics-rules.json` из репо:
//! вшит в сборку и перечитывается с GitHub раз в сутки (не вышло — через час). С сервером — `GET /lyrics/rules`.
//!
//! Здесь же — память промахов по вариантам перезалива (`VariantMisses`): не нашлось ни по одному —
//! `VARIANT_RECHECK` lrclib не спрашиваем снова; сетевой сбой промахом не считается.

use super::norm;
use super::title_split::{DashArtists, Pair};
use serde::Deserialize;
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, LazyLock, Mutex, RwLock};
use std::time::{Duration, Instant};

const REMOTE: &str = "https://raw.githubusercontent.com/folzy1092/Sonar/main/updates/lyrics-rules.json";
const BUNDLED: &str = include_str!("../../../../updates/lyrics-rules.json");
/// Перечитывать файл правил раз в сутки…
const REFRESH_EVERY: Duration = Duration::from_secs(24 * 60 * 60);
/// …а не вышло — через час.
const RETRY_AFTER: Duration = Duration::from_secs(60 * 60);
const FETCH_TIMEOUT: Duration = Duration::from_secs(10);
/// Промах по вариантам перезалива помнится столько.
pub const VARIANT_RECHECK: Duration = Duration::from_secs(6 * 60 * 60);
/// Больше записей в файле не берём — защита от битого файла.
const MAX_ENTRIES: usize = 5000;

/// Ручная пара на трек: искать текст по ней вместо всех шагов.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct ManualPair {
  pub artist: String,
  pub title: String,
  /// Показывать трек под этой парой (для будущего показа перезаливов).
  #[serde(default)]
  pub display: bool,
}

/// Содержимое `lyrics-rules.json`; незнакомые поля (`about`) — мимо.
#[derive(Debug, Clone, Default, Deserialize)]
struct File {
  /// Нет поля — словарь по умолчанию; пустой список — словаря нет.
  #[serde(default)]
  dash_artists: Option<Vec<String>>,
  #[serde(default)]
  reuploaders: Vec<String>,
  #[serde(default)]
  pairs: HashMap<String, ManualPair>,
  #[serde(default)]
  ignore: Vec<String>,
}

/// Готовые к поиску правила.
#[derive(Debug, Clone, Default)]
pub struct Rules {
  pub dash: DashArtists,
  reuploaders: HashSet<String>,
  pairs: HashMap<String, ManualPair>,
  ignore: HashSet<String>,
}

impl Rules {
  /// Разобрать файл правил; битый или слишком большой — `None`.
  pub fn parse(json: &str) -> Option<Self> {
    let f: File = serde_json::from_str(json).ok()?;
    let sizes = [f.dash_artists.as_ref().map_or(0, Vec::len), f.reuploaders.len(), f.pairs.len(), f.ignore.len()];
    if sizes.iter().any(|n| *n > MAX_ENTRIES) {
      return None;
    }
    let pairs = f
      .pairs
      .into_iter()
      .filter(|(r, p)| !r.trim().is_empty() && !p.artist.trim().is_empty() && !p.title.trim().is_empty())
      .map(|(r, p)| (r.trim().to_string(), p))
      .collect();
    Some(Self {
      dash: DashArtists::from_loaded(f.dash_artists),
      reuploaders: f.reuploaders.iter().map(|n| norm(n)).filter(|n| !n.is_empty()).collect(),
      pairs,
      ignore: f.ignore.iter().map(|r| r.trim().to_string()).filter(|r| !r.is_empty()).collect(),
    })
  }

  /// Вшитые в сборку правила.
  pub fn bundled() -> Self {
    Self::parse(BUNDLED).unwrap_or_default()
  }

  /// Залившего этого трека нет смысла считать артистом — разбор «артист - трек» идёт первым.
  pub fn is_reuploader(&self, artist: &str) -> bool {
    let n = norm(artist);
    !n.is_empty() && self.reuploaders.contains(&n)
  }

  pub fn pair(&self, track_ref: &str) -> Option<&ManualPair> {
    self.pairs.get(track_ref)
  }

  /// Текста у трека точно нет — не искать.
  pub fn is_ignored(&self, track_ref: &str) -> bool {
    self.ignore.contains(track_ref)
  }
}

struct Store {
  rules: RwLock<Arc<Rules>>,
  /// Когда перечитывать файл с GitHub; `None` — ещё ни разу.
  next_check: Mutex<Option<Instant>>,
}

static STORE: LazyLock<Store> =
  LazyLock::new(|| Store { rules: RwLock::new(Arc::new(Rules::bundled())), next_check: Mutex::new(None) });

/// Правила сейчас.
pub fn current() -> Arc<Rules> {
  STORE.rules.read().unwrap().clone()
}

/// Перечитать файл правил, если пора (раз в сутки, после сбоя — через час). Ждать не надо: в фоне.
pub fn refresh_in_background(http: &reqwest::Client) {
  if crate::offline::is_on() {
    return;
  }
  {
    let mut next = STORE.next_check.lock().unwrap();
    let now = Instant::now();
    if next.is_some_and(|at| now < at) {
      return;
    }
    // пока идёт запрос, второй не начинаем
    *next = Some(now + RETRY_AFTER);
  }
  let http = http.clone();
  tauri::async_runtime::spawn(async move {
    let ok = match fetch(&http).await {
      Ok(rules) => {
        *STORE.rules.write().unwrap() = Arc::new(rules);
        true
      }
      Err(e) => {
        crate::crashlog::write("warn", &format!("тексты: файл правил недоступен — {e}"));
        false
      }
    };
    let wait = if ok { REFRESH_EVERY } else { RETRY_AFTER };
    *STORE.next_check.lock().unwrap() = Some(Instant::now() + wait);
  });
}

async fn fetch(http: &reqwest::Client) -> anyhow::Result<Rules> {
  let r = http.get(REMOTE).timeout(FETCH_TIMEOUT).send().await?;
  let status = r.status();
  anyhow::ensure!(status.is_success(), "HTTP {status}");
  let text = r.text().await?;
  Rules::parse(&text).ok_or_else(|| anyhow::anyhow!("файл не разобрать"))
}

/// Промахи по вариантам перезалива: ключ трека → до какого момента не пробовать снова.
#[derive(Debug, Default)]
pub struct VariantMisses {
  until: HashMap<String, Instant>,
}

impl VariantMisses {
  /// Промах ещё помнится.
  pub fn is_fresh(&self, key: &str, now: Instant) -> bool {
    self.until.get(key).is_some_and(|at| now < *at)
  }

  pub fn remember(&mut self, key: &str, now: Instant) {
    self.until.retain(|_, at| now < *at);
    self.until.insert(key.to_string(), now + VARIANT_RECHECK);
  }

  /// Ручная перепроверка трека — пробовать варианты снова.
  pub fn forget(&mut self, key: &str) {
    self.until.remove(key);
  }
}

/// Промахи этого запуска Sonar.
pub static MISSES: LazyLock<Mutex<VariantMisses>> = LazyLock::new(Mutex::default);

/// Пара без повторов (без учёта регистра).
pub fn same_pair(a: &Pair, b: &Pair) -> bool {
  norm(&a.0) == norm(&b.0) && norm(&a.1) == norm(&b.1)
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn bundled_file_parses() {
    let r = Rules::parse(BUNDLED).expect("updates/lyrics-rules.json разбирается");
    assert!(r.dash.names().iter().any(|n| n == "cowboyclicker"));
  }

  #[test]
  fn parse_rules() {
    let r = Rules::parse(
      r#"{"dash_artists":["jay-z"],"reuploaders":["Kleyy"],"ignore":["sc:1"],
          "pairs":{"sc:2":{"artist":"cowboyclicker","title":"doesnt matter","display":true},"sc:3":{"artist":"","title":"x"}}}"#,
    )
    .unwrap();
    assert!(r.is_reuploader("kleyy"));
    assert!(!r.is_reuploader("Bones"));
    assert!(r.is_ignored("sc:1"));
    assert_eq!(r.pair("sc:2").map(|p| p.title.as_str()), Some("doesnt matter"));
    assert!(r.pair("sc:3").is_none(), "пустой артист — пары нет");
    assert!(Rules::parse("not json").is_none());
    assert!(Rules::parse("{}").is_some());
  }

  #[test]
  fn misses_expire_and_forget() {
    let mut m = VariantMisses::default();
    let t0 = Instant::now();
    assert!(!m.is_fresh("sc:1", t0));
    m.remember("sc:1", t0);
    assert!(m.is_fresh("sc:1", t0 + Duration::from_secs(60)));
    assert!(!m.is_fresh("sc:1", t0 + VARIANT_RECHECK));
    m.remember("sc:1", t0);
    m.forget("sc:1");
    assert!(!m.is_fresh("sc:1", t0));
  }
}
