//! Поиск дублей в Любимых и своих плейлистах (этап 7 NEXT_PROMPT) — без сети, по сохранённым
//! метаданным. Дубли — это:
//! - один и тот же `ref` дважды (в плейлисте);
//! - тот же трек из разных сервисов и почти одинаковые названия того же исполнителя с той же
//!   длительностью ±3 с — правила `providers/matching.rs` (`Wanted::score`): «версии» (remix, live,
//!   sped up…) должны совпадать, так что ремикс оригиналу не дубль.
//!
//! Строгость сверх `matching` (в одном списке у исполнителя часто «Part 1» и «Part 2» рядом):
//! числа в названиях должны совпасть, а если у одного из треков длительность неизвестна (0) —
//! название без мусора должно совпасть целиком.
//!
//! В группе первым стоит тот, кого оставить по умолчанию: играет (доступен) > лучше звук
//! (`registry::QUALITY_ORDER`: Яндекс > свой файл > Spotify > VK > YouTube Music > SoundCloud) >
//! добавлен раньше > выше в списке. Остальные — по порядку списка.

pub mod commands;

use crate::lyrics::{clean_title, norm};
use crate::providers::matching::{artist_keys, Wanted, MAX_DURATION_DIFF_MS};
use crate::providers::registry::quality_rank;
use crate::store::ListTrack;
use regex::Regex;
use serde::Serialize;
use std::collections::HashMap;
use std::sync::LazyLock;

static NUMBER: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\d+").unwrap());

/// Группа дублей. `keep` — `item_id` того, кого оставить по умолчанию (он же первый в `items`).
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct DupeGroup {
  pub keep: String,
  pub items: Vec<ListTrack>,
}

/// Трек списка с заранее посчитанным: что искать и название для строгой сверки.
struct Entry<'a> {
  item: &'a ListTrack,
  wanted: Wanted,
  /// Название без мусора и без «АРТИСТ - » перезалива, нормализованное.
  title_key: String,
  /// Числа из названия по порядку: «Intro» ≠ «Intro 2», «Part 1» ≠ «Part 2».
  numbers: Vec<String>,
}

impl<'a> Entry<'a> {
  fn new(item: &'a ListTrack) -> Self {
    let wanted = Wanted::from_track(&item.track);
    let title = wanted.titles.first().cloned().unwrap_or_else(|| clean_title(&item.track.title));
    let title_key = norm(&title);
    let numbers = NUMBER.find_iter(&title_key).map(|m| m.as_str().trim_start_matches('0').to_string()).collect();
    Self { item, wanted, title_key, numbers }
  }

  fn duration(&self) -> u64 {
    self.item.track.duration_ms
  }
}

/// Один ли это трек (см. описание модуля).
fn twins(a: &Entry, b: &Entry) -> bool {
  if a.item.track.ref_ == b.item.track.ref_ {
    return true;
  }
  if a.numbers != b.numbers || ((a.duration() == 0 || b.duration() == 0) && a.title_key != b.title_key) {
    return false;
  }
  a.wanted.score(&b.item.track).is_some() || b.wanted.score(&a.item.track).is_some()
}

/// Непересекающиеся множества: дубль дубля — тоже дубль (одна группа).
struct Groups(Vec<usize>);

impl Groups {
  fn new(n: usize) -> Self {
    Self((0..n).collect())
  }

  fn root(&mut self, mut i: usize) -> usize {
    while self.0[i] != i {
      self.0[i] = self.0[self.0[i]];
      i = self.0[i];
    }
    i
  }

  fn join(&mut self, a: usize, b: usize) {
    let (ra, rb) = (self.root(a), self.root(b));
    if ra != rb {
      // корень — меньший индекс: так группы проще упорядочить по месту в списке
      self.0[ra.max(rb)] = ra.min(rb);
    }
  }
}

/// Сверить `a` и `b`, если они ещё не в одной группе.
fn check(groups: &mut Groups, entries: &[Entry], a: usize, b: usize) {
  if a != b && groups.root(a) != groups.root(b) && twins(&entries[a], &entries[b]) {
    groups.join(a, b);
  }
}

/// Пары-кандидаты внутри «корзины» одного исполнителя: с известной длительностью — только соседи
/// в окне ±3 с (после сортировки), с неизвестной — со всеми.
fn scan_bucket(groups: &mut Groups, entries: &[Entry], bucket: &[usize]) {
  let (mut known, unknown): (Vec<usize>, Vec<usize>) = bucket.iter().partition(|&&i| entries[i].duration() > 0);
  known.sort_by_key(|&i| entries[i].duration());
  for (pos, &a) in known.iter().enumerate() {
    for &b in &known[pos + 1..] {
      if entries[b].duration() - entries[a].duration() > MAX_DURATION_DIFF_MS {
        break;
      }
      check(groups, entries, a, b);
    }
  }
  for &u in &unknown {
    for &b in bucket {
      check(groups, entries, u, b);
    }
  }
}

/// Ключ «кого оставить»: меньше — лучше. `idx` — место в списке.
fn keep_key(item: &ListTrack, idx: usize) -> (bool, usize, i64, usize) {
  (!item.track.available, quality_rank(&item.track.ref_), item.added_at, idx)
}

/// Группы дублей в порядке списка (по первому треку группы). Треки без пары не попадают.
pub fn find_groups(items: &[ListTrack]) -> Vec<DupeGroup> {
  let entries: Vec<Entry> = items.iter().map(Entry::new).collect();
  let mut groups = Groups::new(entries.len());

  // корзины: один ref и каждое имя исполнителя — сравниваются только треки из общей корзины
  let mut by_ref: HashMap<&str, Vec<usize>> = HashMap::new();
  let mut by_artist: HashMap<String, Vec<usize>> = HashMap::new();
  for (i, e) in entries.iter().enumerate() {
    by_ref.entry(e.item.track.ref_.as_str()).or_default().push(i);
    for key in artist_keys(&e.item.track, &e.wanted) {
      by_artist.entry(key).or_default().push(i);
    }
  }
  for same in by_ref.values() {
    for &i in &same[1..] {
      groups.join(same[0], i);
    }
  }
  for bucket in by_artist.values().filter(|b| b.len() > 1) {
    scan_bucket(&mut groups, &entries, bucket);
  }

  let mut members: HashMap<usize, Vec<usize>> = HashMap::new();
  for i in 0..entries.len() {
    members.entry(groups.root(i)).or_default().push(i);
  }
  let mut found: Vec<(usize, Vec<usize>)> = members.into_iter().filter(|(_, m)| m.len() > 1).collect();
  found.sort_by_key(|(root, _)| *root);
  found.into_iter().map(|(_, idx)| group_of(items, &idx)).collect()
}

/// Группа из индексов (по порядку списка): лучший — первым.
fn group_of(items: &[ListTrack], idx: &[usize]) -> DupeGroup {
  let best = idx.iter().copied().min_by_key(|&i| keep_key(&items[i], i)).unwrap_or(idx[0]);
  let ordered = std::iter::once(best).chain(idx.iter().copied().filter(|&i| i != best));
  DupeGroup { keep: items[best].item_id.clone(), items: ordered.map(|i| items[i].clone()).collect() }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::providers::{ArtistRef, Track};

  fn item(item_id: &str, r: &str, artist: &str, title: &str, ms: u64, added_at: i64) -> ListTrack {
    ListTrack {
      item_id: item_id.into(),
      added_at,
      added_by: None,
      track: Track {
        ref_: r.into(),
        title: title.into(),
        artist: artist.into(),
        artists: if artist.is_empty() {
          vec![]
        } else {
          vec![ArtistRef { ref_: format!("x:{artist}"), name: artist.into(), avatar_url: None }]
        },
        album: None,
        duration_ms: ms,
        cover_url: None,
        url: None,
        explicit: false,
        available: true,
        plays: None,
        tags: None,
      },
    }
  }

  fn ids(g: &DupeGroup) -> Vec<&str> {
    g.items.iter().map(|i| i.item_id.as_str()).collect()
  }

  #[test]
  fn same_ref_twice_is_a_group_and_earlier_stays() {
    let list = [
      item("a", "sc:1", "A", "Song", 100_000, 20),
      item("b", "sc:2", "B", "Other", 200_000, 10),
      item("c", "sc:1", "A", "Song", 100_000, 5),
    ];
    let g = find_groups(&list);
    assert_eq!(g.len(), 1);
    assert_eq!(g[0].keep, "c", "добавлен раньше");
    assert_eq!(ids(&g[0]), ["c", "a"]);
  }

  #[test]
  fn same_track_across_services_keeps_best_quality() {
    let list = [
      item("sc", "sc:1", "EsDeeKid", "4 Raws", 146_000, 1),
      item("yt", "yt:x", "EsDeeKid", "4 Raws", 147_000, 2),
      item("ym", "ym:9", "EsDeeKid", "4 Raws", 146_500, 3),
      item("sp", "sp:z", "EsDeeKid", "4 Raws", 145_500, 4),
    ];
    let g = find_groups(&list);
    assert_eq!(g.len(), 1);
    assert_eq!(g[0].keep, "ym", "Яндекс лучше всех, хоть добавлен позже");
    assert_eq!(ids(&g[0]), ["ym", "sc", "yt", "sp"], "лучший первым, дальше по порядку списка");
  }

  #[test]
  fn unavailable_is_never_preferred() {
    let mut ym = item("ym", "ym:9", "A", "Song", 100_000, 1);
    ym.track.available = false;
    let list = [ym, item("sc", "sc:1", "A", "Song", 100_000, 2)];
    assert_eq!(find_groups(&list)[0].keep, "sc");
  }

  #[test]
  fn near_identical_title_same_artist_same_length() {
    let list = [
      item("a", "sc:1", "Кизару", "Дежавю (prod. X)", 180_000, 1),
      item("b", "sc:2", "Кизару", "Дежавю", 182_500, 2),
      item("c", "sc:3", "random uploader", "Кизару - Дежавю", 181_000, 3),
    ];
    let g = find_groups(&list);
    assert_eq!(g.len(), 1);
    assert_eq!(ids(&g[0]), ["a", "b", "c"]);
  }

  #[test]
  fn versions_other_lengths_and_other_artists_are_not_dupes() {
    let list = [
      item("a", "ym:1", "A", "Song", 100_000, 1),
      item("b", "ym:2", "A", "Song (Remix)", 100_000, 2),
      item("c", "ym:3", "A", "Song", 110_000, 3),
      item("d", "ym:4", "B", "Song", 100_000, 4),
      item("e", "ym:5", "A", "Song (Sped Up)", 100_000, 5),
      item("f", "ym:6", "A", "Another", 100_000, 6),
    ];
    assert!(find_groups(&list).is_empty());
  }

  #[test]
  fn unknown_length_needs_the_exact_title() {
    let list = [
      item("a", "sc:1", "A", "Intro", 0, 1),
      item("b", "sc:2", "A", "Intro 2", 90_000, 2),
      item("c", "ym:3", "A", "Intro", 91_000, 3),
    ];
    let g = find_groups(&list);
    assert_eq!(g.len(), 1);
    assert_eq!(ids(&g[0]), ["c", "a"], "Intro без длительности — только с точным «Intro»");
  }

  #[test]
  fn numbered_parts_are_not_dupes() {
    let list = [
      // артист в «АРТИСТ - ТРЕК» — от двух букв (docs/TITLE_SPLIT.md), поэтому не «A»
      item("a", "ym:1", "Ab", "Part 1", 100_000, 1),
      item("b", "ym:2", "Ab", "Part 2", 100_000, 2),
      item("c", "sc:3", "uploader", "Ab - Part 01", 101_000, 3),
    ];
    let g = find_groups(&list);
    assert_eq!(g.len(), 1);
    assert_eq!(ids(&g[0]), ["a", "c"], "перезалив «Ab - Part 01» — та же первая часть");
  }

  #[test]
  fn groups_follow_list_order_and_chain() {
    let list = [
      item("x1", "sc:10", "X", "Late", 50_000, 1),
      item("a1", "sc:1", "A", "Song", 100_000, 2),
      item("x2", "yt:10", "X", "Late", 50_000, 3),
      item("a2", "yt:1", "A", "Song", 102_500, 4),
      item("a3", "vk:1", "A", "Song", 105_000, 5),
    ];
    let g = find_groups(&list);
    assert_eq!(g.len(), 2);
    assert_eq!(g[0].keep, "x2", "YouTube Music лучше SoundCloud");
    // a1 ~ a2 (2.5 с), a2 ~ a3 (2.5 с) — одна группа, хоть a1 и a3 разошлись на 5 с
    assert_eq!(g[1].keep, "a3", "VK лучше YouTube Music и SoundCloud");
    assert_eq!(ids(&g[1]), ["a3", "a1", "a2"]);
  }

  #[test]
  fn no_artist_only_same_ref() {
    let list = [item("a", "local:1", "", "Track", 100_000, 1), item("b", "local:2", "", "Track", 100_000, 2)];
    assert!(find_groups(&list).is_empty());
    assert!(find_groups(&[]).is_empty());
  }

  #[test]
  fn big_list_stays_fast() {
    let list: Vec<ListTrack> = (0..3000)
      .map(|i| item(&format!("i{i}"), &format!("sc:{i}"), "Same Artist", &format!("Track {i}"), 60_000 + i * 10, i as i64))
      .collect();
    let started = std::time::Instant::now();
    let g = find_groups(&list);
    assert!(g.is_empty());
    assert!(started.elapsed().as_secs() < 5, "{:?}", started.elapsed());
  }
}
