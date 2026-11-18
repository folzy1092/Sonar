//! Граф исполнителей — чистая функция без базы и сети. Узлы — исполнители из медиатеки и
//! прослушиваний (плюс «неоткрытые» соседи снаружи), рёбра — фиты, подписки SoundCloud, общие
//! соавторы и «похожие» сервиса. Веса логарифмические: десятый фит весит не в десять раз больше первого.

use std::collections::{BTreeMap, BTreeSet, HashMap};

use serde::Serialize;

use super::parse::{self, Credit, Role};
use crate::providers::{Artist, Track};

// ——— веса рёбер ———
const FEAT_BASE: f64 = 2.0;
const FEAT_LOG: f64 = 1.5;
const PROD_BASE: f64 = 1.0;
const PROD_LOG: f64 = 0.8;
const FOLLOW_MUTUAL: f64 = 3.0;
const FOLLOW_ONE_WAY: f64 = 1.2;
const COMMON_STEP: f64 = 0.8;
const COMMON_CAP: usize = 3;
const SIMILAR_STEP: f64 = 0.4;
const SIMILAR_CAP: f64 = 1.2;

// ——— веса узлов ———
const PLAYS_FACTOR: f64 = 0.7;
const SAVED_BONUS: f64 = 0.5;
const MIN_LIBRARY_WEIGHT: f64 = 0.3;
const OUTSIDE_BASE: f64 = 0.3;
const OUTSIDE_LOG: f64 = 0.2;

/// У кого больше соавторов, тот «хаб» (сборник, лейбл) — общих соавторов через него не считаем.
const HUB_DEGREE: usize = 40;
/// Сколько «неоткрытых» соседей показываем — самых связанных с медиатекой.
const MAX_UNDISCOVERED: usize = 60;
/// Сколько общих соавторов называем в подсказке (остальное — числом).
const COMMON_NAMES: usize = 3;
/// Сколько любимых исполнителей дают сигнал «сцены» волне.
const SCENE_SEEDS: usize = 20;

/// Трек медиатеки для графа: `in_library` — в лайках, плейлистах или фантомных лайках сервиса;
/// `plays` — сколько раз слушали в Sonar.
#[derive(Debug, Clone)]
pub struct GraphTrack {
  pub track: Track,
  pub in_library: bool,
  pub plays: u32,
}

/// Всё, из чего строится граф: треки, сохранённые исполнители, подписки SoundCloud
/// (`sca:` того, чьи подписки → список) и «похожие» (ref трека → список треков).
pub struct Input<'a> {
  pub tracks: &'a [GraphTrack],
  pub saved: &'a [Artist],
  pub follows: &'a [(String, Vec<Artist>)],
  pub similar: &'a [(String, Vec<Track>)],
}

#[derive(Debug, Clone, Default, Serialize, PartialEq)]
pub struct Graph {
  pub nodes: Vec<Node>,
  pub edges: Vec<Edge>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Node {
  /// Ключ `parse::key` — по нему же рёбра.
  pub key: String,
  pub name: String,
  /// Ссылки на исполнителя в сервисах (`sca:…`, `yma:…`) — для «Открыть исполнителя».
  pub refs: Vec<String>,
  pub avatar_url: Option<String>,
  pub tracks: u32,
  pub plays: u32,
  pub weight: f64,
  /// `false` — сосед снаружи медиатеки, рисуется бледнее.
  pub discovered: bool,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Edge {
  /// Ключи узлов, `a < b`.
  pub a: String,
  pub b: String,
  pub weight: f64,
  pub reasons: Reasons,
}

/// Почему рядом — из этого интерфейс собирает «4 фита · подписаны друг на друга».
#[derive(Debug, Clone, Default, Serialize, PartialEq)]
pub struct Reasons {
  pub feats: u32,
  pub prods: u32,
  pub follow: Option<Follow>,
  /// Имена общих соавторов (до трёх) и сколько их всего.
  pub common: Vec<String>,
  pub common_count: u32,
  pub similar: u32,
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Follow {
  Mutual,
  OneWay,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Neighbor {
  pub key: String,
  pub name: String,
  pub weight: f64,
  pub discovered: bool,
}

#[derive(Default)]
struct NodeAcc {
  spellings: BTreeMap<String, u32>,
  refs: BTreeSet<String>,
  avatar: Option<String>,
  tracks: u32,
  plays: u32,
  saved: bool,
}

impl NodeAcc {
  fn see(&mut self, name: &str) {
    *self.spellings.entry(name.to_string()).or_default() += 1;
  }

  fn attach(&mut self, r: &str, avatar: Option<&String>) {
    if !r.is_empty() {
      self.refs.insert(r.to_string());
    }
    if self.avatar.is_none() {
      self.avatar = avatar.cloned();
    }
  }

  /// Самое частое написание; при равенстве — первое по алфавиту (чтобы карта не прыгала).
  fn name(&self) -> String {
    self
      .spellings
      .iter()
      .max_by(|a, b| a.1.cmp(b.1).then(b.0.cmp(a.0)))
      .map(|(n, _)| n.clone())
      .unwrap_or_default()
  }
}

#[derive(Default)]
struct EdgeAcc {
  feats: u32,
  prods: u32,
  follow: Option<Follow>,
  common: Vec<String>,
  similar: u32,
}

type Nodes = BTreeMap<String, NodeAcc>;
type Edges = BTreeMap<(String, String), EdgeAcc>;

/// Участники трека: у SoundCloud — разбор названия, у остальных — перечисленные исполнители.
pub fn track_credits(t: &Track) -> Vec<Credit> {
  let listed: Vec<String> = t.artists.iter().map(|a| a.name.clone()).collect();
  parse::credits(&t.title, &t.artist, &listed, t.ref_.starts_with("sc:"))
}

pub fn build(input: &Input) -> Graph {
  let mut nodes = Nodes::new();
  let mut edges = Edges::new();
  let track_keys = add_tracks(&mut nodes, &mut edges, input.tracks);
  for a in input.saved {
    let k = parse::key(&a.name);
    if k.is_empty() {
      continue;
    }
    let acc = nodes.entry(k).or_default();
    acc.see(&a.name);
    acc.saved = true;
    acc.attach(&a.ref_, a.avatar_url.as_ref());
  }
  let mut outside = Nodes::new();
  add_follows(&mut nodes, &mut outside, &mut edges, input.follows);
  add_similar(&nodes, &mut outside, &mut edges, &track_keys, input.similar);
  add_common(&mut edges);
  finish(&nodes, &outside, edges)
}

/// Узлы и фиты из треков; возвращает ref трека → ключи его исполнителей (для «похожих»).
fn add_tracks(nodes: &mut Nodes, edges: &mut Edges, tracks: &[GraphTrack]) -> HashMap<String, Vec<String>> {
  let mut track_keys = HashMap::new();
  for gt in tracks {
    if track_keys.contains_key(&gt.track.ref_) {
      continue;
    }
    let credits = track_credits(&gt.track);
    for c in &credits {
      let k = parse::key(&c.name);
      let acc = nodes.entry(k.clone()).or_default();
      acc.see(&c.name);
      acc.tracks += u32::from(gt.in_library);
      acc.plays += gt.plays;
      for a in gt.track.artists.iter().filter(|a| parse::key(&a.name) == k) {
        acc.attach(&a.ref_, a.avatar_url.as_ref());
      }
    }
    add_credit_pairs(edges, &credits);
    let keys = credits.iter().filter(|c| c.role != Role::Prod).map(|c| parse::key(&c.name)).collect();
    track_keys.insert(gt.track.ref_.clone(), keys);
  }
  track_keys
}

fn pair(a: &str, b: &str) -> (String, String) {
  if a < b {
    (a.to_string(), b.to_string())
  } else {
    (b.to_string(), a.to_string())
  }
}

/// Все со всеми в одном треке: исполнители и гости — фит, продюсер с исполнителем — prod.
fn add_credit_pairs(edges: &mut Edges, credits: &[Credit]) {
  for (i, a) in credits.iter().enumerate() {
    for b in &credits[i + 1..] {
      let prods = usize::from(a.role == Role::Prod) + usize::from(b.role == Role::Prod);
      let (ka, kb) = (parse::key(&a.name), parse::key(&b.name));
      if ka == kb || prods == 2 {
        continue;
      }
      let e = edges.entry(pair(&ka, &kb)).or_default();
      if prods == 0 {
        e.feats += 1;
      } else {
        e.prods += 1;
      }
    }
  }
}

fn ref_index(nodes: &Nodes) -> HashMap<String, String> {
  nodes.iter().flat_map(|(k, acc)| acc.refs.iter().map(move |r| (r.clone(), k.clone()))).collect()
}

/// Подписки SoundCloud: взаимная — сильная связь, в одну сторону — слабее. На кого подписан
/// исполнитель из медиатеки, но кого в ней нет, — кандидат в «неоткрытые».
fn add_follows(nodes: &mut Nodes, outside: &mut Nodes, edges: &mut Edges, follows: &[(String, Vec<Artist>)]) {
  let by_ref = ref_index(nodes);
  let mut directed: BTreeSet<(String, String)> = BTreeSet::new();
  for (who, list) in follows {
    let Some(from) = by_ref.get(who) else { continue };
    for a in list {
      let to = by_ref.get(&a.ref_).cloned().unwrap_or_else(|| parse::key(&a.name));
      if to.is_empty() || &to == from {
        continue;
      }
      let acc = match nodes.get_mut(&to) {
        Some(acc) => acc,
        None => {
          let acc = outside.entry(to.clone()).or_default();
          acc.see(&a.name);
          acc
        }
      };
      acc.attach(&a.ref_, a.avatar_url.as_ref());
      directed.insert((from.clone(), to));
    }
  }
  for (from, to) in &directed {
    let kind = if directed.contains(&(to.clone(), from.clone())) { Follow::Mutual } else { Follow::OneWay };
    let e = edges.entry(pair(from, to)).or_default();
    if e.follow != Some(Follow::Mutual) {
      e.follow = Some(kind);
    }
  }
}

/// «Похожие» сервиса: исполнители похожих треков рядом с исполнителями исходного трека (слабо).
fn add_similar(
  nodes: &Nodes,
  outside: &mut Nodes,
  edges: &mut Edges,
  track_keys: &HashMap<String, Vec<String>>,
  similar: &[(String, Vec<Track>)],
) {
  for (seed, list) in similar {
    let Some(seed_keys) = track_keys.get(seed) else { continue };
    for t in list {
      for c in track_credits(t).into_iter().filter(|c| c.role != Role::Prod) {
        let k = parse::key(&c.name);
        if !nodes.contains_key(&k) {
          let acc = outside.entry(k.clone()).or_default();
          acc.see(&c.name);
          for a in t.artists.iter().filter(|a| parse::key(&a.name) == k) {
            acc.attach(&a.ref_, a.avatar_url.as_ref());
          }
        }
        for s in seed_keys.iter().filter(|s| **s != k) {
          edges.entry(pair(s, &k)).or_default().similar += 1;
        }
      }
    }
  }
}

/// Общий соавтор: A и B оба записывались с C. Через «хабы» не считаем — иначе связано всё со всем.
fn add_common(edges: &mut Edges) {
  let mut adj: BTreeMap<String, BTreeSet<String>> = BTreeMap::new();
  for ((a, b), _) in edges.iter().filter(|(_, e)| e.feats + e.prods > 0) {
    adj.entry(a.clone()).or_default().insert(b.clone());
    adj.entry(b.clone()).or_default().insert(a.clone());
  }
  let mut common: BTreeMap<(String, String), Vec<String>> = BTreeMap::new();
  for (via, around) in adj.iter().filter(|(_, n)| n.len() <= HUB_DEGREE) {
    let around: Vec<&String> = around.iter().collect();
    for (i, a) in around.iter().enumerate() {
      for b in &around[i + 1..] {
        // множество отсортировано, поэтому a < b — пара уже в нужном порядке
        common.entry(((*a).clone(), (*b).clone())).or_default().push(via.clone());
      }
    }
  }
  for (p, via) in common {
    edges.entry(p).or_default().common = via;
  }
}

fn edge_weight(e: &EdgeAcc) -> f64 {
  let feats = if e.feats > 0 { FEAT_BASE + FEAT_LOG * f64::from(e.feats).ln() } else { 0.0 };
  let prods = if e.prods > 0 { PROD_BASE + PROD_LOG * f64::from(e.prods).ln() } else { 0.0 };
  let follow = match e.follow {
    Some(Follow::Mutual) => FOLLOW_MUTUAL,
    Some(Follow::OneWay) => FOLLOW_ONE_WAY,
    None => 0.0,
  };
  let common = COMMON_STEP * e.common.len().min(COMMON_CAP) as f64;
  let similar = (SIMILAR_STEP * f64::from(e.similar)).min(SIMILAR_CAP);
  feats + prods + follow + common + similar
}

fn library_weight(acc: &NodeAcc) -> f64 {
  let saved = if acc.saved { SAVED_BONUS } else { 0.0 };
  let w = (1.0 + f64::from(acc.tracks)).ln() + PLAYS_FACTOR * (1.0 + f64::from(acc.plays)).ln() + saved;
  w.max(MIN_LIBRARY_WEIGHT)
}

fn round3(x: f64) -> f64 {
  (x * 1000.0).round() / 1000.0
}

/// Взвесить рёбра, оставить самых связанных «неоткрытых», собрать ответ в устойчивом порядке.
fn finish(nodes: &Nodes, outside: &Nodes, edges: Edges) -> Graph {
  let weighted: Vec<((String, String), EdgeAcc, f64)> = edges
    .into_iter()
    .map(|(p, e)| {
      let w = edge_weight(&e);
      (p, e, w)
    })
    .filter(|(_, _, w)| *w > 0.0)
    .collect();
  let kept = rank_outside(nodes, outside, &weighted);

  let mut out_nodes: Vec<Node> = nodes
    .iter()
    .map(|(k, acc)| node(k, acc, library_weight(acc), true))
    .chain(outside.iter().filter_map(|(k, acc)| {
      let links = kept.get(k)?;
      Some(node(k, acc, OUTSIDE_BASE + OUTSIDE_LOG * (1.0 + f64::from(*links)).ln(), false))
    }))
    .collect();
  out_nodes.sort_by(|a, b| b.weight.total_cmp(&a.weight).then(a.key.cmp(&b.key)));

  let names: HashMap<&str, &str> = out_nodes.iter().map(|n| (n.key.as_str(), n.name.as_str())).collect();
  let out_edges: Vec<Edge> = weighted
    .into_iter()
    .filter(|((a, b), _, _)| names.contains_key(a.as_str()) && names.contains_key(b.as_str()))
    .map(|((a, b), e, w)| Edge {
      a,
      b,
      weight: round3(w),
      reasons: Reasons {
        feats: e.feats,
        prods: e.prods,
        follow: e.follow,
        common_count: e.common.len() as u32,
        common: e
          .common
          .iter()
          .take(COMMON_NAMES)
          .map(|k| names.get(k.as_str()).map_or_else(|| k.clone(), |n| n.to_string()))
          .collect(),
        similar: e.similar,
      },
    })
    .collect();
  Graph { nodes: out_nodes, edges: out_edges }
}

fn node(k: &str, acc: &NodeAcc, weight: f64, discovered: bool) -> Node {
  Node {
    key: k.to_string(),
    name: acc.name(),
    refs: acc.refs.iter().cloned().collect(),
    avatar_url: acc.avatar.clone(),
    tracks: acc.tracks,
    plays: acc.plays,
    weight: round3(weight),
    discovered,
  }
}

/// «Неоткрытые», которых показываем: ключ → сколько у него связей с медиатекой.
fn rank_outside(nodes: &Nodes, outside: &Nodes, weighted: &[((String, String), EdgeAcc, f64)]) -> HashMap<String, u32> {
  let mut strength: BTreeMap<&str, (f64, u32)> = BTreeMap::new();
  for ((a, b), _, w) in weighted {
    for (x, y) in [(a, b), (b, a)] {
      if outside.contains_key(x) && nodes.contains_key(y) {
        let s = strength.entry(x.as_str()).or_default();
        s.0 += w;
        s.1 += 1;
      }
    }
  }
  let mut ranked: Vec<(&str, f64, u32)> = strength.into_iter().map(|(k, (w, n))| (k, w, n)).collect();
  ranked.sort_by(|a, b| b.1.total_cmp(&a.1).then(a.0.cmp(b.0)));
  ranked.into_iter().take(MAX_UNDISCOVERED).map(|(k, _, n)| (k.to_string(), n)).collect()
}

/// Ближайшие соседи исполнителя по силе связи (для «Похоже на» и «Новое для тебя»).
pub fn neighbors(g: &Graph, name: &str, limit: usize) -> Vec<Neighbor> {
  let k = parse::key(name);
  let by_key: HashMap<&str, &Node> = g.nodes.iter().map(|n| (n.key.as_str(), n)).collect();
  let mut out: Vec<Neighbor> = g
    .edges
    .iter()
    .filter_map(|e| {
      let other = if e.a == k {
        &e.b
      } else if e.b == k {
        &e.a
      } else {
        return None;
      };
      by_key.get(other.as_str()).map(|n| Neighbor {
        key: n.key.clone(),
        name: n.name.clone(),
        weight: e.weight,
        discovered: n.discovered,
      })
    })
    .collect();
  out.sort_by(|a, b| b.weight.total_cmp(&a.weight).then(a.key.cmp(&b.key)));
  out.truncate(limit);
  out
}

/// «Сцена» для волны: ключ исполнителя → 0..1, насколько он близок к твоим любимым. Берём
/// `SCENE_SEEDS` самых весомых исполнителей медиатеки; сила соседа — вес ребра (от самого сильного)
/// × вес любимого (от самого весомого), из нескольких путей — наибольшая.
pub fn scene(g: &Graph) -> HashMap<String, f64> {
  let max_edge = g.edges.iter().map(|e| e.weight).fold(0.0, f64::max);
  let seeds: Vec<&Node> = g.nodes.iter().filter(|n| n.discovered).take(SCENE_SEEDS).collect();
  let Some(top) = seeds.first().map(|n| n.weight).filter(|w| *w > 0.0) else {
    return HashMap::new();
  };
  if max_edge <= 0.0 {
    return HashMap::new();
  }
  let rel: HashMap<&str, f64> = seeds.iter().map(|n| (n.key.as_str(), n.weight / top)).collect();
  let mut out: HashMap<String, f64> = HashMap::new();
  for e in &g.edges {
    for (from, to) in [(&e.a, &e.b), (&e.b, &e.a)] {
      let Some(r) = rel.get(from.as_str()) else { continue };
      let v = e.weight / max_edge * r;
      let slot = out.entry(to.clone()).or_insert(0.0);
      if v > *slot {
        *slot = v;
      }
    }
  }
  out
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::providers::ArtistRef;

  fn track(r: &str, title: &str, artist: &str, artist_ref: &str) -> Track {
    Track {
      ref_: r.into(),
      title: title.into(),
      artist: artist.into(),
      artists: vec![ArtistRef { ref_: artist_ref.into(), name: artist.into(), avatar_url: None }],
      album: None,
      duration_ms: 1000,
      cover_url: None,
      url: None,
      explicit: false,
      available: true,
      plays: None,
      tags: None,
    }
  }

  fn lib(r: &str, title: &str, artist: &str, artist_ref: &str) -> GraphTrack {
    GraphTrack { track: track(r, title, artist, artist_ref), in_library: true, plays: 0 }
  }

  fn artist(r: &str, name: &str) -> Artist {
    Artist { ref_: r.into(), name: name.into(), avatar_url: None, followers: None, url: None }
  }

  fn graph(tracks: &[GraphTrack], follows: &[(String, Vec<Artist>)], similar: &[(String, Vec<Track>)]) -> Graph {
    build(&Input { tracks, saved: &[], follows, similar })
  }

  fn edge<'a>(g: &'a Graph, a: &str, b: &str) -> &'a Edge {
    let (a, b) = pair(&parse::key(a), &parse::key(b));
    g.edges.iter().find(|e| e.a == a && e.b == b).unwrap_or_else(|| panic!("нет ребра {a}–{b}"))
  }

  fn node_of<'a>(g: &'a Graph, name: &str) -> &'a Node {
    let k = parse::key(name);
    g.nodes.iter().find(|n| n.key == k).unwrap_or_else(|| panic!("нет узла {k}"))
  }

  #[test]
  fn feats_make_edge_with_log_weight() {
    let g = graph(&[lib("sc:1", "U - S1 (feat. K)", "U", "sca:1"), lib("sc:2", "S2 ft. K", "U", "sca:1")], &[], &[]);
    let e = edge(&g, "U", "K");
    assert_eq!(e.reasons.feats, 2);
    assert_eq!(e.weight, round3(FEAT_BASE + FEAT_LOG * 2f64.ln()));
    assert_eq!(node_of(&g, "U").tracks, 2);
    assert_eq!(node_of(&g, "K").tracks, 2);
  }

  #[test]
  fn prod_is_counted_apart_from_feats() {
    let g = graph(&[lib("sc:1", "Song [prod. P]", "U", "sca:1")], &[], &[]);
    let e = edge(&g, "U", "P");
    assert_eq!((e.reasons.feats, e.reasons.prods), (0, 1));
    assert_eq!(e.weight, PROD_BASE);
  }

  #[test]
  fn spellings_merge_into_one_node() {
    let g = graph(&[lib("sc:1", "Song", "lilpeep", "sca:1"), lib("sc:2", "Other (feat. Lil Peep)", "X", "sca:2"), lib("sc:3", "Third (feat. Lil Peep)", "Y", "sca:3")], &[], &[]);
    let n = node_of(&g, "Lil Peep");
    assert_eq!(n.name, "Lil Peep");
    assert_eq!(n.tracks, 3);
    assert_eq!(n.refs, vec!["sca:1".to_string()]);
  }

  #[test]
  fn plays_raise_node_weight() {
    let mut played = lib("sc:2", "Song", "B", "sca:2");
    played.plays = 10;
    let g = graph(&[lib("sc:1", "Song", "A", "sca:1"), played], &[], &[]);
    assert!(node_of(&g, "B").weight > node_of(&g, "A").weight);
    // самый весомый — первым
    assert_eq!(g.nodes[0].key, "b");
  }

  #[test]
  fn mutual_follow_is_stronger_than_one_way() {
    let tracks = [lib("sc:1", "a", "A", "sca:1"), lib("sc:2", "b", "B", "sca:2"), lib("sc:3", "c", "C", "sca:3")];
    let follows = vec![
      ("sca:1".to_string(), vec![artist("sca:2", "B"), artist("sca:3", "C")]),
      ("sca:2".to_string(), vec![artist("sca:1", "A")]),
    ];
    let g = graph(&tracks, &follows, &[]);
    assert_eq!(edge(&g, "A", "B").reasons.follow, Some(Follow::Mutual));
    assert_eq!(edge(&g, "A", "C").reasons.follow, Some(Follow::OneWay));
    assert!(edge(&g, "A", "B").weight > edge(&g, "A", "C").weight);
  }

  #[test]
  fn followed_outsiders_are_undiscovered_and_capped() {
    let many: Vec<Artist> = (0..MAX_UNDISCOVERED + 10).map(|i| artist(&format!("sca:{}", 100 + i), &format!("Out{i}"))).collect();
    let g = graph(&[lib("sc:1", "a", "A", "sca:1")], &[("sca:1".to_string(), many)], &[]);
    let hidden: Vec<&Node> = g.nodes.iter().filter(|n| !n.discovered).collect();
    assert_eq!(hidden.len(), MAX_UNDISCOVERED);
    assert!(hidden.iter().all(|n| n.weight < node_of(&g, "A").weight + 1.0));
    assert!(g.edges.iter().all(|e| g.nodes.iter().any(|n| n.key == e.a) && g.nodes.iter().any(|n| n.key == e.b)));
  }

  #[test]
  fn common_collaborator_links_two_artists() {
    let g = graph(&[lib("sc:1", "x (feat. C)", "A", "sca:1"), lib("sc:2", "y (feat. C)", "B", "sca:2")], &[], &[]);
    let e = edge(&g, "A", "B");
    assert_eq!(e.reasons.common, vec!["C".to_string()]);
    assert_eq!(e.reasons.common_count, 1);
    assert_eq!(e.weight, COMMON_STEP);
  }

  #[test]
  fn similar_adds_weak_edge_to_outsider() {
    let similar = vec![("sc:1".to_string(), vec![track("sc:9", "z", "Z", "sca:9")])];
    let g = graph(&[lib("sc:1", "a", "A", "sca:1")], &[], &similar);
    let e = edge(&g, "A", "Z");
    assert_eq!(e.reasons.similar, 1);
    assert_eq!(e.weight, SIMILAR_STEP);
    assert!(!node_of(&g, "Z").discovered);
  }

  #[test]
  fn saved_artist_without_tracks_is_a_node() {
    let g = build(&Input { tracks: &[], saved: &[artist("yma:5", "Кино")], follows: &[], similar: &[] });
    let n = node_of(&g, "Кино");
    assert!(n.discovered);
    assert_eq!(n.refs, vec!["yma:5".to_string()]);
    assert!(n.weight >= MIN_LIBRARY_WEIGHT);
  }

  #[test]
  fn build_is_deterministic() {
    let tracks = [lib("sc:1", "A x B - s (feat. C)", "A", "sca:1"), lib("sc:2", "s [prod. D]", "B", "sca:2"), lib("ym:3", "s", "E", "yma:3")];
    assert_eq!(graph(&tracks, &[], &[]), graph(&tracks, &[], &[]));
  }

  #[test]
  fn duplicate_tracks_count_once() {
    let g = graph(&[lib("sc:1", "s (feat. K)", "U", "sca:1"), lib("sc:1", "s (feat. K)", "U", "sca:1")], &[], &[]);
    assert_eq!(edge(&g, "U", "K").reasons.feats, 1);
  }

  #[test]
  fn neighbors_are_sorted_by_strength() {
    let g = graph(
      &[lib("sc:1", "x (feat. K)", "U", "sca:1"), lib("sc:2", "y (feat. K)", "U", "sca:1"), lib("sc:3", "z [prod. P]", "U", "sca:1")],
      &[],
      &[],
    );
    let names: Vec<String> = neighbors(&g, "u", 10).into_iter().map(|n| n.name).collect();
    assert_eq!(names, vec!["K".to_string(), "P".to_string()]);
    assert_eq!(neighbors(&g, "U", 1).len(), 1);
    assert!(neighbors(&g, "nobody", 10).is_empty());
  }

  #[test]
  fn scene_marks_neighbours_of_favourites() {
    assert!(scene(&Graph::default()).is_empty());
    let similar = vec![("sc:1".to_string(), vec![track("sc:9", "z", "Z", "sca:9")])];
    let g = graph(&[lib("sc:1", "a (feat. K)", "A", "sca:1")], &[], &similar);
    let s = scene(&g);
    assert!(s["k"] > s["z"], "фит сильнее «похожих»");
    assert!(s.values().all(|v| *v > 0.0 && *v <= 1.0));
  }
}
