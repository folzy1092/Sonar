//! Данные для своей волны (SPEC §3.7): сиды, сигналы вкуса, дизлайки и пропуски.

use super::{now_ms, Store, LOCAL_USER};
use crate::providers::registry::{parse_ref, RefKind};
use anyhow::Result;
use rusqlite::{params, OptionalExtension};
use std::collections::{HashMap, HashSet};

const DAY: i64 = 24 * 3600 * 1000;

/// Профиль тегов смотрит на столько дней истории (лайки — на всю).
const PROFILE_DAYS: i64 = 180;
/// Полураспад веса прослушивания, пропуска и исхода волны, дней.
const HALF_LIFE_DAYS: f64 = 30.0;
/// Полураспад веса лайка, дней; но не ниже `LIKE_FLOOR` — старый лайк всё равно что-то значит.
const LIKE_HALF_LIFE_DAYS: f64 = 90.0;
const LIKE_FLOOR: f64 = 0.3;
const LIKE_WEIGHT: f64 = 1.5;
/// Тег, за которым меньше такого суммарного веса событий, профиль не оценивает — мало данных.
const MIN_TAG_SUPPORT: f64 = 2.0;
/// Сколько «воображаемых» событий с общей долей плюсов добавляется каждому тегу — чтобы редкий тег
/// не получал крайнюю оценку из двух-трёх случаев.
const PRIOR_STRENGTH: f64 = 5.0;
/// Общая доля плюсов, пока минусов нет совсем.
const DEFAULT_POSITIVE_SHARE: f64 = 0.8;

/// Вес события с возрастом `age_ms` и полураспадом `half_life_days`.
fn decay(age_ms: i64, half_life_days: f64) -> f64 {
  0.5f64.powf(age_ms.max(0) as f64 / DAY as f64 / half_life_days)
}

/// Тег → (сумма «за», сумма «против»).
type TagSums = HashMap<String, (f64, f64)>;

fn add_tags(sums: &mut TagSums, tags: &[String], pos: f64, neg: f64) {
  for t in tags {
    let e = sums.entry(t.clone()).or_default();
    e.0 += pos;
    e.1 += neg;
  }
}

/// Оценка каждого тега −1…1 из сумм «за» и «против» (docs/WAVE.md 2.4). `p0` — общая доля плюсов;
/// оценка тега — его доля плюсов, подтянутая к `p0` (`PRIOR_STRENGTH` воображаемых событий), минус
/// `p0`: тег, который есть у всего подряд, — около нуля, тег только с пропусками — минус, тег только с
/// любимым — плюс. Теги с малым весом событий не оцениваются.
pub fn tag_values(sums: &TagSums) -> HashMap<String, f64> {
  let pos: f64 = sums.values().map(|v| v.0).sum();
  let neg: f64 = sums.values().map(|v| v.1).sum();
  let p0 = if neg > 0.0 && pos + neg > 0.0 { pos / (pos + neg) } else { DEFAULT_POSITIVE_SHARE };
  sums
    .iter()
    .filter(|(_, (p, n))| p + n >= MIN_TAG_SUPPORT)
    .map(|(t, (p, n))| (t.clone(), (p + PRIOR_STRENGTH * p0) / (p + n + PRIOR_STRENGTH) - p0))
    .collect()
}
/// Артисты строки истории: из `artists_json` кэша треков (совместный трек — все), а если записи
/// нет — сохранённая строка `artist` (как `wave::artist_names`).
fn row_artists(artist: &str, json: Option<String>) -> Vec<String> {
  let list: Vec<crate::providers::ArtistRef> = json.and_then(|j| serde_json::from_str(&j).ok()).unwrap_or_default();
  crate::wave::artist_names(artist, &list)
}

/// Вкус по истории: лайкнутые исполнители, «за» и «против» артиста (по имени в нижнем регистре; у
/// совместного трека засчитывается каждому артисту — `wave::artist_keys`). Суммы с затуханием
/// (docs/WAVE.md 2.1–2.3): событие весит `0.5 ^ (возраст / 30 дней)`, окно 180 дней.
#[derive(Debug, Default, Clone)]
pub struct Taste {
  pub liked_artists: HashSet<String>,
  /// Σ вес · p по прослушиваниям: дослушал (≥ 80 %) — p = 1, иначе 0.4.
  pub plays: HashMap<String, f64>,
  /// Σ вес · |оценка| по пропускам.
  pub skips: HashMap<String, f64>,
  /// Штраф самому треку: Σ вес · |оценка| по его пропускам.
  pub track_skips: HashMap<String, f64>,
  /// Доля прослушиваний артиста в это время суток (±2 ч от текущего часа, за 60 дней), 0…1.
  pub hour_share: HashMap<String, f64>,
  /// Профиль тегов: тег → оценка −1…1 по лайкам, прослушиваниям, пропускам и 👎 (`Store::tag_profile`).
  pub tag_profile: HashMap<String, f64>,
  /// Профиль тегов режима волны («Грустная», «Жёсткая» …): чем кончались треки с тегом именно в нём.
  pub mode_tag_profile: HashMap<String, f64>,
}

impl Store {
  fn refs(&self, sql: &str, p: impl rusqlite::Params) -> Result<Vec<String>> {
    let mut st = self.db.prepare(sql)?;
    let rows = st.query_map(p, |r| r.get::<_, String>(0))?;
    Ok(rows.collect::<rusqlite::Result<_>>()?)
  }

  /// Последние лайки треков (новые первыми).
  pub fn recent_like_refs(&self, n: usize) -> Result<Vec<String>> {
    self.refs(
      "SELECT ref FROM likes WHERE user_id = ?1 AND kind = 'track' AND deleted = 0 ORDER BY added_at DESC LIMIT ?2",
      params![LOCAL_USER, n as i64],
    )
  }

  /// Старые лайки (после `skip` последних) — для «разведки».
  pub fn old_like_refs(&self, skip: usize, n: usize) -> Result<Vec<String>> {
    self.refs(
      "SELECT ref FROM likes WHERE user_id = ?1 AND kind = 'track' AND deleted = 0
       ORDER BY added_at DESC LIMIT ?3 OFFSET ?2",
      params![LOCAL_USER, skip as i64, n as i64],
    )
  }

  /// Последние дослушанные (≥ 80 % длительности) — «вкус сейчас».
  pub fn recent_finished_refs(&self, n: usize) -> Result<Vec<String>> {
    self.refs(
      "SELECT p.ref FROM plays p JOIN tracks t ON t.ref = p.ref
       WHERE p.user_id = ?1 AND t.duration_ms > 0 AND p.listened_ms * 5 >= t.duration_ms * 4
       GROUP BY p.ref ORDER BY MAX(p.played_at) DESC LIMIT ?2",
      params![LOCAL_USER, n as i64],
    )
  }

  /// Недавно игравшие треки (без повторов, свежие первыми) — «Недавнее» на главной.
  pub fn recent_play_refs(&self, n: usize) -> Result<Vec<String>> {
    self.refs(
      "SELECT ref FROM plays WHERE user_id = ?1 GROUP BY ref ORDER BY MAX(played_at) DESC LIMIT ?2",
      params![LOCAL_USER, n as i64],
    )
  }

  /// Что слушали за последние `days` дней — волна это не повторяет.
  pub fn played_since_days(&self, days: i64) -> Result<HashSet<String>> {
    Ok(self
      .refs("SELECT DISTINCT ref FROM plays WHERE user_id = ?1 AND played_at >= ?2", params![LOCAL_USER, now_ms() - days * DAY])?
      .into_iter()
      .collect())
  }

  pub fn disliked_refs(&self) -> Result<Vec<String>> {
    self.refs("SELECT ref FROM dislikes WHERE user_id = ?1 AND deleted = 0", params![LOCAL_USER])
  }

  /// 👎: трек больше не попадает в волну (снятие — `on = false`, строка остаётся для синка).
  pub fn set_dislike(&self, r: &str, artist: &str, on: bool) -> Result<()> {
    let rev = self.next_rev()?;
    self.db.execute(
      "INSERT INTO dislikes (user_id, ref, artist, added_at, deleted, rev) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
       ON CONFLICT(user_id, ref) DO UPDATE SET deleted = ?5, added_at = ?4, rev = ?6",
      params![LOCAL_USER, r, artist, now_ms(), if on { 0 } else { 1 }, rev],
    )?;
    Ok(())
  }

  /// Ручной пропуск в волне с оценкой < 0 (`wave::reward`) — минус артисту и треку.
  pub fn add_skip(&self, r: &str, artist: &str, played_ms: i64) -> Result<()> {
    self.db.execute(
      "INSERT INTO skips (user_id, ref, artist, played_ms, at) VALUES (?1, ?2, ?3, ?4, ?5)",
      params![LOCAL_USER, r, artist, played_ms, now_ms()],
    )?;
    Ok(())
  }

  /// Сигналы вкуса за последние 90 дней.
  /// Время суток: кого ты слушаешь в эти часы (±2 ч) чаще, чем обычно. `tz_min` — смещение
  /// часового пояса как у `Date.getTimezoneOffset()` (минуты, UTC минус местное).
  pub fn hour_share(&self, tz_min: i64) -> Result<HashMap<String, f64>> {
    let since = now_ms() - 60 * DAY;
    let local_ms = now_ms() - tz_min * 60_000;
    let hour = (local_ms / 3_600_000).rem_euclid(24);
    let mut st = self.db.prepare(
      "SELECT p.artist, t.artists_json, ((p.played_at - ?3 * 60000) / 3600000) % 24 AS h
       FROM plays p LEFT JOIN tracks t ON t.ref = p.ref WHERE p.user_id = ?1 AND p.played_at >= ?2",
    )?;
    let rows = st.query_map(params![LOCAL_USER, since, tz_min], |r| {
      Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?, r.get::<_, i64>(2)?))
    })?;
    let mut near: HashMap<String, f64> = HashMap::new();
    let mut all: HashMap<String, f64> = HashMap::new();
    for row in rows {
      let (artist, json, h) = row?;
      let d = (h.rem_euclid(24) - hour).rem_euclid(24);
      for a in row_artists(&artist, json) {
        *all.entry(a.clone()).or_insert(0.0) += 1.0;
        if d <= 2 || d >= 22 {
          *near.entry(a).or_insert(0.0) += 1.0;
        }
      }
    }
    Ok(near.into_iter().filter_map(|(a, n)| all.get(&a).filter(|&&t| t >= 3.0).map(|t| (a, n / t))).collect())
  }

  /// Профиль тегов (docs/WAVE.md 2.4): `тег → оценка −1…1`.
  /// `mode = None` — общий: лайки (вес 1.5, полураспад 90 дней, не ниже 0.3), прослушивания
  /// (дослушал — 1, иначе 0.4), пропуски и 👎 — против; полураспад 30 дней, окно 180.
  /// `mode = Some(режим)` — только исходы **этого режима** волны из `wave_events` (оценка > 0 — «за»,
  /// < 0 — «против»): так «Грустная» учится, что заходит тебе в грусти, а не вообще.
  pub fn tag_profile(&self, mode: Option<&str>) -> Result<HashMap<String, f64>> {
    let now = now_ms();
    let since = now - PROFILE_DAYS * DAY;
    let mut sums = TagSums::new();
    // теги строки: без имени собственного артиста
    let tags_of = |tags: String, artist: &str, json: Option<String>| crate::wave::parse_tags(&tags, &row_artists(artist, json));
    match mode {
      Some(m) => {
        let mut st = self.db.prepare(
          "SELECT t.tags, t.artist, t.artists_json, e.served_at, e.reward FROM wave_events e JOIN tracks t ON t.ref = e.ref
           WHERE e.user_id = ?1 AND e.mode = ?2 AND e.reward IS NOT NULL AND e.served_at >= ?3 AND t.tags IS NOT NULL",
        )?;
        let rows = st.query_map(params![LOCAL_USER, m, since], |r| {
          Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, Option<String>>(2)?, r.get::<_, i64>(3)?, r.get::<_, f64>(4)?))
        })?;
        for row in rows {
          let (tags, artist, json, at, reward) = row?;
          let w = decay(now - at, HALF_LIFE_DAYS);
          add_tags(&mut sums, &tags_of(tags, &artist, json), w * reward.max(0.0), w * (-reward).max(0.0));
        }
      }
      None => {
        let mut st = self.db.prepare(
          "SELECT t.tags, t.artist, t.artists_json, l.added_at FROM likes l JOIN tracks t ON t.ref = l.ref
           WHERE l.user_id = ?1 AND l.kind = 'track' AND l.deleted = 0 AND t.tags IS NOT NULL",
        )?;
        let rows = st.query_map([LOCAL_USER], |r| {
          Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, Option<String>>(2)?, r.get::<_, i64>(3)?))
        })?;
        for row in rows {
          let (tags, artist, json, at) = row?;
          let w = LIKE_WEIGHT * decay(now - at, LIKE_HALF_LIFE_DAYS).max(LIKE_FLOOR);
          add_tags(&mut sums, &tags_of(tags, &artist, json), w, 0.0);
        }

        let mut st = self.db.prepare(
          "SELECT t.tags, t.artist, t.artists_json, p.played_at, p.listened_ms, t.duration_ms FROM plays p
           JOIN tracks t ON t.ref = p.ref WHERE p.user_id = ?1 AND p.played_at >= ?2 AND t.tags IS NOT NULL",
        )?;
        let rows = st.query_map(params![LOCAL_USER, since], |r| {
          Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, Option<String>>(2)?,
            r.get::<_, i64>(3)?,
            r.get::<_, i64>(4)?,
            r.get::<_, i64>(5)?,
          ))
        })?;
        for row in rows {
          let (tags, artist, json, at, listened, duration) = row?;
          let full = if duration > 0 { listened * 5 >= duration * 4 } else { listened >= 150_000 };
          let p = if full { 1.0 } else { 0.4 };
          add_tags(&mut sums, &tags_of(tags, &artist, json), decay(now - at, HALF_LIFE_DAYS) * p, 0.0);
        }

        let mut st = self.db.prepare(
          "SELECT t.tags, t.artist, t.artists_json, s.at, s.played_ms, t.duration_ms FROM skips s
           JOIN tracks t ON t.ref = s.ref WHERE s.user_id = ?1 AND s.at >= ?2 AND t.tags IS NOT NULL",
        )?;
        let rows = st.query_map(params![LOCAL_USER, since], |r| {
          Ok((
            r.get::<_, String>(0)?,
            r.get::<_, String>(1)?,
            r.get::<_, Option<String>>(2)?,
            r.get::<_, i64>(3)?,
            r.get::<_, i64>(4)?,
            r.get::<_, i64>(5)?,
          ))
        })?;
        for row in rows {
          let (tags, artist, json, at, played, duration) = row?;
          // насколько плох пропуск — по той же шкале, что оценка исхода; длительность неизвестна — как ранний
          let m = if duration > 0 { -crate::wave::reward(played.max(0) as u64, duration as u64, true, false, false) } else { 1.0 };
          add_tags(&mut sums, &tags_of(tags, &artist, json), 0.0, decay(now - at, HALF_LIFE_DAYS) * m.max(0.0));
        }

        // 👎 — явный минус, сильнее любого пропуска
        let mut st = self.db.prepare(
          "SELECT t.tags, t.artist, t.artists_json, d.added_at FROM dislikes d JOIN tracks t ON t.ref = d.ref
           WHERE d.user_id = ?1 AND d.deleted = 0 AND d.added_at >= ?2 AND t.tags IS NOT NULL",
        )?;
        let rows = st.query_map(params![LOCAL_USER, since], |r| {
          Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, Option<String>>(2)?, r.get::<_, i64>(3)?))
        })?;
        for row in rows {
          let (tags, artist, json, at) = row?;
          add_tags(&mut sums, &tags_of(tags, &artist, json), 0.0, 2.0 * decay(now - at, HALF_LIFE_DAYS));
        }
      }
    }
    Ok(tag_values(&sums))
  }

  pub fn taste(&self) -> Result<Taste> {
    let now = now_ms();
    let since = now - PROFILE_DAYS * DAY;
    let mut t = Taste::default();
    // артисты — из кэша треков (совместный трек засчитывается каждому), нет записи — строка из истории
    let mut st = self.db.prepare(
      "SELECT p.artist, t.artists_json, p.played_at, p.listened_ms, t.duration_ms FROM plays p
       LEFT JOIN tracks t ON t.ref = p.ref WHERE p.user_id = ?1 AND p.played_at >= ?2",
    )?;
    let rows = st.query_map(params![LOCAL_USER, since], |r| {
      Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?, r.get::<_, i64>(2)?, r.get::<_, i64>(3)?, r.get::<_, Option<i64>>(4)?))
    })?;
    for row in rows {
      let (artist, json, at, listened, duration) = row?;
      let duration = duration.unwrap_or(0);
      let full = if duration > 0 { listened * 5 >= duration * 4 } else { listened >= 150_000 };
      let w = decay(now - at, HALF_LIFE_DAYS) * if full { 1.0 } else { 0.4 };
      for a in row_artists(&artist, json) {
        *t.plays.entry(a).or_insert(0.0) += w;
      }
    }
    let mut st = self.db.prepare(
      "SELECT s.ref, s.artist, t.artists_json, s.at, s.played_ms, t.duration_ms FROM skips s
       LEFT JOIN tracks t ON t.ref = s.ref WHERE s.user_id = ?1 AND s.at >= ?2",
    )?;
    let rows = st.query_map(params![LOCAL_USER, since], |r| {
      Ok((
        r.get::<_, String>(0)?,
        r.get::<_, String>(1)?,
        r.get::<_, Option<String>>(2)?,
        r.get::<_, i64>(3)?,
        r.get::<_, i64>(4)?,
        r.get::<_, Option<i64>>(5)?,
      ))
    })?;
    for row in rows {
      let (r, artist, json, at, played, duration) = row?;
      let duration = duration.unwrap_or(0);
      // насколько плох пропуск — по шкале оценки исхода; длительность неизвестна — как ранний
      let m = if duration > 0 { (-crate::wave::reward(played.max(0) as u64, duration as u64, true, false, false)).max(0.0) } else { 1.0 };
      let w = decay(now - at, HALF_LIFE_DAYS) * m;
      if w <= 0.0 {
        continue;
      }
      *t.track_skips.entry(r).or_insert(0.0) += w;
      for a in row_artists(&artist, json) {
        *t.skips.entry(a).or_insert(0.0) += w;
      }
    }
    let mut st = self.db.prepare(
      "SELECT t.artist, t.artists_json FROM likes l JOIN tracks t ON t.ref = l.ref
       WHERE l.user_id = ?1 AND l.kind = 'track' AND l.deleted = 0",
    )?;
    for row in st.query_map([LOCAL_USER], |r| Ok((r.get::<_, String>(0)?, r.get::<_, Option<String>>(1)?)))? {
      let (artist, json) = row?;
      t.liked_artists.extend(row_artists(&artist, json));
    }
    Ok(t)
  }

  /// «Забытые любимые» для волны (docs/WAVE.md 4.1): лайкнутые треки из кэша, которые не играли
  /// `days` дней (или ни разу), без 👎; до `n` штук вперемешку.
  pub fn forgotten_likes(&self, days: i64, n: usize) -> Result<Vec<crate::providers::Track>> {
    let refs = self.refs(
      "SELECT l.ref FROM likes l JOIN tracks t ON t.ref = l.ref
       WHERE l.user_id = ?1 AND l.kind = 'track' AND l.deleted = 0
         AND NOT EXISTS (SELECT 1 FROM plays p WHERE p.user_id = ?1 AND p.ref = l.ref AND p.played_at >= ?2)
         AND NOT EXISTS (SELECT 1 FROM dislikes d WHERE d.user_id = ?1 AND d.ref = l.ref AND d.deleted = 0)
       ORDER BY RANDOM() LIMIT ?3",
      params![LOCAL_USER, now_ms() - days * DAY, n as i64],
    )?;
    self.tracks(&refs)
  }

  /// Сиды, чьи предложения в волне чаще 60 % заканчивались минусом (не меньше 5 исходов за `days`
  /// дней), — их вес при выборе сидов режется (docs/WAVE.md 4.3).
  pub fn weak_seeds(&self, days: i64) -> Result<HashSet<String>> {
    self.refs(
      "SELECT seed_ref FROM wave_events WHERE user_id = ?1 AND seed_ref IS NOT NULL AND reward IS NOT NULL AND served_at >= ?2
       GROUP BY seed_ref HAVING COUNT(*) >= 5 AND SUM(CASE WHEN reward < 0 THEN 1 ELSE 0 END) * 5 > COUNT(*) * 3",
      params![LOCAL_USER, now_ms() - days * DAY],
    )
    .map(|v| v.into_iter().collect())
  }

  /// Кэш «похожих» (docs/WAVE.md 4.4): список по ref трека живёт `max_age_ms`. Хранится в `catalog`
  /// под ключом `similar:<ref>`, чтобы не пересекаться с лайкнутыми альбомами и плейлистами.
  pub fn cached_similar(&self, r: &str, max_age_ms: i64) -> Result<Option<Vec<crate::providers::Track>>> {
    let row: Option<String> = self
      .db
      .query_row(
        "SELECT json FROM catalog WHERE ref = ?1 AND kind = 'similar' AND fetched_at >= ?2",
        params![format!("similar:{r}"), now_ms() - max_age_ms],
        |x| x.get(0),
      )
      .optional()?;
    Ok(row.and_then(|j| serde_json::from_str(&j).ok()))
  }

  pub fn put_similar(&self, r: &str, list: &[crate::providers::Track]) -> Result<()> {
    self.put_catalog(&format!("similar:{r}"), "similar", &serde_json::to_value(list)?)
  }

  /// Удалить устаревшие списки похожих (при запуске).
  pub(super) fn prune_similar(&self) -> Result<usize> {
    Ok(self.db.execute("DELETE FROM catalog WHERE kind = 'similar' AND fetched_at < ?1", [now_ms() - 2 * DAY])?)
  }

  /// Подборка «под время суток» на главной: треки, которые ты слушаешь в эти часы (±2 ч от
  /// текущего, за 90 дней), вперемешку с лайками; лайки сдвигаются по дню, чтобы подборка
  /// менялась каждый день, но не прыгала в течение дня. `tz_min` — как `Date.getTimezoneOffset()`.
  pub fn daypart_refs(&self, tz_min: i64, n: usize) -> Result<Vec<String>> {
    let now = now_ms();
    let local = now - tz_min * 60_000;
    let hour = (local / 3_600_000).rem_euclid(24);
    let day = local.div_euclid(DAY);
    let mut st = self.db.prepare(
      "SELECT ref, ((played_at - ?3 * 60000) / 3600000) % 24 AS h, played_at FROM plays
       WHERE user_id = ?1 AND played_at >= ?2",
    )?;
    let rows = st.query_map(params![LOCAL_USER, now - 90 * DAY, tz_min], |r| {
      Ok((r.get::<_, String>(0)?, r.get::<_, i64>(1)?, r.get::<_, i64>(2)?))
    })?;
    let mut score: HashMap<String, (u32, i64)> = HashMap::new();
    for row in rows {
      let (r, h, at) = row?;
      let d = (h.rem_euclid(24) - hour).rem_euclid(24);
      if d <= 2 || d >= 22 {
        let e = score.entry(r).or_insert((0, 0));
        e.0 += 1;
        e.1 = e.1.max(at);
      }
    }
    let disliked: HashSet<String> = self.disliked_refs()?.into_iter().collect();
    let mut hours: Vec<(String, (u32, i64))> = score.into_iter().filter(|(r, _)| !disliked.contains(r)).collect();
    hours.sort_by(|a, b| b.1 .0.cmp(&a.1 .0).then(b.1 .1.cmp(&a.1 .1)));
    let mut likes = self.recent_like_refs(120)?;
    likes.retain(|r| !disliked.contains(r));
    if !likes.is_empty() {
      let k = (day as usize).wrapping_mul(7) % likes.len();
      likes.rotate_left(k);
    }
    // по два «своих часа» на один лайк: подборка про это время, а лайки её освежают
    let mut out = Vec::with_capacity(n);
    let mut seen = HashSet::new();
    let (mut h, mut l) = (hours.into_iter().map(|x| x.0), likes.into_iter());
    let mut turn = 0;
    while out.len() < n {
      let next = if turn % 3 == 2 { l.next().or_else(|| h.next()) } else { h.next().or_else(|| l.next()) };
      let Some(r) = next else { break };
      turn += 1;
      if seen.insert(r.clone()) {
        out.push(r);
      }
    }
    Ok(out)
  }

  /// Исполнители для «Релизов недели»: на кого стоят лайки — лайкнутые исполнители, потом авторы
  /// лайкнутых треков (свежие лайки первыми), потом самые слушаемые. Только `sca:`/`yma:`.
  pub fn release_artist_refs(&self, n: usize) -> Result<Vec<String>> {
    let mut out: Vec<String> = self.refs(
      "SELECT ref FROM likes WHERE user_id = ?1 AND kind = 'artist' AND deleted = 0 ORDER BY added_at DESC LIMIT ?2",
      params![LOCAL_USER, n as i64],
    )?;
    let mut st = self.db.prepare(
      "SELECT t.artists_json FROM likes l JOIN tracks t ON t.ref = l.ref
       WHERE l.user_id = ?1 AND l.kind = 'track' AND l.deleted = 0 ORDER BY l.added_at DESC LIMIT 300",
    )?;
    let rows = st.query_map([LOCAL_USER], |r| r.get::<_, Option<String>>(0))?;
    for json in rows.flatten().flatten() {
      if out.len() >= n {
        break;
      }
      let Ok(list) = serde_json::from_str::<Vec<crate::providers::ArtistRef>>(&json) else { continue };
      if let Some(a) = list.first() {
        let artist = matches!(parse_ref(&a.ref_), Some((s, RefKind::Artist)) if s.implemented);
        if artist && !out.contains(&a.ref_) {
          out.push(a.ref_.clone());
        }
      }
    }
    for r in self.favorite_artist_refs(n)? {
      if out.len() >= n {
        break;
      }
      if !out.contains(&r) {
        out.push(r);
      }
    }
    out.truncate(n);
    Ok(out)
  }

  /// Исполнители для «Релизов»: лайкнутые и самые слушаемые (ref `sca:`/`yma:`), без повторов.
  pub fn favorite_artist_refs(&self, n: usize) -> Result<Vec<String>> {
    let mut out: Vec<String> = self.refs(
      "SELECT ref FROM likes WHERE user_id = ?1 AND kind = 'artist' AND deleted = 0 ORDER BY added_at DESC LIMIT ?2",
      params![LOCAL_USER, n as i64],
    )?;
    let mut st = self.db.prepare(
      "SELECT t.artists_json FROM plays p JOIN tracks t ON t.ref = p.ref
       WHERE p.user_id = ?1 GROUP BY p.ref ORDER BY COUNT(*) DESC LIMIT 60",
    )?;
    let rows = st.query_map([LOCAL_USER], |r| r.get::<_, Option<String>>(0))?;
    for json in rows.flatten().flatten() {
      let Ok(list) = serde_json::from_str::<Vec<crate::providers::ArtistRef>>(&json) else { continue };
      if let Some(a) = list.first() {
        if !out.contains(&a.ref_) {
          out.push(a.ref_.clone());
        }
      }
      if out.len() >= n {
        break;
      }
    }
    out.truncate(n);
    Ok(out)
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::store::Play;

  fn close(x: Option<&f64>, v: f64) -> bool {
    x.is_some_and(|x| (x - v).abs() < 1e-3)
  }

  #[test]
  fn dislikes_and_skips() {
    let s = Store::memory().unwrap();
    s.set_dislike("sc:1", "A", true).unwrap();
    s.set_dislike("sc:2", "B", true).unwrap();
    s.set_dislike("sc:2", "B", false).unwrap();
    assert_eq!(s.disliked_refs().unwrap(), vec!["sc:1".to_owned()]);
    s.add_skip("sc:3", "Art", 4000).unwrap();
    s.add_skip("sc:4", "art", 2000).unwrap();
    s.add_play(&Play { ref_: "sc:5".into(), artist: "Art".into(), context: None, played_at: now_ms(), listened_ms: 60_000 }).unwrap();
    let t = s.taste().unwrap();
    // два ранних пропуска без длительности — по 1; прослушивание минуту без длительности — недослушано, 0.4
    assert!(close(t.skips.get("art"), 2.0), "{:?}", t.skips);
    assert!(close(t.plays.get("art"), 0.4), "{:?}", t.plays);
    assert!(close(t.track_skips.get("sc:3"), 1.0) && close(t.track_skips.get("sc:4"), 1.0));
    assert!(s.played_since_days(7).unwrap().contains("sc:5"));
    assert_eq!(s.recent_play_refs(5).unwrap(), vec!["sc:5".to_owned()]);
  }

  #[test]
  fn taste_counts_every_artist_of_joint_track() {
    use crate::providers::{ArtistRef, Track};
    let mut s = Store::memory().unwrap();
    let joint = Track {
      ref_: "ym:1".into(),
      title: "t".into(),
      artist: "A, B".into(),
      artists: ["A", "B"].iter().map(|n| ArtistRef { ref_: format!("yma:{n}"), name: (*n).into(), avatar_url: None }).collect(),
      album: None,
      duration_ms: 200_000,
      cover_url: None,
      url: None,
      explicit: false,
      available: true,
      plays: None,
      tags: None,
    };
    s.upsert_tracks(&[joint]).unwrap();
    s.add_play(&Play { ref_: "ym:1".into(), artist: "A, B".into(), context: None, played_at: now_ms(), listened_ms: 200_000 }).unwrap();
    s.add_skip("ym:1", "A, B", 5000).unwrap();
    s.set_like("ym:1", true).unwrap();
    // трека без записи в кэше — по строке из истории
    s.add_play(&Play { ref_: "sc:7".into(), artist: "Solo".into(), context: None, played_at: now_ms(), listened_ms: 60_000 }).unwrap();
    let t = s.taste().unwrap();
    assert!(close(t.plays.get("a"), 1.0) && close(t.plays.get("b"), 1.0), "{:?}", t.plays);
    assert_eq!(t.plays.get("a, b"), None);
    assert!(close(t.skips.get("b"), 1.0), "{:?}", t.skips);
    assert!(t.liked_artists.contains("a") && t.liked_artists.contains("b"));
    assert!(close(t.plays.get("solo"), 0.4));
    assert!(s.hour_share(0).unwrap().is_empty(), "меньше трёх прослушиваний — без доли");
  }

  fn tr(r: &str, artist: &str, tags: &str) -> crate::providers::Track {
    use crate::providers::{ArtistRef, Track};
    Track {
      ref_: r.into(),
      title: r.into(),
      artist: artist.into(),
      artists: vec![ArtistRef { ref_: format!("sca:{artist}"), name: artist.into(), avatar_url: None }],
      album: None,
      duration_ms: 200_000,
      cover_url: None,
      url: None,
      explicit: false,
      available: true,
      plays: None,
      tags: Some(tags.into()),
    }
  }

  #[test]
  fn decay_halves_every_half_life() {
    assert_eq!(decay(0, 30.0), 1.0);
    assert!((decay(30 * DAY, 30.0) - 0.5).abs() < 1e-12);
    assert!((decay(60 * DAY, 30.0) - 0.25).abs() < 1e-12);
    assert_eq!(decay(-5 * DAY, 30.0), 1.0, "из будущего — не больше единицы");
  }

  #[test]
  fn tag_values_love_hate_and_everywhere() {
    let mut sums = TagSums::new();
    sums.insert("loved".into(), (10.0, 0.0));
    sums.insert("hated".into(), (0.0, 6.0));
    sums.insert("everywhere".into(), (20.0, 6.0));
    sums.insert("rare".into(), (1.0, 0.5));
    let v = tag_values(&sums);
    assert!(v["loved"] > 0.1, "{v:?}");
    assert!(v["hated"] < -0.3, "{v:?}");
    assert!(v["everywhere"].abs() < 0.1, "тег у всего подряд — около нуля: {v:?}");
    assert!(!v.contains_key("rare"), "мало данных — не оцениваем");
    assert!(v.values().all(|x| (-1.0..=1.0).contains(x)));
    // минусов нет совсем — общая доля плюсов 0.8, любимый тег всё равно в плюсе
    let mut only_plus = TagSums::new();
    only_plus.insert("a".into(), (5.0, 0.0));
    assert!(tag_values(&only_plus)["a"] > 0.0);
    assert!(tag_values(&TagSums::new()).is_empty());
  }

  #[test]
  fn tag_profile_from_history_with_decay() {
    let mut s = Store::memory().unwrap();
    s.upsert_tracks(&[
      tr("sc:1", "Lil Tracy", "\"lil peep\" gothboiclique 2016"),
      tr("sc:2", "Polka Band", "polka accordion"),
      tr("sc:3", "Old Fan", "oldschool"),
      tr("sc:4", "Lil Peep", "\"lil peep\" emo"),
    ])
    .unwrap();
    let now = now_ms();
    // sc:1 — лайк и дослушивание; sc:2 — три ранних пропуска и 👎
    s.set_like("sc:1", true).unwrap();
    s.add_play(&Play { ref_: "sc:1".into(), artist: "Lil Tracy".into(), context: None, played_at: now - 1000, listened_ms: 200_000 }).unwrap();
    for i in 0..3 {
      s.add_skip("sc:2", "Polka Band", 4_000 + i).unwrap();
    }
    s.set_dislike("sc:2", "Polka Band", true).unwrap();
    // sc:3 — давно (120 дней назад) слушали четыре раза, недавно пропустили трижды: старое почти не весит
    for i in 0..4 {
      s.add_play(&Play { ref_: "sc:3".into(), artist: "Old Fan".into(), context: None, played_at: now - 120 * DAY + i, listened_ms: 200_000 }).unwrap();
    }
    for _ in 0..3 {
      s.add_skip("sc:3", "Old Fan", 3_000).unwrap();
    }
    // sc:4 — собственный тег артиста
    s.set_like("sc:4", true).unwrap();
    s.add_play(&Play { ref_: "sc:4".into(), artist: "Lil Peep".into(), context: None, played_at: now - 2000, listened_ms: 200_000 }).unwrap();

    let p = s.tag_profile(None).unwrap();
    assert!(p["gothboiclique"] > 0.0 && p["2016"] > 0.0, "год и фраза учтены: {p:?}");
    assert!(p["lil peep"] > 0.0, "на чужом треке тег с именем артиста — метка сцены");
    assert!(p["polka"] < 0.0 && p["accordion"] < 0.0, "пропуски и 👎 — минус: {p:?}");
    assert!(p["oldschool"] < 0.0, "старые прослушивания затухли, свежие пропуски перевесили: {p:?}");
    assert!(p["emo"] > 0.0);
    // у Lil Peep его собственное имя из тегов выброшено, но `lil peep` с трека Lil Tracy остаётся
    assert!(p.contains_key("lil peep"));
  }

  #[test]
  fn mode_profile_learns_from_outcomes_of_that_mode_only() {
    let mut s = Store::memory().unwrap();
    s.upsert_tracks(&[tr("sc:1", "A", "gothboiclique"), tr("sc:2", "B", "gothboiclique"), tr("sc:3", "C", "phonk")]).unwrap();
    // «Грустная»: gothboiclique дослушивают; «Жёсткая»: его же пропускают; phonk — наоборот
    let run = |s: &mut Store, mode: &str, session: &str, r: &str, reward: f64| {
      s.log_wave_served(session, mode, &[crate::store::ServedEvent { ref_: r.into(), artist: "x".into(), source: "similar".into(), seed_ref: None, features_json: None }]).unwrap();
      assert!(s.finish_wave_event(session, r, reward, 100_000).unwrap());
    };
    for (i, r) in ["sc:1", "sc:2", "sc:1"].iter().enumerate() {
      run(&mut s, "sad", &format!("s{i}"), r, 1.0);
      run(&mut s, "hard", &format!("h{i}"), r, -1.0);
    }
    run(&mut s, "hard", "h9", "sc:3", 1.0);
    run(&mut s, "hard", "h8", "sc:3", 1.0);
    run(&mut s, "hard", "h7", "sc:3", 1.0);
    // выданный, но не сыгранный трек в профиль не попадает
    s.log_wave_served("s9", "sad", &[crate::store::ServedEvent { ref_: "sc:3".into(), artist: "x".into(), source: "similar".into(), seed_ref: None, features_json: None }]).unwrap();

    let sad = s.tag_profile(Some("sad")).unwrap();
    let hard = s.tag_profile(Some("hard")).unwrap();
    assert!(sad["gothboiclique"] > 0.0, "{sad:?}");
    assert!(hard["gothboiclique"] < 0.0, "{hard:?}");
    assert!(hard["phonk"] > 0.0 && !sad.contains_key("phonk"), "{sad:?} {hard:?}");
    // режим без событий — пустой профиль
    assert!(s.tag_profile(Some("calm")).unwrap().is_empty());
    // общий профиль — это не профиль режима: журнал волны в него не входит
    assert!(s.tag_profile(None).unwrap().is_empty());
  }

  #[test]
  fn daypart_mixes_hours_and_likes() {
    let s = Store::memory().unwrap();
    let now = now_ms();
    let play = |r: &str, at: i64| {
      s.add_play(&Play { ref_: r.into(), artist: "A".into(), context: None, played_at: at, listened_ms: 60_000 }).unwrap()
    };
    // в это время суток (сегодня и вчера) — sc:1 дважды, sc:2 раз; sc:3 — через 12 часов
    play("sc:1", now - 60_000);
    play("sc:1", now - DAY);
    play("sc:2", now - DAY - 3_600_000);
    play("sc:3", now - 12 * 3_600_000);
    s.set_like("sc:9", true).unwrap();
    s.set_dislike("sc:2", "A", true).unwrap();
    let out = s.daypart_refs(0, 10).unwrap();
    assert_eq!(out, vec!["sc:1".to_owned(), "sc:9".to_owned()]);
  }

  #[test]
  fn taste_decays_and_penalizes_skipped_track() {
    let s = Store::memory().unwrap();
    let now = now_ms();
    s.add_play(&Play { ref_: "sc:1".into(), artist: "Old".into(), context: None, played_at: now - 60 * DAY, listened_ms: 200_000 }).unwrap();
    s.add_play(&Play { ref_: "sc:2".into(), artist: "New".into(), context: None, played_at: now, listened_ms: 200_000 }).unwrap();
    // за окном 180 дней — не считается
    s.add_play(&Play { ref_: "sc:3".into(), artist: "Ancient".into(), context: None, played_at: now - 200 * DAY, listened_ms: 200_000 }).unwrap();
    let t = s.taste().unwrap();
    assert!(close(t.plays.get("new"), 1.0));
    assert!(close(t.plays.get("old"), 0.25), "два полураспада — четверть: {:?}", t.plays);
    assert!(t.plays.get("ancient").is_none());
  }

  #[test]
  fn forgotten_likes_skip_recent_and_disliked() {
    let mut s = Store::memory().unwrap();
    for r in ["sc:1", "sc:2", "sc:3"] {
      s.upsert_tracks(&[tr(r, "A", "x")]).unwrap();
      s.set_like(r, true).unwrap();
    }
    s.add_play(&Play { ref_: "sc:1".into(), artist: "A".into(), context: None, played_at: now_ms(), listened_ms: 200_000 }).unwrap();
    s.set_dislike("sc:2", "A", true).unwrap();
    let refs: Vec<String> = s.forgotten_likes(30, 40).unwrap().into_iter().map(|t| t.ref_).collect();
    assert_eq!(refs, vec!["sc:3".to_owned()]);
  }

  #[test]
  fn similar_cache_lives_a_day() {
    let s = Store::memory().unwrap();
    assert!(s.cached_similar("sc:1", DAY).unwrap().is_none());
    s.put_similar("sc:1", &[tr("sc:9", "B", "x")]).unwrap();
    let got = s.cached_similar("sc:1", DAY).unwrap().unwrap();
    assert_eq!(got[0].ref_, "sc:9");
    assert!(s.cached_similar("sc:1", -1).unwrap().is_none(), "старше срока — нет");
    assert!(s.liked_catalog("similar").unwrap().is_empty(), "кэш не путается с лайкнутым каталогом");
  }
}
