//! Перевод текста песни (меню текста → «Перевести», решение владельца 2026-11-17). Без сервера и ключей:
//! открытая точка Google Translate расширения Chrome (`clients5`, `dict-chrome-ex`) — каждая строка
//! отдельным `q` одним запросом, ответ построчно. Запасной путь — `translate.googleapis.com` (`gtx`,
//! строки через перевод строки): его Google порой отдаёт капчей. Пустые строки (паузы) не отправляем.
//! Строки, которые уже на языке интерфейса, не переводим (решение владельца 2026-11-19): язык смотрим
//! у каждой строки (clients5 отдаёт его построчно), а перевод, совпавший с оригиналом, тоже убираем.

use anyhow::{bail, Result};
use serde::Serialize;
use serde_json::Value;

const URL: &str = "https://clients5.google.com/translate_a/t";
const URL_GTX: &str = "https://translate.googleapis.com/translate_a/single";

#[derive(Serialize)]
pub struct Translation {
  /// Перевод каждой строки (той же длины, что и вход; пауза — пустая строка).
  pub lines: Vec<String>,
  /// Язык оригинала, как его определил Google (`en`, `ja`…) — самый частый по строкам; весь текст уже
  /// на языке `to` — ровно `to` (клиент тогда пишет «Текст уже на этом языке»).
  pub source: String,
}

pub async fn translate(http: &reqwest::Client, lines: &[String], to: &str) -> Result<Translation> {
  let idx: Vec<usize> = (0..lines.len()).filter(|&i| !lines[i].trim().is_empty()).collect();
  if idx.is_empty() {
    return Ok(Translation { lines: vec![String::new(); lines.len()], source: String::new() });
  }
  let src: Vec<&str> = idx.iter().map(|&i| lines[i].trim()).collect();
  let (got, sources) = match by_lines(http, &src, to).await {
    Ok(r) if r.0.len() == src.len() => r,
    _ => by_text(http, &src, to).await?,
  };
  let (got, source) = drop_same_language(&src, got, &sources, to);
  let mut out = vec![String::new(); lines.len()];
  for (k, &i) in idx.iter().enumerate() {
    out[i] = got.get(k).cloned().unwrap_or_default();
  }
  Ok(Translation { lines: out, source })
}

/// Убирает перевод у строк, которые уже на языке `to`: Google определил у строки этот язык или перевод
/// совпал с оригиналом (без регистра и знаков). `sources` — язык каждой строки (gtx знает один на весь
/// текст — тогда он один в списке). Возвращает строки и язык оригинала: самый частый среди
/// переведённых строк, а если переводить нечего — `to`.
fn drop_same_language(src: &[&str], got: Vec<String>, sources: &[String], to: &str) -> (Vec<String>, String) {
  let target = base_lang(to);
  let line_source = |k: usize| -> &str {
    match sources {
      [one] => one,
      many => many.get(k).map(String::as_str).unwrap_or(""),
    }
  };
  let mut counts: Vec<(String, usize)> = Vec::new();
  let lines: Vec<String> = got
    .into_iter()
    .enumerate()
    .map(|(k, tr)| {
      let lang = base_lang(line_source(k));
      let same = lang == target || src.get(k).is_some_and(|o| same_text(o, &tr));
      if same || tr.is_empty() {
        return String::new();
      }
      if !lang.is_empty() {
        match counts.iter_mut().find(|(l, _)| *l == lang) {
          Some((_, n)) => *n += 1,
          None => counts.push((lang, 1)),
        }
      }
      tr
    })
    .collect();
  let source = if lines.iter().all(String::is_empty) {
    target
  } else {
    counts.into_iter().max_by_key(|(_, n)| *n).map(|(l, _)| l).unwrap_or_default()
  };
  (lines, source)
}

/// `pt-BR` → `pt`, `RU` → `ru`.
fn base_lang(code: &str) -> String {
  code.split(['-', '_']).next().unwrap_or("").trim().to_lowercase()
}

/// Совпадают ли строки без регистра, пробелов и знаков: «Привет, мир!» = «привет мир».
fn same_text(a: &str, b: &str) -> bool {
  let norm = |s: &str| s.chars().filter(|c| c.is_alphanumeric()).flat_map(char::to_lowercase).collect::<String>();
  let (a, b) = (norm(a), norm(b));
  !a.is_empty() && a == b
}

async fn by_lines(http: &reqwest::Client, src: &[&str], to: &str) -> Result<(Vec<String>, Vec<String>)> {
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

async fn by_text(http: &reqwest::Client, src: &[&str], to: &str) -> Result<(Vec<String>, Vec<String>)> {
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
  let (lines, source) = parse(&resp.text().await?)?;
  Ok((lines, vec![source]))
}

/// Ответ clients5: `[["перевод","en"],…]` (или просто `["перевод",…]`, если язык оригинала задан) —
/// перевод и язык каждой строки (без языка — пустая строка).
fn parse_lines(body: &str) -> Result<(Vec<String>, Vec<String>)> {
  let v: Value = serde_json::from_str(body)?;
  let Some(items) = v.as_array() else { bail!("неожиданный ответ переводчика") };
  let mut out = Vec::with_capacity(items.len());
  let mut sources = Vec::with_capacity(items.len());
  for it in items {
    match it {
      Value::String(s) => {
        out.push(s.trim().to_string());
        sources.push(String::new());
      }
      Value::Array(a) => {
        out.push(a.first().and_then(Value::as_str).unwrap_or_default().trim().to_string());
        sources.push(a.get(1).and_then(Value::as_str).unwrap_or_default().to_string());
      }
      _ => bail!("неожиданный ответ переводчика"),
    }
  }
  Ok((out, sources))
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
    assert_eq!(src, vec!["en", "en"]);
    let (lines, _) = parse_lines(r#"["раз","два"]"#).unwrap();
    assert_eq!(lines, vec!["раз", "два"]);
  }

  fn owned(v: &[&str]) -> Vec<String> {
    v.iter().map(|s| s.to_string()).collect()
  }

  #[test]
  fn skips_lines_already_in_target_language() {
    // русская песня с английским припевом, интерфейс на русском: переводим только английское
    let src = ["Я иду домой", "Hello darkness", "Ночь темна"];
    let got = owned(&["Я иду домой", "Привет, тьма", "Ночь темна"]);
    let (lines, source) = drop_same_language(&src, got, &owned(&["ru", "en", "ru"]), "ru");
    assert_eq!(lines, vec!["", "Привет, тьма", ""]);
    assert_eq!(source, "en");
  }

  #[test]
  fn whole_text_in_target_language_reports_target() {
    let src = ["Hello", "World"];
    let (lines, source) = drop_same_language(&src, owned(&["Hello", "World"]), &owned(&["en", "en"]), "en");
    assert_eq!(lines, vec!["", ""]);
    assert_eq!(source, "en");
  }

  #[test]
  fn first_line_language_does_not_decide_for_all() {
    // раньше язык брали по первой строке: «[Intro]»-строка на английском заставляла переводить всё
    let src = ["Yeah", "Ты моя звезда"];
    let got = owned(&["Ага", "Ты моя звезда"]);
    let (lines, source) = drop_same_language(&src, got, &owned(&["en", "ru"]), "ru-RU");
    assert_eq!(lines, vec!["Ага", ""]);
    assert_eq!(source, "en");
  }

  #[test]
  fn drops_translation_equal_to_original_without_language() {
    // gtx: один язык на весь текст, но строка не изменилась — значит, переводить нечего
    let src = ["Привет, мир!", "Bonjour"];
    let got = owned(&["привет мир", "Привет"]);
    let (lines, source) = drop_same_language(&src, got, &owned(&["fr"]), "ru");
    assert_eq!(lines, vec!["", "Привет"]);
    assert_eq!(source, "fr");
  }

  #[test]
  fn rejects_garbage() {
    assert!(parse("{}").is_err());
  }
}
