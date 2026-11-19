//! Перезаливы SoundCloud: настоящий артист в названии «АРТИСТ - ТРЕК» (docs/TITLE_SPLIT.md, порт
//! `title_split.py` из selfbot). Чистые функции без сети: запасные пары для поиска текста
//! (`reupload_variants`) и одна пара «настоящий артист + чистое название» для Genius и показа (`search_pair`).

use regex::Regex;
use std::collections::HashSet;
use std::sync::LazyLock;

/// Запасных пар — не больше.
pub const MAX_VARIANTS: usize = 4;
/// Имя из словаря «артист-трек» — не длиннее.
const DASH_NAME_MAX: usize = 40;
/// Словарь по умолчанию (когда список не прочитался).
pub const DEFAULT_DASH_ARTISTS: &[&str] = &["cowboyclicker"];
/// Раундов чистки названия.
const CLEAN_ROUNDS: usize = 8;
/// Обратная пара: «артист» справа — не длиннее и не больше слов.
const SWAP_NAME_MAX: usize = 40;
const SWAP_WORDS_MAX: usize = 4;
/// Похоже на имя артиста: не длиннее и не больше слов.
const ARTIST_MAX: usize = 60;
const ARTIST_WORDS_MAX: usize = 6;
/// Часть «A/B» берётся первой, только если все части не короче.
const SLASH_PART_MIN: usize = 3;

/// Тире: дефис, U+2010…U+2015, минус.
const DASH_CHARS: [char; 8] = ['-', '\u{2010}', '\u{2011}', '\u{2012}', '\u{2013}', '\u{2014}', '\u{2015}', '\u{2212}'];
const DASH: &str = r"\-\x{2010}\x{2011}\x{2012}\x{2013}\x{2014}\x{2015}\x{2212}";

/// Шаблон с `{DASH}` — набор тире в квадратных скобках.
fn re(pattern: &str) -> Regex {
  Regex::new(&pattern.replace("{DASH}", DASH)).unwrap()
}

static SEPARATOR: LazyLock<Regex> = LazyLock::new(|| re(r"\s+[{DASH}]\s+"));
static MULTI_ARTIST: LazyLock<Regex> =
  LazyLock::new(|| re(r"(?i)\s*,\s*|\s+(?:&|feat\.?|ft\.?|x\+?|\+|×|и|and|with|w/)\s+"));
static COLLAB: LazyLock<Regex> = LazyLock::new(|| re(r"(?i)^[+@]|\s+(?:x\+?|\+|×|feat\.?|ft\.?)\s+|,\s"));
static LEAD_MARKS: LazyLock<Regex> = LazyLock::new(|| re(r"^[\s+@~#*]+"));
static TRAILING_GROUP: LazyLock<Regex> =
  LazyLock::new(|| re(r"\s*(?:\([^()]*\)|\[[^\[\]]*\]|\{[^{}]*\}|\*\*[^*]*\*\*)\s*$"));
static ANY_STARS: LazyLock<Regex> = LazyLock::new(|| re(r"\s*\*\*[^*]*\*\*"));
static SPACED_COMPACT: LazyLock<Regex> = LazyLock::new(|| re(r"^([^{DASH}]*,[^{DASH}]*)[{DASH}](\S.*)$"));
static LABEL_HEAD: LazyLock<Regex> = LazyLock::new(|| re(r"^[\s(\[]*(?:feat|ft|featuring|prod|produced)\b"));
static LABEL_NUMBER: LazyLock<Regex> = LazyLock::new(|| re(r"^(?:(?:19[5-9]|20[0-3])\d|v\d+)$"));
static WORD: LazyLock<Regex> = LazyLock::new(|| re(r"[^\W_]+"));

/// Хвостовой мусор названия — применяется по кругу.
static TITLE_TAILS: LazyLock<Vec<Regex>> = LazyLock::new(|| {
  [
    r"(?i)\.(?:mp3|мп3|wav|flac|m4a)\s*$",
    r"(?i)\s+prod(?:uced)?\b.*$",
    r"(?i)\s+p/\S.*$",
    r"(?i)\s+(?:feat|ft)\.?\s.*$",
    r"(?i)\s+\+.*$",
    r"(?i)\s*#\S*(?:\s+#\S*)*\s*$",
    r"(?i)\s+@\S+\s*$",
    r"(?i)\s+archive\s*$",
    r"(?i)\s+\d+\s*(?:й|-й|st|nd|rd|th)?\s*(?:парт|part)\w*\s*$",
    r"(?i)\s+tiktok\s+remix\s*$",
    r"(?i)\s+(?:speed(?:ed)?|sped|slowed|nightcore)(?:\s+(?:up|down|x\s+mix|mix|\+\s*reverb|and\s+reverb))*\s*$",
  ]
  .iter()
  .map(|p| re(p))
  .collect()
});

/// Метки перед артистом: «REMIX - A & B - TRACK».
const LEAD_TAGS: &[&str] = &[
  "remix", "official", "new", "exclusive", "unreleased", "leak", "leaked", "snippet", "preview", "premiere", "free",
  "mashup", "full", "tiktok remix",
];

/// Слова-метки версии: правая часть только из них — не название.
const LABEL_WORDS: &[&str] = &[
  "live", "edition", "remaster", "remastered", "remasters", "remix", "rmx", "edit", "edited", "radio", "acoustic",
  "version", "ver", "instrumental", "demo", "slowed", "sped", "speed", "up", "down", "nightcore", "reverb", "reverbed",
  "mix", "extended", "original", "deluxe", "bonus", "mono", "stereo", "explicit", "clean", "reprise", "unplugged",
  "session", "sessions", "cover", "official", "audio", "video", "lyric", "lyrics", "hq", "hd", "and", "x", "mixed",
  "bass", "boosted", "ремикс", "ремастер", "ремастеринг", "слоуд", "слоу", "замедленная", "замедленный", "ускоренная",
  "ускоренный", "версия", "акустика", "акустическая", "живое", "лайв", "инструментал", "демо", "оригинал", "радио",
  "эдит", "спид", "ап", "найткор", "реверб", "микс", "и",
];

/// Как получена пара: разрез по тире или обратный порядок («ТРЕК - АРТИСТ»).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
  Split,
  Swap,
}

/// Пара для поиска: (исполнитель, название).
pub type Pair = (String, String);

// ——— словарь «артист-трек» ———

/// Имена, у которых тире без пробелов — разделитель («cowboyclicker-трек»). Длинные первыми.
#[derive(Debug, Clone)]
pub struct DashArtists {
  #[cfg_attr(not(test), allow(dead_code))]
  names: Vec<String>,
  patterns: Vec<Regex>,
}

impl Default for DashArtists {
  fn default() -> Self {
    Self::new(DEFAULT_DASH_ARTISTS.iter().copied())
  }
}

impl DashArtists {
  pub fn new<S: AsRef<str>>(names: impl IntoIterator<Item = S>) -> Self {
    let mut list: Vec<String> = Vec::new();
    for name in names.into_iter().filter_map(|n| normalize_dash_name(n.as_ref())) {
      if !list.contains(&name) {
        list.push(name);
      }
    }
    list.sort_by(|a, b| b.chars().count().cmp(&a.chars().count()).then_with(|| a.cmp(b)));
    let patterns = list
      .iter()
      .map(|n| Regex::new(&format!(r"(?i)^\s*({})\s*[{DASH}]\s*(\S.*)$", regex::escape(n))).unwrap())
      .collect();
    Self { names: list, patterns }
  }

  /// Список прочитался — он (пустой — пусто), не прочитался — по умолчанию.
  pub fn from_loaded<S: AsRef<str>>(loaded: Option<Vec<S>>) -> Self {
    loaded.map(Self::new).unwrap_or_default()
  }

  #[cfg_attr(not(test), allow(dead_code))]
  pub fn names(&self) -> &[String] {
    &self.names
  }

  /// «cowboyclicker-трек» → «cowboyclicker - трек»; только с начала названия, регистр — как был.
  fn compact(&self, title: &str) -> String {
    self
      .patterns
      .iter()
      .find_map(|p| p.captures(title).map(|c| format!("{} - {}", &c[1], &c[2])))
      .unwrap_or_else(|| title.to_string())
  }
}

/// Имя словаря: без `@`, пробелы схлопнуты, нижний регистр. Мусор — `None`.
pub fn normalize_dash_name(raw: &str) -> Option<String> {
  let trimmed = raw.trim();
  if trimmed.contains(['\n', '\r']) {
    return None;
  }
  let name = fold(trimmed.trim_start_matches('@'));
  let alnum = name.chars().filter(|c| c.is_alphanumeric()).count();
  (alnum >= 2 && name.chars().count() <= DASH_NAME_MAX).then_some(name)
}

// ——— помощники ———

/// Нижний регистр, пробелы схлопнуты.
pub fn fold(s: &str) -> String {
  s.split_whitespace().collect::<Vec<_>>().join(" ").to_lowercase()
}

fn letters(s: &str) -> usize {
  s.chars().filter(|c| c.is_alphabetic()).count()
}

/// Метка версии («Live», «2011 Remaster», «speed up + reverb»), а не название.
pub fn is_label(text: &str) -> bool {
  let t = text.to_lowercase().replace("(ed)", "ed");
  if LABEL_HEAD.is_match(&t) {
    return true;
  }
  let words: Vec<&str> = WORD.find_iter(&t).map(|m| m.as_str()).collect();
  !words.is_empty() && words.iter().all(|w| LABEL_WORDS.contains(w) || LABEL_NUMBER.is_match(w))
}

/// Хвост после последнего разделителя — метка: «Song - Slowed» → «Song».
fn strip_label_tail(text: &str) -> String {
  match SEPARATOR.find_iter(text).last() {
    Some(m) if is_label(&text[m.end()..]) => text[..m.start()].to_string(),
    _ => text.to_string(),
  }
}

/// Шаг чистки: пустой результат — оставить как было.
fn keep(before: &str, after: &str) -> String {
  let after = after.trim();
  if after.is_empty() { before.to_string() } else { after.to_string() }
}

fn trim_edges(s: &str) -> &str {
  s.trim_matches(|c: char| c.is_whitespace() || DASH_CHARS.contains(&c))
}

/// Название без мусора: «**…**», хвостовые скобки, «prod …», «.mp3», «#2016», метки версии.
pub fn clean_title(title: &str) -> String {
  let original = title.trim().to_string();
  let mut cur = original.clone();
  for _ in 0..CLEAN_ROUNDS {
    let mut next = keep(&cur, &ANY_STARS.replace_all(&cur, ""));
    next = keep(&next, &TRAILING_GROUP.replace(&next, ""));
    for tail in TITLE_TAILS.iter() {
      next = keep(&next, &tail.replace(&next, ""));
    }
    next = keep(&next, &strip_label_tail(&next));
    next = keep(&next, trim_edges(&next));
    if next == cur {
      break;
    }
    cur = next;
  }
  if cur.is_empty() { original } else { cur }
}

/// Имя артиста без меток «+», «@», хвостовой скобки; «ШИПЫ/ONDA ANDAR» → «ШИПЫ», «AC/DC» — как есть.
pub fn clean_artist(name: &str) -> String {
  let name = name.trim();
  let mut s = keep(name, &LEAD_MARKS.replace(name, ""));
  s = keep(&s, &TRAILING_GROUP.replace(&s, ""));
  if s.contains('/') {
    let parts: Vec<&str> = s.split('/').map(str::trim).collect();
    if parts.iter().all(|p| p.chars().count() >= SLASH_PART_MIN) {
      s = parts[0].to_string();
    }
  }
  keep(&s, &LEAD_MARKS.replace(&s, ""))
}

fn first_artist(name: &str) -> String {
  MULTI_ARTIST.split(name).next().unwrap_or("").trim().to_string()
}

fn looks_like_artist(name: &str) -> bool {
  !name.is_empty()
    && name.chars().count() <= ARTIST_MAX
    && name.split_whitespace().count() <= ARTIST_WORDS_MAX
    && name.chars().any(char::is_alphanumeric)
}

fn is_uploader(name: &str, uploader: &str) -> bool {
  fold(name) == uploader || fold(&first_artist(name)) == uploader
}

fn usable(name: &str, track: &str) -> bool {
  let clean = clean_title(track);
  letters(name) >= 2 && letters(&clean) >= 2 && !is_label(track) && !is_label(&clean)
}

// ——— подготовка названия ———

/// «vzk1ll, cowboyclicker, jetcasse -много дел» → «… - много дел» (только без разделителя с пробелами).
fn spaced_compact(title: &str) -> String {
  if SEPARATOR.is_match(title) {
    return title.to_string();
  }
  let Some(c) = SPACED_COMPACT.captures(title) else { return title.to_string() };
  let left = c[1].trim();
  let parts: Vec<&str> = left.split(',').map(str::trim).collect();
  if parts.len() >= 2 && parts.iter().all(|p| p.chars().count() >= 2) {
    format!("{left} - {}", &c[2])
  } else {
    title.to_string()
  }
}

/// «REMIX - A & B - TRACK» → «A & B - TRACK»; вместе с разделителями того, что осталось.
fn drop_lead_tags(title: &str) -> (String, Vec<(usize, usize)>) {
  let mut work = title.to_string();
  loop {
    let spans: Vec<(usize, usize)> = SEPARATOR.find_iter(&work).map(|m| (m.start(), m.end())).collect();
    if spans.len() >= 2 && LEAD_TAGS.contains(&fold(&work[..spans[0].0]).as_str()) {
      work = work[spans[0].1..].to_string();
      continue;
    }
    return (work, spans);
  }
}

// ——— сбор вариантов ———

type Variant = (String, String, Kind);

/// Обратная пара «ТРЕК - АРТИСТ» — только с доказательством: справа заливший или слева явный мусор.
/// `Some((пара, справа_заливший))`.
fn swap_variant(artist: &str, uploader: &str, left: &str, right: &str) -> Option<(Variant, bool)> {
  if is_uploader(left, uploader) || COLLAB.is_match(left) || is_label(right) {
    return None;
  }
  let who = clean_artist(&clean_title(right));
  let by_uploader = is_uploader(&who, uploader);
  let marked = clean_title(left) != left;
  let fits = looks_like_artist(&who)
    && who.chars().count() <= SWAP_NAME_MAX
    && who.split_whitespace().count() <= SWAP_WORDS_MAX;
  if !fits || !(by_uploader || marked) {
    return None;
  }
  let who = if by_uploader { artist.to_string() } else { who };
  let track = clean_title(left);
  usable(&who, &track).then_some(((who, track, Kind::Swap), by_uploader))
}

fn collect(artist: &str, title: &str, dash: &DashArtists) -> Vec<Variant> {
  let artist = artist.trim();
  let title = title.trim();
  let (work, spans) = drop_lead_tags(&spaced_compact(&dash.compact(title)));
  let (Some(&first), Some(&last)) = (spans.first(), spans.last()) else { return Vec::new() };
  let uploader = fold(artist);
  let (mut raw, mut clean, mut swapped) = (Vec::new(), Vec::new(), Vec::new());
  let mut swapped_first = false;
  let cuts = if first == last { vec![first] } else { vec![first, last] };
  for (start, end) in cuts {
    let left = work[..start].trim();
    let right = work[end..].trim();
    if left.is_empty() || right.is_empty() || is_label(left) {
      continue;
    }
    let who = if fold(left) == uploader { artist.to_string() } else { clean_artist(left) };
    if looks_like_artist(&who) && usable(&who, right) {
      let tidy = clean_title(right);
      if tidy != right {
        clean.push((who.clone(), tidy, Kind::Split));
      }
      raw.push((who, right.to_string(), Kind::Split));
    }
    if spans.len() == 1 {
      if let Some((pair, by_uploader)) = swap_variant(artist, &uploader, left, right) {
        swapped_first |= by_uploader;
        swapped.push(pair);
      }
    }
  }
  let ordered = if swapped_first { [swapped, raw, clean].concat() } else { [raw, clean, swapped].concat() };
  let mut seen: HashSet<(String, String)> = HashSet::from([(fold(artist), fold(title))]);
  ordered.into_iter().filter(|(a, t, _)| seen.insert((fold(a), fold(t)))).collect()
}

/// До `MAX_VARIANTS` запасных пар для поиска текста; исходной среди них нет. Нет разделителя — пусто.
pub fn reupload_variants(artist: &str, title: &str, dash: &DashArtists) -> Vec<Pair> {
  collect(artist, title, dash).into_iter().take(MAX_VARIANTS).map(|(a, t, _)| (a, t)).collect()
}

/// Одна пара «настоящий артист + чистое название» для Genius и показа. Не похоже на перезалив — исходная.
pub fn search_pair(artist: &str, title: &str, dash: &DashArtists) -> Pair {
  let original = (artist.to_string(), title.to_string());
  match collect(artist, title, dash).into_iter().next() {
    None => original,
    Some((who, _, Kind::Swap)) if fold(&who) != fold(artist) => original,
    Some((who, track, _)) => (who, clean_title(&track)),
  }
}

#[cfg(test)]
#[path = "title_split_tests.rs"]
mod tests;
