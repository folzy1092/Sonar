//! Genius — обычный текст без таймкодов. Порт `_genius_text` / `_genius_queries` /
//! `_genius_pick` из selfbot: песня берётся, только если её исполнитель совпадает с нашим
//! (или с фитом из названия), а название похоже (≥ 0.8).

use super::{first_artist, keyword_title, norm, similarity};
use anyhow::{bail, Result};
use regex::Regex;
use serde_json::Value;
use std::collections::HashSet;
use std::sync::LazyLock;
use std::time::Duration;

const USER_AGENT: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";
const MIN_TITLE: f64 = 0.8;
const PER_PAGE: usize = 5;

static SECTION: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^\[[^\]]*\]$").unwrap());
static ALL_BRACKETS: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\s*[(\[][^)\]]*[)\]]|\s+(?i:feat|ft)\.?\s.*$").unwrap());
static FEAT_TAIL: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)\s+(?:\+|&|x|w/|with)\s+.*$").unwrap());
static ARTIST_SPLIT: LazyLock<Regex> =
  LazyLock::new(|| Regex::new(r"(?i)\s*(?:[,&+()]|\b(?:feat|ft)\b\.?|\b(?:x|and|with|и)\b)\s*").unwrap());

fn artist_names(text: &str) -> HashSet<String> {
  ARTIST_SPLIT.split(text).map(norm).filter(|s| !s.is_empty()).collect()
}

/// Запросы по порядку: как есть, по ядру, по ключевым словам, только название, только исполнитель.
pub fn genius_queries(first: &str, clean: &str, keywords: &str, core: &str) -> Vec<String> {
  let mut qs = vec![format!("{first} {clean}"), format!("{first} {core}"), format!("{first} {keywords}")];
  if core.chars().filter(|c| c.is_alphabetic()).count() >= 3 {
    qs.push(core.to_string());
  }
  qs.push(first.to_string());
  let mut seen = HashSet::new();
  qs.into_iter()
    .map(|q| q.split_whitespace().collect::<Vec<_>>().join(" "))
    .filter(|q| !q.is_empty() && seen.insert(q.to_lowercase()))
    .collect()
}

/// Лучшая песня из выдачи: исполнитель из `allowed`, название похоже на один из вариантов.
fn pick(hits: &[Value], variants: &[String], allowed: &HashSet<String>) -> Option<String> {
  let mut best: Option<(String, f64)> = None;
  for hit in hits {
    if hit["type"] != "song" {
      continue;
    }
    let song = &hit["result"];
    let Some(url) = song["url"].as_str() else { continue };
    let mut names = artist_names(song["artist_names"].as_str().unwrap_or(""));
    names.extend(artist_names(song["primary_artist"]["name"].as_str().unwrap_or("")));
    if names.is_disjoint(allowed) {
      continue; // чужой исполнитель — не берём, даже если название то же
    }
    let found = norm(&ALL_BRACKETS.replace_all(song["title"].as_str().unwrap_or(""), ""));
    let score = variants.iter().map(|v| similarity(&norm(v), &found)).fold(0.0, f64::max);
    if best.as_ref().is_none_or(|b| score > b.1) {
      best = Some((url.to_string(), score));
    }
  }
  best.filter(|b| b.1 >= MIN_TITLE).map(|b| b.0)
}

/// Ответ Genius: тело или ошибка с понятной причиной.
fn check(status: u16, body: String, cf_challenge: bool) -> Result<String> {
  if (200..300).contains(&status) {
    return Ok(body);
  }
  if cf_challenge || body.contains("challenge-platform") {
    bail!("Genius: Cloudflare требует проверку «я не робот»");
  }
  bail!("Genius: HTTP {status}")
}

/// GET к Genius. Cloudflare у Genius отвечает проверкой «я не робот» на TLS-отпечаток Rust-клиентов
/// (и rustls, и schannel через reqwest), а системный `curl.exe` Windows 10+ пропускает
/// (проверено 2026-11-14). Поэтому сначала curl.exe скрытым процессом, reqwest — запасной путь.
async fn get(http: &reqwest::Client, url: &str, query: &[(&str, String)]) -> Result<String> {
  let full = reqwest::Url::parse_with_params(url, query)?.to_string();
  #[cfg(windows)]
  {
    let u = full.clone();
    let out = tokio::task::spawn_blocking(move || {
      use std::os::windows::process::CommandExt;
      const CREATE_NO_WINDOW: u32 = 0x0800_0000;
      std::process::Command::new(r"C:\Windows\System32\curl.exe")
        .args(["-s", "-L", "--max-time", "15", "-A", USER_AGENT, "-w", "\n%{http_code}", &u])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
    })
    .await?;
    if let Ok(o) = out {
      let text = String::from_utf8_lossy(&o.stdout).into_owned();
      if let Some((body, code)) = text.rsplit_once('\n') {
        if let Ok(code) = code.trim().parse::<u16>() {
          if code != 0 {
            return check(code, body.to_string(), false);
          }
        }
      }
    }
  }
  let r = http.get(&full).header("User-Agent", USER_AGENT).timeout(Duration::from_secs(12)).send().await?;
  let status = r.status().as_u16();
  let cf = r.headers().get("cf-mitigated").is_some_and(|v| v == "challenge");
  check(status, r.text().await?, cf)
}

/// Сырой текст песни с Genius (строки через `\n`) или None.
pub async fn genius_text(http: &reqwest::Client, artist: &str, title: &str) -> Result<Option<String>> {
  let clean = ALL_BRACKETS.replace_all(title, "").trim().to_string();
  let clean = if clean.is_empty() { title.to_string() } else { clean };
  let first = first_artist(artist);
  let (keywords, core, feats) = keyword_title(title);
  let mut allowed: HashSet<String> = feats.iter().map(|f| norm(f)).collect();
  allowed.insert(norm(&first));
  allowed.remove("");
  if allowed.is_empty() {
    return Ok(None);
  }
  let mut variants: Vec<String> = Vec::new();
  for v in [clean.clone(), FEAT_TAIL.replace(&clean, "").to_string(), keywords.clone(), core.clone()] {
    if !v.is_empty() && !variants.contains(&v) {
      variants.push(v);
    }
  }

  let mut url = None;
  for (i, q) in genius_queries(&first, &clean, &keywords, &core).into_iter().enumerate() {
    let mut hits: Vec<Value> = Vec::new();
    let pages = if i == 0 { 1 } else { 2 };
    for page in 1..=pages {
      let r = match get(
        http,
        "https://genius.com/api/search/multi",
        &[("q", q.clone()), ("per_page", PER_PAGE.to_string()), ("page", page.to_string())],
      )
      .await
      {
        Ok(body) => body,
        Err(e) if e.to_string().contains("HTTP 422") => break, // запрос не понравился — следующий
        Err(e) => return Err(e),
      };
      let json: Value = serde_json::from_str(&r)?;
      let found: Vec<Value> = json["response"]["sections"]
        .as_array()
        .into_iter()
        .flatten()
        .flat_map(|s| s["hits"].as_array().cloned().unwrap_or_default())
        .collect();
      let n = found.len();
      hits.extend(found);
      if n < PER_PAGE {
        break;
      }
    }
    url = pick(&hits, &variants, &allowed);
    if url.is_some() {
      break;
    }
  }
  let Some(url) = url else { return Ok(None) };
  let html = get(http, &url, &[]).await?;
  let text = lyrics_from_html(&html);
  Ok((!text.trim().is_empty()).then_some(text))
}

/// Заголовки частей («[Припев]», «[Куплет 1: …]») → пустая строка между куплетами.
pub fn strip_sections(text: &str) -> String {
  text.lines().map(|l| if SECTION.is_match(l.trim()) { "" } else { l }).collect::<Vec<_>>().join("\n")
}

fn unescape(s: &str) -> String {
  if !s.contains('&') {
    return s.to_string();
  }
  let mut out = String::with_capacity(s.len());
  let mut rest = s;
  while let Some(i) = rest.find('&') {
    out.push_str(&rest[..i]);
    rest = &rest[i..];
    let Some(end) = rest[..rest.len().min(12)].find(';') else {
      out.push('&');
      rest = &rest[1..];
      continue;
    };
    let ent = &rest[1..end];
    let ch = match ent {
      "amp" => Some('&'),
      "lt" => Some('<'),
      "gt" => Some('>'),
      "quot" => Some('"'),
      "apos" => Some('\''),
      "nbsp" => Some(' '),
      _ if ent.starts_with("#x") || ent.starts_with("#X") => u32::from_str_radix(&ent[2..], 16).ok().and_then(char::from_u32),
      _ if ent.starts_with('#') => ent[1..].parse().ok().and_then(char::from_u32),
      _ => None,
    };
    match ch {
      Some(c) => {
        out.push(c);
        rest = &rest[end + 1..];
      }
      None => {
        out.push('&');
        rest = &rest[1..];
      }
    }
  }
  out.push_str(rest);
  out
}

/// Текст из блоков `data-lyrics-container="true"`; вставки `data-exclude-from-selection` пропускаются.
pub fn lyrics_from_html(html: &str) -> String {
  let mut parts = String::new();
  let (mut depth, mut skip) = (0usize, 0usize);
  let mut rest = html;
  while let Some(lt) = rest.find('<') {
    if depth > 0 && skip == 0 {
      parts.push_str(&unescape(&rest[..lt]));
    }
    rest = &rest[lt..];
    let Some(gt) = rest.find('>') else { break };
    let tag = &rest[1..gt];
    rest = &rest[gt + 1..];
    let closing = tag.starts_with('/');
    let name: String = tag.trim_start_matches('/').chars().take_while(|c| c.is_ascii_alphanumeric()).collect::<String>().to_lowercase();
    if depth > 0 {
      match (name.as_str(), closing) {
        ("div", false) => {
          depth += 1;
          if skip > 0 || tag.contains(r#"data-exclude-from-selection="true""#) {
            skip += 1;
          }
        }
        ("div", true) => {
          skip = skip.saturating_sub(1);
          depth -= 1;
        }
        ("br", _) if skip == 0 => parts.push('\n'),
        _ => {}
      }
    } else if name == "div" && !closing && tag.contains(r#"data-lyrics-container="true""#) {
      depth = 1;
      parts.push('\n');
    }
  }
  parts
}

#[cfg(test)]
mod tests {
  use super::*;
  use serde_json::json;

  #[test]
  fn html_parsing_skips_excluded() {
    let html = r##"<html><div data-lyrics-container="true"><div data-exclude-from-selection="true">12 Contributors<div>x</div></div>[Припев]<br/>Раз &amp; два<br><a href="#">Три</a></div><script>a<b</script></html>"##;
    let t = lyrics_from_html(html);
    assert_eq!(t, "\n[Припев]\nРаз & два\nТри");
    assert_eq!(strip_sections(&t), "\n\nРаз & два\nТри");
  }

  #[test]
  fn unescape_entities() {
    assert_eq!(unescape("a&#x27;b &#39; &quot;q&quot; & x"), "a'b ' \"q\" & x");
  }

  #[test]
  fn pick_requires_artist() {
    let hits = vec![
      json!({"type":"song","result":{"url":"u1","title":"Дежавю","artist_names":"Другой","primary_artist":{"name":"Другой"}}}),
      json!({"type":"song","result":{"url":"u2","title":"Дежавю (Remix)","artist_names":"Кизару & X","primary_artist":{"name":"Кизару"}}}),
    ];
    let allowed: HashSet<String> = [norm("Кизару")].into();
    assert_eq!(pick(&hits, &["Дежавю".into()], &allowed).as_deref(), Some("u2"));
  }

  #[test]
  fn queries_are_unique() {
    let q = genius_queries("A", "Song", "Song", "Song");
    assert_eq!(q, vec!["A Song", "Song", "A"]);
  }
}
