//! NetEase Cloud Music — запасной источник синхронного текста (решение владельца 2026-11-16):
//! спрашиваем, только если lrclib синхронного не нашёл; дальше — Genius. Главное — пословная
//! разметка YRC (`[начало,длит](начало_слова,длит,0)слово…`), её нет почти нигде; нет YRC — обычный
//! LRC построчно. Совпадение строгое: название, артист и длительность ±3 с — чужую песню не берём.

use super::{norm, parse_lrc, similarity, Line, Lyrics, Word};
use anyhow::Result;
use serde_json::Value;

const UA: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36";
const SEARCH: &str = "https://music.163.com/api/search/get";
const LYRIC: &str = "https://music.163.com/api/song/lyric/v1";

/// Строки-титры NetEase (автор слов, музыки, аранжировка…) — не текст песни.
fn is_credit(text: &str) -> bool {
  let t = text.trim();
  ["作词", "作曲", "编曲", "制作", "混音", "母带", "录音", "和声", "吉他", "贝斯", "鼓", "监制", "出品", "发行"]
    .iter()
    .any(|k| t.starts_with(k) && (t.contains(':') || t.contains('：')))
}

/// YRC → строки со словами. Строки-метаданные (`{"t":…}`) и титры пропускаются.
pub fn parse_yrc(text: &str) -> Vec<Line> {
  let mut out = Vec::new();
  for raw in text.lines() {
    let raw = raw.trim();
    if !raw.starts_with('[') {
      continue;
    }
    let Some(close) = raw.find(']') else { continue };
    let head: Vec<&str> = raw[1..close].split(',').collect();
    let (Some(start), Some(dur)) = (head.first().and_then(|v| v.parse::<f64>().ok()), head.get(1).and_then(|v| v.parse::<f64>().ok())) else {
      continue;
    };
    let mut words: Vec<Word> = Vec::new();
    let mut rest = &raw[close + 1..];
    while let Some(open) = rest.find('(') {
      let Some(end) = rest[open..].find(')') else { break };
      let tag: Vec<&str> = rest[open + 1..open + end].split(',').collect();
      let after = &rest[open + end + 1..];
      let next = after.find('(').unwrap_or(after.len());
      let chunk = &after[..next];
      if let (Some(ws), Some(wd)) = (tag.first().and_then(|v| v.parse::<f64>().ok()), tag.get(1).and_then(|v| v.parse::<f64>().ok())) {
        let w = chunk.trim();
        if !w.is_empty() {
          words.push(Word {
            time: ws / 1000.0,
            duration: wd / 1000.0,
            text: w.to_owned(),
            is_background: false,
            has_space_after: chunk.ends_with(' '),
          });
        }
      }
      rest = &after[next..];
    }
    let text: String = words.iter().map(|w| if w.has_space_after { format!("{} ", w.text) } else { w.text.clone() }).collect();
    let text = text.trim().to_owned();
    if text.is_empty() || is_credit(&text) {
      continue;
    }
    if let Some(last) = words.last_mut() {
      last.has_space_after = false;
    }
    out.push(Line {
      time: start / 1000.0,
      duration: dur / 1000.0,
      is_background: text.starts_with('(') && text.ends_with(')'),
      text,
      translation: None,
      agent: None,
      words: Some(words),
    });
  }
  out.sort_by(|a, b| a.time.partial_cmp(&b.time).unwrap_or(std::cmp::Ordering::Equal));
  out
}

/// Лучшая песня из выдачи поиска: название ≥ 0.75, хоть один артист ≥ 0.6, длительность ±3 с.
pub fn pick(songs: &[Value], artist: &str, title: &str, duration: f64) -> Option<u64> {
  let (na, nt) = (norm(artist), norm(title));
  songs
    .iter()
    .filter_map(|s| {
      let id = s["id"].as_u64()?;
      let name = norm(s["name"].as_str()?);
      let ms = s["duration"].as_f64().unwrap_or(0.0);
      if duration > 0.0 && ms > 0.0 && (ms / 1000.0 - duration).abs() > 3.0 {
        return None;
      }
      let ts = similarity(&name, &nt);
      let as_ = s["artists"]
        .as_array()
        .map(|a| a.iter().filter_map(|x| x["name"].as_str()).map(|n| similarity(&norm(n), &na)).fold(0.0, f64::max))
        .unwrap_or(0.0);
      (ts >= 0.75 && as_ >= 0.6).then_some((id, ts + as_))
    })
    .max_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal))
    .map(|x| x.0)
}

/// Найти синхронный текст на NetEase. `Ok(None)` — не нашли (или только титры).
pub async fn fetch(http: &reqwest::Client, artist: &str, title: &str, duration: f64) -> Result<Option<Lyrics>> {
  let q = format!("{artist} {title}");
  let v: Value = http
    .get(SEARCH)
    .query(&[("s", q.as_str()), ("type", "1"), ("limit", "10")])
    .header("Referer", "https://music.163.com/")
    .header("User-Agent", UA)
    .timeout(std::time::Duration::from_secs(8))
    .send()
    .await?
    .json()
    .await?;
  let songs = v["result"]["songs"].as_array().cloned().unwrap_or_default();
  let Some(id) = pick(&songs, artist, title, duration) else { return Ok(None) };
  let id = id.to_string();
  let l: Value = http
    .get(LYRIC)
    .query(&[("id", id.as_str()), ("lv", "0"), ("yv", "0"), ("tv", "0"), ("rv", "0"), ("kv", "0")])
    .header("Referer", "https://music.163.com/")
    .header("User-Agent", UA)
    .timeout(std::time::Duration::from_secs(8))
    .send()
    .await?
    .json()
    .await?;
  if let Some(yrc) = l["yrc"]["lyric"].as_str().filter(|s| !s.trim().is_empty()) {
    let lines = parse_yrc(yrc);
    if lines.len() >= 3 {
      return Ok(Some(Lyrics { is_synced: true, source: "netease".into(), lines }));
    }
  }
  if let Some(lrc) = l["lrc"]["lyric"].as_str().filter(|s| !s.trim().is_empty()) {
    let lines: Vec<Line> = parse_lrc(lrc, duration).into_iter().filter(|x| !is_credit(&x.text)).collect();
    // «纯音乐，请欣赏» и подобное — инструментал, текста нет
    if lines.iter().filter(|x| !x.text.is_empty()).count() >= 3 {
      return Ok(Some(Lyrics { is_synced: true, source: "netease".into(), lines }));
    }
  }
  Ok(None)
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn yrc_words_and_credits() {
    let yrc = "{\"t\":0,\"c\":[{\"tx\":\"作词: \"},{\"tx\":\"Someone\"}]}\n\
               [1000,1500](1000,500,0)Hello (1500,1000,0)world\n\
               [3000,900](3000,900,0)again";
    let l = parse_yrc(yrc);
    assert_eq!(l.len(), 2);
    assert_eq!(l[0].text, "Hello world");
    let w = l[0].words.as_ref().unwrap();
    assert_eq!((w[0].time, w[0].duration), (1.0, 0.5));
    assert!(w[0].has_space_after && !w[1].has_space_after);
    assert_eq!(l[1].time, 3.0);
  }

  #[test]
  fn pick_strict_match() {
    let songs: Vec<Value> = serde_json::from_str(
      r#"[{"id":1,"name":"Yellow","duration":266000,"artists":[{"name":"Coldplay"}]},
          {"id":2,"name":"Yellow (Live)","duration":300000,"artists":[{"name":"Coldplay"}]},
          {"id":3,"name":"Yellow","duration":266500,"artists":[{"name":"Someone Else"}]}]"#,
    )
    .unwrap();
    assert_eq!(pick(&songs, "Coldplay", "Yellow", 267.0), Some(1));
    assert_eq!(pick(&songs, "Coldplay", "Yellow", 200.0), None, "длительность не та — не берём");
  }

  #[tokio::test]
  #[ignore]
  async fn live_netease() {
    let http = reqwest::Client::new();
    let l = fetch(&http, "Coldplay", "Yellow", 266.0).await.unwrap();
    let l = l.expect("Yellow есть на NetEase");
    assert!(l.is_synced && l.lines.len() > 10);
    eprintln!("words: {}", l.lines[0].words.is_some());
  }
}
