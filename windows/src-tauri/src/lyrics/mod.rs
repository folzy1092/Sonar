//! Тексты песен на устройстве (SPEC §3.7б, docs/LYRICS.md): lrclib → упрощённый запрос →
//! NetEase (пословный YRC) → Genius. Порт `selfbot/code/lyrics.py` + Genius-часть `ai_lyrics.py`, те же шаги и имена
//! (`fetch_any`, `fetch`, `genius_text`, `genius_queries`). На выходе всегда `Lyrics` из §1.

pub mod genius;
pub mod lrclib;
pub mod netease;
pub mod rules;
mod search;
pub mod title_split;
pub mod translate;

use crate::providers::Track;
use anyhow::Result;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::sync::LazyLock;

/// «Текста нет» перепроверяется не чаще раза в 30 мин (как в selfbot).
pub const RECHECK_TTL_MS: i64 = 30 * 60 * 1000;
/// Последняя строка длится до конца трека, но не дольше 10 с.
const LAST_LINE_MAX: f64 = 10.0;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Lyrics {
  pub is_synced: bool,
  pub source: String,
  pub lines: Vec<Line>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Line {
  pub time: f64,
  pub duration: f64,
  pub text: String,
  #[serde(skip_serializing_if = "Option::is_none", default)]
  pub translation: Option<String>,
  #[serde(skip_serializing_if = "Option::is_none", default)]
  pub agent: Option<String>,
  pub is_background: bool,
  #[serde(skip_serializing_if = "Option::is_none", default)]
  pub words: Option<Vec<Word>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct Word {
  pub time: f64,
  pub duration: f64,
  pub text: String,
  pub is_background: bool,
  pub has_space_after: bool,
}

/// Что ищем: исполнитель, название, длительность в секундах.
#[derive(Debug, Clone)]
pub struct Meta {
  pub artist: String,
  pub title: String,
  pub duration: f64,
}

impl Meta {
  pub fn of(t: &Track) -> Self {
    Self { artist: t.artist.clone(), title: t.title.clone(), duration: t.duration_ms as f64 / 1000.0 }
  }
}

// ——— LRC ———

static TIME_TAG: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\[(\d+):(\d+(?:[.:]\d+)?)\]").unwrap());
static WORD_TAG: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"<(\d+):(\d+(?:[.:]\d+)?)>").unwrap());
static OFFSET_TAG: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)^\[offset:\s*([+-]?\d+)\s*\]").unwrap());

fn seconds(m: &str, s: &str) -> f64 {
  m.parse::<f64>().unwrap_or(0.0) * 60.0 + s.replace(':', ".").parse::<f64>().unwrap_or(0.0)
}

/// Строка целиком в скобках — бэк-вокал.
fn is_background(text: &str) -> bool {
  let t = text.trim();
  t.len() > 2 && t.starts_with('(') && t.ends_with(')')
}

/// Слова enhanced-LRC (`<mm:ss.xx>слово`). Нет тегов — None. Длительности слов считаются потом.
fn parse_words(raw: &str, shift: f64) -> (String, Option<Vec<Word>>) {
  let tags: Vec<_> = WORD_TAG.captures_iter(raw).collect();
  if tags.is_empty() {
    return (raw.trim().to_string(), None);
  }
  let mut words = Vec::new();
  for (i, c) in tags.iter().enumerate() {
    let m = c.get(0).unwrap();
    let end = tags.get(i + 1).map(|n| n.get(0).unwrap().start()).unwrap_or(raw.len());
    let chunk = &raw[m.end()..end];
    let text = chunk.trim();
    let time = (seconds(&c[1], &c[2]) - shift).max(0.0);
    if text.is_empty() {
      // пустой тег в конце строки — конец последнего слова
      if let Some(last) = words.last_mut() {
        let w: &mut Word = last;
        w.duration = (time - w.time).max(0.0);
      }
      continue;
    }
    words.push(Word {
      time,
      duration: -1.0,
      text: text.to_string(),
      is_background: is_background(text),
      has_space_after: chunk.ends_with(' ') || chunk.ends_with('\t'),
    });
  }
  let text = words.iter().map(|w| if w.has_space_after { format!("{} ", w.text) } else { w.text.clone() }).collect::<String>();
  let text = text.trim().to_string();
  if words.is_empty() { (text, None) } else { (text, Some(words)) }
}

/// LRC → строки по времени (LYRICS.md §1): несколько таймкодов на строку, `[offset:±ms]`,
/// пустые строки — паузы, строки в `( )` — бэк-вокал, слова из enhanced-LRC.
/// `track_len` — длительность трека в секундах (для последней строки), 0 — неизвестна.
pub fn parse_lrc(text: &str, track_len: f64) -> Vec<Line> {
  let mut shift = 0.0;
  let mut lines: Vec<Line> = Vec::new();
  for raw in text.lines() {
    let raw = raw.trim_end_matches('\r');
    if let Some(c) = OFFSET_TAG.captures(raw.trim()) {
      // положительный offset в LRC — текст раньше
      shift = c[1].parse::<f64>().unwrap_or(0.0) / 1000.0;
      continue;
    }
    let tags: Vec<_> = TIME_TAG.captures_iter(raw).collect();
    // теги должны идти подряд с начала строки
    let mut end = 0;
    let mut times = Vec::new();
    for c in &tags {
      let m = c.get(0).unwrap();
      if raw[end..m.start()].trim().is_empty() {
        end = m.end();
        times.push(seconds(&c[1], &c[2]));
      } else {
        break;
      }
    }
    if times.is_empty() {
      continue;
    }
    let (body, words) = parse_words(&raw[end..], shift);
    for t in times {
      let time = (t - shift).max(0.0);
      // у повтора строки (несколько таймкодов) слова сдвигаются вместе с ней
      let words = words.as_ref().map(|ws| {
        let base = ws.first().map(|w| w.time).unwrap_or(time);
        ws.iter().map(|w| Word { time: time + (w.time - base).max(0.0), ..w.clone() }).collect::<Vec<_>>()
      });
      lines.push(Line {
        time,
        duration: 0.0,
        text: body.clone(),
        translation: None,
        agent: None,
        is_background: is_background(&body),
        words,
      });
    }
  }
  lines.sort_by(|a, b| a.time.total_cmp(&b.time));
  // подряд идущие пустые строки — одна пауза
  lines.dedup_by(|b, a| a.text.is_empty() && b.text.is_empty());
  fill_durations(&mut lines, track_len);
  // пустые строки в начале не нужны: до первой строки и так «•••»
  while lines.first().is_some_and(|l| l.text.is_empty()) {
    lines.remove(0);
  }
  lines
}

fn fill_durations(lines: &mut [Line], track_len: f64) {
  let n = lines.len();
  for i in 0..n {
    let end = if i + 1 < n {
      lines[i + 1].time
    } else if track_len > lines[i].time {
      (lines[i].time + LAST_LINE_MAX).min(track_len)
    } else {
      lines[i].time + LAST_LINE_MAX
    };
    let line = &mut lines[i];
    line.duration = (end - line.time).max(0.0);
    let line_end = end;
    if let Some(words) = line.words.as_mut() {
      let m = words.len();
      for j in 0..m {
        if words[j].duration < 0.0 {
          let next = if j + 1 < m { words[j + 1].time } else { line_end };
          words[j].duration = (next - words[j].time).max(0.0);
        }
      }
    }
  }
}

/// Обычный текст (plain из lrclib, Genius) — строки без таймкодов.
pub fn plain_lines(text: &str) -> Vec<Line> {
  let mut out: Vec<Line> = Vec::new();
  for raw in text.lines() {
    let t = raw.trim();
    if t.is_empty() && out.last().is_none_or(|l| l.text.is_empty()) {
      continue;
    }
    out.push(Line { time: 0.0, duration: 0.0, text: t.to_string(), translation: None, agent: None, is_background: is_background(t), words: None });
  }
  while out.last().is_some_and(|l| l.text.is_empty()) {
    out.pop();
  }
  out
}

// ——— названия и исполнители ———

/// «(prod. …)», «[Official Video]», «feat. …» мешают найти трек.
static TITLE_NOISE: LazyLock<Regex> = LazyLock::new(|| {
  Regex::new(r"(?i)\s*[(\[][^)\]]*(?:prod|feat|ft\.|official|video|audio|lyric|remaster)[^)\]]*[)\]]|\s+(?:feat|ft)\.?\s.*$").unwrap()
});
/// «A, B», «A & B», «A x B», «A feat. B», «A и B» — несколько артистов.
static ARTIST_SPLIT: LazyLock<Regex> =
  LazyLock::new(|| Regex::new(r"(?i)\s*,\s*|\s+(?:&|feat\.?|ft\.?|x\+?|\+|×|и|and|with|w/)\s+").unwrap());
static ANY_BRACKETS: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\s*[(\[][^)\]]*[)\]]").unwrap());
static FEAT_CREDIT: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)\b(?:feat|ft)\b\.?\s+([^()\[\],&+]+)").unwrap());
static FEAT_SPLIT: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)\s+(?:\+|&|w/|feat\.?|ft\.?)\s*").unwrap());
static FEAT_HEAD: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)^(?:\+|&|w/|feat\.?|ft\.?)\s*(\S+)\s+").unwrap());
static EMOTICON: LazyLock<Regex> =
  LazyLock::new(|| Regex::new(r"^(?:[:;=8][-'^]?[()\[\]DdPpOo3|/*]+|<3+|x[Dd]+|\^[_.-]?\^|T_T)$").unwrap());

pub fn clean_title(title: &str) -> String {
  TITLE_NOISE.replace_all(title, "").trim().to_string()
}

pub fn first_artist(artist: &str) -> String {
  ARTIST_SPLIT.split(artist).next().unwrap_or("").trim().to_string()
}

/// «Big Baby Tape, Kizaru» → [«Big Baby Tape, Kizaru», «Big Baby Tape»]: в lrclib чаще только первый.
pub fn artist_variants(artist: &str) -> Vec<String> {
  let mut out = vec![artist.trim().to_string()];
  let first = first_artist(artist);
  if !first.is_empty() && first != out[0] {
    out.push(first);
  }
  out.retain(|s| !s.is_empty());
  out
}

fn is_pictograph(c: char) -> bool {
  let u = c as u32;
  (0x1F000..=0x1FAFF).contains(&u) || (0x2190..=0x2BFF).contains(&u) || (0x2600..=0x27BF).contains(&u) || u == 0xFE0F || u == 0x200D
}

/// Название без мусора SoundCloud: (ключевые слова, ядро без фитов, фиты).
/// «+ elox1m PAGER =( #2016» → («elox1m PAGER», «PAGER», [«elox1m»]).
pub fn keyword_title(title: &str) -> (String, String, Vec<String>) {
  let mut feats: Vec<String> =
    FEAT_CREDIT.captures_iter(title).map(|c| c[1].trim().to_string()).filter(|s| !s.is_empty()).collect();
  let text: String = ANY_BRACKETS.replace_all(title, " ").chars().map(|c| if is_pictograph(c) { ' ' } else { c }).collect();
  let text = TITLE_NOISE.replace_all(&text, " ").to_string();
  let words: Vec<&str> = text
    .split_whitespace()
    .filter(|w| !w.starts_with('#') && !w.starts_with('@') && !EMOTICON.is_match(w))
    .filter(|w| w.chars().any(|c| c.is_alphanumeric()) || matches!(*w, "+" | "&" | "w/"))
    .collect();
  let text = words.join(" ");
  let mut core = text.clone();
  if let Some(c) = FEAT_HEAD.captures(&text) {
    feats.push(c[1].to_string());
    core = text[c.get(0).unwrap().end()..].to_string();
  }
  let parts: Vec<&str> = FEAT_SPLIT.split(&core).collect();
  if parts.len() > 1 && !parts[0].trim().is_empty() {
    feats.extend(parts[1..].iter().map(|p| p.trim().to_string()).filter(|p| !p.is_empty()));
    core = parts[0].to_string();
  }
  let core = core.trim_matches(|c: char| c == '+' || c == '&' || c.is_whitespace()).to_string();
  let keywords = words.iter().filter(|w| !matches!(**w, "+" | "&" | "w/")).copied().collect::<Vec<_>>().join(" ");
  (keywords, core, feats)
}

/// Для сравнения: нижний регистр, без знаков, ё → е.
pub fn norm(s: &str) -> String {
  s.to_lowercase().replace('ё', "е").chars().filter(|c| c.is_alphanumeric()).collect()
}

/// Похожесть строк 0..1 (как difflib.ratio: 2·совпадения / сумма длин, через LCS).
pub fn similarity(a: &str, b: &str) -> f64 {
  let a: Vec<char> = a.chars().collect();
  let b: Vec<char> = b.chars().collect();
  if a.is_empty() && b.is_empty() {
    return 1.0;
  }
  let mut prev = vec![0usize; b.len() + 1];
  for x in &a {
    let mut cur = vec![0usize; b.len() + 1];
    for (j, y) in b.iter().enumerate() {
      cur[j + 1] = if x == y { prev[j] + 1 } else { prev[j + 1].max(cur[j]) };
    }
    prev = cur;
  }
  2.0 * prev[b.len()] as f64 / (a.len() + b.len()) as f64
}

// ——— поиск ———

/// Найти текст без правил на трек (ref неизвестен) — для живой проверки; порядок — `search.rs`.
/// `Ok(None)` — текста нигде нет; `Err` — сеть не ответила (не кэшировать как «нет»).
#[cfg(test)]
pub async fn fetch_any(http: &reqwest::Client, meta: &Meta) -> Result<Option<Lyrics>> {
  let rules = rules::current();
  search::search(&search::Net(http), search::Query { meta, key: "" }, &rules, &rules::MISSES, std::time::Instant::now()).await
}

/// Найти текст трека: правила из `updates/lyrics-rules.json` (ручная пара, игнор, перезаливщики) и память
/// промахов по вариантам перезалива. `recheck` — ручная перепроверка: промах забывается.
pub async fn fetch_track(http: &reqwest::Client, track: &Track, recheck: bool) -> Result<Option<Lyrics>> {
  rules::refresh_in_background(http);
  if recheck {
    rules::MISSES.lock().unwrap().forget(&track.ref_);
  }
  let rules = rules::current();
  let meta = Meta::of(track);
  let q = search::Query { meta: &meta, key: &track.ref_ };
  search::search(&search::Net(http), q, &rules, &rules::MISSES, std::time::Instant::now()).await
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn lrc_lines_durations_and_pauses() {
    let lrc = "[ar:x]\n[00:01.00]Раз\n[00:03.50]Два\n[00:05.00]\n[00:06.00]\n[00:08.00](эхо)\n";
    let l = parse_lrc(lrc, 12.0);
    assert_eq!(l.len(), 4);
    assert_eq!(l[0].text, "Раз");
    assert!((l[0].duration - 2.5).abs() < 1e-9);
    assert_eq!(l[2].text, "");
    assert!((l[2].duration - 3.0).abs() < 1e-9);
    assert!(l[3].is_background);
    assert!((l[3].duration - 4.0).abs() < 1e-9); // до конца трека
  }

  #[test]
  fn lrc_multiple_tags_and_offset() {
    let lrc = "[offset:+500]\n[00:10.00][00:02.00]Припев\n[00:05.00]Куплет";
    let l = parse_lrc(lrc, 0.0);
    let times: Vec<f64> = l.iter().map(|x| x.time).collect();
    assert_eq!(times, vec![1.5, 4.5, 9.5]);
    assert!((l[2].duration - 10.0).abs() < 1e-9); // трек неизвестен — 10 с
  }

  #[test]
  fn lrc_enhanced_words() {
    let lrc = "[00:01.00]<00:01.00>Hello <00:01.50>world<00:02.40>\n[00:03.00]<00:03.00>Next";
    let l = parse_lrc(lrc, 5.0);
    assert_eq!(l[0].text, "Hello world");
    let w = l[0].words.as_ref().unwrap();
    assert_eq!(w.len(), 2);
    assert!(w[0].has_space_after);
    assert!((w[0].duration - 0.5).abs() < 1e-9);
    assert!((w[1].duration - 0.9).abs() < 1e-9);
    let w2 = l[1].words.as_ref().unwrap();
    assert!((w2[0].duration - 2.0).abs() < 1e-9);
  }

  #[test]
  fn plain_text_collapses_blank_lines() {
    let l = plain_lines("\n\nОдин\n\n\nДва\n\n");
    let t: Vec<&str> = l.iter().map(|x| x.text.as_str()).collect();
    assert_eq!(t, vec!["Один", "", "Два"]);
  }

  #[test]
  fn titles_and_artists() {
    assert_eq!(clean_title("gates (prod. nepuhz)"), "gates");
    assert_eq!(clean_title("Song feat. X"), "Song");
    assert_eq!(artist_variants("Big Baby Tape, Kizaru"), vec!["Big Baby Tape, Kizaru", "Big Baby Tape"]);
    assert_eq!(artist_variants("Solo"), vec!["Solo"]);
    let (kw, core, feats) = keyword_title("+ elox1m PAGER =( #2016");
    assert_eq!(kw, "elox1m PAGER");
    assert_eq!(core, "PAGER");
    assert_eq!(feats, vec!["elox1m"]);
  }

  #[test]
  fn similarity_is_sane() {
    assert!((similarity("abc", "abc") - 1.0).abs() < 1e-9);
    assert!(similarity("gates", "gatesaltered") < 0.8);
    assert!(similarity(&norm("Дежавю!"), &norm("дежавю")) > 0.99);
  }
}

#[cfg(test)]
mod live {
  use super::*;

  #[tokio::test]
  #[ignore = "живые запросы к lrclib и Genius"]
  async fn live_fetch_any() {
    let http = reqwest::Client::new();
    let l = fetch_any(&http, &Meta { artist: "Coldplay".into(), title: "Yellow".into(), duration: 269.0 }).await.unwrap().unwrap();
    assert!(l.is_synced && l.lines.len() > 10);
    let g = genius::genius_text(&http, "Coldplay", "Yellow").await;
    println!("genius: {:?}", g.as_ref().map(|t| t.as_ref().map(|t| t.chars().take(120).collect::<String>())));
  }
}
