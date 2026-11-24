//! Реестр сервисов: id, ключ, имя, цвет, знаки, префиксы ref и что сервис умеет.
//! Одна таблица на всё приложение — тот же порядок и те же значения, что `lib/services.ts`
//! и `ServiceRegistry.swift` (docs/API.md «Префиксы ref»).

use serde::{Deserialize, Serialize};

/// Короткий id сервиса: параметр `src` поиска и корень всех префиксов ref.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ServiceId {
  Sc,
  Ym,
  Yt,
  Vk,
  Sp,
  Local,
}

impl ServiceId {
  pub const fn as_str(self) -> &'static str {
    match self {
      ServiceId::Sc => "sc",
      ServiceId::Ym => "ym",
      ServiceId::Yt => "yt",
      ServiceId::Vk => "vk",
      ServiceId::Sp => "sp",
      ServiceId::Local => "local",
    }
  }

  pub fn info(self) -> &'static ServiceInfo {
    info(self)
  }

  /// Длинный ключ: имя записи в keyring, `service_accounts.service`, `general.platform`.
  pub fn key(self) -> &'static str {
    self.info().key
  }
}

/// Что за объект у ref: трек, альбом, исполнитель или плейлист.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum RefKind {
  Track,
  Album,
  Artist,
  Playlist,
}

/// Префиксы ref сервиса (без двоеточия).
#[derive(Debug, Clone, Copy, Serialize)]
pub struct Prefixes {
  pub track: &'static str,
  pub album: Option<&'static str>,
  pub artist: Option<&'static str>,
  pub playlist: Option<&'static str>,
}

impl Prefixes {
  /// Все префиксы сервиса с видом объекта, в порядке трек → альбом → артист → плейлист.
  fn all(&self) -> [(Option<&'static str>, RefKind); 4] {
    [
      (Some(self.track), RefKind::Track),
      (self.album, RefKind::Album),
      (self.artist, RefKind::Artist),
      (self.playlist, RefKind::Playlist),
    ]
  }
}

/// Что сервис умеет (у неподключённых в этой версии — только описание цели, ничего по ним не делается).
#[derive(Debug, Clone, Copy, Serialize)]
pub struct Caps {
  pub search: bool,
  pub stream: bool,
  pub library: bool,
  pub playlists: bool,
  pub similar: bool,
  pub login: bool,
  pub key: bool,
}

#[derive(Debug, Serialize)]
pub struct ServiceInfo {
  pub id: ServiceId,
  pub key: &'static str,
  /// Имя по-русски — исходная строка для `t()` в интерфейсе.
  pub name: &'static str,
  /// Цвет знака, `#RRGGBB` заглавными.
  pub color: &'static str,
  /// Цветной знак — имя файла в `brand/icon/`.
  pub icon: Option<&'static str>,
  /// Одноцветный знак — имя файла в `brand/icon/`.
  pub icon_mono: Option<&'static str>,
  pub prefixes: Prefixes,
  pub caps: Caps,
  /// Сервис уже работает в Sonar. Нереализованные в интерфейсе не показываются; убранный (VK) остаётся
  /// в реестре без возможностей, чтобы старые ref в медиатеке узнавались и играли через резерв.
  pub implemented: bool,
}

/// Убранный сервис: ни поиска, ни потока, ни входа.
const NO_CAPS: Caps = Caps { search: false, stream: false, library: false, playlists: false, similar: false, login: false, key: false };

const ALL_CAPS: Caps = Caps { search: true, stream: true, library: true, playlists: true, similar: true, login: true, key: true };

/// Все сервисы в порядке показа. Порядок совпадает с порядком `ServiceId` (на этом стоит `info`).
pub const REGISTRY: &[ServiceInfo] = &[
  ServiceInfo {
    id: ServiceId::Sc,
    key: "soundcloud",
    name: "SoundCloud",
    color: "#FF5500",
    icon: Some("SoundCloud.svg"),
    icon_mono: Some("soundcloud-mono.svg"),
    prefixes: Prefixes { track: "sc", album: Some("scalb"), artist: Some("sca"), playlist: Some("scpl") },
    caps: ALL_CAPS,
    implemented: true,
  },
  ServiceInfo {
    id: ServiceId::Ym,
    key: "yandex",
    name: "Яндекс Музыка",
    color: "#FFBC0D",
    icon: Some("Yandex-Music.svg"),
    icon_mono: Some("yandex-music-mono.svg"),
    prefixes: Prefixes { track: "ym", album: Some("ymalb"), artist: Some("yma"), playlist: Some("ympl") },
    caps: ALL_CAPS,
    implemented: true,
  },
  ServiceInfo {
    id: ServiceId::Yt,
    key: "youtube",
    name: "YouTube Music",
    color: "#FF0033",
    icon: Some("youtube-music.svg"),
    icon_mono: Some("youtube-music-mono.svg"),
    prefixes: Prefixes { track: "yt", album: Some("ytalb"), artist: Some("yta"), playlist: Some("ytpl") },
    caps: ALL_CAPS,
    implemented: true,
  },
  ServiceInfo {
    id: ServiceId::Vk,
    key: "vk",
    name: "VK Музыка",
    color: "#0077FF",
    icon: Some("vk.svg"),
    icon_mono: Some("vk-mono.svg"),
    prefixes: Prefixes { track: "vk", album: Some("vkalb"), artist: Some("vka"), playlist: Some("vkpl") },
    // убран 2026-11-25: после лимитов VK вход через Kate Mobile не проходит; старые `vk:` — через резерв
    caps: NO_CAPS,
    implemented: false,
  },
  ServiceInfo {
    id: ServiceId::Sp,
    key: "spotify",
    name: "Spotify",
    color: "#1ED760",
    icon: Some("spotify.svg"),
    icon_mono: Some("spotify-mono.svg"),
    prefixes: Prefixes { track: "sp", album: Some("spalb"), artist: Some("spa"), playlist: Some("sppl") },
    // поток — только Premium через librespot (фича `spotify-playback`), без неё — резервный сервис;
    // рекомендаций Spotify не берём
    caps: Caps { stream: false, similar: false, ..ALL_CAPS },
    implemented: true,
  },
  ServiceInfo {
    id: ServiceId::Local,
    key: "local",
    name: "Локальные файлы",
    color: "#8E8E93",
    icon: None,
    icon_mono: None,
    prefixes: Prefixes { track: "local", album: None, artist: None, playlist: None },
    caps: Caps { search: false, stream: true, library: true, playlists: false, similar: false, login: false, key: false },
    implemented: true,
  },
];

/// Описание сервиса по id (есть у каждого id — паники не бывает).
pub fn info(id: ServiceId) -> &'static ServiceInfo {
  &REGISTRY[id as usize]
}

/// Сервис по короткому id (`sc`) или длинному ключу (`soundcloud`).
pub fn by_key(s: &str) -> Option<&'static ServiceInfo> {
  REGISTRY.iter().find(|i| i.id.as_str() == s || i.key == s)
}

/// `scpl:likes` → `("scpl", "likes")`. Делит по первому `:`; без `:` или с пустым префиксом — None.
pub fn split_ref(r: &str) -> Option<(&str, &str)> {
  r.split_once(':').filter(|(prefix, _)| !prefix.is_empty())
}

/// Сервис и вид объекта по ref: префикс до первого `:` должен в точности совпасть с префиксом
/// из реестра. `pl_…`, `similar:…` и всё прочее — None.
pub fn parse_ref(r: &str) -> Option<(&'static ServiceInfo, RefKind)> {
  let (prefix, _) = split_ref(r)?;
  REGISTRY.iter().find_map(|s| {
    s.prefixes.all().into_iter().find_map(|(p, kind)| (p == Some(prefix)).then_some((s, kind)))
  })
}

/// Сервис по ref (любого вида).
pub fn service_of(r: &str) -> Option<ServiceId> {
  parse_ref(r).map(|(s, _)| s.id)
}

/// ref относится к сервису `id` и это объект вида `kind`.
pub fn is_kind(r: &str, id: ServiceId, kind: RefKind) -> bool {
  matches!(parse_ref(r), Some((s, k)) if s.id == id && k == kind)
}

/// Лайки аккаунта как плейлист: `scpl:likes` / `ympl:likes` / `ytpl:likes` / `sppl:likes`. У остальных пока нет.
pub fn likes_ref(id: ServiceId) -> Option<String> {
  match id {
    ServiceId::Sc | ServiceId::Ym | ServiceId::Yt | ServiceId::Sp => info(id).prefixes.playlist.map(|p| format!("{p}:likes")),
    _ => None,
  }
}

/// Сервисы, которые уже работают в Sonar (SoundCloud, Яндекс Музыка, YouTube Music, Spotify, локальные файлы).
#[allow(dead_code)] // часть API реестра (как в services.ts); в Rust пока зовут только тесты
pub fn implemented() -> impl Iterator<Item = &'static ServiceInfo> {
  REGISTRY.iter().filter(|s| s.implemented)
}

/// Сервисы от лучшего звука к худшему — кого оставлять из дублей (этап 7 NEXT_PROMPT): Яндекс
/// (до FLAC) > свой файл > Spotify (Ogg 320) > YouTube Music (AAC/Opus) > SoundCloud > убранный VK
/// (сам не играет). Тот же порядок — `QUALITY_ORDER` в `ServiceRegistry.swift`.
pub const QUALITY_ORDER: &[ServiceId] =
  &[ServiceId::Ym, ServiceId::Local, ServiceId::Sp, ServiceId::Yt, ServiceId::Sc, ServiceId::Vk];

/// Место трека по качеству звука: меньше — лучше; ref без сервиса — последним.
pub fn quality_rank(r: &str) -> usize {
  parse_ref(r).and_then(|(s, _)| QUALITY_ORDER.iter().position(|id| *id == s.id)).unwrap_or(QUALITY_ORDER.len())
}

#[cfg(test)]
mod tests {
  use super::*;
  use std::collections::HashSet;

  type Row = (ServiceId, &'static str, &'static str, &'static str, Option<&'static str>, Option<&'static str>);
  type Pfx = (&'static str, Option<&'static str>, Option<&'static str>, Option<&'static str>);

  /// docs/NEXT_PROMPT.md §2 / контракт §1.2.
  const TABLE: &[(Row, Pfx, [bool; 7], bool)] = &[
    (
      (ServiceId::Sc, "soundcloud", "SoundCloud", "#FF5500", Some("SoundCloud.svg"), Some("soundcloud-mono.svg")),
      ("sc", Some("scalb"), Some("sca"), Some("scpl")),
      [true, true, true, true, true, true, true],
      true,
    ),
    (
      (ServiceId::Ym, "yandex", "Яндекс Музыка", "#FFBC0D", Some("Yandex-Music.svg"), Some("yandex-music-mono.svg")),
      ("ym", Some("ymalb"), Some("yma"), Some("ympl")),
      [true, true, true, true, true, true, true],
      true,
    ),
    (
      (ServiceId::Yt, "youtube", "YouTube Music", "#FF0033", Some("youtube-music.svg"), Some("youtube-music-mono.svg")),
      ("yt", Some("ytalb"), Some("yta"), Some("ytpl")),
      [true, true, true, true, true, true, true],
      true,
    ),
    (
      (ServiceId::Vk, "vk", "VK Музыка", "#0077FF", Some("vk.svg"), Some("vk-mono.svg")),
      ("vk", Some("vkalb"), Some("vka"), Some("vkpl")),
      [false, false, false, false, false, false, false],
      false,
    ),
    (
      (ServiceId::Sp, "spotify", "Spotify", "#1ED760", Some("spotify.svg"), Some("spotify-mono.svg")),
      ("sp", Some("spalb"), Some("spa"), Some("sppl")),
      [true, false, true, true, false, true, true],
      true,
    ),
    (
      (ServiceId::Local, "local", "Локальные файлы", "#8E8E93", None, None),
      ("local", None, None, None),
      [false, true, true, false, false, false, false],
      true,
    ),
  ];

  #[test]
  fn registry_table() {
    let ids: Vec<ServiceId> = REGISTRY.iter().map(|s| s.id).collect();
    assert_eq!(ids, [ServiceId::Sc, ServiceId::Ym, ServiceId::Yt, ServiceId::Vk, ServiceId::Sp, ServiceId::Local]);
    assert_eq!(REGISTRY.len(), TABLE.len());
    for (s, ((id, key, name, color, icon, mono), (track, album, artist, playlist), caps, implemented)) in REGISTRY.iter().zip(TABLE) {
      assert_eq!(s.id, *id);
      assert_eq!(info(*id).id, *id, "info() по id отдаёт свою строку");
      assert_eq!((s.key, s.name, s.color, s.icon, s.icon_mono), (*key, *name, *color, *icon, *mono), "{key}");
      assert_eq!(id.key(), *key);
      assert_eq!(id.as_str(), s.prefixes.track, "id — это префикс трека");
      let p = s.prefixes;
      assert_eq!((p.track, p.album, p.artist, p.playlist), (*track, *album, *artist, *playlist), "{key}");
      let c = s.caps;
      assert_eq!([c.search, c.stream, c.library, c.playlists, c.similar, c.login, c.key], *caps, "{key}: caps");
      assert_eq!(s.implemented, *implemented, "{key}");
      assert_eq!(s.color, s.color.to_uppercase(), "цвет заглавными");
    }
  }

  #[test]
  fn prefixes_unique() {
    let mut seen = HashSet::new();
    for s in REGISTRY {
      for (p, _) in s.prefixes.all() {
        if let Some(p) = p {
          assert!(seen.insert(p), "префикс {p} повторяется");
        }
      }
    }
    assert_eq!(seen.len(), 21);
  }

  #[test]
  fn parse_ref_cases() {
    use RefKind::*;
    let cases: &[(&str, Option<(ServiceId, RefKind)>)] = &[
      ("sc:123", Some((ServiceId::Sc, Track))),
      ("scalb:9", Some((ServiceId::Sc, Album))),
      ("sca:7", Some((ServiceId::Sc, Artist))),
      ("scpl:likes", Some((ServiceId::Sc, Playlist))),
      ("ympl:42:1003", Some((ServiceId::Ym, Playlist))),
      ("ymalb:5", Some((ServiceId::Ym, Album))),
      ("yma:1", Some((ServiceId::Ym, Artist))),
      ("yt:abc", Some((ServiceId::Yt, Track))),
      ("local:abc", Some((ServiceId::Local, Track))),
      ("pl_x", None),
      ("similar:sc:1", None),
      ("sc", None),
      ("", None),
      (":1", None),
    ];
    for (r, want) in cases {
      let got = parse_ref(r).map(|(s, k)| (s.id, k));
      assert_eq!(got, *want, "{r}");
      assert_eq!(service_of(r), want.map(|(id, _)| id), "{r}");
    }
  }

  #[test]
  fn parse_ref_every_prefix() {
    for s in REGISTRY {
      for (p, kind) in s.prefixes.all() {
        let Some(p) = p else { continue };
        let r = format!("{p}:x");
        assert!(is_kind(&r, s.id, kind), "{r}");
        // префикс сравнивается целиком, а не началом строки
        assert!(parse_ref(&format!("{p}x:1")).is_none(), "{p}x");
      }
    }
    assert!(!is_kind("scpl:likes", ServiceId::Sc, RefKind::Track));
    assert!(!is_kind("ym:1", ServiceId::Sc, RefKind::Track));
  }

  #[test]
  fn split_ref_first_colon() {
    assert_eq!(split_ref("ympl:42:1003"), Some(("ympl", "42:1003")));
    assert_eq!(split_ref("scpl:likes"), Some(("scpl", "likes")));
    assert_eq!(split_ref("sc:"), Some(("sc", "")));
    assert_eq!(split_ref("sc"), None);
    assert_eq!(split_ref(":1"), None);
    assert_eq!(split_ref(""), None);
  }

  #[test]
  fn by_key_accepts_short_and_long() {
    assert_eq!(by_key("sc").map(|s| s.id), Some(ServiceId::Sc));
    assert_eq!(by_key("soundcloud").map(|s| s.id), Some(ServiceId::Sc));
    assert_eq!(by_key("yandex").map(|s| s.id), Some(ServiceId::Ym));
    assert_eq!(by_key("youtube").map(|s| s.id), Some(ServiceId::Yt));
    assert_eq!(by_key("yt").map(|s| s.id), Some(ServiceId::Yt));
    assert_eq!(by_key("local").map(|s| s.id), Some(ServiceId::Local));
    assert!(by_key("x").is_none());
    assert!(by_key("").is_none());
    assert!(by_key("SC").is_none(), "регистр важен");
  }

  #[test]
  fn service_id_serde() {
    assert_eq!(serde_json::to_string(&ServiceId::Local).unwrap(), "\"local\"");
    for s in REGISTRY {
      let json = serde_json::to_string(&s.id).unwrap();
      assert_eq!(json, format!("\"{}\"", s.id.as_str()));
      assert_eq!(serde_json::from_str::<ServiceId>(&json).unwrap(), s.id);
    }
    assert_eq!(serde_json::to_string(&RefKind::Playlist).unwrap(), "\"playlist\"");
  }

  #[test]
  fn likes_ref_values() {
    assert_eq!(likes_ref(ServiceId::Sc).as_deref(), Some("scpl:likes"));
    assert_eq!(likes_ref(ServiceId::Ym).as_deref(), Some("ympl:likes"));
    assert_eq!(likes_ref(ServiceId::Yt).as_deref(), Some("ytpl:likes"));
    assert_eq!(likes_ref(ServiceId::Vk), None, "VK убран");
    assert_eq!(likes_ref(ServiceId::Sp).as_deref(), Some("sppl:likes"));
    assert_eq!(likes_ref(ServiceId::Local), None);
  }

  #[test]
  fn quality_order_covers_every_service_once() {
    let mut ids: Vec<ServiceId> = QUALITY_ORDER.to_vec();
    assert_eq!(ids.len(), REGISTRY.len());
    ids.sort_by_key(|id| *id as usize);
    ids.dedup();
    assert_eq!(ids.len(), REGISTRY.len());
    assert!(quality_rank("ym:1") < quality_rank("sp:1"));
    assert!(quality_rank("sp:1") < quality_rank("yt:1"));
    assert!(quality_rank("yt:1") < quality_rank("sc:1"));
    assert!(quality_rank("sc:1") < quality_rank("vk:1"), "убранный VK — последним");
    assert_eq!(quality_rank("pl_x"), QUALITY_ORDER.len());
  }

  #[test]
  fn implemented_is_sc_ym_yt_sp_and_local() {
    let ids: Vec<ServiceId> = implemented().map(|s| s.id).collect();
    assert_eq!(ids, [ServiceId::Sc, ServiceId::Ym, ServiceId::Yt, ServiceId::Sp, ServiceId::Local]);
  }

  #[test]
  fn capabilities() {
    // реализованные сервисы с аккаунтом ищут, дают медиатеку, плейлисты, вход и ключ; поток и похожие —
    // кроме Spotify; локальные файлы — без входа и ключа (папки — в Хранилище)
    for s in implemented().filter(|s| s.caps.login) {
      let c = s.caps;
      assert!(c.search && c.library && c.playlists && c.login && c.key, "{}", s.key);
      assert_eq!(c.stream && c.similar, s.id != ServiceId::Sp, "{}", s.key);
    }
    assert!(!info(ServiceId::Sp).caps.stream, "Spotify сам не играет — нужен резервный сервис");
    let local = info(ServiceId::Local).caps;
    assert!(!local.search && local.stream && !local.login && !local.key);
    // у каждого работающего сервиса с плейлистами есть префикс плейлиста
    for s in implemented() {
      assert_eq!(s.caps.playlists, s.prefixes.playlist.is_some(), "{}", s.key);
    }
  }
}
