//! Обложки для коллажа без повторов (docs/POLISH_PROMPT.md п. 1). Зеркало — `windows/src/lib/covers.ts`
//! и iPhone `Core/Library/Covers.swift`.
//!
//! Повтор — тот же альбом, тот же адрес картинки после нормализации (без размера, схемы и `?…`) или, у
//! трека без альбома, тот же исполнитель + адрес. Идём по порядку и останавливаемся на четвёртой
//! разной — порядок стабильный. Итог: 4 разные → сетка 2×2; 1–3 → одна первая обложка; 0 → пусто.
//! Сравнение по пикселям (perceptual hash) — потом, если повторы всё ещё будут видны.

use std::collections::HashSet;
use std::sync::OnceLock;

use regex::Regex;

/// Сколько обложек в сетке коллажа.
pub const COLLAGE_SIZE: usize = 4;

/// Что нужно знать о треке, чтобы выбрать обложку.
pub struct CoverSource<'a> {
  pub cover_url: &'a str,
  pub artist: &'a str,
  pub album_ref: Option<&'a str>,
}

fn size_patterns() -> &'static [(Regex, &'static str); 3] {
  static RE: OnceLock<[(Regex, &'static str); 3]> = OnceLock::new();
  RE.get_or_init(|| {
    [
      (Regex::new(r"(?i)-(t\d+x\d+|large|crop|original|small|tiny|badge|mini|medium)(\.\w+)$").unwrap(), "$2"),
      (Regex::new(r"(?i)/(%%|m?\d+x\d+)$").unwrap(), ""),
      (Regex::new(r"(?i)=(w\d+-h\d+|s\d+)[^/]*$").unwrap(), ""),
    ]
  })
}

/// Адрес обложки без схемы, `?…`, `#…` и размера (SoundCloud, Яндекс, YouTube).
pub fn cover_key(url: &str) -> String {
  let u = url.trim();
  let u = u.split_once("://").map(|(_, rest)| rest).unwrap_or(u.trim_start_matches("//"));
  let u = u.split(['?', '#']).next().unwrap_or(u);
  let mut out = u.to_string();
  for (re, rep) in size_patterns() {
    out = re.replace(&out, *rep).into_owned();
  }
  out.to_lowercase()
}

/// До `n` разных обложек по порядку списка.
pub fn distinct<'a>(tracks: impl IntoIterator<Item = CoverSource<'a>>, n: usize) -> Vec<String> {
  let mut seen = HashSet::new();
  let mut out = Vec::new();
  for t in tracks {
    if out.len() >= n {
      break;
    }
    if t.cover_url.is_empty() {
      continue;
    }
    let key = cover_key(t.cover_url);
    let second = match t.album_ref {
      Some(a) if !a.is_empty() => format!("a:{a}"),
      _ => format!("p:{}|{key}", t.artist.trim().to_lowercase()),
    };
    let first = format!("u:{key}");
    if seen.contains(&first) || seen.contains(&second) {
      continue;
    }
    seen.insert(first);
    seen.insert(second);
    out.push(t.cover_url.to_string());
  }
  out
}

/// Что рисовать: 4 разные — сетка, иначе одна первая обложка, или пусто.
pub fn collage<'a>(tracks: impl IntoIterator<Item = CoverSource<'a>>) -> Vec<String> {
  let mut covers = distinct(tracks, COLLAGE_SIZE);
  if covers.len() < COLLAGE_SIZE {
    covers.truncate(1);
  }
  covers
}

#[cfg(test)]
mod tests {
  use super::*;

  fn src<'a>(url: &'a str, album: Option<&'a str>, artist: &'a str) -> CoverSource<'a> {
    CoverSource { cover_url: url, artist, album_ref: album }
  }

  #[test]
  fn key_strips_sizes_scheme_and_query() {
    assert_eq!(cover_key("https://i1.sndcdn.com/artworks-a-t500x500.jpg"), "i1.sndcdn.com/artworks-a.jpg");
    assert_eq!(cover_key("http://i1.sndcdn.com/artworks-a-large.jpg?x=1"), "i1.sndcdn.com/artworks-a.jpg");
    assert_eq!(cover_key("https://avatars.yandex.net/get-music-content/1/a/%%"), "avatars.yandex.net/get-music-content/1/a");
    assert_eq!(cover_key("https://avatars.yandex.net/get-music-content/1/a/400x400"), "avatars.yandex.net/get-music-content/1/a");
    assert_eq!(cover_key("https://lh3.googleusercontent.com/abc=w544-h544-l90-rj"), "lh3.googleusercontent.com/abc");
  }

  #[test]
  fn one_album_and_three_others_give_four_distinct() {
    let urls: Vec<String> = (0..10).map(|i| format!("https://c/alb-{i}.jpg")).collect();
    let mut list: Vec<CoverSource> = urls.iter().map(|u| src(u, Some("ym:alb"), "A")).collect();
    list.push(src("https://c/x.jpg", Some("ym:x"), "A"));
    list.push(src("https://c/y.jpg", Some("ym:y"), "A"));
    list.push(src("https://c/z.jpg", None, "Z"));
    assert_eq!(collage(list), ["https://c/alb-0.jpg", "https://c/x.jpg", "https://c/y.jpg", "https://c/z.jpg"]);
  }

  #[test]
  fn same_picture_other_size_is_a_repeat() {
    let list = [src("https://c/a-t500x500.jpg", Some("sc:1"), "A"), src("https://c/a-large.jpg", Some("sc:2"), "A"), src("https://c/b.jpg", None, "A")];
    assert_eq!(distinct(list, 4), ["https://c/a-t500x500.jpg", "https://c/b.jpg"]);
  }

  #[test]
  fn two_or_three_distinct_collapse_to_first() {
    let list = [src("https://c/1.jpg", None, "A"), src("https://c/2.jpg", None, "A"), src("https://c/3.jpg", None, "A")];
    assert_eq!(collage(list), ["https://c/1.jpg"]);
    assert!(collage(Vec::<CoverSource>::new()).is_empty());
  }
}
