//! Ссылка из буфера в строке поиска (решение владельца 2026-11-16) и «Перенести по ссылке» в
//! медиатеке (этап 5): трек, альбом, артист или плейлист SoundCloud, Яндекс Музыки, Spotify,
//! YouTube / YouTube Music, VK и Apple Music → что это.
//! Яндекс, Spotify, YouTube и VK разбираются по адресу; SoundCloud — через `resolve` его API (адрес —
//! имя пользователя и трека, id в нём нет), короткие `on.soundcloud.com` раскрываются переходом;
//! Apple Music своего сервиса в Sonar не имеет — его страница читается только для импорта.

use url::Url;

/// Что за ссылка, до похода в сеть.
#[derive(Debug, Clone, PartialEq)]
pub enum Link {
  /// Готовый ref Sonar: `ym:…`, `ymalb:…`, `sppl:…`, `ytpl:…`, `vkpl:<owner>_<id>[_<key>]` и т. д.
  Ref(String),
  /// Ссылка SoundCloud — узнать, что за ней, можно только у API (`resolve`).
  SoundCloud(String),
  /// Плейлист или альбом Apple Music (адрес без параметров) — читается страницей (`apple.rs`).
  Apple(String),
}

/// Хосты, по которым строка поиска узнаёт ссылку без `https://` (тот же список — в api.ts `LINK_HOSTS`).
#[cfg(test)]
const LINK_HOSTS: &[&str] =
  &["soundcloud.com/", "music.yandex.", "open.spotify.com/", "youtube.com/", "youtu.be/", "vk.com/", "music.apple.com/"];

/// Похоже ли на ссылку (то же решает строка поиска в api.ts `looksLikeLink`; здесь — для тестов).
#[cfg(test)]
pub fn looks_like_link(s: &str) -> bool {
  let s = s.trim();
  !s.contains(char::is_whitespace)
    && (s.starts_with("http://") || s.starts_with("https://") || s.starts_with("spotify:") || LINK_HOSTS.iter().any(|h| s.contains(h)))
}

pub fn parse(raw: &str) -> Option<Link> {
  let raw = raw.trim();
  if let Some(uri) = raw.strip_prefix("spotify:") {
    return spotify_uri(uri);
  }
  let url = Url::parse(raw).or_else(|_| Url::parse(&format!("https://{raw}"))).ok()?;
  let host = url.host_str()?.trim_start_matches("www.").trim_start_matches("m.").to_owned();
  let parts: Vec<&str> = url.path_segments()?.filter(|p| !p.is_empty()).collect();
  if host.ends_with("soundcloud.com") || host == "snd.sc" {
    // свои страницы SoundCloud без контента — не ссылки на музыку
    if host == "soundcloud.com" && parts.is_empty() {
      return None;
    }
    return Some(Link::SoundCloud(without_query(&url)));
  }
  if host.starts_with("music.yandex.") {
    return yandex(&parts);
  }
  match host.as_str() {
    "open.spotify.com" | "play.spotify.com" => spotify(&parts),
    "youtube.com" | "music.youtube.com" | "youtu.be" => youtube(&host, &parts, &url),
    "vk.com" | "vk.ru" => vk(&parts, &url),
    "music.apple.com" => apple(&parts).then(|| Link::Apple(without_query(&url))),
    _ => None,
  }
}

fn without_query(url: &Url) -> String {
  let mut clean = url.clone();
  clean.set_query(None);
  clean.set_fragment(None);
  clean.to_string()
}

fn r(prefix: &str, id: &str) -> Option<Link> {
  Some(Link::Ref(format!("{prefix}:{id}")))
}

fn digits(s: &str) -> bool {
  !s.is_empty() && s.chars().all(|c| c.is_ascii_digit())
}

fn yandex(parts: &[&str]) -> Option<Link> {
  let num = |s: &str| digits(s).then(|| s.to_owned());
  match parts {
    ["album", _, "track", t, ..] | ["track", t, ..] => num(t).map(|t| Link::Ref(format!("ym:{t}"))),
    ["album", a, ..] => num(a).map(|a| Link::Ref(format!("ymalb:{a}"))),
    ["artist", a, ..] => num(a).map(|a| Link::Ref(format!("yma:{a}"))),
    ["users", user, "playlists", kind, ..] => num(kind).map(|k| Link::Ref(format!("ympl:{user}:{k}"))),
    _ => None,
  }
}

/// id Spotify — 22 знака base62.
fn spotify_id(s: &str) -> bool {
  s.len() == 22 && s.chars().all(|c| c.is_ascii_alphanumeric())
}

fn spotify_kind(kind: &str, id: &str) -> Option<Link> {
  let prefix = match kind {
    "track" => "sp",
    "album" => "spalb",
    "artist" => "spa",
    "playlist" => "sppl",
    _ => return None,
  };
  spotify_id(id).then(|| Link::Ref(format!("{prefix}:{id}")))
}

fn spotify(parts: &[&str]) -> Option<Link> {
  // `open.spotify.com/intl-de/track/…` — тот же трек
  let parts = match parts.first() {
    Some(p) if p.starts_with("intl-") => &parts[1..],
    _ => parts,
  };
  match parts {
    ["collection", "tracks", ..] => r("sppl", "likes"),
    [kind, id, ..] => spotify_kind(kind, id),
    _ => None,
  }
}

/// `spotify:track:<id>` (часть после `spotify:`).
fn spotify_uri(uri: &str) -> Option<Link> {
  let (kind, id) = uri.split_once(':')?;
  spotify_kind(kind, id)
}

fn youtube(host: &str, parts: &[&str], url: &Url) -> Option<Link> {
  let query = |key: &str| url.query_pairs().find(|(k, _)| k == key).map(|(_, v)| v.into_owned()).filter(|v| !v.is_empty());
  let video_id = |s: &str| s.len() == 11 && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_');
  if host == "youtu.be" {
    return parts.first().filter(|id| video_id(id)).and_then(|id| r("yt", id));
  }
  match parts {
    ["watch", ..] => query("v").filter(|v| video_id(v)).and_then(|v| r("yt", &v)),
    ["shorts", id, ..] if video_id(id) => r("yt", id),
    ["playlist", ..] => match query("list")?.as_str() {
      "LM" => r("ytpl", "likes"),
      list => r("ytpl", list.trim_start_matches("VL")),
    },
    ["browse", id, ..] if id.starts_with("MPREb_") => r("ytalb", id),
    ["browse", id, ..] if id.starts_with("VL") => r("ytpl", &id[2..]),
    ["channel", id, ..] if id.starts_with("UC") => r("yta", id),
    _ => None,
  }
}

/// `<owner>_<id>[_<key>]` VK: числа и ключ из букв и цифр.
fn vk_id(s: &str) -> Option<String> {
  crate::providers::vk::PlaylistId::parse(s).map(|_| s.to_owned())
}

fn vk(parts: &[&str], url: &Url) -> Option<Link> {
  // `vk.com/music?z=audio_playlist-2000_123/abc` — старый вид ссылки на плейлист
  if let Some((_, z)) = url.query_pairs().find(|(k, _)| k == "z") {
    if let Some(rest) = z.strip_prefix("audio_playlist") {
      let id = rest.replacen('/', "_", 1);
      return vk_id(&id).and_then(|id| r("vkpl", &id));
    }
  }
  match parts {
    ["music", "playlist", id, ..] => vk_id(id).and_then(|id| r("vkpl", &id)),
    ["music", "album", id, ..] => vk_id(id).and_then(|id| r("vkalb", &id)),
    ["artist", id, ..] => r("vka", id),
    [one] if one.starts_with("audio_playlist") => vk_id(&one["audio_playlist".len()..]).and_then(|id| r("vkpl", &id)),
    [one] if one.starts_with("audio") => {
      let id = &one["audio".len()..];
      crate::providers::vk::is_audio_id(id).then(|| Link::Ref(format!("vk:{id}")))
    }
    _ => None,
  }
}

/// `music.apple.com/<страна>/playlist|album/<имя>/<id>` — с id, без библиотеки пользователя.
fn apple(parts: &[&str]) -> bool {
  matches!(parts, [_, "playlist" | "album", _, id, ..] if !id.is_empty())
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
    assert_eq!(parse("https://example.com/watch?v=1"), None);
  }

  #[test]
  fn spotify_links() {
    let id = "37i9dQZF1DXcBWIGoYBM5M";
    assert_eq!(parse(&format!("https://open.spotify.com/playlist/{id}?si=abc")), r(&format!("sppl:{id}")));
    assert_eq!(parse(&format!("https://open.spotify.com/intl-de/track/{id}")), r(&format!("sp:{id}")));
    assert_eq!(parse(&format!("open.spotify.com/album/{id}")), r(&format!("spalb:{id}")));
    assert_eq!(parse(&format!("spotify:artist:{id}")), r(&format!("spa:{id}")));
    assert_eq!(parse("https://open.spotify.com/collection/tracks"), r("sppl:likes"));
    assert_eq!(parse("https://open.spotify.com/playlist/short"), None);
    assert_eq!(parse(&format!("https://open.spotify.com/show/{id}")), None);
  }

  #[test]
  fn youtube_links() {
    assert_eq!(parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=RD"), r("yt:dQw4w9WgXcQ"));
    assert_eq!(parse("https://youtu.be/dQw4w9WgXcQ?t=3"), r("yt:dQw4w9WgXcQ"));
    assert_eq!(parse("https://music.youtube.com/watch?v=dQw4w9WgXcQ"), r("yt:dQw4w9WgXcQ"));
    assert_eq!(parse("https://music.youtube.com/playlist?list=PLabc_123"), r("ytpl:PLabc_123"));
    assert_eq!(parse("https://music.youtube.com/playlist?list=LM"), r("ytpl:likes"));
    assert_eq!(parse("https://music.youtube.com/browse/MPREb_abc"), r("ytalb:MPREb_abc"));
    assert_eq!(parse("https://music.youtube.com/browse/VLPLxyz"), r("ytpl:PLxyz"));
    assert_eq!(parse("https://music.youtube.com/channel/UCabc"), r("yta:UCabc"));
    assert_eq!(parse("https://youtube.com/watch?v=1"), None);
    assert_eq!(parse("https://youtube.com/feed/library"), None);
  }

  #[test]
  fn vk_links() {
    assert_eq!(parse("https://vk.com/music/playlist/-2000123_456_ab12cd"), r("vkpl:-2000123_456_ab12cd"));
    assert_eq!(parse("https://vk.com/music/album/-2000123_456_ab12cd"), r("vkalb:-2000123_456_ab12cd"));
    assert_eq!(parse("https://vk.com/music?z=audio_playlist-2000123_456/ab12cd"), r("vkpl:-2000123_456_ab12cd"));
    assert_eq!(parse("https://vk.com/audio_playlist123_7"), r("vkpl:123_7"));
    assert_eq!(parse("https://vk.com/audio-2001_456"), r("vk:-2001_456"));
    assert_eq!(parse("https://vk.com/artist/zemfira"), r("vka:zemfira"));
    assert_eq!(parse("https://vk.com/music/playlist/abc"), None);
    assert_eq!(parse("https://vk.com/id1"), None);
  }

  #[test]
  fn apple_links() {
    let pl = "https://music.apple.com/us/playlist/todays-hits/pl.f4d106fed2bd41149aaacabb233eb5eb";
    assert_eq!(parse(&format!("{pl}?l=ru")), Some(Link::Apple(pl.into())));
    let al = "https://music.apple.com/ru/album/housewife/6822497770";
    assert_eq!(parse(&format!("{al}?i=6822497774")), Some(Link::Apple(al.into())));
    assert_eq!(parse("https://music.apple.com/us/artist/tate-mcrae/1446365464"), None);
    assert_eq!(parse("https://music.apple.com/library/playlist/p.abc"), None);
  }

  #[test]
  fn link_detection() {
    assert!(looks_like_link("https://soundcloud.com/a/b"));
    assert!(looks_like_link("music.yandex.ru/album/1"));
    assert!(looks_like_link("open.spotify.com/track/1"));
    assert!(looks_like_link("spotify:track:1"));
    assert!(looks_like_link("youtu.be/abc"));
    assert!(looks_like_link("vk.com/music/playlist/1_2"));
    assert!(!looks_like_link("lil peep star shopping"));
  }
}
