use super::*;
use crate::lyrics::rules::VARIANT_RECHECK;
use std::time::Duration;

const SYNCED: &str = "[00:01.00]Строка\n[00:03.00]Ещё строка";
const UPLOADER: &str = "juchen";
const TITLE: &str = "gothviolence – не могу уснуть";
const KEY: &str = "sc:1";

fn p(a: &str, t: &str) -> Pair {
  (a.to_string(), t.to_string())
}

/// Подмена сети: какие пары lrclib знает, на каких падает, и журнал вызовов.
#[derive(Default)]
struct Fake {
  synced: Vec<Pair>,
  broken: Vec<Pair>,
  lrclib_calls: Mutex<Vec<Pair>>,
  genius_calls: Mutex<Vec<Pair>>,
  netease_calls: Mutex<Vec<Pair>>,
}

impl Fake {
  fn knows(pairs: &[Pair]) -> Self {
    Self { synced: pairs.to_vec(), ..Self::default() }
  }
  fn lrclib(&self) -> Vec<Pair> {
    self.lrclib_calls.lock().unwrap().clone()
  }
}

impl Source for Fake {
  async fn lrclib(&self, artist: &str, title: &str, _: f64) -> Result<lrclib::Found> {
    let pair = p(artist, title);
    self.lrclib_calls.lock().unwrap().push(pair.clone());
    if self.broken.contains(&pair) {
      anyhow::bail!("сеть");
    }
    Ok(lrclib::Found { synced: self.synced.contains(&pair).then(|| SYNCED.to_string()), plain: None })
  }
  async fn netease(&self, artist: &str, title: &str, _: f64) -> Result<Option<Lyrics>> {
    self.netease_calls.lock().unwrap().push(p(artist, title));
    Ok(None)
  }
  async fn genius(&self, artist: &str, title: &str) -> Result<Option<String>> {
    self.genius_calls.lock().unwrap().push(p(artist, title));
    Ok(None)
  }
}

fn meta(artist: &str, title: &str) -> Meta {
  Meta { artist: artist.into(), title: title.into(), duration: 120.0 }
}

async fn run(src: &Fake, m: &Meta, rules: &Rules, misses: &Mutex<VariantMisses>, now: Instant) -> Result<Option<Lyrics>> {
  search(src, Query { meta: m, key: KEY }, rules, misses, now).await
}

#[tokio::test]
async fn first_pair_found_variants_not_tried() {
  let src = Fake::knows(&[p(UPLOADER, TITLE)]);
  let found = run(&src, &meta(UPLOADER, TITLE), &Rules::bundled(), &Mutex::default(), Instant::now()).await.unwrap();
  assert!(found.unwrap().is_synced);
  assert_eq!(src.lrclib(), vec![p(UPLOADER, TITLE)]);
}

#[tokio::test]
async fn not_found_tries_reupload_variant() {
  let src = Fake::knows(&[p("gothviolence", "не могу уснуть")]);
  let found = run(&src, &meta(UPLOADER, TITLE), &Rules::bundled(), &Mutex::default(), Instant::now()).await.unwrap();
  assert!(found.unwrap().is_synced);
  let calls = src.lrclib();
  assert_eq!(calls.first(), Some(&p(UPLOADER, TITLE)), "сначала обычная пара");
  assert_eq!(calls.last(), Some(&p("gothviolence", "не могу уснуть")));
  assert!(src.genius_calls.lock().unwrap().is_empty());
}

#[tokio::test]
async fn no_variants_one_request() {
  let src = Fake::default();
  let found = run(&src, &meta("Bones", "Sodium"), &Rules::bundled(), &Mutex::default(), Instant::now()).await.unwrap();
  assert!(found.is_none());
  assert_eq!(src.lrclib(), vec![p("Bones", "Sodium")]);
  assert_eq!(*src.genius_calls.lock().unwrap(), vec![p("Bones", "Sodium")]);
}

#[tokio::test]
async fn network_failure_on_variant_stops_without_miss() {
  let src = Fake { broken: vec![p("gothviolence", "не могу уснуть")], ..Fake::default() };
  let misses = Mutex::default();
  let now = Instant::now();
  assert!(run(&src, &meta(UPLOADER, TITLE), &Rules::bundled(), &misses, now).await.is_err());
  assert_eq!(src.lrclib().last(), Some(&p("gothviolence", "не могу уснуть")), "после сбоя lrclib больше не спрашиваем");
  assert!(!misses.lock().unwrap().is_fresh(KEY, now), "сбой сети — не промах");
}

#[tokio::test]
async fn miss_is_remembered_and_expires() {
  let misses = Mutex::default();
  let now = Instant::now();
  let m = meta(UPLOADER, TITLE);
  let first = Fake::default();
  assert!(run(&first, &m, &Rules::bundled(), &misses, now).await.unwrap().is_none());
  assert!(first.lrclib().contains(&p("gothviolence", "не могу уснуть")));

  let second = Fake::default();
  run(&second, &m, &Rules::bundled(), &misses, now + Duration::from_secs(60)).await.unwrap();
  assert!(second.lrclib().iter().all(|(a, _)| a == UPLOADER), "промах помнится — только обычный поиск");

  let later = Fake::default();
  run(&later, &m, &Rules::bundled(), &misses, now + VARIANT_RECHECK).await.unwrap();
  assert!(later.lrclib().contains(&p("gothviolence", "не могу уснуть")), "промах истёк");
}

#[tokio::test]
async fn manual_recheck_resets_miss() {
  let misses = Mutex::default();
  let now = Instant::now();
  let m = meta(UPLOADER, TITLE);
  run(&Fake::default(), &m, &Rules::bundled(), &misses, now).await.unwrap();
  misses.lock().unwrap().forget(KEY);
  let again = Fake::default();
  run(&again, &m, &Rules::bundled(), &misses, now).await.unwrap();
  assert!(again.lrclib().contains(&p("gothviolence", "не могу уснуть")));
}

#[tokio::test]
async fn reuploader_variants_first() {
  let rules = Rules::parse(r#"{"reuploaders":["Juchen"]}"#).unwrap();
  let src = Fake::default();
  run(&src, &meta(UPLOADER, TITLE), &rules, &Mutex::default(), Instant::now()).await.unwrap();
  assert_eq!(src.lrclib().first(), Some(&p("gothviolence", "не могу уснуть")));
}

#[tokio::test]
async fn manual_pair_replaces_steps() {
  let rules = Rules::parse(r#"{"pairs":{"sc:1":{"artist":"cowboyclicker","title":"doesnt matter"}}}"#).unwrap();
  let src = Fake::default();
  run(&src, &meta("Kleyy", "cowboyclicker - doesnt matter (prod. gloro)"), &rules, &Mutex::default(), Instant::now()).await.unwrap();
  assert_eq!(src.lrclib(), vec![p("cowboyclicker", "doesnt matter")]);
  assert_eq!(*src.genius_calls.lock().unwrap(), vec![p("cowboyclicker", "doesnt matter")]);
}

#[tokio::test]
async fn ignored_track_not_searched() {
  let rules = Rules::parse(r#"{"ignore":["sc:1"]}"#).unwrap();
  let src = Fake::default();
  assert!(run(&src, &meta(UPLOADER, TITLE), &rules, &Mutex::default(), Instant::now()).await.unwrap().is_none());
  assert!(src.lrclib().is_empty() && src.genius_calls.lock().unwrap().is_empty());
}

#[tokio::test]
async fn genius_and_netease_use_search_pair() {
  let src = Fake::default();
  run(&src, &meta("Kleyy", "cowboyclicker - doesnt matter (prod. gloro)"), &Rules::bundled(), &Mutex::default(), Instant::now())
    .await
    .unwrap();
  assert_eq!(*src.genius_calls.lock().unwrap(), vec![p("cowboyclicker", "doesnt matter")]);
  assert_eq!(*src.netease_calls.lock().unwrap(), vec![p("cowboyclicker", "doesnt matter")]);
}
