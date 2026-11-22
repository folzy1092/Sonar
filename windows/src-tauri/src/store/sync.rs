//! Синхронизация на стороне клиента (SPEC §синхронизация, API.md §6) — готова до сервера.
//!
//! Очереди операций отдельной таблицей нет: каждое изменение лайков, плейлистов, настроек, 👎,
//! настроек трека и журнала волны уже поднимает глобальный счётчик `sync_rev` и пишет его в `rev`
//! строки. «Не отправлено» = `rev` новее `pushed_rev` (в `sync_state`). Отправка собирает такие строки
//! в операции `POST /sync/push`; после ответа `pushed_rev` сдвигается.
//!
//! Пришедшее с сервера (`GET /sync/pull`) пишется с `rev = 0` — оно уже на сервере и обратно не
//! поедет. Если у строки есть своё неотправленное изменение — пришедшее пропускается: своё уйдёт
//! следующей отправкой, и сервер решит, кто позже (настройки — по `client_ts`).
//!
//! Прослушивания едут отдельно (`POST /plays`) — курсор `plays_uploaded_id`.

use super::{new_id, now_ms, Store, LOCAL_USER};
use anyhow::Result;
use rusqlite::{params, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

const DAY: i64 = 24 * 3600 * 1000;

/// Настройки, которые остаются на устройстве (SETTINGS.md, столбец sync = «нет», и всё системное).
const LOCAL_SETTINGS: &[&str] = &[
  "general.language",
  "audio.quality",
  "audio.sc_via_yandex",
  "audio.output_device",
  "appearance.scale_window",
  "appearance.scale_fullscreen",
  "player.volume",
  "audio.eq",
  "player.speed_mode",
  "player.tempo",
  "obs.token",
  "lyrics.view",
];
const LOCAL_PREFIXES: &[&str] = &["system.", "update.", "storage.", "sync.", "remote."];

pub fn setting_syncs(key: &str) -> bool {
  !LOCAL_SETTINGS.contains(&key) && !LOCAL_PREFIXES.iter().any(|p| key.starts_with(p))
}

/// Операция `POST /sync/push`. `value = null` — удалено (tombstone).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Op {
  /// Детерминированный: повтор после сбоя сети сервер узнаёт и не применяет дважды.
  pub op_id: String,
  #[serde(rename = "type")]
  pub kind: String,
  pub key: String,
  pub value: Option<Value>,
  pub client_ts: i64,
  /// Локальный `rev` строки — для сдвига `pushed_rev`; на сервер не едет.
  #[serde(skip)]
  pub rev: i64,
}

/// Изменение из `GET /sync/pull`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Change {
  #[serde(rename = "type")]
  pub kind: String,
  pub key: String,
  pub value: Option<Value>,
  pub rev: i64,
}

/// Что отправить: операции по возрастанию `rev` и до какого `rev` они всё покрывают.
#[derive(Debug, Clone, Default)]
pub struct PushPlan {
  pub ops: Vec<Op>,
  pub upto: i64,
}

/// Прослушивание для `POST /plays`.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct PlayUpload {
  #[serde(skip)]
  pub id: i64,
  #[serde(rename = "ref")]
  pub ref_: String,
  pub played_at: i64,
  pub listened_ms: i64,
  pub context: Option<String>,
}

impl Store {
  fn state(&self, key: &str) -> Result<Option<String>> {
    Ok(self.db.query_row("SELECT value FROM sync_state WHERE key = ?1", [key], |r| r.get(0)).optional()?)
  }

  fn set_state(&self, key: &str, value: &str) -> Result<()> {
    self.db.execute(
      "INSERT INTO sync_state (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = ?2",
      params![key, value],
    )?;
    Ok(())
  }

  fn state_i64(&self, key: &str) -> Result<i64> {
    Ok(self.state(key)?.and_then(|v| v.parse().ok()).unwrap_or(0))
  }

  /// Id этого устройства (`d_…`), создаётся при первом запуске.
  pub fn device_id(&self) -> Result<String> {
    if let Some(id) = self.state("device_id")? {
      return Ok(id);
    }
    let id = new_id("d");
    self.set_state("device_id", &id)?;
    Ok(id)
  }

  /// До какого серверного `rev` уже получено (`GET /sync/pull?since=`).
  pub fn pulled_rev(&self) -> Result<i64> {
    self.state_i64("pulled_rev")
  }

  pub fn set_pulled_rev(&self, rev: i64) -> Result<()> {
    self.set_state("pulled_rev", &rev.to_string())
  }

  fn pushed_rev(&self) -> Result<i64> {
    self.state_i64("pushed_rev")
  }

  /// Неотправленные изменения, не больше `limit` операций (по возрастанию `rev`).
  pub fn pending_ops(&self, limit: usize) -> Result<PushPlan> {
    let since = self.pushed_rev()?;
    let device = self.device_id()?;
    let mut ops: Vec<Op> = Vec::new();
    let mut push = |kind: &str, key: String, value: Option<Value>, ts: i64, rev: i64| {
      ops.push(Op { op_id: format!("{device}:{kind}:{key}:{rev}"), kind: kind.into(), key, value, client_ts: ts, rev });
    };

    let mut st = self.db.prepare("SELECT ref, kind, added_at, deleted, rev FROM likes WHERE user_id = ?1 AND rev > ?2")?;
    for row in st.query_map(params![LOCAL_USER, since], |r| {
      Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, i64>(2)?, r.get::<_, bool>(3)?, r.get::<_, i64>(4)?))
    })? {
      let (r, kind, at, deleted, rev) = row?;
      push("like", r, (!deleted).then(|| json!({ "kind": kind, "added_at": at })), at, rev);
    }

    let mut st = self.db.prepare(
      "SELECT id, name, hidden, source_ref, created_at, updated_at, deleted, rev FROM playlists WHERE user_id = ?1 AND rev > ?2",
    )?;
    for row in st.query_map(params![LOCAL_USER, since], |r| {
      Ok((
        r.get::<_, String>(0)?,
        r.get::<_, String>(1)?,
        r.get::<_, bool>(2)?,
        r.get::<_, Option<String>>(3)?,
        r.get::<_, i64>(4)?,
        r.get::<_, i64>(5)?,
        r.get::<_, bool>(6)?,
        r.get::<_, i64>(7)?,
      ))
    })? {
      let (id, name, hidden, source, created, updated, deleted, rev) = row?;
      let value = (!deleted).then(|| json!({ "name": name, "hidden": hidden, "source_ref": source, "created_at": created, "updated_at": updated }));
      push("playlist", id, value, updated, rev);
    }

    let mut st = self.db.prepare(
      "SELECT i.id, i.playlist_id, i.ref, i.position, i.added_at, i.deleted, i.rev FROM playlist_items i
       JOIN playlists p ON p.id = i.playlist_id WHERE p.user_id = ?1 AND i.rev > ?2",
    )?;
    for row in st.query_map(params![LOCAL_USER, since], |r| {
      Ok((
        r.get::<_, String>(0)?,
        r.get::<_, String>(1)?,
        r.get::<_, String>(2)?,
        r.get::<_, f64>(3)?,
        r.get::<_, i64>(4)?,
        r.get::<_, bool>(5)?,
        r.get::<_, i64>(6)?,
      ))
    })? {
      let (id, pl, r, pos, at, deleted, rev) = row?;
      push("playlist_item", id, (!deleted).then(|| json!({ "playlist_id": pl, "ref": r, "position": pos, "added_at": at })), at, rev);
    }

    let mut st = self.db.prepare("SELECT key, value_json, client_ts, rev FROM settings WHERE user_id = ?1 AND rev > ?2")?;
    for row in st.query_map(params![LOCAL_USER, since], |r| {
      Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, i64>(2)?, r.get::<_, i64>(3)?))
    })? {
      let (key, raw, ts, rev) = row?;
      if setting_syncs(&key) {
        push("setting", key, serde_json::from_str(&raw).ok(), ts, rev);
      }
    }

    let mut st = self.db.prepare("SELECT ref, artist, added_at, deleted, rev FROM dislikes WHERE user_id = ?1 AND rev > ?2")?;
    for row in st.query_map(params![LOCAL_USER, since], |r| {
      Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, i64>(2)?, r.get::<_, bool>(3)?, r.get::<_, i64>(4)?))
    })? {
      let (r, artist, at, deleted, rev) = row?;
      push("dislike", r, (!deleted).then(|| json!({ "artist": artist, "added_at": at })), at, rev);
    }

    // звук трека (`sound`) — скорость, тон, реверб, эквалайзер; `speed` рядом для старых клиентов
    let mut st =
      self.db.prepare("SELECT ref, speed, lyrics_offset_ms, sound_json, deleted, rev FROM track_prefs WHERE user_id = ?1 AND rev > ?2")?;
    for row in st.query_map(params![LOCAL_USER, since], |r| {
      Ok((
        r.get::<_, String>(0)?,
        r.get::<_, Option<f64>>(1)?,
        r.get::<_, Option<i64>>(2)?,
        r.get::<_, Option<String>>(3)?,
        r.get::<_, bool>(4)?,
        r.get::<_, i64>(5)?,
      ))
    })? {
      let (r, speed, offset, sound, deleted, rev) = row?;
      let sound: Option<Value> = sound.and_then(|j| serde_json::from_str(&j).ok());
      let empty = speed.is_none() && offset.is_none() && sound.is_none();
      push(
        "track_pref",
        r,
        (!deleted && !empty).then(|| json!({ "speed": speed, "lyrics_offset_ms": offset, "sound": sound })),
        now_ms(),
        rev,
      );
    }

    // журнал волны — без features_json (WAVE.md §3а): их можно пересчитать, а весят они больше всего
    let mut st = self.db.prepare(
      "SELECT id, device_id, session_id, ref, artist, mode, source, seed_ref, served_at, reward, listened_ms, ended_at, rev
       FROM wave_events WHERE user_id = ?1 AND rev > ?2",
    )?;
    for row in st.query_map(params![LOCAL_USER, since], |r| {
      Ok((
        r.get::<_, String>(0)?,
        json!({
          "device_id": r.get::<_, String>(1)?, "session_id": r.get::<_, String>(2)?, "ref": r.get::<_, String>(3)?,
          "artist": r.get::<_, String>(4)?, "mode": r.get::<_, String>(5)?, "source": r.get::<_, String>(6)?,
          "seed_ref": r.get::<_, Option<String>>(7)?, "served_at": r.get::<_, i64>(8)?, "reward": r.get::<_, Option<f64>>(9)?,
          "listened_ms": r.get::<_, Option<i64>>(10)?, "ended_at": r.get::<_, Option<i64>>(11)?,
        }),
        r.get::<_, i64>(8)?,
        r.get::<_, i64>(12)?,
      ))
    })? {
      let (id, value, at, rev) = row?;
      push("wave_event", id, Some(value), at, rev);
    }

    // карточка трека — с лайком и элементом плейлиста: на другом устройстве её может не быть в кэше
    let refs: Vec<String> = ops
      .iter()
      .filter_map(|o| match (o.kind.as_str(), &o.value) {
        ("like", Some(_)) => Some(o.key.clone()),
        ("playlist_item", Some(v)) => v["ref"].as_str().map(str::to_owned),
        _ => None,
      })
      .collect();
    if !refs.is_empty() {
      let cards: std::collections::HashMap<String, Value> = self
        .tracks(&refs)?
        .into_iter()
        .filter_map(|t| serde_json::to_value(&t).ok().map(|v| (t.ref_.clone(), v)))
        .collect();
      for o in ops.iter_mut() {
        let r = match (o.kind.as_str(), &o.value) {
          ("like", Some(_)) => o.key.clone(),
          ("playlist_item", Some(v)) => v["ref"].as_str().unwrap_or_default().to_owned(),
          _ => continue,
        };
        if let (Some(card), Some(v)) = (cards.get(&r), o.value.as_mut()) {
          v["track"] = card.clone();
        }
      }
    }

    ops.sort_by_key(|o| o.rev);
    // режем по границе rev: операции с одним rev (порция волны) уходят вместе
    let mut upto = ops.last().map(|o| o.rev).unwrap_or(since);
    if ops.len() > limit {
      let cut = ops[limit].rev;
      ops.retain(|o| o.rev < cut);
      upto = cut - 1;
    }
    Ok(PushPlan { ops, upto })
  }

  /// Сервер принял отправку — всё до `upto` отправлено.
  pub fn mark_pushed(&self, upto: i64) -> Result<()> {
    if upto > self.pushed_rev()? {
      self.set_state("pushed_rev", &upto.to_string())?;
    }
    Ok(())
  }

  /// Есть ли у строки своё неотправленное изменение.
  fn local_pending(&self, sql: &str, key: &str) -> Result<bool> {
    let rev: Option<i64> = self.db.query_row(sql, params![LOCAL_USER, key], |r| r.get(0)).optional()?;
    Ok(rev.is_some_and(|r| r > self.pushed_rev().unwrap_or(0)))
  }

  /// Применить пришедшие изменения; вернёт, сколько применено. Неизвестные типы пропускаются —
  /// сервер новее клиента.
  pub fn apply_changes(&mut self, changes: &[Change]) -> Result<usize> {
    let mut applied = 0;
    for c in changes {
      if self.apply_one(c)? {
        applied += 1;
      }
    }
    let max = changes.iter().map(|c| c.rev).max().unwrap_or(0);
    if max > self.pulled_rev()? {
      self.set_pulled_rev(max)?;
    }
    Ok(applied)
  }

  fn apply_one(&mut self, c: &Change) -> Result<bool> {
    let v = c.value.as_ref();
    // карточка трека, если приехала, — в кэш (иначе лайк и плейлист на этом устройстве без названий)
    if let Some(card) = v.and_then(|v| v.get("track")).and_then(|t| serde_json::from_value::<crate::providers::Track>(t.clone()).ok()) {
      self.upsert_tracks(std::slice::from_ref(&card))?;
    }
    let get_i = |k: &str| v.and_then(|v| v[k].as_i64()).unwrap_or_else(now_ms);
    match c.kind.as_str() {
      "like" => {
        if self.local_pending("SELECT rev FROM likes WHERE user_id = ?1 AND ref = ?2", &c.key)? {
          return Ok(false);
        }
        let Some(kind) = super::like_kind(&c.key) else { return Ok(false) };
        self.db.execute(
          "INSERT INTO likes (user_id, ref, kind, added_at, deleted, rev) VALUES (?1, ?2, ?3, ?4, ?5, 0)
           ON CONFLICT(user_id, ref) DO UPDATE SET added_at = ?4, deleted = ?5, rev = 0",
          params![LOCAL_USER, c.key, kind, get_i("added_at"), v.is_none()],
        )?;
      }
      "playlist" => {
        if self.local_pending("SELECT rev FROM playlists WHERE user_id = ?1 AND id = ?2", &c.key)? {
          return Ok(false);
        }
        match v {
          Some(v) => {
            self.db.execute(
              "INSERT INTO playlists (id, user_id, name, hidden, source_ref, created_at, updated_at, deleted, rev)
               VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 0, 0)
               ON CONFLICT(id) DO UPDATE SET name = ?3, hidden = ?4, source_ref = ?5, updated_at = ?7, deleted = 0, rev = 0",
              params![
                c.key,
                LOCAL_USER,
                v["name"].as_str().unwrap_or("Плейлист"),
                v["hidden"].as_bool().unwrap_or(false),
                v["source_ref"].as_str(),
                get_i("created_at"),
                get_i("updated_at"),
              ],
            )?;
          }
          None => {
            self.db.execute("UPDATE playlists SET deleted = 1, rev = 0 WHERE user_id = ?1 AND id = ?2", params![LOCAL_USER, c.key])?;
          }
        }
      }
      "playlist_item" => {
        let pending: Option<i64> =
          self.db.query_row("SELECT rev FROM playlist_items WHERE id = ?1", [&c.key], |r| r.get(0)).optional()?;
        if pending.is_some_and(|r| r > self.pushed_rev().unwrap_or(0)) {
          return Ok(false);
        }
        match v {
          Some(v) => {
            let pl = v["playlist_id"].as_str().unwrap_or_default();
            // элемент плейлиста, которого здесь ещё нет (порядок pull не гарантирован), — заглушка;
            // сам плейлист придёт своим изменением и перезапишет её
            self.db.execute(
              "INSERT OR IGNORE INTO playlists (id, user_id, name, created_at, updated_at, rev) VALUES (?1, ?2, 'Плейлист', ?3, ?3, 0)",
              params![pl, LOCAL_USER, now_ms()],
            )?;
            self.db.execute(
              "INSERT INTO playlist_items (id, playlist_id, ref, position, added_at, deleted, rev) VALUES (?1, ?2, ?3, ?4, ?5, 0, 0)
               ON CONFLICT(id) DO UPDATE SET playlist_id = ?2, ref = ?3, position = ?4, deleted = 0, rev = 0",
              params![c.key, pl, v["ref"].as_str().unwrap_or_default(), v["position"].as_f64().unwrap_or(0.0), get_i("added_at")],
            )?;
          }
          None => {
            self.db.execute("UPDATE playlist_items SET deleted = 1, rev = 0 WHERE id = ?1", [&c.key])?;
          }
        }
      }
      "setting" => {
        if !setting_syncs(&c.key) || self.local_pending("SELECT rev FROM settings WHERE user_id = ?1 AND key = ?2", &c.key)? {
          return Ok(false);
        }
        match v {
          Some(v) => {
            self.db.execute(
              "INSERT INTO settings (user_id, key, value_json, client_ts, rev) VALUES (?1, ?2, ?3, ?4, 0)
               ON CONFLICT(user_id, key) DO UPDATE SET value_json = ?3, client_ts = ?4, rev = 0",
              params![LOCAL_USER, c.key, v.to_string(), now_ms()],
            )?;
          }
          None => {
            self.db.execute("DELETE FROM settings WHERE user_id = ?1 AND key = ?2", params![LOCAL_USER, c.key])?;
          }
        }
      }
      "dislike" => {
        if self.local_pending("SELECT rev FROM dislikes WHERE user_id = ?1 AND ref = ?2", &c.key)? {
          return Ok(false);
        }
        self.db.execute(
          "INSERT INTO dislikes (user_id, ref, artist, added_at, deleted, rev) VALUES (?1, ?2, ?3, ?4, ?5, 0)
           ON CONFLICT(user_id, ref) DO UPDATE SET added_at = ?4, deleted = ?5, rev = 0",
          params![LOCAL_USER, c.key, v.and_then(|v| v["artist"].as_str()).unwrap_or_default(), get_i("added_at"), v.is_none()],
        )?;
      }
      "track_pref" => {
        if self.local_pending("SELECT rev FROM track_prefs WHERE user_id = ?1 AND ref = ?2", &c.key)? {
          return Ok(false);
        }
        // звук: `sound`, у старых клиентов — из `speed` (store/track_sound.rs)
        let sound = v.and_then(super::TrackSound::from_sync);
        self.db.execute(
          "INSERT INTO track_prefs (user_id, ref, speed, lyrics_offset_ms, sound_json, deleted, rev) VALUES (?1, ?2, ?3, ?4, ?5, ?6, 0)
           ON CONFLICT(user_id, ref) DO UPDATE SET speed = ?3, lyrics_offset_ms = ?4, sound_json = ?5, deleted = ?6, rev = 0",
          params![
            LOCAL_USER,
            c.key,
            sound.as_ref().map(|s| s.rate),
            v.and_then(|v| v["lyrics_offset_ms"].as_i64()),
            sound.as_ref().map(serde_json::to_string).transpose()?,
            v.is_none()
          ],
        )?;
      }
      "wave_event" => {
        let Some(v) = v else { return Ok(false) };
        // старше полугода — уже подрезано локально, не возвращаем
        if get_i("served_at") < now_ms() - super::wave_events::KEEP_DAYS * DAY {
          return Ok(false);
        }
        let s = |k: &str| v[k].as_str().map(str::to_owned);
        // события неизменяемы, кроме исхода: строка с исходом важнее строки без него
        self.db.execute(
          "INSERT INTO wave_events (id, user_id, device_id, session_id, ref, artist, mode, source, seed_ref, served_at,
             reward, listened_ms, ended_at, rev)
           VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, 0)
           ON CONFLICT(id) DO UPDATE SET reward = COALESCE(reward, ?11), listened_ms = COALESCE(listened_ms, ?12),
             ended_at = COALESCE(ended_at, ?13)",
          params![
            c.key,
            LOCAL_USER,
            s("device_id").unwrap_or_default(),
            s("session_id").unwrap_or_default(),
            s("ref").unwrap_or_default(),
            s("artist").unwrap_or_default(),
            s("mode").unwrap_or_else(|| "own".into()),
            s("source").unwrap_or_else(|| "similar".into()),
            s("seed_ref"),
            get_i("served_at"),
            v["reward"].as_f64(),
            v["listened_ms"].as_i64(),
            v["ended_at"].as_i64(),
          ],
        )?;
      }
      _ => return Ok(false),
    }
    Ok(true)
  }

  /// Прослушивания, ещё не отправленные в `POST /plays` (по возрастанию id).
  pub fn plays_to_upload(&self, limit: usize) -> Result<Vec<PlayUpload>> {
    let since = self.state_i64("plays_uploaded_id")?;
    let mut st = self.db.prepare(
      "SELECT id, ref, played_at, listened_ms, context FROM plays WHERE user_id = ?1 AND id > ?2 ORDER BY id LIMIT ?3",
    )?;
    let rows = st.query_map(params![LOCAL_USER, since, limit as i64], |r| {
      Ok(PlayUpload { id: r.get(0)?, ref_: r.get(1)?, played_at: r.get(2)?, listened_ms: r.get(3)?, context: r.get(4)? })
    })?;
    Ok(rows.collect::<rusqlite::Result<_>>()?)
  }

  pub fn mark_plays_uploaded(&self, upto_id: i64) -> Result<()> {
    if upto_id > self.state_i64("plays_uploaded_id")? {
      self.set_state("plays_uploaded_id", &upto_id.to_string())?;
    }
    Ok(())
  }
}
