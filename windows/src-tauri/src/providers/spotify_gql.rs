//! Spotify через внутренний GraphQL веб-плеера («Pathfinder», `api-partner.spotify.com`): с декабря 2025
//! открытый Web API (`api.spotify.com/v1`) на токен веб-плеера отвечает 429 на всё подряд, а сам веб-плеер
//! ходит сюда. Запросы — «сохранённые» (persisted queries): имя операции + sha256 её текста. Хэши Spotify
//! меняет с выпусками веб-плеера: вшиты проверенные 2026-11-24, устаревший хэш сервер отвергает (HTTP 412
//! «Invalid query hash») — тогда Sonar сам скачивает скрипт веб-плеера и вынимает свежие хэши (`refresh`).
//!
//! Здесь — операции, хэши и разбор ответов в наши `Track` / `Album` / …; сеть и токен — в `spotify.rs`.
//! Образцы ответов — `fixtures/spotify/` (публичные сняты вживую анонимным токеном, ответы аккаунта
//! собраны по коду веб-плеера: анонимно их не получить).

use super::{Account, Album, AlbumRef, Artist, ArtistRef, ServicePlaylist, Track, UA};
use regex::Regex;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::{LazyLock, RwLock};
use std::time::{Duration, Instant};

pub const ENDPOINT: &str = "https://api-partner.spotify.com/pathfinder/v2/query";
const WEB_PLAYER: &str = "https://open.spotify.com/";
/// Пересобирать хэши из веб-плеера не чаще: скрипт весит ~5 МБ.
const RESCAN_EVERY: Duration = Duration::from_secs(10 * 60);
/// Максимум строк на страницу у Pathfinder.
pub const PAGE: u32 = 50;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Op {
  Profile,
  Account,
  SearchTracks,
  SearchDesktop,
  LibraryTracks,
  LibraryV3,
  Playlist,
  ArtistOverview,
  Discography,
  Album,
}

impl Op {
  pub const ALL: [Op; 10] = [
    Op::Profile,
    Op::Account,
    Op::SearchTracks,
    Op::SearchDesktop,
    Op::LibraryTracks,
    Op::LibraryV3,
    Op::Playlist,
    Op::ArtistOverview,
    Op::Discography,
    Op::Album,
  ];

  pub fn name(self) -> &'static str {
    match self {
      Op::Profile => "profileAttributes",
      Op::Account => "accountAttributes",
      Op::SearchTracks => "searchTracks",
      Op::SearchDesktop => "searchDesktop",
      Op::LibraryTracks => "fetchLibraryTracks",
      Op::LibraryV3 => "libraryV3",
      Op::Playlist => "fetchPlaylist",
      Op::ArtistOverview => "queryArtistOverview",
      Op::Discography => "queryArtistDiscographyAll",
      Op::Album => "getAlbum",
    }
  }

  /// Вшитый хэш — из веб-плеера `web-player.e2037ec6.js` и его кусков, проверен 2026-11-24.
  fn builtin(self) -> &'static str {
    match self {
      Op::Profile => "08ffb4730af3746e04a8301396f20875dbbce10c75243803091a9274eacc8ac0",
      Op::Account => "be4ce359daee01463ddb8e77536220e108e3d28105e12199f244d7a5954e9d14",
      Op::SearchTracks => "b02683192a98dde7966b5e6655a79eeb62713eab703eda9902c932818dd52751",
      Op::SearchDesktop => "eef7cc54888d91bdd6802623477873caa3948ae173a0c34fd86827b267e94c03",
      Op::LibraryTracks => "087278b20b743578a6262c2b0b4bcd20d879c503cc359a2285baf083ef944240",
      Op::LibraryV3 => "390c78e5b951029bad359785e69b07b536a509c581cbcd0aded5e5067f187455",
      Op::Playlist => "21ea11a6ac75a5f3e01fd365d29c18e0a4a8b7dc09f89bbb5d73910190c6acaf",
      Op::ArtistOverview => "eafb1620d783ece118e72fbfede2b0064483e029d3c1aafafa1c2de0e25a89e7",
      Op::Discography => "5e07d323febb57b4a56a42abbf781490e58764aa45feb6e3dc0591564fc56599",
      Op::Album => "0b6ce3511e1b02e4a40fa95440f992acbe85080eb308af9194322d708fc1914f",
    }
  }

  /// Ленивый кусок веб-плеера, где лежит операция (в основном скрипте её нет).
  fn chunk(self) -> Option<&'static str> {
    match self {
      Op::SearchTracks | Op::SearchDesktop => Some("xpui-routes-search"),
      Op::Discography => Some("xpui-routes-artist"),
      _ => None,
    }
  }
}

/// Тело POST-запроса операции.
pub fn body(op: Op, hash: &str, variables: Value) -> Value {
  json!({
    "variables": variables,
    "operationName": op.name(),
    "extensions": { "persistedQuery": { "version": 1, "sha256Hash": hash } },
  })
}

// --- хэши ---

/// Текущие хэши: вшитые, пока веб-плеер не дал свежие.
pub struct Hashes {
  map: RwLock<HashMap<Op, String>>,
  scanned: tokio::sync::Mutex<Option<Instant>>,
}

pub static HASHES: LazyLock<Hashes> = LazyLock::new(Hashes::default);

impl Default for Hashes {
  fn default() -> Self {
    Self { map: RwLock::new(Op::ALL.iter().map(|op| (*op, op.builtin().to_owned())).collect()), scanned: tokio::sync::Mutex::new(None) }
  }
}

impl Hashes {
  pub fn get(&self, op: Op) -> String {
    let map = self.map.read().unwrap_or_else(|e| e.into_inner());
    map.get(&op).cloned().unwrap_or_else(|| op.builtin().to_owned())
  }

  /// Принять найденные в скриптах хэши; `true` — что-то сменилось.
  pub fn adopt(&self, found: &HashMap<String, String>) -> bool {
    let mut map = self.map.write().unwrap_or_else(|e| e.into_inner());
    let mut changed = false;
    for op in Op::ALL {
      if let Some(h) = found.get(op.name()).filter(|h| map.get(&op) != Some(h)) {
        map.insert(op, h.clone());
        changed = true;
      }
    }
    changed
  }

  /// Скачать веб-плеер и вынуть свежие хэши (не чаще `RESCAN_EVERY`). `true` — хэш `op` сменился.
  pub async fn refresh(&self, http: &reqwest::Client, op: Op) -> bool {
    let mut scanned = self.scanned.lock().await;
    if scanned.is_some_and(|at| at.elapsed() < RESCAN_EVERY) {
      return false;
    }
    *scanned = Some(Instant::now());
    let before = self.get(op);
    match scan_web_player(http).await {
      Ok(found) => {
        self.adopt(&found);
        let changed = self.get(op) != before;
        let note = if changed { "хэш сменился" } else { "хэш тот же" };
        crate::crashlog::write("info", &format!("Spotify: хэши веб-плеера перечитаны ({} операций), {}: {note}", found.len(), op.name()));
        changed
      }
      Err(e) => {
        crate::crashlog::write("warn", &format!("Spotify: хэши веб-плеера не прочитались: {e}"));
        false
      }
    }
  }
}

async fn text(http: &reqwest::Client, url: &str) -> anyhow::Result<String> {
  let r = http.get(url).header("User-Agent", UA).send().await?;
  if !r.status().is_success() {
    anyhow::bail!("HTTP {}", r.status().as_u16());
  }
  Ok(r.text().await?)
}

/// open.spotify.com → основной скрипт веб-плеера → его ленивые куски с поиском и исполнителем → хэши.
async fn scan_web_player(http: &reqwest::Client) -> anyhow::Result<HashMap<String, String>> {
  let html = text(http, WEB_PLAYER).await?;
  let mut found = HashMap::new();
  let mut main = None;
  for url in script_urls(&html) {
    let js = text(http, &url).await?;
    found.extend(scan(&js));
    if url.contains("/web-player.") {
      main = Some((url, js));
    }
  }
  let (main_url, main_js) = main.ok_or_else(|| anyhow::anyhow!("нет основного скрипта"))?;
  let mut chunks: Vec<&str> = Op::ALL.iter().filter_map(|op| op.chunk()).collect();
  chunks.dedup();
  for name in chunks {
    if let Some(url) = chunk_url(&main_url, &main_js, name) {
      found.extend(scan(&text(http, &url).await?));
    }
  }
  Ok(found)
}

static SCRIPT_RE: LazyLock<Regex> =
  LazyLock::new(|| Regex::new(r#"https://open\.spotifycdn\.com/cdn/build/web-player/[A-Za-z0-9_~.\-]+\.js"#).unwrap());
static OP_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#""([A-Za-z0-9_]+)",\s*"(?:query|mutation)",\s*"([0-9a-f]{64})""#).unwrap());
/// Карта ленивых кусков webpack: `({id:"имя",…})[e]||e)+"."+({id:"хэш",…})[e]+".js"`.
static CHUNK_RE: LazyLock<Regex> =
  LazyLock::new(|| Regex::new(r#"\(\{([^}]*)\}\)\[e\]\|\|e\)\+"\."\+\(\{([^}]*)\}\)\[e\]\+"\.js""#).unwrap());
static PAIR_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"(\d+):"([^"]+)""#).unwrap());

/// Адреса скриптов веб-плеера на странице (без повторов, по порядку).
pub fn script_urls(html: &str) -> Vec<String> {
  let mut out: Vec<String> = Vec::new();
  for m in SCRIPT_RE.find_iter(html) {
    if !out.iter().any(|u| u == m.as_str()) {
      out.push(m.as_str().to_owned());
    }
  }
  out
}

/// Пары «операция → хэш» из скрипта.
pub fn scan(js: &str) -> HashMap<String, String> {
  OP_RE.captures_iter(js).map(|c| (c[1].to_owned(), c[2].to_owned())).collect()
}

/// Адрес ленивого куска `name` по карте в основном скрипте.
pub fn chunk_url(main_url: &str, main_js: &str, name: &str) -> Option<String> {
  let caps = CHUNK_RE.captures(main_js)?;
  let pairs = |s: &str| PAIR_RE.captures_iter(s).map(|c| (c[1].to_owned(), c[2].to_owned())).collect::<HashMap<_, _>>();
  let names = pairs(&caps[1]);
  let hashes = pairs(&caps[2]);
  let id = names.iter().find(|(_, n)| n.as_str() == name)?.0;
  let base = &main_url[..main_url.rfind('/')? + 1];
  Some(format!("{base}{name}.{}.js", hashes.get(id)?))
}

// --- разбор ответов ---

/// `spotify:track:ID` → `ID` (только нужного вида).
pub fn id_of<'a>(uri: &'a str, kind: &str) -> Option<&'a str> {
  let rest = uri.strip_prefix("spotify:")?.strip_prefix(kind)?.strip_prefix(':')?;
  (!rest.is_empty()).then_some(rest)
}

fn web_url(kind: &str, id: &str) -> String {
  format!("https://open.spotify.com/{kind}/{id}")
}

/// Самая крупная картинка из `sources` (размера может не быть — тогда последняя: Spotify кладёт 640 в конец).
pub fn best_source(sources: &Value) -> Option<String> {
  sources
    .as_array()?
    .iter()
    .enumerate()
    .filter_map(|(i, s)| Some((s["width"].as_u64().unwrap_or(0), i, s["url"].as_str()?)))
    .max_by_key(|(w, i, _)| (*w, *i))
    .map(|(_, _, u)| u.to_owned())
}

fn artist_refs(v: &Value) -> Vec<ArtistRef> {
  let items = v["artists"]["items"].as_array().map(Vec::as_slice).unwrap_or_default();
  items
    .iter()
    .filter_map(|a| {
      let id = id_of(a["uri"].as_str()?, "artist")?;
      Some(ArtistRef { ref_: format!("spa:{id}"), name: a["profile"]["name"].as_str()?.to_owned(), avatar_url: None })
    })
    .collect()
}

fn joined(artists: &[ArtistRef]) -> String {
  artists.iter().map(|a| a.name.as_str()).collect::<Vec<_>>().join(", ")
}

/// Альбом, к которому относится трек (у треков альбома своего `albumOfTrack` нет — его дают снаружи).
#[derive(Debug, Clone, Default)]
pub struct AlbumCtx {
  pub album: Option<AlbumRef>,
  pub cover: Option<String>,
}

impl AlbumCtx {
  pub fn of(album: &Album) -> Self {
    Self { album: Some(AlbumRef { ref_: album.ref_.clone(), title: album.title.clone() }), cover: album.cover_url.clone() }
  }
}

/// Трек из `Track` (`data` обёртки). Не трек (эпизод, «не найдено», локальный файл) — `None`.
pub fn track(v: &Value, outer: Option<&AlbumCtx>) -> Option<Track> {
  if v["__typename"].as_str().is_some_and(|t| t != "Track") {
    return None;
  }
  let id = id_of(v["uri"].as_str()?, "track")?;
  let artists = artist_refs(v);
  let alb = &v["albumOfTrack"];
  let own = alb["uri"].as_str().and_then(|u| id_of(u, "album")).map(|a| AlbumRef {
    ref_: format!("spalb:{a}"),
    title: alb["name"].as_str().unwrap_or("").to_owned(),
  });
  let (album, cover) = match outer {
    Some(ctx) if own.is_none() => (ctx.album.clone(), ctx.cover.clone()),
    _ => (own, best_source(&alb["coverArt"]["sources"])),
  };
  Some(Track {
    ref_: format!("sp:{id}"),
    title: v["name"].as_str()?.to_owned(),
    artist: joined(&artists),
    artists,
    album,
    duration_ms: v["duration"]["totalMilliseconds"].as_u64().unwrap_or(0),
    cover_url: cover,
    url: Some(web_url("track", id)),
    explicit: v["contentRating"]["label"].as_str() == Some("EXPLICIT"),
    // играет через резервный сервис — для очереди трек доступен
    available: true,
    plays: None,
    tags: None,
  })
}

/// Год и полная дата из `date` (`year` или `isoString` с точностью `DAY`).
fn dates(v: &Value) -> (Option<u32>, Option<String>) {
  let iso = v["isoString"].as_str();
  let year = v["year"].as_u64().map(|y| y as u32).or_else(|| iso?.get(..4)?.parse().ok());
  let day = iso.filter(|_| v["precision"].as_str() == Some("DAY")).and_then(|s| s.get(..10)).map(str::to_owned);
  (year, day)
}

pub fn album(v: &Value) -> Option<Album> {
  if v["__typename"].as_str().is_some_and(|t| t != "Album") {
    return None;
  }
  let id = id_of(v["uri"].as_str()?, "album")?;
  let artists = artist_refs(v);
  let (year, released) = dates(&v["date"]);
  let count = v["tracks"]["totalCount"].as_u64().or(v["tracksV2"]["totalCount"].as_u64()).unwrap_or(0);
  Some(Album {
    ref_: format!("spalb:{id}"),
    title: v["name"].as_str()?.to_owned(),
    artist: joined(&artists),
    artists,
    cover_url: best_source(&v["coverArt"]["sources"]),
    year,
    released,
    track_count: count as u32,
    url: Some(web_url("album", id)),
  })
}

pub fn artist(v: &Value) -> Option<Artist> {
  if v["__typename"].as_str().is_some_and(|t| t != "Artist") {
    return None;
  }
  let id = id_of(v["uri"].as_str()?, "artist")?;
  Some(Artist {
    ref_: format!("spa:{id}"),
    name: v["profile"]["name"].as_str()?.to_owned(),
    avatar_url: best_source(&v["visuals"]["avatarImage"]["sources"]),
    followers: v["stats"]["followers"].as_u64(),
    url: Some(web_url("artist", id)),
  })
}

pub fn playlist(v: &Value) -> Option<ServicePlaylist> {
  if v["__typename"].as_str().is_some_and(|t| t != "Playlist") {
    return None;
  }
  let id = id_of(v["uri"].as_str()?, "playlist")?;
  let owner = &v["ownerV2"]["data"];
  Some(ServicePlaylist {
    ref_: format!("sppl:{id}"),
    title: v["name"].as_str()?.to_owned(),
    owner: owner["name"].as_str().or(owner["username"].as_str()).unwrap_or("").to_owned(),
    cover_url: v["images"]["items"].as_array().and_then(|a| a.iter().find_map(|i| best_source(&i["sources"]))),
    track_count: v["content"]["totalCount"].as_u64().unwrap_or(0) as u32,
  })
}

/// Профиль (`profileAttributes`) + подписка (`accountAttributes`, может не прийти — тогда «не знаем»).
pub fn account(profile: &Value, acc: Option<&Value>) -> Account {
  let p = &profile["me"]["profile"];
  Account {
    name: p["name"].as_str().or(p["username"].as_str()).map(str::to_owned),
    avatar_url: best_source(&p["avatar"]["sources"]),
    uid: p["username"].as_str().map(str::to_owned),
    premium: acc.and_then(|a| a["me"]["account"]["product"].as_str()).map(|p| p.eq_ignore_ascii_case("premium")),
  }
}

/// Элементы списка и сколько их всего: `{items, totalCount}`.
pub fn page<'a>(v: &'a Value) -> (&'a [Value], Option<u64>) {
  (v["items"].as_array().map(Vec::as_slice).unwrap_or_default(), v["totalCount"].as_u64())
}

/// Треки поиска (`searchTracks` / `searchDesktop`): `searchV2.tracksV2.items[].item.data`.
pub fn search_tracks(data: &Value) -> Vec<Track> {
  page(&data["searchV2"]["tracksV2"]).0.iter().filter_map(|i| track(&i["item"]["data"], None)).collect()
}

/// Исполнители, альбомы и плейлисты из `searchDesktop`.
pub fn search_more(data: &Value) -> (Vec<Artist>, Vec<Album>, Vec<ServicePlaylist>) {
  let s = &data["searchV2"];
  let pick = |key: &str| page(&s[key]).0.iter().map(|i| &i["data"]).collect::<Vec<_>>();
  (
    pick("artists").into_iter().filter_map(artist).collect(),
    pick("albumsV2").into_iter().filter_map(album).collect(),
    pick("playlists").into_iter().filter_map(playlist).collect(),
  )
}

/// Страница «Любимых»: `me.library.tracks.items[].track.data`.
pub fn library_tracks(data: &Value) -> (Vec<Track>, usize, Option<u64>) {
  let (items, total) = page(&data["me"]["library"]["tracks"]);
  (items.iter().filter_map(|i| track(&i["track"]["data"], None)).collect(), items.len(), total)
}

/// Страница библиотеки (только плейлисты): `me.libraryV3.items[].item.data`.
pub fn library_playlists(data: &Value) -> (Vec<ServicePlaylist>, usize, Option<u64>) {
  let (items, total) = page(&data["me"]["libraryV3"]);
  let lists = items
    .iter()
    .filter(|i| i["item"]["__typename"].as_str() == Some("PlaylistResponseWrapper"))
    .filter_map(|i| playlist(&i["item"]["data"]))
    .collect();
  (lists, items.len(), total)
}

/// Страница плейлиста: шапка и треки `playlistV2.content.items[].itemV2.data`.
pub fn playlist_page(data: &Value) -> (Option<ServicePlaylist>, Vec<Track>, usize, Option<u64>) {
  let p = &data["playlistV2"];
  let (items, total) = page(&p["content"]);
  let tracks = items.iter().filter_map(|i| track(&i["itemV2"]["data"], None)).collect();
  (playlist(p), tracks, items.len(), total)
}

/// Исполнитель и популярные треки: `artistUnion` + `discography.topTracks.items[].track`.
pub fn artist_overview(data: &Value) -> Option<(Artist, Vec<Track>)> {
  let a = &data["artistUnion"];
  let top = page(&a["discography"]["topTracks"]).0.iter().filter_map(|i| track(&i["track"], None)).collect();
  Some((artist(a)?, top))
}

/// Страница дискографии (`all`): релизы по группам; сборники пропускаем (как `include_groups=album,single`).
pub fn discography(data: &Value, artist: Option<&ArtistRef>) -> (Vec<Album>, usize, Option<u64>) {
  let (groups, total) = page(&data["artistUnion"]["discography"]["all"]);
  let albums = groups
    .iter()
    .flat_map(|g| page(&g["releases"]).0)
    .filter(|r| r["type"].as_str() != Some("COMPILATION"))
    .filter_map(|r| {
      let mut a = album(r)?;
      if a.artists.is_empty() {
        if let Some(by) = artist {
          a.artists = vec![by.clone()];
          a.artist = by.name.clone();
        }
      }
      Some(a)
    })
    .collect();
  (albums, groups.len(), total)
}

/// Альбом и страница его треков: `albumUnion` + `tracksV2.items[].track`.
pub fn album_page(data: &Value) -> Option<(Album, Vec<Track>, usize, Option<u64>)> {
  let u = &data["albumUnion"];
  let head = album(u)?;
  let ctx = AlbumCtx::of(&head);
  let (items, total) = page(&u["tracksV2"]);
  let tracks = items.iter().filter_map(|i| track(&i["track"], Some(&ctx))).collect();
  Some((head, tracks, items.len(), total))
}

#[cfg(test)]
mod tests {
  use super::*;

  fn fx(name: &str) -> Value {
    let raw = match name {
      "search_desktop" => include_str!("fixtures/spotify/search_desktop.json"),
      "search_tracks" => include_str!("fixtures/spotify/search_tracks.json"),
      "artist_overview" => include_str!("fixtures/spotify/artist_overview.json"),
      "discography_all" => include_str!("fixtures/spotify/discography_all.json"),
      "album" => include_str!("fixtures/spotify/album.json"),
      "playlist" => include_str!("fixtures/spotify/playlist.json"),
      "library_tracks" => include_str!("fixtures/spotify/library_tracks.json"),
      "library_v3" => include_str!("fixtures/spotify/library_v3.json"),
      "profile" => include_str!("fixtures/spotify/profile.json"),
      "account" => include_str!("fixtures/spotify/account.json"),
      _ => unreachable!(),
    };
    serde_json::from_str::<Value>(raw).unwrap()["data"].clone()
  }

  #[test]
  fn ids_from_uris() {
    assert_eq!(id_of("spotify:track:5Z01UMMf7V1o0MzF86s6WJ", "track"), Some("5Z01UMMf7V1o0MzF86s6WJ"));
    assert_eq!(id_of("spotify:album:x", "track"), None);
    assert_eq!(id_of("spotify:track:", "track"), None);
    assert_eq!(id_of("spotify:trackx:1", "track"), None);
  }

  #[test]
  fn biggest_image_even_without_sizes() {
    let sized = json!([{ "url": "a", "width": 300 }, { "url": "b", "width": 64 }, { "url": "c", "width": 640 }]);
    assert_eq!(best_source(&sized).as_deref(), Some("c"));
    let bare = json!([{ "url": "300" }, { "url": "64" }, { "url": "640" }]);
    assert_eq!(best_source(&bare).as_deref(), Some("640"));
    assert_eq!(best_source(&json!([])), None);
  }

  #[test]
  fn search_tracks_live_shape() {
    let tracks = search_tracks(&fx("search_tracks"));
    assert_eq!(tracks.len(), 2);
    let t = &tracks[0];
    assert!(t.ref_.starts_with("sp:") && t.ref_.len() > 10);
    assert!(!t.title.is_empty() && !t.artist.is_empty());
    assert!(t.duration_ms > 60_000);
    assert!(t.album.as_ref().is_some_and(|a| a.ref_.starts_with("spalb:") && !a.title.is_empty()));
    assert!(t.cover_url.as_deref().is_some_and(|u| u.contains("b273")), "640-я обложка");
    assert!(t.url.as_deref().is_some_and(|u| u.starts_with("https://open.spotify.com/track/")));
  }

  #[test]
  fn search_desktop_all_sections() {
    let data = fx("search_desktop");
    assert!(!search_tracks(&data).is_empty());
    let (artists, albums, playlists) = search_more(&data);
    assert_eq!(artists[0].name, "Eminem");
    assert!(artists[0].avatar_url.is_some());
    assert!(albums[0].ref_.starts_with("spalb:") && albums[0].year.is_some() && !albums[0].artist.is_empty());
    assert!(playlists[0].ref_.starts_with("sppl:") && !playlists[0].owner.is_empty() && playlists[0].cover_url.is_some());
  }

  #[test]
  fn artist_overview_and_top_tracks() {
    let (a, top) = artist_overview(&fx("artist_overview")).unwrap();
    assert_eq!(a.ref_, "spa:7dGJo4pcD2V6oG8kP0tJRR");
    assert!(a.followers.is_some_and(|f| f > 1_000_000) && a.avatar_url.is_some());
    assert_eq!(top.len(), 2);
    assert!(top[0].cover_url.as_deref().is_some_and(|u| u.contains("b273")), "без размеров — последняя, 640");
    assert!(top[0].explicit);
  }

  #[test]
  fn discography_releases_take_artist() {
    let by = ArtistRef { ref_: "spa:7dGJo4pcD2V6oG8kP0tJRR".into(), name: "Eminem".into(), avatar_url: None };
    let (albums, groups, total) = discography(&fx("discography_all"), Some(&by));
    assert!(!albums.is_empty() && groups > 0 && total.is_some());
    assert!(albums.iter().all(|a| a.artist == "Eminem" && a.ref_.starts_with("spalb:") && a.year.is_some()));
    assert_eq!(albums[0].released.as_deref(), Some("2026-11-13"));
  }

  #[test]
  fn album_tracks_take_outer_album() {
    let (head, tracks, n, total) = album_page(&fx("album")).unwrap();
    assert_eq!(head.title, "The Marshall Mathers LP");
    assert_eq!(head.released.as_deref(), Some("2000-05-23"));
    assert_eq!(head.track_count, 18);
    assert_eq!((n, total), (3, Some(18)));
    assert_eq!(tracks[0].album.as_ref().map(|a| a.title.as_str()), Some("The Marshall Mathers LP"));
    assert_eq!(tracks[0].cover_url, head.cover_url);
  }

  #[test]
  fn playlist_head_and_rows() {
    let (head, tracks, n, total) = playlist_page(&fx("playlist"));
    let head = head.unwrap();
    assert_eq!(head.ref_, "sppl:3xqcAMgjHGrv3ElA51zZRj");
    assert_eq!(head.track_count, 53);
    assert_eq!((tracks.len(), n, total), (2, 2, Some(53)));
    assert!(tracks[0].artists.len() >= 2);
  }

  #[test]
  fn library_skips_missing_and_non_playlists() {
    let (tracks, n, total) = library_tracks(&fx("library_tracks"));
    assert_eq!((tracks.len(), n, total), (1, 2, Some(2)), "«не найдено» — мимо, но в счёт страницы");
    let (lists, n, _) = library_playlists(&fx("library_v3"));
    assert_eq!((lists.len(), n), (1, 3));
  }

  #[test]
  fn account_from_profile_and_product() {
    let a = account(&fx("profile"), Some(&fx("account")));
    assert_eq!(a.name.as_deref(), Some("Folzy"));
    assert_eq!(a.uid.as_deref(), Some("31folzy"));
    assert_eq!(a.avatar_url.as_deref(), Some("https://i.scdn.co/image/avatar300"));
    assert_eq!(a.premium, Some(true));
    assert_eq!(account(&fx("profile"), None).premium, None);
  }

  #[test]
  fn scan_finds_ops_and_chunks() {
    let js = r#"x=new aX.l("fetchLibraryTracks","query","087278b20b743578a6262c2b0b4bcd20d879c503cc359a2285baf083ef944240",null),y=new aX.l("addToLibrary","mutation","1111111111111111111111111111111111111111111111111111111111111111",null);u.u=e=>""+(({1872:"xpui-routes-playlist",4241:"xpui-routes-search"})[e]||e)+"."+({1872:"aaaa1111",4241:"b12d67ce",99:"33ddb874"})[e]+".js",u.miniCssF"#;
    let found = scan(js);
    assert_eq!(found.get("fetchLibraryTracks").map(String::as_str), Some(Op::LibraryTracks.builtin()));
    assert_eq!(found.len(), 2);
    let main = "https://open.spotifycdn.com/cdn/build/web-player/web-player.e2037ec6.js";
    assert_eq!(
      chunk_url(main, js, "xpui-routes-search").as_deref(),
      Some("https://open.spotifycdn.com/cdn/build/web-player/xpui-routes-search.b12d67ce.js")
    );
    assert_eq!(chunk_url(main, js, "xpui-routes-nope"), None);
    let html = r#"<script src="https://open.spotifycdn.com/cdn/build/web-player/vendor~web-player.eadaf34e.js"></script><script src="https://open.spotifycdn.com/cdn/build/web-player/web-player.e2037ec6.js"></script><link href="https://open.spotifycdn.com/cdn/build/web-player/web-player.e2037ec6.js">"#;
    assert_eq!(script_urls(html).len(), 2);
  }

  #[test]
  fn hashes_adopt_only_known_changes() {
    let h = Hashes::default();
    assert_eq!(h.get(Op::Album), Op::Album.builtin());
    let same: HashMap<String, String> = [("getAlbum".to_owned(), Op::Album.builtin().to_owned())].into();
    assert!(!h.adopt(&same));
    let fresh: HashMap<String, String> = [("getAlbum".to_owned(), "f".repeat(64)), ("unknownOp".to_owned(), "e".repeat(64))].into();
    assert!(h.adopt(&fresh));
    assert_eq!(h.get(Op::Album), "f".repeat(64));
  }

  #[test]
  fn request_body_shape() {
    let b = body(Op::SearchTracks, "abc", json!({ "searchTerm": "x" }));
    assert_eq!(b["operationName"], "searchTracks");
    assert_eq!(b["extensions"]["persistedQuery"]["sha256Hash"], "abc");
    assert_eq!(b["extensions"]["persistedQuery"]["version"], 1);
    assert_eq!(b["variables"]["searchTerm"], "x");
  }
}
