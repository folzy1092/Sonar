//! Разбор ответов InnerTube YouTube Music (клиент WEB_REMIX) в модели Sonar. Только чистые функции:
//! на вход — JSON ответа, на выход — `Track`/`Album`/…; сеть — в `mod.rs`. Ответы глубоко вложены и
//! меняют обёртки, поэтому нужные «рендереры» ищем рекурсивно по имени ключа, а не по полному пути.
//! Тесты — на сохранённых ответах из `fixtures/` (адреса потоков в них заменены на тестовые).

use super::super::{Account, Album, AlbumRef, Artist, ArtistRef, ServicePlaylist, Track};
use anyhow::{anyhow, Result};
use regex::Regex;
use serde_json::Value;
use std::sync::LazyLock;

/// Сайт YouTube Music — для ссылок «Открыть в YouTube Music».
pub const WEB: &str = "https://music.youtube.com";
/// Сторона обложки, до которой растягиваем картинки googleusercontent (как самая крупная в ответах).
const COVER_SIDE: u32 = 544;
/// Разделитель колонок в строках YouTube Music: «Lil Peep • Альбом • 2:26».
const DOT: &str = " • ";
const EXPLICIT: &str = "MUSIC_EXPLICIT_BADGE";
const GREY_OUT: &str = "MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT";
const PAGE_ARTIST: &str = "MUSIC_PAGE_TYPE_ARTIST";
const PAGE_CHANNEL: &str = "MUSIC_PAGE_TYPE_USER_CHANNEL";
const PAGE_ALBUM: &str = "MUSIC_PAGE_TYPE_ALBUM";
const PAGE_PLAYLIST: &str = "MUSIC_PAGE_TYPE_PLAYLIST";
/// Плейлист «Понравившиеся» в YouTube Music (`VLLM` в browse) — у нас это `ytpl:likes`.
pub const LIKES_BROWSE_ID: &str = "VLLM";
/// Первая часть строки, которая говорит о типе, а не об исполнителе (поиск без фильтра).
const TYPE_WORDS: [&str; 8] = ["Песня", "Song", "Видео", "Video", "Трек", "Пісня", "Відео", "Episode"];

static SIZE_WH: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"=w\d+-h\d+").expect("regex"));
static SIZE_S: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"=s\d+").expect("regex"));

// ---------- ссылки ----------

pub fn track_url(video_id: &str) -> String {
  format!("{WEB}/watch?v={video_id}")
}

pub fn artist_url(channel_id: &str) -> String {
  format!("{WEB}/channel/{channel_id}")
}

pub fn album_url(browse_id: &str) -> String {
  format!("{WEB}/browse/{browse_id}")
}

// ---------- общие помощники ----------

/// Текст поля: `runs` склеиваются, иначе `simpleText` или `content`.
pub fn text(v: &Value) -> String {
  if let Some(runs) = v["runs"].as_array() {
    return runs.iter().filter_map(|r| r["text"].as_str()).collect();
  }
  v["simpleText"].as_str().or_else(|| v["content"].as_str()).unwrap_or_default().to_owned()
}

/// Все значения ключа `key` на любой глубине, по порядку обхода.
pub fn find_all<'a>(v: &'a Value, key: &str) -> Vec<&'a Value> {
  let mut out = Vec::new();
  collect(v, key, &mut out);
  out
}

fn collect<'a>(v: &'a Value, key: &str, out: &mut Vec<&'a Value>) {
  match v {
    Value::Object(m) => {
      for (k, child) in m {
        if k == key {
          out.push(child);
        }
        collect(child, key, out);
      }
    }
    Value::Array(a) => a.iter().for_each(|child| collect(child, key, out)),
    _ => {}
  }
}

pub fn find_first<'a>(v: &'a Value, key: &str) -> Option<&'a Value> {
  match v {
    Value::Object(m) => m.get(key).or_else(|| m.values().find_map(|c| find_first(c, key))),
    Value::Array(a) => a.iter().find_map(|c| find_first(c, key)),
    _ => None,
  }
}

/// Самая крупная картинка из ближайшего `thumbnails`; обложки googleusercontent — до 544×544.
pub fn best_thumb(v: &Value) -> Option<String> {
  let list = find_first(v, "thumbnails")?.as_array()?;
  let best = list.iter().max_by_key(|t| t["width"].as_u64().unwrap_or(0))?;
  best["url"].as_str().filter(|u| !u.is_empty()).map(upscale)
}

/// `=w120-h120` → `=w544-h544`, `=s192` → `=s544` у картинок Google; превью видео `i.ytimg.com` — как есть.
pub fn upscale(url: &str) -> String {
  let google = url.contains(".googleusercontent.com/") || url.contains(".ggpht.com/");
  if !google {
    return url.to_owned();
  }
  let side = COVER_SIDE;
  let wh = SIZE_WH.replace(url, format!("=w{side}-h{side}").as_str()).into_owned();
  SIZE_S.replace(&wh, format!("=s{side}").as_str()).into_owned()
}

/// «2:26» → 146 000 мс, «1:02:03» → 3 723 000 мс.
pub fn parse_duration(s: &str) -> Option<u64> {
  let s = s.trim();
  if s.is_empty() || !s.contains(':') {
    return None;
  }
  let mut total = 0u64;
  for part in s.split(':') {
    let n: u64 = part.trim().parse().ok()?;
    total = total * 60 + n;
  }
  Some(total * 1000)
}

/// «1.2K plays» → 1200, «61,5 млн» → 61 500 000, «500 треков» → 500.
pub fn parse_count(s: &str) -> Option<u64> {
  let s = s.replace('\u{a0}', " ");
  let start = s.find(|c: char| c.is_ascii_digit())?;
  let rest = &s[start..];
  let end = rest.find(|c: char| !(c.is_ascii_digit() || c == '.' || c == ',')).unwrap_or(rest.len());
  let tail = rest[end..].trim_start().to_lowercase();
  let mult = if tail.starts_with("млрд") || tail.starts_with('b') {
    1e9
  } else if tail.starts_with("млн") || (tail.starts_with('m') && !tail.starts_with("min")) {
    1e6
  } else if tail.starts_with("тыс") || tail.starts_with('k') {
    1e3
  } else {
    1.0
  };
  let num = &rest[..end];
  let value: f64 = if mult > 1.0 { num.replace(',', ".").parse().ok()? } else { num.replace([',', '.'], "").parse().ok()? };
  Some((value * mult).round() as u64)
}

/// Последний год в строке («Сингл • 2015» → 2015).
pub fn last_year(s: &str) -> Option<u32> {
  s.split(|c: char| !c.is_ascii_digit())
    .filter(|t| t.len() == 4)
    .filter_map(|t| t.parse::<u32>().ok())
    .filter(|y| (1900..=2100).contains(y))
    .last()
}

fn page_type(run: &Value) -> &str {
  run["navigationEndpoint"]["browseEndpoint"]["browseEndpointContextSupportedConfigs"]["browseEndpointContextMusicConfig"]["pageType"]
    .as_str()
    .unwrap_or_default()
}

fn browse_id(run: &Value) -> Option<&str> {
  run["navigationEndpoint"]["browseEndpoint"]["browseId"].as_str().filter(|s| !s.is_empty())
}

/// Части строки между « • ».
fn segments(runs: &[Value]) -> Vec<Vec<&Value>> {
  let mut out = vec![Vec::new()];
  for r in runs {
    if r["text"].as_str() == Some(DOT) {
      out.push(Vec::new());
    } else if let Some(last) = out.last_mut() {
      last.push(r);
    }
  }
  out.retain(|s| !s.is_empty());
  out
}

fn seg_text(seg: &[&Value]) -> String {
  seg.iter().filter_map(|r| r["text"].as_str()).collect::<String>().trim().to_owned()
}

fn flex_runs(item: &Value, col: usize) -> &[Value] {
  item["flexColumns"][col]["musicResponsiveListItemFlexColumnRenderer"]["text"]["runs"].as_array().map(Vec::as_slice).unwrap_or_default()
}

fn flex_count(item: &Value) -> usize {
  item["flexColumns"].as_array().map_or(0, Vec::len)
}

fn artist_ref(run: &Value) -> Option<ArtistRef> {
  let id = browse_id(run)?;
  let name = run["text"].as_str()?.trim();
  Some(ArtistRef { ref_: format!("yta:{id}"), name: name.to_owned(), avatar_url: None })
}

fn is_artist_run(run: &Value) -> bool {
  matches!(page_type(run), PAGE_ARTIST | PAGE_CHANNEL)
}

/// Исполнители из ссылок в строке (без повторов).
fn artists_in(runs: &[&Value]) -> Vec<ArtistRef> {
  let mut out: Vec<ArtistRef> = Vec::new();
  for a in runs.iter().filter(|r| is_artist_run(r)).filter_map(|r| artist_ref(r)) {
    if !out.iter().any(|x| x.ref_ == a.ref_) {
      out.push(a);
    }
  }
  out
}

fn album_in(runs: &[&Value]) -> Option<AlbumRef> {
  let run = runs.iter().find(|r| page_type(r) == PAGE_ALBUM)?;
  Some(AlbumRef { ref_: format!("ytalb:{}", browse_id(run)?), title: run["text"].as_str()?.to_owned() })
}

fn has_explicit(v: &Value) -> bool {
  find_all(v, "iconType").iter().any(|t| t.as_str() == Some(EXPLICIT))
}

fn names(artists: &[ArtistRef]) -> String {
  artists.iter().map(|a| a.name.as_str()).collect::<Vec<_>>().join(", ")
}

/// Что подставить треку, если в строке этого нет (на странице альбома у треков пусто).
#[derive(Default, Clone)]
pub struct Fallback {
  pub artists: Vec<ArtistRef>,
  pub album: Option<AlbumRef>,
  pub cover: Option<String>,
}

// ---------- треки ----------

/// Строка списка (`musicResponsiveListItemRenderer`) → трек. Не трек (артист, альбом) — None.
pub fn track_from_item(item: &Value, fb: &Fallback) -> Option<Track> {
  let col0 = flex_runs(item, 0);
  let video_id = item["playlistItemData"]["videoId"]
    .as_str()
    .or_else(|| col0.first().and_then(|r| r["navigationEndpoint"]["watchEndpoint"]["videoId"].as_str()))?;
  let title = col0.iter().filter_map(|r| r["text"].as_str()).collect::<String>();
  let other: Vec<&Value> = (1..flex_count(item)).flat_map(|c| flex_runs(item, c)).collect();
  let col1: Vec<Vec<&Value>> = segments(flex_runs(item, 1));
  let mut artists = artists_in(&other);
  let first = col1.first().map(|s| seg_text(s)).filter(|t| !TYPE_WORDS.contains(&t.as_str()));
  let first = first.or_else(|| col1.get(1).map(|s| seg_text(s)));
  let mut artist = first.filter(|t| parse_duration(t).is_none()).unwrap_or_default();
  if artists.is_empty() && artist.is_empty() {
    artists = fb.artists.clone();
  }
  if artist.is_empty() {
    artist = names(&artists);
  }
  let fixed = item["fixedColumns"][0]["musicResponsiveListItemFixedColumnRenderer"]["text"].clone();
  let duration_ms = parse_duration(&text(&fixed))
    .or_else(|| col1.iter().rev().find_map(|s| parse_duration(&seg_text(s))))
    .unwrap_or(0);
  let plays = flex_runs(item, 2).first().and_then(|r| r["text"].as_str()).and_then(parse_count);
  Some(Track {
    ref_: format!("yt:{video_id}"),
    title,
    artist,
    artists,
    album: album_in(&other).or_else(|| fb.album.clone()),
    duration_ms,
    cover_url: best_thumb(&item["thumbnail"]).or_else(|| fb.cover.clone()),
    url: Some(track_url(video_id)),
    explicit: has_explicit(item),
    available: item["musicItemRendererDisplayPolicy"].as_str() != Some(GREY_OUT),
    plays,
    tags: None,
  })
}

/// Трек очереди «Похожие» (`playlistPanelVideoRenderer`).
pub fn track_from_panel(p: &Value) -> Option<Track> {
  let video_id = p["videoId"].as_str()?;
  let byline = p["longBylineText"]["runs"].as_array().map(Vec::as_slice).unwrap_or_default();
  let segs = segments(byline);
  let all: Vec<&Value> = byline.iter().collect();
  let artists = artists_in(&all);
  let artist = segs.first().map(|s| seg_text(s)).filter(|t| !t.is_empty()).unwrap_or_else(|| names(&artists));
  Some(Track {
    ref_: format!("yt:{video_id}"),
    title: text(&p["title"]),
    artist,
    artists,
    album: album_in(&all),
    duration_ms: parse_duration(&text(&p["lengthText"])).unwrap_or(0),
    cover_url: best_thumb(&p["thumbnail"]),
    url: Some(track_url(video_id)),
    explicit: has_explicit(p),
    available: true,
    plays: None,
    tags: None,
  })
}

fn tracks_in(v: &Value, fb: &Fallback) -> Vec<Track> {
  find_all(v, "musicResponsiveListItemRenderer").into_iter().filter_map(|i| track_from_item(i, fb)).collect()
}

/// Токен следующей страницы списка (`continuationItemRenderer` или старый `nextContinuationData`).
pub fn continuation(v: &Value) -> Option<String> {
  find_first(v, "continuationCommand")
    .and_then(|c| c["token"].as_str())
    .or_else(|| find_first(v, "nextContinuationData").and_then(|c| c["continuation"].as_str()))
    .map(str::to_owned)
}

/// Похожие треки (`next` с `RDAMVM<id>`), без самого трека.
pub fn next_tracks(v: &Value, seed: &str) -> Vec<Track> {
  find_all(v, "playlistPanelVideoRenderer").into_iter().filter_map(track_from_panel).filter(|t| t.ref_ != format!("yt:{seed}")).collect()
}

/// Продолжение списка: треки и токен следующей страницы.
pub fn continuation_page(v: &Value) -> (Vec<Track>, Option<String>) {
  (tracks_in(v, &Fallback::default()), continuation(v))
}

// ---------- поиск ----------

fn item_browse(item: &Value) -> Option<(&str, &str)> {
  let ep = &item["navigationEndpoint"]["browseEndpoint"];
  let id = ep["browseId"].as_str()?;
  let kind = ep["browseEndpointContextSupportedConfigs"]["browseEndpointContextMusicConfig"]["pageType"].as_str().unwrap_or_default();
  Some((id, kind))
}

fn list_items(v: &Value) -> Vec<&Value> {
  find_all(v, "musicResponsiveListItemRenderer")
}

pub fn search_tracks(v: &Value) -> Vec<Track> {
  tracks_in(v, &Fallback::default())
}

pub fn search_artists(v: &Value) -> Vec<Artist> {
  list_items(v)
    .into_iter()
    .filter_map(|item| {
      let (id, kind) = item_browse(item)?;
      if kind != PAGE_ARTIST && !id.starts_with("UC") {
        return None;
      }
      Some(Artist {
        ref_: format!("yta:{id}"),
        name: seg_text(&flex_runs(item, 0).iter().collect::<Vec<_>>()),
        avatar_url: best_thumb(&item["thumbnail"]),
        followers: None,
        url: Some(artist_url(id)),
      })
    })
    .collect()
}

pub fn search_albums(v: &Value) -> Vec<Album> {
  list_items(v)
    .into_iter()
    .filter_map(|item| {
      let (id, kind) = item_browse(item)?;
      if kind != PAGE_ALBUM {
        return None;
      }
      let col1 = segments(flex_runs(item, 1));
      let runs: Vec<&Value> = flex_runs(item, 1).iter().collect();
      let artists = artists_in(&runs);
      // «Сингл • Lil Peep • 2015»: исполнители — вторая часть
      let artist = col1.get(1).map(|s| seg_text(s)).filter(|t| last_year(t).is_none()).unwrap_or_else(|| names(&artists));
      Some(Album {
        ref_: format!("ytalb:{id}"),
        title: seg_text(&flex_runs(item, 0).iter().collect::<Vec<_>>()),
        artist,
        artists,
        cover_url: best_thumb(&item["thumbnail"]),
        year: col1.last().and_then(|s| last_year(&seg_text(s))),
        released: None,
        track_count: 0,
        url: Some(album_url(id)),
      })
    })
    .collect()
}

/// Число треков из строки вида «500 треков» / «12 songs».
fn track_count_in(segs: &[String]) -> Option<u32> {
  segs
    .iter()
    .find(|s| {
      let l = s.to_lowercase();
      ["трек", "track", "song", "песн", "пісн"].iter().any(|w| l.contains(w))
    })
    .and_then(|s| parse_count(s))
    .map(|n| n as u32)
}

fn strip_vl(id: &str) -> &str {
  id.strip_prefix("VL").unwrap_or(id)
}

pub fn search_playlists(v: &Value) -> Vec<ServicePlaylist> {
  list_items(v)
    .into_iter()
    .filter_map(|item| {
      let (id, kind) = item_browse(item)?;
      if kind != PAGE_PLAYLIST || id == LIKES_BROWSE_ID {
        return None;
      }
      let col1: Vec<String> = segments(flex_runs(item, 1)).iter().map(|s| seg_text(s)).collect();
      Some(ServicePlaylist {
        ref_: format!("ytpl:{}", strip_vl(id)),
        title: seg_text(&flex_runs(item, 0).iter().collect::<Vec<_>>()),
        owner: col1.first().cloned().unwrap_or_default(),
        cover_url: best_thumb(&item["thumbnail"]),
        track_count: track_count_in(&col1).unwrap_or(0),
      })
    })
    .collect()
}

// ---------- страницы ----------

/// Страница исполнителя: он сам, «Топ треков», альбомы и синглы, id плейлиста «все треки».
pub struct ArtistParsed {
  pub artist: Artist,
  pub top: Vec<Track>,
  pub albums: Vec<Album>,
  /// Плейлист со всеми треками исполнителя (`OLAK5uy_…`, без `VL`) — для вкладки «Треки».
  pub all_tracks: Option<String>,
}

pub fn artist_page(v: &Value, channel_id: &str) -> Result<ArtistParsed> {
  let header = v["header"]
    .as_object()
    .and_then(|h| h.values().next())
    .ok_or_else(|| anyhow!("YouTube Music: исполнитель не найден"))?;
  let name = text(&header["title"]);
  let me = ArtistRef { ref_: format!("yta:{channel_id}"), name: name.clone(), avatar_url: None };
  let avatar = best_thumb(&v["microformat"]).or_else(|| best_thumb(&header["thumbnail"]));
  let shelf = find_first(v, "musicShelfRenderer");
  let fb = Fallback { artists: vec![me.clone()], ..Fallback::default() };
  let top = shelf.map(|s| tracks_in(&s["contents"], &fb)).unwrap_or_default();
  let all_tracks = shelf
    .and_then(|s| s["bottomEndpoint"]["browseEndpoint"]["browseId"].as_str().or_else(|| s["title"]["runs"][0]["navigationEndpoint"]["browseEndpoint"]["browseId"].as_str()))
    .map(|id| strip_vl(id).to_owned());
  let mut albums: Vec<Album> = Vec::new();
  for item in find_all(v, "musicTwoRowItemRenderer") {
    if let Some(a) = album_from_two_row(item, &me) {
      if !albums.iter().any(|x| x.ref_ == a.ref_) {
        albums.push(a);
      }
    }
  }
  let artist = Artist { ref_: me.ref_.clone(), name, avatar_url: avatar, followers: None, url: Some(artist_url(channel_id)) };
  Ok(ArtistParsed { artist, top, albums, all_tracks })
}

fn album_from_two_row(item: &Value, me: &ArtistRef) -> Option<Album> {
  let run = &item["title"]["runs"][0];
  if page_type(run) != PAGE_ALBUM {
    return None;
  }
  let id = browse_id(run)?;
  Some(Album {
    ref_: format!("ytalb:{id}"),
    title: run["text"].as_str()?.to_owned(),
    artist: me.name.clone(),
    artists: vec![me.clone()],
    cover_url: best_thumb(&item["thumbnailRenderer"]),
    year: last_year(&text(&item["subtitle"])),
    released: None,
    track_count: 0,
    url: Some(album_url(id)),
  })
}

fn header(v: &Value) -> Option<&Value> {
  find_first(v, "musicResponsiveHeaderRenderer").or_else(|| find_first(v, "musicDetailHeaderRenderer"))
}

pub fn album_page(v: &Value, browse_id: &str) -> Result<(Album, Vec<Track>)> {
  let h = header(v).ok_or_else(|| anyhow!("YouTube Music: альбом не найден"))?;
  let title = text(&h["title"]);
  let strap: Vec<&Value> = h["straplineTextOne"]["runs"].as_array().map(|a| a.iter().collect()).unwrap_or_default();
  let artists = artists_in(&strap);
  let artist = Some(text(&h["straplineTextOne"])).filter(|t| !t.is_empty()).unwrap_or_else(|| names(&artists));
  let cover = best_thumb(&h["thumbnail"]);
  let album_ref = AlbumRef { ref_: format!("ytalb:{browse_id}"), title: title.clone() };
  let fb = Fallback { artists: artists.clone(), album: Some(album_ref), cover: cover.clone() };
  let tracks: Vec<Track> = find_all(v, "musicShelfRenderer").into_iter().flat_map(|s| tracks_in(&s["contents"], &fb)).collect();
  let album = Album {
    ref_: format!("ytalb:{browse_id}"),
    title,
    artist,
    artists,
    cover_url: cover,
    year: last_year(&text(&h["subtitle"])),
    released: None,
    track_count: tracks.len() as u32,
    url: Some(album_url(browse_id)),
  };
  Ok((album, tracks))
}

/// Плейлист: шапка, первые треки и токен продолжения.
pub fn playlist_page(v: &Value, list_id: &str) -> Result<(ServicePlaylist, Vec<Track>, Option<String>)> {
  let shelf = find_first(v, "musicPlaylistShelfRenderer").or_else(|| find_first(v, "musicShelfRenderer"));
  let h = header(v);
  if h.is_none() && shelf.is_none() {
    return Err(anyhow!("YouTube Music: плейлист не найден"));
  }
  let empty = Value::Null;
  let h = h.unwrap_or(&empty);
  let tracks = shelf.map(|s| tracks_in(&s["contents"], &Fallback::default())).unwrap_or_default();
  let token = shelf.and_then(|s| continuation(&s["contents"]));
  let owner = h["facepile"]["avatarStackViewModel"]["text"]["content"].as_str().map(str::to_owned).unwrap_or_else(|| text(&h["straplineTextOne"]));
  let second: Vec<String> = h["secondSubtitle"]["runs"]
    .as_array()
    .map(|r| segments(r).iter().map(|s| seg_text(s)).collect())
    .unwrap_or_default();
  let playlist = ServicePlaylist {
    ref_: format!("ytpl:{list_id}"),
    title: text(&h["title"]),
    owner,
    cover_url: best_thumb(&h["thumbnail"]).or_else(|| tracks.first().and_then(|t| t.cover_url.clone())),
    track_count: track_count_in(&second).unwrap_or(tracks.len() as u32),
  };
  Ok((playlist, tracks, token))
}

/// Плейлисты библиотеки (`FEmusic_liked_playlists`) без «Понравившихся» — те идут первой строкой.
pub fn library_playlists(v: &Value) -> Vec<ServicePlaylist> {
  let mut out: Vec<ServicePlaylist> = Vec::new();
  for item in find_all(v, "musicTwoRowItemRenderer") {
    let Some(id) = item["navigationEndpoint"]["browseEndpoint"]["browseId"].as_str() else { continue };
    if !id.starts_with("VL") || id == LIKES_BROWSE_ID {
      continue;
    }
    let sub: Vec<&Value> = item["subtitle"]["runs"].as_array().map(|r| r.iter().collect()).unwrap_or_default();
    let segs: Vec<String> = item["subtitle"]["runs"].as_array().map(|r| segments(r).iter().map(|s| seg_text(s)).collect()).unwrap_or_default();
    let owner = sub.iter().find(|r| is_artist_run(r)).and_then(|r| r["text"].as_str()).map(str::to_owned).unwrap_or_default();
    let p = ServicePlaylist {
      ref_: format!("ytpl:{}", strip_vl(id)),
      title: text(&item["title"]),
      owner,
      cover_url: best_thumb(&item["thumbnailRenderer"]),
      track_count: track_count_in(&segs).unwrap_or(0),
    };
    if !out.iter().any(|x| x.ref_ == p.ref_) {
      out.push(p);
    }
  }
  out
}

// ---------- аккаунт ----------

/// `account/account_menu` → имя и аватар. Нет шапки аккаунта — cookie не подошёл.
pub fn account(v: &Value) -> Result<Account> {
  let h = find_first(v, "activeAccountHeaderRenderer").ok_or_else(|| anyhow!("YouTube Music: cookie не подошёл или устарел — войди заново"))?;
  let name = Some(text(&h["accountName"])).filter(|n| !n.is_empty());
  Ok(Account { name, avatar_url: best_thumb(&h["accountPhoto"]), uid: None, premium: premium(v) })
}

/// YouTube Premium по служебным параметрам ответа (`has_unlimited_entitlement`). Не сказано — None.
pub fn premium(v: &Value) -> Option<bool> {
  let services = v["responseContext"]["serviceTrackingParams"].as_array()?;
  services.iter().flat_map(|s| s["params"].as_array().into_iter().flatten()).find_map(|p| {
    (p["key"].as_str() == Some("has_unlimited_entitlement")).then(|| p["value"].as_str() == Some("True") || p["value"].as_str() == Some("true"))
  })
}

// ---------- поток ----------

/// Аудиодорожка из ответа `player`.
#[derive(Debug, Clone, PartialEq)]
pub struct Format {
  pub itag: u32,
  pub url: String,
  pub mime: String,
  pub bitrate: u64,
}

/// Opus 256 — только с YouTube Premium.
pub const ITAG_OPUS_256: u32 = 774;
pub const ITAG_OPUS_160: u32 = 251;
pub const ITAG_AAC_128: u32 = 140;

/// Аудио с прямой ссылкой. Трек не играется — ошибка с причиной от YouTube.
pub fn player_formats(v: &Value) -> Result<Vec<Format>> {
  let st = &v["playabilityStatus"];
  let status = st["status"].as_str().unwrap_or("UNKNOWN");
  if status != "OK" {
    let reason = st["reason"].as_str().unwrap_or(status);
    return Err(anyhow!("YouTube Music: трек не играется ({reason})"));
  }
  let formats: Vec<Format> = v["streamingData"]["adaptiveFormats"]
    .as_array()
    .into_iter()
    .flatten()
    .filter(|f| f["mimeType"].as_str().is_some_and(|m| m.starts_with("audio/")))
    .filter_map(|f| {
      Some(Format {
        itag: f["itag"].as_u64()? as u32,
        url: f["url"].as_str()?.to_owned(),
        mime: f["mimeType"].as_str()?.to_owned(),
        bitrate: f["bitrate"].as_u64().unwrap_or(0),
      })
    })
    .collect();
  if formats.is_empty() {
    return Err(anyhow!("YouTube Music: у трека нет аудио с прямой ссылкой"));
  }
  Ok(formats)
}

/// «Высокое» — Opus 256 (Premium), иначе Opus 160; «Обычное» — AAC 128. Нет нужной — лучшая из есть.
pub fn pick_format(formats: &[Format], high: bool) -> Option<&Format> {
  let order: &[u32] = if high { &[ITAG_OPUS_256, ITAG_OPUS_160, ITAG_AAC_128] } else { &[ITAG_AAC_128, ITAG_OPUS_160] };
  order.iter().find_map(|i| formats.iter().find(|f| f.itag == *i)).or_else(|| formats.iter().max_by_key(|f| f.bitrate))
}

/// Плашка качества в плеере.
pub fn quality_label(f: &Format) -> String {
  match f.itag {
    ITAG_OPUS_256 => "Opus 256".into(),
    ITAG_OPUS_160 => "Opus 160".into(),
    ITAG_AAC_128 => "AAC 128".into(),
    _ => {
      let codec = if f.mime.contains("opus") { "Opus" } else { "AAC" };
      format!("{codec} {}", f.bitrate / 1000)
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn fx(name: &str) -> Value {
    let raw = match name {
      "search_songs" => include_str!("fixtures/search_songs.json"),
      "search_artists" => include_str!("fixtures/search_artists.json"),
      "search_albums" => include_str!("fixtures/search_albums.json"),
      "search_playlists" => include_str!("fixtures/search_playlists.json"),
      "artist" => include_str!("fixtures/artist.json"),
      "album" => include_str!("fixtures/album.json"),
      "playlist" => include_str!("fixtures/playlist.json"),
      "playlist_cont" => include_str!("fixtures/playlist_cont.json"),
      "next" => include_str!("fixtures/next.json"),
      "player_ios" => include_str!("fixtures/player_ios.json"),
      other => panic!("нет фикстуры {other}"),
    };
    serde_json::from_str(raw).expect("фикстура — JSON")
  }

  #[test]
  fn search_songs_parse_track_fields() {
    let tracks = search_tracks(&fx("search_songs"));
    assert_eq!(tracks.len(), 4);
    let t = &tracks[0];
    assert_eq!(t.ref_, "yt:q7mwXbOw58g");
    assert_eq!(t.title, "Star Shopping");
    assert_eq!(t.artist, "Cut-Off");
    assert_eq!(t.artists[0].ref_, "yta:UCIzdQrjdn8XVyWI4p7N55SA");
    assert_eq!(t.album.as_ref().map(|a| a.ref_.as_str()), Some("ytalb:MPREb_2EPG9Eh31Fr"));
    assert_eq!(t.duration_ms, 146_000);
    assert_eq!(t.plays, Some(1200));
    assert_eq!(t.url.as_deref(), Some("https://music.youtube.com/watch?v=q7mwXbOw58g"));
    assert!(t.cover_url.as_deref().unwrap().contains("=w544-h544"));
    let peep = &tracks[1];
    assert_eq!((peep.artist.as_str(), peep.duration_ms, peep.plays), ("Lil Peep", 245_000, Some(251_000_000)));
    assert_eq!(peep.album.as_ref().unwrap().title, "Come Over When You're Sober, Pt. 2");
  }

  #[test]
  fn search_artists_albums_playlists() {
    let artists = search_artists(&fx("search_artists"));
    assert_eq!(artists[0].ref_, "yta:UCxcyWcW0kZFGRyetDHr3UuA");
    assert_eq!(artists[0].name, "LiL PEEP");
    assert_eq!(artists.len(), 3);
    let albums = search_albums(&fx("search_albums"));
    assert_eq!(albums[0].ref_, "ytalb:MPREb_onqktzsmdxw");
    assert_eq!((albums[0].artist.as_str(), albums[0].year), ("Lil Peep", Some(2015)));
    assert_eq!(albums[1].artist, "Lil Peep и ILOVEMAKONNEN");
    assert!(albums[0].cover_url.as_deref().unwrap().contains("544"));
    let lists = search_playlists(&fx("search_playlists"));
    assert_eq!(lists[0].ref_, "ytpl:PLFQ6IvlXwKtgvr-BripRdnRS2cediaKA6");
    assert_eq!(lists[0].owner, "metlast");
    assert!(lists[0].cover_url.as_deref().unwrap().starts_with("https://i.ytimg.com/"));
  }

  #[test]
  fn artist_page_header_top_albums() {
    let p = artist_page(&fx("artist"), "UCxcyWcW0kZFGRyetDHr3UuA").unwrap();
    assert_eq!(p.artist.name, "LiL PEEP");
    assert_eq!(p.artist.ref_, "yta:UCxcyWcW0kZFGRyetDHr3UuA");
    assert!(p.artist.avatar_url.as_deref().unwrap().contains("=w544-h544"));
    assert_eq!(p.top.len(), 3);
    assert_eq!(p.top[0].ref_, "yt:DmhdcDQt7Dk");
    assert_eq!(p.top[0].artist, "Lil Peep и XXXTENTACION");
    assert_eq!(p.top[0].album.as_ref().map(|a| a.ref_.as_str()), Some("ytalb:MPREb_K4OwytHjekv"));
    assert_eq!(p.all_tracks.as_deref(), Some("OLAK5uy_m2QvXUMCoZqqmp1JMnlY_dncmcaLj2ehM"));
    let diamonds = p.albums.iter().find(|a| a.ref_ == "ytalb:MPREb_nEhq7bxafxu").unwrap();
    assert_eq!((diamonds.title.as_str(), diamonds.year, diamonds.artist.as_str()), ("DIAMONDS", Some(2023), "LiL PEEP"));
  }

  #[test]
  fn album_page_fills_tracks_from_header() {
    let (album, tracks) = album_page(&fx("album"), "MPREb_onqktzsmdxw").unwrap();
    assert_eq!(album.title, "The Way I See Things");
    assert_eq!((album.artist.as_str(), album.year, album.track_count), ("Lil Peep", Some(2015), 1));
    assert_eq!(album.artists[0].ref_, "yta:UCxcyWcW0kZFGRyetDHr3UuA");
    let t = &tracks[0];
    assert_eq!((t.ref_.as_str(), t.duration_ms, t.artist.as_str()), ("yt:C4gVlt46voo", 131_000, "Lil Peep"));
    assert_eq!(t.album.as_ref().unwrap().ref_, "ytalb:MPREb_onqktzsmdxw");
    assert_eq!(t.cover_url, album.cover_url);
  }

  #[test]
  fn playlist_page_and_continuation() {
    let (pl, tracks, token) = playlist_page(&fx("playlist"), "PLwNv9Hhd8gZjNoQdpd2kBa3fwXNeJjzDX").unwrap();
    assert_eq!(pl.title, "500 Greatest Love Songs Of All Time");
    assert_eq!((pl.owner.as_str(), pl.track_count), ("Inko Infinity2", 500));
    assert!(pl.cover_url.as_deref().unwrap().ends_with("=s544"));
    assert_eq!(tracks.len(), 3);
    assert_eq!((tracks[0].title.as_str(), tracks[0].artist.as_str(), tracks[0].duration_ms), ("I Will Always Love You", "Whitney Houston", 274_000));
    assert!(token.is_some());
    let (more, next) = continuation_page(&fx("playlist_cont"));
    assert_eq!(more.len(), 3);
    assert_eq!(more[0].ref_, "yt:qxZInIyOBXk");
    assert!(next.is_some());
  }

  #[test]
  fn next_skips_seed() {
    let t = next_tracks(&fx("next"), "q7mwXbOw58g");
    assert!(!t.is_empty());
    assert!(t.iter().all(|t| t.ref_ != "yt:q7mwXbOw58g"));
    let first = &t[0];
    assert_eq!((first.ref_.as_str(), first.title.as_str(), first.duration_ms), ("yt:8aaoYbPXOPs", "Fuck Love", 147_000));
    assert_eq!(first.artist, "XXXTENTACION и Trippie Redd");
    assert_eq!(first.album.as_ref().unwrap().ref_, "ytalb:MPREb_Tr9YVfRfip1");
  }

  #[test]
  fn player_picks_quality() {
    let f = player_formats(&fx("player_ios")).unwrap();
    assert!(f.iter().all(|f| f.mime.starts_with("audio/")));
    assert_eq!(pick_format(&f, false).map(|f| f.itag), Some(ITAG_AAC_128));
    assert_eq!(pick_format(&f, true).map(|f| f.itag), Some(ITAG_OPUS_160));
    assert_eq!(quality_label(pick_format(&f, true).unwrap()), "Opus 160");
    let premium = vec![Format { itag: 774, url: "u".into(), mime: "audio/webm; codecs=\"opus\"".into(), bitrate: 256_000 }];
    assert_eq!(pick_format(&premium, true).map(|f| f.itag), Some(ITAG_OPUS_256));
    // нет AAC — «Обычное» берёт то, что есть
    assert_eq!(pick_format(&premium, false).map(|f| f.itag), Some(ITAG_OPUS_256));
  }

  #[test]
  fn player_error_has_reason() {
    let v = serde_json::json!({"playabilityStatus": {"status": "LOGIN_REQUIRED", "reason": "Sign in to confirm you're not a bot"}});
    let e = player_formats(&v).unwrap_err().to_string();
    assert_eq!(e, "YouTube Music: трек не играется (Sign in to confirm you're not a bot)");
    let empty = serde_json::json!({"playabilityStatus": {"status": "OK"}, "streamingData": {"adaptiveFormats": []}});
    assert!(player_formats(&empty).is_err());
  }

  #[test]
  fn account_and_premium() {
    let v = serde_json::json!({
      "responseContext": {"serviceTrackingParams": [{"service": "GFEEDBACK", "params": [{"key": "has_unlimited_entitlement", "value": "True"}]}]},
      "actions": [{"openPopupAction": {"popup": {"multiPageMenuRenderer": {"header": {"activeAccountHeaderRenderer": {
        "accountName": {"runs": [{"text": "Folzy"}]},
        "accountPhoto": {"thumbnails": [{"url": "https://yt3.ggpht.com/a=s48", "width": 48}, {"url": "https://yt3.ggpht.com/a=s88", "width": 88}]}
      }}}}}}]
    });
    let a = account(&v).unwrap();
    assert_eq!((a.name.as_deref(), a.premium), (Some("Folzy"), Some(true)));
    assert_eq!(a.avatar_url.as_deref(), Some("https://yt3.ggpht.com/a=s544"));
    assert!(account(&serde_json::json!({})).is_err());
    assert_eq!(premium(&serde_json::json!({})), None);
  }

  #[test]
  fn library_skips_likes_and_dupes() {
    let item = |id: &str, title: &str| {
      serde_json::json!({"musicTwoRowItemRenderer": {
        "title": {"runs": [{"text": title}]},
        "subtitle": {"runs": [{"text": "Плейлист"}, {"text": " • "}, {"text": "Folzy", "navigationEndpoint": {"browseEndpoint": {"browseId": "UC1", "browseEndpointContextSupportedConfigs": {"browseEndpointContextMusicConfig": {"pageType": "MUSIC_PAGE_TYPE_USER_CHANNEL"}}}}}, {"text": " • "}, {"text": "12 треков"}]},
        "navigationEndpoint": {"browseEndpoint": {"browseId": id}}
      }})
    };
    let v = serde_json::json!({"items": [item("VLLM", "Понравившиеся"), item("VLPL1", "Мой"), item("VLPL1", "Мой"), item("FEmusic_x", "не плейлист")]});
    let got = library_playlists(&v);
    assert_eq!(got.len(), 1);
    assert_eq!((got[0].ref_.as_str(), got[0].owner.as_str(), got[0].track_count), ("ytpl:PL1", "Folzy", 12));
  }

  #[test]
  fn helpers() {
    assert_eq!(parse_duration("1:02:03"), Some(3_723_000));
    assert_eq!(parse_duration("abc"), None);
    assert_eq!(parse_count("61,5\u{a0}млн слушателей"), Some(61_500_000));
    assert_eq!(parse_count("422 тыс. просмотров"), Some(422_000));
    assert_eq!(parse_count("1,234 plays"), Some(1234));
    assert_eq!(parse_count("нет"), None);
    assert_eq!(last_year("Сингл • 2015"), Some(2015));
    assert_eq!(last_year("12 треков"), None);
    assert_eq!(upscale("https://lh3.googleusercontent.com/x=w60-h60-l90-rj"), "https://lh3.googleusercontent.com/x=w544-h544-l90-rj");
    assert_eq!(upscale("https://i.ytimg.com/vi/x/hq.jpg?a=w60-h60"), "https://i.ytimg.com/vi/x/hq.jpg?a=w60-h60");
  }
}
