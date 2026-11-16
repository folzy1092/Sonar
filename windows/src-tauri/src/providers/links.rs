//! Ссылка из буфера в строке поиска (решение владельца 2026-11-16): трек, альбом, артист или
//! плейлист SoundCloud / Яндекс Музыки → что это и как добавить в медиатеку.
//! Яндекс разбирается по адресу; SoundCloud — через `resolve` его API (адрес — имя пользователя
//! и трека, id в нём нет), короткие `on.soundcloud.com` раскрываются переходом.

use url::Url;

/// Что за ссылка, до похода в сеть.
#[derive(Debug, Clone, PartialEq)]
pub enum Link {
  /// Готовый ref Sonar: `ym:…`, `ymalb:…`, `yma:…`, `ympl:<uid>:<kind>`.
  Ref(String),
  /// Ссылка SoundCloud — узнать, что за ней, можно только у API (`resolve`).
  SoundCloud(String),
}

/// Похоже ли на ссылку (то же решает строка поиска в api.ts `looksLikeLink`; здесь — для тестов).
#[cfg(test)]
pub fn looks_like_link(s: &str) -> bool {
  let s = s.trim();
  !s.contains(char::is_whitespace) && (s.starts_with("http://") || s.starts_with("https://") || s.contains("soundcloud.com/") || s.contains("music.yandex."))
}

pub fn parse(raw: &str) -> Option<Link> {
  let raw = raw.trim();
  let url = Url::parse(raw).or_else(|_| Url::parse(&format!("https://{raw}"))).ok()?;
  let host = url.host_str()?.trim_start_matches("www.").trim_start_matches("m.").to_owned();
  let parts: Vec<&str> = url.path_segments()?.filter(|p| !p.is_empty()).collect();
  if host.ends_with("soundcloud.com") || host == "snd.sc" {
    // свои страницы SoundCloud без контента — не ссылки на музыку
    if host == "soundcloud.com" && parts.is_empty() {
      return None;
    }
    let mut clean = url.clone();
    clean.set_query(None);
    clean.set_fragment(None);
    return Some(Link::SoundCloud(clean.to_string()));
  }
  if !host.starts_with("music.yandex.") {
    return None;
  }
  let num = |s: &str| s.chars().all(|c| c.is_ascii_digit()).then(|| s.to_owned());
  match parts.as_slice() {
    ["album", _, "track", t, ..] | ["track", t, ..] => num(t).map(|t| Link::Ref(format!("ym:{t}"))),
    ["album", a, ..] => num(a).map(|a| Link::Ref(format!("ymalb:{a}"))),
    ["artist", a, ..] => num(a).map(|a| Link::Ref(format!("yma:{a}"))),
    ["users", user, "playlists", kind, ..] => num(kind).map(|k| Link::Ref(format!("ympl:{user}:{k}"))),
    _ => None,
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn r(s: &str) -> Option<Link> {
    Some(Link::Ref(s.into()))
  }

  #[test]
  fn yandex_links() {
    assert_eq!(parse("https://music.yandex.ru/album/123/track/456?utm_source=x"), r("ym:456"));
    assert_eq!(parse("https://music.yandex.com/track/789"), r("ym:789"));
    assert_eq!(parse("music.yandex.ru/album/123"), r("ymalb:123"));
    assert_eq!(parse("https://music.yandex.by/artist/42/tracks"), r("yma:42"));
    assert_eq!(parse("https://music.yandex.ru/users/folzy/playlists/1003"), r("ympl:folzy:1003"));
    assert_eq!(parse("https://music.yandex.ru/home"), None);
    assert_eq!(parse("https://music.yandex.ru/album/abc"), None);
  }

  #[test]
  fn soundcloud_links() {
    assert_eq!(
      parse("https://soundcloud.com/lil-peep/star-shopping?si=abc&utm_medium=text"),
      Some(Link::SoundCloud("https://soundcloud.com/lil-peep/star-shopping".into()))
    );
    assert_eq!(parse("https://m.soundcloud.com/x/sets/y"), Some(Link::SoundCloud("https://m.soundcloud.com/x/sets/y".into())));
    assert!(matches!(parse("https://on.soundcloud.com/AbC123"), Some(Link::SoundCloud(_))));
    assert_eq!(parse("https://soundcloud.com/"), None);
    assert_eq!(parse("https://youtube.com/watch?v=1"), None);
  }

  #[test]
  fn link_detection() {
    assert!(looks_like_link("https://soundcloud.com/a/b"));
    assert!(looks_like_link("music.yandex.ru/album/1"));
    assert!(!looks_like_link("lil peep star shopping"));
  }
}
