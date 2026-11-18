//! Кто участвует в треке. У SoundCloud исполнитель — только тот, кто залил трек, а соавторы живут
//! в названии: «A x B - Song (feat. C) [prod. D]». Разбор осторожный: делим только по разделителям
//! с пробелами вокруг («x» внутри слова не трогаем), а «&» без подтверждения не считаем дуэтом —
//! «Simon & Garfunkel» и «Love & Hate - Intro» остаются одним именем / названием.

use std::collections::HashSet;

use serde::Serialize;

/// Роль в треке: основной исполнитель, гость (feat.) или продюсер (prod.).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Role {
  Main,
  Feat,
  Prod,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Credit {
  pub name: String,
  pub role: Role,
}

/// Длиннее — это уже не имя, а кусок названия.
const MAX_NAME_CHARS: usize = 40;

const DASHES: &[&str] = &[" - ", " – ", " — "];
/// Разделители имён, которым верим и без совпадения с тем, кто залил трек.
const STRONG_SEPS: &[&str] = &[", ", " x ", " + ", " vs. ", " vs ", " / "];
/// «&» и «and» часто внутри названия группы или фразы — верим только вместе с тем, кто залил трек.
const WEAK_SEPS: &[&str] = &[" & ", " and "];

/// Пометки прямо в строке: «Song ft. A prod. B».
const INLINE: &[(&str, Role)] = &[
  (" featuring ", Role::Feat),
  (" feat. ", Role::Feat),
  (" feat ", Role::Feat),
  (" ft. ", Role::Feat),
  (" ft ", Role::Feat),
  (" produced by ", Role::Prod),
  (" prod. by ", Role::Prod),
  (" prod by ", Role::Prod),
  (" prod. ", Role::Prod),
];

/// Начало скобки: «(feat. A)», «[prod. B]», «(with C)». Длинные варианты раньше коротких.
const GROUP: &[(&str, Role)] = &[
  ("featuring ", Role::Feat),
  ("feat. ", Role::Feat),
  ("feat.", Role::Feat),
  ("feat ", Role::Feat),
  ("ft. ", Role::Feat),
  ("ft.", Role::Feat),
  ("ft ", Role::Feat),
  ("with ", Role::Feat),
  ("w/ ", Role::Feat),
  ("w/", Role::Feat),
  ("produced by ", Role::Prod),
  ("prod. by ", Role::Prod),
  ("prod by ", Role::Prod),
  ("prod. ", Role::Prod),
  ("prod.", Role::Prod),
  ("prod ", Role::Prod),
];

/// Ключ исполнителя: только буквы и цифры в нижнем регистре — «Lil Peep», «lilpeep» и «LIL PEEP!»
/// сходятся в один узел карты. Если букв нет совсем («$$$»), — само имя в нижнем регистре.
pub fn key(name: &str) -> String {
  let k: String = name.chars().filter(|c| c.is_alphanumeric()).flat_map(char::to_lowercase).collect();
  if k.is_empty() {
    name.trim().to_lowercase()
  } else {
    k
  }
}

/// Имя без мусора по краям: пробелы, «@», кавычки, скобки и знаки препинания в конце.
pub fn clean_name(s: &str) -> String {
  s.trim()
    .trim_start_matches('@')
    .trim_matches(|c: char| matches!(c, '"' | '«' | '»' | '(' | ')' | '[' | ']'))
    .trim_end_matches(|c: char| matches!(c, '.' | ',' | ';' | ':' | '!' | '?' | '-' | '–' | '—' | '|' | '/'))
    .trim()
    .to_string()
}

/// Все участники трека, без повторов (кто встретился раньше — с той ролью и остаётся, основные первыми).
/// `parse_dash` — искать исполнителей слева от « - » (только SoundCloud: у остальных сервисов
/// исполнители уже перечислены в `listed`).
pub fn credits(title: &str, uploader: &str, listed: &[String], parse_dash: bool) -> Vec<Credit> {
  let (stripped, mut extra) = strip_groups(title);
  let mains = if parse_dash {
    let upl = clean_name(uploader);
    match split_dash(&stripped) {
      Some((left, right)) => {
        let (head, left_more) = inline(left);
        let (_, right_more) = inline(right);
        extra.extend(left_more);
        extra.extend(right_more);
        left_mains(head, &upl)
      }
      None => {
        extra.extend(inline(&stripped).1);
        vec![upl]
      }
    }
  } else {
    extra.extend(inline(&stripped).1);
    let named: Vec<String> = listed.iter().map(|n| clean_name(n)).collect();
    if named.iter().any(|n| !n.is_empty()) {
      named
    } else {
      vec![clean_name(uploader)]
    }
  };
  let mut seen = HashSet::new();
  mains
    .into_iter()
    .map(|name| Credit { name, role: Role::Main })
    .chain(extra)
    .filter(|c| !c.name.is_empty() && c.name.chars().count() <= MAX_NAME_CHARS && seen.insert(key(&c.name)))
    .collect()
}

/// Основные исполнители слева от тире. Совпало с тем, кто залил, целиком — одно имя («Simon & Garfunkel»).
/// Иначе делим: верим, если среди имён есть залившим или разделитель «сильный» («A x B»);
/// одно чужое имя слева («Intro - Song» или «Artist - Song» у лейбла) — основной только тот, кто залил.
fn left_mains(head: &str, upl: &str) -> Vec<String> {
  let upl_key = key(upl);
  if key(head) == upl_key {
    return vec![upl.to_string()];
  }
  let (names, strong) = split_names(head);
  let has_uploader = names.iter().any(|n| key(n) == upl_key);
  if has_uploader || (names.len() >= 2 && strong) {
    names
  } else {
    vec![upl.to_string()]
  }
}

/// Убрать скобочные группы из названия; из групп «feat./prod./with» достать участников.
fn strip_groups(title: &str) -> (String, Vec<Credit>) {
  let mut stripped = String::with_capacity(title.len());
  let mut found = Vec::new();
  let mut last = 0;
  for (start, end) in groups(title) {
    stripped.push_str(&title[last..start]);
    stripped.push(' ');
    // скобки однобайтовые, поэтому срез по байтам безопасен
    found.extend(group_credits(&title[start + 1..end - 1]));
    last = end;
  }
  stripped.push_str(&title[last..]);
  (stripped, found)
}

/// Границы групп `(…)` и `[…]` в байтах, вместе со скобками. Вложенные — до первой закрывающей.
fn groups(title: &str) -> Vec<(usize, usize)> {
  let mut out = Vec::new();
  let mut open: Option<(usize, char)> = None;
  for (i, c) in title.char_indices() {
    match open {
      None if c == '(' => open = Some((i, ')')),
      None if c == '[' => open = Some((i, ']')),
      Some((start, close)) if c == close => {
        out.push((start, i + 1));
        open = None;
      }
      _ => {}
    }
  }
  out
}

fn group_credits(inner: &str) -> Vec<Credit> {
  let t = inner.trim();
  let lower = t.to_ascii_lowercase();
  let Some((prefix, role)) = GROUP.iter().find(|(p, _)| lower.starts_with(*p)) else {
    return Vec::new();
  };
  // внутри одной скобки бывает и «feat. A prod. B»
  let (head, more) = inline(&t[prefix.len()..]);
  let mut out = names_with(head, *role);
  out.extend(more);
  out
}

/// Левая и правая часть по первому тире с пробелами.
fn split_dash(s: &str) -> Option<(&str, &str)> {
  DASHES
    .iter()
    .filter_map(|d| s.find(d).map(|i| (i, d.len())))
    .min_by_key(|(i, _)| *i)
    .map(|(i, len)| (&s[..i], &s[i + len..]))
}

/// Текст до первой пометки «feat./prod.» и участники после пометок.
fn inline(seg: &str) -> (&str, Vec<Credit>) {
  let pats: Vec<&str> = INLINE.iter().map(|(p, _)| *p).collect();
  let hits = find_all(&seg.to_ascii_lowercase(), &pats);
  let Some(first) = hits.first() else {
    return (seg, Vec::new());
  };
  let mut out = Vec::new();
  for (n, (_, end, which)) in hits.iter().enumerate() {
    let until = hits.get(n + 1).map_or(seg.len(), |h| h.0);
    out.extend(names_with(&seg[*end..until], INLINE[*which].1));
  }
  (&seg[..first.0], out)
}

fn names_with(s: &str, role: Role) -> Vec<Credit> {
  split_names(s).0.into_iter().map(|name| Credit { name, role }).collect()
}

/// Делит строку на имена; второе значение — был ли «сильный» разделитель.
fn split_names(s: &str) -> (Vec<String>, bool) {
  let pats: Vec<&str> = STRONG_SEPS.iter().chain(WEAK_SEPS).copied().collect();
  // ASCII-нижний регистр не меняет длину в байтах, поэтому позиции годятся и для `s`
  let hits = find_all(&s.to_ascii_lowercase(), &pats);
  let strong = hits.iter().any(|(_, _, which)| *which < STRONG_SEPS.len());
  let mut parts = Vec::with_capacity(hits.len() + 1);
  let mut start = 0;
  for (from, to, _) in &hits {
    parts.push(&s[start..*from]);
    start = *to;
  }
  parts.push(&s[start..]);
  let mut seen = HashSet::new();
  let names = parts
    .into_iter()
    .map(clean_name)
    .filter(|n| !n.is_empty() && seen.insert(key(n)))
    .collect();
  (names, strong)
}

/// Вхождения шаблонов без наложений, на каждой позиции — самый длинный: (начало, конец, номер шаблона).
fn find_all(lower: &str, pats: &[&str]) -> Vec<(usize, usize, usize)> {
  let mut out = Vec::new();
  let mut i = 0;
  while i < lower.len() {
    if !lower.is_char_boundary(i) {
      i += 1;
      continue;
    }
    let rest = &lower[i..];
    let best = pats.iter().enumerate().filter(|(_, p)| rest.starts_with(**p)).max_by_key(|(_, p)| p.len());
    match best {
      Some((which, p)) => {
        out.push((i, i + p.len(), which));
        i += p.len().max(1);
      }
      None => i += 1,
    }
  }
  out
}

#[cfg(test)]
mod tests {
  use super::*;

  fn sc(title: &str, uploader: &str) -> Vec<(String, Role)> {
    credits(title, uploader, &[], true).into_iter().map(|c| (c.name, c.role)).collect()
  }

  fn main(n: &str) -> (String, Role) {
    (n.to_string(), Role::Main)
  }

  #[test]
  fn key_merges_spellings() {
    assert_eq!(key("Lil Peep"), "lilpeep");
    assert_eq!(key("lilpeep"), "lilpeep");
    assert_eq!(key("LIL PEEP!"), "lilpeep");
    assert_eq!(key("Кино"), "кино");
    assert_eq!(key("$$$"), "$$$");
  }

  #[test]
  fn clean_name_strips_noise() {
    assert_eq!(clean_name("  @cowboyclicker. "), "cowboyclicker");
    assert_eq!(clean_name("«Кино»"), "Кино");
    assert_eq!(clean_name("D)"), "D");
  }

  #[test]
  fn x_inside_word_is_not_a_separator() {
    assert_eq!(sc("Alex Wann - Maximum", "Alex Wann"), vec![main("Alex Wann")]);
    // совпало с залившим — берём его написание, красивое имя потом выберет граф по частоте
    assert_eq!(sc("Xxanax - Phonk", "xxanax"), vec![main("xxanax")]);
  }

  #[test]
  fn x_between_names_gives_two_mains() {
    assert_eq!(sc("A x B - Song", "phonk channel"), vec![main("A"), main("B")]);
    assert_eq!(sc("Rex X Lexx - Song", "rex"), vec![main("Rex"), main("Lexx")]);
  }

  #[test]
  fn band_with_ampersand_stays_one_name() {
    assert_eq!(sc("Simon & Garfunkel - Song", "Simon & Garfunkel"), vec![main("Simon & Garfunkel")]);
    assert_eq!(sc("Simon & Garfunkel - Song", "simongarfunkel"), vec![main("simongarfunkel")]);
  }

  #[test]
  fn ampersand_needs_uploader_to_split() {
    // «Love & Hate» — не дуэт, а название: основной — тот, кто залил
    assert_eq!(sc("Love & Hate - Intro", "someone"), vec![main("someone")]);
    // а здесь залил один из двоих — значит, дуэт
    assert_eq!(sc("A & B - Song", "a"), vec![main("A"), main("B")]);
  }

  #[test]
  fn single_foreign_name_left_of_dash_keeps_uploader() {
    assert_eq!(sc("Intro - Interlude", "beatmaker"), vec![main("beatmaker")]);
  }

  #[test]
  fn feat_in_brackets_gives_all_guests() {
    assert_eq!(
      sc("Song (feat. A & B)", "U"),
      vec![main("U"), ("A".into(), Role::Feat), ("B".into(), Role::Feat)]
    );
    assert_eq!(sc("Song [ft.C]", "U"), vec![main("U"), ("C".into(), Role::Feat)]);
  }

  #[test]
  fn prod_is_parsed_in_brackets_and_inline() {
    assert_eq!(sc("Song [prod. D]", "U"), vec![main("U"), ("D".into(), Role::Prod)]);
    assert_eq!(sc("Song (Prod. by D x E)", "U"), vec![main("U"), ("D".into(), Role::Prod), ("E".into(), Role::Prod)]);
    assert_eq!(
      sc("U - Song ft. K prod. P", "U"),
      vec![main("U"), ("K".into(), Role::Feat), ("P".into(), Role::Prod)]
    );
  }

  #[test]
  fn feat_left_of_dash_is_a_guest() {
    assert_eq!(sc("U ft. K - Song", "U"), vec![main("U"), ("K".into(), Role::Feat)]);
  }

  #[test]
  fn plain_brackets_are_ignored() {
    assert_eq!(sc("Song (Slowed + Reverb) [Remix]", "U"), vec![main("U")]);
  }

  #[test]
  fn feat_word_inside_title_is_not_a_marker() {
    assert_eq!(sc("Defeat the feather", "U"), vec![main("U")]);
  }

  #[test]
  fn listed_artists_are_not_split_for_other_services() {
    let listed = vec!["Simon & Garfunkel".to_string(), "B".to_string()];
    let got: Vec<_> = credits("Song (feat. B)", "", &listed, false).into_iter().map(|c| (c.name, c.role)).collect();
    assert_eq!(got, vec![main("Simon & Garfunkel"), main("B")]);
  }

  #[test]
  fn no_listed_falls_back_to_uploader() {
    let got = credits("Song", "Someone", &[], false);
    assert_eq!(got, vec![Credit { name: "Someone".into(), role: Role::Main }]);
  }

  #[test]
  fn too_long_names_are_dropped() {
    let long = "a".repeat(MAX_NAME_CHARS + 1);
    assert_eq!(sc(&format!("Song (feat. {long})"), "U"), vec![main("U")]);
  }
}
