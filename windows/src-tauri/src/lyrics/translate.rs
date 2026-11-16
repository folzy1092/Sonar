//! Перевод текста песни (меню текста → «Перевести», решение владельца 2026-11-17). Без сервера и ключей:
//! открытая точка Google Translate расширения Chrome (`clients5`, `dict-chrome-ex`) — каждая строка
//! отдельным `q` одним запросом, ответ построчно. Запасной путь — `translate.googleapis.com` (`gtx`,
//! строки через перевод строки): его Google порой отдаёт капчей. Пустые строки (паузы) не отправляем.

use anyhow::{bail, Result};
use serde::Serialize;
use serde_json::Value;

const URL: &str = "https://clients5.google.com/translate_a/t";
const URL_GTX: &str = "https://translate.googleapis.com/translate_a/single";

#[derive(Serialize)]
pub struct Translation {
  /// Перевод каждой строки (той же длины, что и вход; пауза — пустая строка).
  pub lines: Vec<String>,
  /// Язык оригинала, как его определил Google (`en`, `ja`…).
  pub source: String,
}

pub async fn translate(http: &reqwest::Client, lines: &[String], to: &str) -> Result<Translation> {
  let idx: Vec<usize> = (0..lines.len()).filter(|&i| !lines[i].trim().is_empty()).collect();
  if idx.is_empty() {
    return Ok(Translation { lines: vec![String::new(); lines.len()], source: String::new() });
  }
  let src: Vec<&str> = idx.iter().map(|&i| lines[i].trim()).collect();
  let (got, source) = match by_lines(http, &src, to).await {
    Ok(r) if r.0.len() == src.len() => r,
    _ => by_text(http, &src, to).await?,
  };
  let mut out = vec![String::new(); lines.len()];
  for (k, &i) in idx.iter().enumerate() {
    out[i] = got.get(k).cloned().unwrap_or_default();
  }
  Ok(Translation { lines: out, source })
}

async fn by_lines(http: &reqwest::Client, src: &[&str], to: &str) -> Result<(Vec<String>, String)> {
  let form: Vec<(&str, &str)> = src.iter().map(|q| ("q", *q)).collect();
  let resp = http
    .post(URL)
    .query(&[("client", "dict-chrome-ex"), ("sl", "auto"), ("tl", to)])
    .form(&form)
    .send()
    .await?;
  if !resp.status().is_success() {
    bail!("переводчик ответил {}", resp.status());
  }
  parse_lines(&resp.text().await?)
}

async fn by_text(http: &reqwest::Client, src: &[&str], to: &str) -> Result<(Vec<String>, String)> {
  let text = src.join("\n");
  let resp = http
    .post(URL_GTX)
    .query(&[("client", "gtx"), ("sl", "auto"), ("tl", to), ("dt", "t")])
    .form(&[("q", text.as_str())])
    .send()
    .await?;
  if !resp.status().is_success() {
    bail!("переводчик ответил {}", resp.status());
  }
  parse(&resp.text().await?)
}

/// Ответ clients5: `[["перевод","en"],…]` (или просто `["перевод",…]`, если язык оригинала задан).
fn parse_lines(body: &str) -> Result<(Vec<String>, String)> {
  let v: Value = serde_json::from_str(body)?;
  let Some(items) = v.as_array() else { bail!("неожиданный ответ переводчика") };
  let mut source = String::new();
  let mut out = Vec::with_capacity(items.len());
  for it in items {
    match it {
      Value::String(s) => out.push(s.trim().to_string()),
      Value::Array(a) => {
        out.push(a.first().and_then(Value::as_str).unwrap_or_default().trim().to_string());
        if source.is_empty() {
          source = a.get(1).and_then(Value::as_str).unwrap_or_default().to_string();
        }
      }
      _ => bail!("неожиданный ответ переводчика"),
    }
  }
  Ok((out, source))
}

/// Ответ gtx: `[[["перевод\n","original\n",…],…],null,"en",…]` — склеиваем куски и режем по строкам.
fn parse(body: &str) -> Result<(Vec<String>, String)> {
  let v: Value = serde_json::from_str(body)?;
  let Some(parts) = v.get(0).and_then(Value::as_array) else { bail!("неожиданный ответ переводчика") };
  let joined: String = parts.iter().filter_map(|p| p.get(0).and_then(Value::as_str)).collect();
  let source = v.get(2).and_then(Value::as_str).unwrap_or_default().to_string();
  Ok((joined.split('\n').map(|s| s.trim().to_string()).collect(), source))
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn parses_lines_and_source() {
    let body = r#"[[["Привет\n","Hello\n",null,null,10],["мир","world",null,null,10]],null,"en",null]"#;
    let (lines, src) = parse(body).unwrap();
    assert_eq!(lines, vec!["Привет", "мир"]);
    assert_eq!(src, "en");
  }

  #[test]
  fn parses_per_line_answer() {
    let (lines, src) = parse_lines(r#"[["Я вижу свет","en"],["в твоих глазах","en"]]"#).unwrap();
    assert_eq!(lines, vec!["Я вижу свет", "в твоих глазах"]);
    assert_eq!(src, "en");
    let (lines, _) = parse_lines(r#"["раз","два"]"#).unwrap();
    assert_eq!(lines, vec!["раз", "два"]);
  }

  #[test]
  fn rejects_garbage() {
    assert!(parse("{}").is_err());
  }
}
