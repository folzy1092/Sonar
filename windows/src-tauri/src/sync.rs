//! Обмен с сервером Sonar (API.md §6): отправить неотправленное (`POST /sync/push`), забрать чужое
//! (`GET /sync/pull?since=`), отдельно — прослушивания (`POST /plays`). Сервера пока нет, поэтому
//! обмен включается, только когда заданы адрес и токен сессии (`sync_once` зовут, когда они есть);
//! логика целиком проверена тестами на сервере в памяти (`MemoryServer`): два устройства одного
//! аккаунта обмениваются лайками, плейлистами, настройками и журналом волны.

use crate::store::{Change, Op, PlayUpload, Store};
use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use std::sync::Mutex;

/// Операций в одной отправке.
const PUSH_BATCH: usize = 500;
/// Прослушиваний в одной отправке.
const PLAYS_BATCH: usize = 500;

/// Ответ `POST /sync/push`: какие операции приняты (серверный `rev` в ответе клиенту не нужен —
/// свои изменения вернутся в `pull` и применятся без отправки обратно).
#[derive(Debug, Clone, Deserialize)]
pub struct PushReply {
  pub applied: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct PullReply {
  pub rev: i64,
  pub changes: Vec<Change>,
  /// Сервер отдал не всё (предел ~1 МБ за ответ) — просить ещё с `rev`.
  #[serde(default)]
  pub more: bool,
}

/// Сколько страниц `pull` забирать за один обмен: первая синхронизация большой медиатеки — несколько МБ.
const PULL_PAGES: usize = 200;

/// Куда отправлять: HTTP к серверу или сервер в памяти (тесты).
#[allow(async_fn_in_trait)]
pub trait Transport {
  async fn push(&self, ops: &[Op]) -> Result<PushReply>;
  async fn pull(&self, since: i64) -> Result<PullReply>;
  async fn plays(&self, plays: &[PlayUpload]) -> Result<usize>;
  /// Отправлять ли прослушивания. Хаб ПК в локальной сети их не берёт: своя статистика ПК уже у него,
  /// а на сервер они уедут, когда он появится (`remote/sync_hub.rs`).
  fn sends_plays(&self) -> bool {
    true
  }
}

/// Итог одного обмена.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct SyncReport {
  pub pushed: usize,
  pub pulled: usize,
  pub plays: usize,
}

/// Один полный обмен: отправить всё своё (пачками), отправить прослушивания, забрать чужое.
/// База блокируется только на чтение и запись, не на время сети.
pub async fn sync_once(db: &Mutex<Store>, t: &impl Transport) -> Result<SyncReport> {
  let mut report = SyncReport::default();
  loop {
    let plan = db.lock().unwrap().pending_ops(PUSH_BATCH)?;
    if plan.ops.is_empty() {
      db.lock().unwrap().mark_pushed(plan.upto)?;
      break;
    }
    let reply = t.push(&plan.ops).await?;
    // сервер подтверждает каждую операцию; не все — не сдвигаем курсор, повторим в следующий раз
    if plan.ops.iter().any(|o| !reply.applied.contains(&o.op_id)) {
      bail!("сервер принял не все изменения ({} из {})", reply.applied.len(), plan.ops.len());
    }
    report.pushed += plan.ops.len();
    db.lock().unwrap().mark_pushed(plan.upto)?;
    if plan.ops.len() < PUSH_BATCH {
      break;
    }
  }
  while t.sends_plays() {
    let plays = db.lock().unwrap().plays_to_upload(PLAYS_BATCH)?;
    let Some(last) = plays.last().map(|p| p.id) else { break };
    t.plays(&plays).await?;
    report.plays += plays.len();
    db.lock().unwrap().mark_plays_uploaded(last)?;
    if plays.len() < PLAYS_BATCH {
      break;
    }
  }
  let since = db.lock().unwrap().pulled_rev()?;
  let reply = t.pull(since).await?;
  {
    let mut store = db.lock().unwrap();
    report.pulled = store.apply_changes(&reply.changes)?;
    if reply.rev > store.pulled_rev()? {
      store.set_pulled_rev(reply.rev)?;
    }
  }
  Ok(report)
}

/// Сервер Sonar по HTTP: `base` — адрес API (`https://sonar-api.folzy.ru`), `token` — сессия.
pub struct Http<'a> {
  pub http: &'a reqwest::Client,
  pub base: String,
  pub token: String,
}

impl Transport for Http<'_> {
  async fn push(&self, ops: &[Op]) -> Result<PushReply> {
    let r = self
      .http
      .post(format!("{}/sync/push", self.base))
      .bearer_auth(&self.token)
      .json(&serde_json::json!({ "ops": ops }))
      .send()
      .await?
      .error_for_status()?;
    Ok(r.json().await?)
  }

  /// Все страницы подряд (`more`), одним ответом для `sync_once`.
  async fn pull(&self, since: i64) -> Result<PullReply> {
    let mut out = PullReply { rev: since, changes: Vec::new(), more: false };
    for _ in 0..PULL_PAGES {
      let page: PullReply = self
        .http
        .get(format!("{}/sync/pull", self.base))
        .query(&[("since", out.rev)])
        .bearer_auth(&self.token)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
      out.changes.extend(page.changes);
      out.rev = out.rev.max(page.rev);
      if !page.more {
        return Ok(out);
      }
    }
    out.more = true; // остальное — в следующий обмен, курсор уже сдвинут на полученное
    Ok(out)
  }

  async fn plays(&self, plays: &[PlayUpload]) -> Result<usize> {
    #[derive(Deserialize)]
    struct Accepted {
      accepted: usize,
    }
    let r = self
      .http
      .post(format!("{}/plays", self.base))
      .bearer_auth(&self.token)
      .json(&serde_json::json!({ "plays": plays }))
      .send()
      .await?
      .error_for_status()?;
    Ok(r.json::<Accepted>().await?.accepted)
  }
}

/// Адрес API (`account::base`: `sync.server` или `https://try-sonar.ru/api`) и сессия из keyring
/// (`sonar_session`). Не вошли в аккаунт — обмена с сервером нет (Wi‑Fi с телефоном работает как раньше).
pub(crate) fn configured(db: &Mutex<Store>) -> Option<(String, String)> {
  let token: String = crate::secrets::load("sonar_session")?;
  (!token.is_empty()).then(|| (crate::account::base(db), token))
}

/// Обмен сейчас (команда `sync_now`): нет сервера — понятная ошибка.
pub async fn sync_now(http: &reqwest::Client, db: &Mutex<Store>) -> Result<SyncReport> {
  let Some((base, token)) = configured(db) else { bail!("Сервер Sonar ещё не подключён — синхронизация включится вместе с ним") };
  // до сервера ПК менялся с хабом в локальной сети — курсоры того обмена серверу не подходят
  db.lock().unwrap().sync_target("server")?;
  sync_once(db, &Http { http, base, token }).await
}

/// Фоновый обмен: через 10 с после запуска, дальше раз в 2 минуты, когда вошли в аккаунт (`lib.rs`).
/// Пришло чужое — окну `sync-applied`: Медиатека и настройки перечитываются.
pub async fn background(app: tauri::AppHandle) {
  use tauri::{Emitter, Manager};
  let mut wait = 10;
  let mut tick: u32 = 0;
  loop {
    tokio::time::sleep(std::time::Duration::from_secs(wait)).await;
    wait = 120;
    let (Some(core), Some(db)) = (app.try_state::<std::sync::Arc<crate::services::Core>>(), app.try_state::<crate::commands::Db>()) else {
      continue;
    };
    if configured(&db.0).is_none() {
      continue;
    }
    if crate::offline::is_on() {
      continue;
    }
    // Доступность Яндекса с этого устройства — серверу (статус судит по устройствам, с сервера Яндекс отвечает 451):
    // сразу после запуска и дальше раз в ~6 минут, отчёт живёт на сервере 20.
    tick = tick.wrapping_add(1);
    if tick % 3 == 1 {
      crate::account::report_yandex(&core, &db.0).await;
    }
    match sync_now(&core.http(), &db.0).await {
      Ok(r) if r.pulled > 0 => {
        let _ = app.emit("sync-applied", r.pulled);
      }
      Ok(_) => {}
      Err(e) => {
        log::warn!("синхронизация: {e}");
        // Обмен упал: если сервер говорит «заблокирован» или «сессии нет» — выйти и сказать окну (`account-ended`).
        crate::account::probe(&app).await;
        if configured(&db.0).is_none() {
          continue;
        }
      }
    }
    match crate::cred_sync::run(&core, &db.0).await {
      Ok(true) => {
        let _ = app.emit("services-changed", ());
      }
      Ok(false) => {}
      Err(e) => {
        log::warn!("входы в сервисы: {e}");
        crate::account::notify_ended(&app, &e.to_string());
      }
    }
  }
}

/// Сервер в памяти с той же логикой, что в API.md §6: глобальный `rev`, повтор `op_id` не
/// применяется дважды, настройки — «побеждает позднее» по `client_ts`. Для тестов клиента и как
/// образец для серверной части.
#[cfg(test)]
#[derive(Default)]
pub struct MemoryServer {
  inner: Mutex<MemoryState>,
}

#[cfg(test)]
#[derive(Default)]
struct MemoryState {
  rev: i64,
  /// (тип, ключ) → (значение, rev, client_ts)
  rows: std::collections::HashMap<(String, String), (Option<serde_json::Value>, i64, i64)>,
  seen_ops: std::collections::HashSet<String>,
  plays: usize,
}

#[cfg(test)]
impl Transport for MemoryServer {
  async fn push(&self, ops: &[Op]) -> Result<PushReply> {
    let mut s = self.inner.lock().unwrap();
    let mut applied = Vec::new();
    for o in ops {
      if s.seen_ops.insert(o.op_id.clone()) {
        let k = (o.kind.clone(), o.key.clone());
        let older = s.rows.get(&k).is_some_and(|(_, _, ts)| o.kind == "setting" && *ts > o.client_ts);
        if !older {
          s.rev += 1;
          let rev = s.rev;
          s.rows.insert(k, (o.value.clone(), rev, o.client_ts));
        }
      }
      applied.push(o.op_id.clone());
    }
    Ok(PushReply { applied })
  }

  async fn pull(&self, since: i64) -> Result<PullReply> {
    let s = self.inner.lock().unwrap();
    let mut changes: Vec<Change> = s
      .rows
      .iter()
      .filter(|(_, (_, rev, _))| *rev > since)
      .map(|((kind, key), (value, rev, _))| Change { kind: kind.clone(), key: key.clone(), value: value.clone(), rev: *rev })
      .collect();
    changes.sort_by_key(|c| c.rev);
    Ok(PullReply { rev: s.rev, changes, more: false })
  }

  async fn plays(&self, plays: &[PlayUpload]) -> Result<usize> {
    self.inner.lock().unwrap().plays += plays.len();
    Ok(plays.len())
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::store::{now_ms, Play, ServedEvent};

  fn block<F: std::future::Future>(f: F) -> F::Output {
    tokio::runtime::Builder::new_current_thread().enable_all().build().unwrap().block_on(f)
  }

  #[test]
  fn two_devices_share_likes_playlists_settings_and_wave() {
    let server = MemoryServer::default();
    let a = Mutex::new(Store::memory().unwrap());
    let b = Mutex::new(Store::memory().unwrap());
    {
      let mut s = a.lock().unwrap();
      let card = |r: &str| crate::providers::Track {
        ref_: r.into(),
        title: format!("трек {r}"),
        artist: "A".into(),
        artists: vec![],
        album: None,
        duration_ms: 200_000,
        cover_url: None,
        url: None,
        explicit: false,
        available: true,
        plays: None,
        tags: None,
      };
      s.upsert_tracks(&[card("sc:1"), card("ym:5")]).unwrap();
      s.set_like("sc:1", true).unwrap();
      s.set_like("sc:2", true).unwrap();
      s.set_like("sc:2", false).unwrap();
      let pl = s.create_playlist("ночь", &["sc:1".into(), "ym:5".into()], None).unwrap();
      s.update_playlist(&pl, Some("ночной вайб"), None).unwrap();
      s.set_setting("appearance.cover_theme", &serde_json::json!(true)).unwrap();
      s.set_setting("player.volume", &serde_json::json!(0.3)).unwrap();
      s.set_dislike("sc:9", "Bad", true).unwrap();
      s.log_wave_served("sess", "own", &[ServedEvent {
        ref_: "sc:7".into(),
        artist: "x".into(),
        source: "similar".into(),
        seed_ref: None,
        features_json: Some("{}".into()),
      }])
      .unwrap();
      s.finish_wave_event("sess", "sc:7", 1.0, 200_000).unwrap();
      s.add_play(&Play { ref_: "sc:1".into(), artist: "A".into(), context: None, played_at: now_ms(), listened_ms: 90_000 }).unwrap();
    }
    let ra = block(sync_once(&a, &server)).unwrap();
    assert!(ra.pushed >= 6, "{ra:?}");
    assert_eq!(ra.plays, 1);
    // своё вернулось с сервера — применено, но обратно уже не поедет
    let again = block(sync_once(&a, &server)).unwrap();
    assert_eq!(again.pushed, 0, "повторная отправка пустая: {again:?}");

    let rb = block(sync_once(&b, &server)).unwrap();
    assert!(rb.pulled >= 6, "{rb:?}");
    let s = b.lock().unwrap();
    let liked: Vec<String> = s.likes("track").unwrap().into_iter().map(|x| x.0).collect();
    assert_eq!(liked, vec!["sc:1".to_owned()], "снятый лайк не приехал как лайк");
    let pls = s.playlists().unwrap();
    assert_eq!(pls.len(), 1);
    assert_eq!(pls[0].name, "ночной вайб");
    let pl = s.playlist(&pls[0].id).unwrap().unwrap();
    assert_eq!(pl.tracks.map(|t| t.len()), Some(2), "треки плейлиста приехали");
    assert_eq!(s.setting("appearance.cover_theme").unwrap(), Some(serde_json::json!(true)));
    assert_eq!(s.setting("player.volume").unwrap(), None, "громкость — настройка устройства");
    assert_eq!(s.disliked_refs().unwrap(), vec!["sc:9".to_owned()]);
    let st = s.wave_stats(30).unwrap();
    assert_eq!(st.by_mode[0].played, 1, "исход волны приехал");
    drop(s);
    assert_eq!(block(sync_once(&b, &server)).unwrap().pushed, 0, "чужое не отправляется обратно");
  }

  #[test]
  fn track_sound_follows_the_user_and_later_edit_replaces_it() {
    use crate::store::TrackSound;
    let server = MemoryServer::default();
    let a = Mutex::new(Store::memory().unwrap());
    let b = Mutex::new(Store::memory().unwrap());
    let slowed = TrackSound { rate: 0.8, pitch: 0.0, linked: true, reverb: 0.4, eq: Some(vec![2.0; 12]), space: 0.0 };
    a.lock().unwrap().set_track_sound("sc:1", Some(slowed.clone())).unwrap();
    block(sync_once(&a, &server)).unwrap();
    // новое устройство: взялось с сервера, дальше живёт в своей базе
    block(sync_once(&b, &server)).unwrap();
    assert_eq!(b.lock().unwrap().track_sound("sc:1").unwrap(), Some(slowed.clone()));
    assert_eq!(b.lock().unwrap().track_sound("sc:2").unwrap(), None);
    // на B трек перенастроили — A получает только эту строку (rev выше), без сверки хэшей
    let faster = TrackSound { rate: 1.25, ..slowed };
    b.lock().unwrap().set_track_sound("sc:1", Some(faster.clone())).unwrap();
    block(sync_once(&b, &server)).unwrap();
    let r = block(sync_once(&a, &server)).unwrap();
    assert_eq!(r.pulled, 1, "{r:?}");
    assert_eq!(a.lock().unwrap().track_sound("sc:1").unwrap(), Some(faster));
    // «забыть» тоже едет
    a.lock().unwrap().set_track_sound("sc:1", None).unwrap();
    block(sync_once(&a, &server)).unwrap();
    block(sync_once(&b, &server)).unwrap();
    assert_eq!(b.lock().unwrap().track_sound("sc:1").unwrap(), None);
    // старый клиент прислал только «Запомнить скорость» — это скорость с сохранением тона
    let old = Op {
      op_id: "old:1".into(),
      kind: "track_pref".into(),
      key: "ym:5".into(),
      value: Some(serde_json::json!({ "speed": 1.1, "lyrics_offset_ms": null })),
      client_ts: now_ms(),
      rev: 0,
    };
    block(server.push(&[old])).unwrap();
    block(sync_once(&a, &server)).unwrap();
    let s = a.lock().unwrap().track_sound("ym:5").unwrap().unwrap();
    assert_eq!((s.rate, s.linked, s.reverb, s.eq), (1.1, false, 0.0, None));
  }

  #[test]
  fn own_pending_change_beats_incoming_and_later_setting_wins() {
    let server = MemoryServer::default();
    let a = Mutex::new(Store::memory().unwrap());
    let b = Mutex::new(Store::memory().unwrap());
    a.lock().unwrap().set_setting("wave.mode", &serde_json::json!("sad")).unwrap();
    block(sync_once(&a, &server)).unwrap();
    // B успел поменять то же самое позже, ещё не отправив
    std::thread::sleep(std::time::Duration::from_millis(5));
    b.lock().unwrap().set_setting("wave.mode", &serde_json::json!("fun")).unwrap();
    block(sync_once(&b, &server)).unwrap();
    assert_eq!(b.lock().unwrap().setting("wave.mode").unwrap(), Some(serde_json::json!("fun")));
    block(sync_once(&a, &server)).unwrap();
    assert_eq!(a.lock().unwrap().setting("wave.mode").unwrap(), Some(serde_json::json!("fun")), "позднее победило");
  }

  #[test]
  fn failed_push_keeps_changes_pending() {
    struct Down;
    impl Transport for Down {
      async fn push(&self, _: &[Op]) -> Result<PushReply> {
        bail!("нет сети")
      }
      async fn pull(&self, _: i64) -> Result<PullReply> {
        bail!("нет сети")
      }
      async fn plays(&self, _: &[PlayUpload]) -> Result<usize> {
        bail!("нет сети")
      }
    }
    let a = Mutex::new(Store::memory().unwrap());
    a.lock().unwrap().set_like("sc:1", true).unwrap();
    assert!(block(sync_once(&a, &Down)).is_err());
    assert_eq!(a.lock().unwrap().pending_ops(10).unwrap().ops.len(), 1, "не отправилось — осталось в очереди");
    let server = MemoryServer::default();
    assert_eq!(block(sync_once(&a, &server)).unwrap().pushed, 1);
  }

  #[test]
  fn op_ids_are_stable_for_retries() {
    let s = Store::memory().unwrap();
    s.set_like("sc:1", true).unwrap();
    let a = s.pending_ops(10).unwrap();
    let b = s.pending_ops(10).unwrap();
    assert_eq!(a.ops, b.ops);
    assert!(a.ops[0].op_id.starts_with("d_"));
  }
}
