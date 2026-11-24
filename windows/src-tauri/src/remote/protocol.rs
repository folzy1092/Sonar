//! Сообщения пульта (docs/API.md «Пульт»): JSON-конверт `{v, type, id, re?, body}`.
//! Транспорт сейчас — WebSocket в локальной сети, потом те же конверты будет пересылать сервер Sonar
//! (добавит `from` / `to`), поэтому разбор не зависит от того, откуда пришла строка.
//! Здесь только разбор и сборка — без сети, Tauri и keyring (всё покрыто тестами).

use crate::providers::registry::{parse_ref, RefKind};
use crate::providers::Track;
use crate::store::{HubPlay, Op};
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::sync::atomic::{AtomicU64, Ordering};

/// Версия протокола: несовместимая правка формата — новая версия.
pub const VERSION: u32 = 1;
/// Сколько треков «Далее» уходит в `state`.
pub const QUEUE_LIMIT: usize = 50;
/// Самое длинное сообщение с телефона (трек с обложкой и артистами — пара килобайт).
pub const MAX_MESSAGE: usize = 64 * 1024;
/// Самое длинное сообщение синка (`sync_push` / `plays` пачкой). Сокет принимает до этого, остальные типы
/// по-прежнему режутся на `MAX_MESSAGE` (`fits`).
pub const MAX_SYNC_MESSAGE: usize = 4 * 1024 * 1024;
/// Больше операций или прослушиваний в одном сообщении — ошибка (телефон шлёт пачками поменьше).
pub const MAX_SYNC_BATCH: usize = 500;
const MAX_OP_ID: usize = 256;
const MAX_OP_KEY: usize = 512;
/// Типы строк синка (API.md §6) — то же, что умеет `apply_changes`.
const SYNC_KINDS: [&str; 7] = ["like", "playlist", "playlist_item", "setting", "dislike", "track_pref", "wave_event"];
const MAX_DEVICE_ID: usize = 64;
const MAX_DEVICE_NAME: usize = 64;
const MAX_REF: usize = 256;
const MAX_MSG_ID: usize = 64;
/// Перемотка дальше суток — точно ошибка.
const MAX_SEEK_MS: u64 = 24 * 60 * 60 * 1000;
pub const CODE_LEN: usize = 6;
const KEY_MIN: usize = 16;
const KEY_MAX: usize = 128;

/// Конверт любого сообщения пульта.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Envelope {
  pub v: u32,
  #[serde(rename = "type")]
  pub kind: String,
  /// id сообщения у отправителя — по нему приходит ответ (`re`).
  #[serde(default)]
  pub id: String,
  /// На какое сообщение это ответ.
  #[serde(default, skip_serializing_if = "Option::is_none")]
  pub re: Option<String>,
  #[serde(default, skip_serializing_if = "Value::is_null")]
  pub body: Value,
}

/// Почему сообщение не принято — код уходит телефону в `error`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ParseError {
  /// Не JSON или нет `v` / `type`.
  BadJson,
  /// Другая версия протокола.
  BadVersion(u32),
  /// Неизвестный `type`.
  Unknown(String),
  /// Тело не подходит к типу (`what` — что именно, для журнала).
  BadBody(&'static str),
}

impl ParseError {
  pub fn code(&self) -> &'static str {
    match self {
      ParseError::BadJson => "bad_json",
      ParseError::BadVersion(_) => "bad_version",
      ParseError::Unknown(_) => "unknown_type",
      ParseError::BadBody(_) => "bad_body",
    }
  }
}

/// Телефон, который подключается: постоянный id (Keychain телефона) и имя для списка устройств.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct DeviceHello {
  pub id: String,
  pub name: String,
}

/// Что пришло с телефона.
#[derive(Debug, Clone, PartialEq)]
pub enum Incoming {
  /// Уже привязан: постоянный ключ устройства.
  Hello { device: DeviceHello, key: String },
  /// Привязка 6-значным кодом с экрана ПК.
  Pair { device: DeviceHello, code: String },
  /// Проверка связи (раз в ~20 с) — ПК отвечает `pong`.
  Ping,
  Command(Command),
  /// Синк по Wi‑Fi, пока сервера нет (API.md §6 поверх пульта): только привязанным.
  Sync(SyncRequest),
}

/// Запрос синка — то же, что `POST /sync/push`, `GET /sync/pull`, `POST /plays` у сервера.
#[derive(Debug, Clone, PartialEq)]
pub enum SyncRequest {
  Push(Vec<Op>),
  Pull { since: i64 },
  Plays(Vec<HubPlay>),
}

/// Команда плееру ПК — уходит в интерфейс событием `remote-command` в этом же виде.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Command {
  Toggle,
  Next,
  Prev,
  Seek {
    ms: u64,
  },
  /// 0..1
  Volume {
    value: f64,
  },
  /// Лайк трека (`ref` нет — текущего). `value` нет — переключить.
  Like {
    #[serde(rename = "ref", skip_serializing_if = "Option::is_none")]
    ref_: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    value: Option<bool>,
  },
  /// Включить Sonar Mix (`wave: true`) или трек по `ref` (`track` — целиком, если у ПК его нет в кэше).
  Play {
    wave: bool,
    #[serde(rename = "ref", skip_serializing_if = "Option::is_none")]
    ref_: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    track: Option<Track>,
  },
  /// В очередь: `next` — следующим, иначе в конец.
  QueueAdd {
    #[serde(rename = "ref")]
    ref_: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    track: Option<Track>,
    next: bool,
  },
  /// Сыграть трек из `queue` последнего `state` (номер в этом списке).
  QueuePlayIndex {
    index: usize,
  },
}

// ——— разбор ———

/// Разобрать строку с телефона.
pub fn parse(text: &str) -> Result<(Envelope, Incoming), ParseError> {
  let env: Envelope = serde_json::from_str(text).map_err(|_| ParseError::BadJson)?;
  if env.v != VERSION {
    return Err(ParseError::BadVersion(env.v));
  }
  if env.id.len() > MAX_MSG_ID {
    return Err(ParseError::BadBody("id"));
  }
  let incoming = parse_body(&env.kind, &env.body)?;
  Ok((env, incoming))
}

fn parse_body(kind: &str, body: &Value) -> Result<Incoming, ParseError> {
  let cmd = |c: Command| Ok(Incoming::Command(c));
  match kind {
    "hello" => {
      let device = device(body)?;
      let key = str_field(body, "key").filter(|k| is_key(k)).ok_or(ParseError::BadBody("key"))?;
      Ok(Incoming::Hello { device, key: key.to_owned() })
    }
    "pair" => {
      let device = device(body)?;
      let code = str_field(body, "code").map(str::trim).filter(|c| is_code(c)).ok_or(ParseError::BadBody("code"))?;
      Ok(Incoming::Pair { device, code: code.to_owned() })
    }
    "ping" => Ok(Incoming::Ping),
    "sync_push" => sync_push(body),
    "sync_pull" => {
      let since = match body.get("since") {
        None | Some(Value::Null) => 0,
        Some(v) => v.as_i64().filter(|s| *s >= 0).ok_or(ParseError::BadBody("since"))?,
      };
      Ok(Incoming::Sync(SyncRequest::Pull { since }))
    }
    "plays" => sync_plays(body),
    "toggle" => cmd(Command::Toggle),
    "next" => cmd(Command::Next),
    "prev" => cmd(Command::Prev),
    "seek" => {
      let ms = body.get("ms").and_then(Value::as_f64).filter(|m| m.is_finite() && *m >= 0.0).ok_or(ParseError::BadBody("ms"))?;
      cmd(Command::Seek { ms: (ms as u64).min(MAX_SEEK_MS) })
    }
    "volume" => {
      let v = body.get("value").and_then(Value::as_f64).filter(|v| v.is_finite()).ok_or(ParseError::BadBody("value"))?;
      cmd(Command::Volume { value: v.clamp(0.0, 1.0) })
    }
    "like" => {
      let ref_ = optional_ref(body)?;
      let value = match body.get("value") {
        None | Some(Value::Null) => None,
        Some(Value::Bool(b)) => Some(*b),
        Some(_) => return Err(ParseError::BadBody("value")),
      };
      cmd(Command::Like { ref_, value })
    }
    "play" => parse_play(body),
    "queue_add" => {
      let (ref_, track) = track_arg(body)?;
      let next = body.get("next").and_then(Value::as_bool).unwrap_or(false);
      cmd(Command::QueueAdd { ref_, track, next })
    }
    "queue_play_index" => {
      let index = body.get("index").and_then(Value::as_u64).map(|i| i as usize).filter(|i| *i < QUEUE_LIMIT);
      cmd(Command::QueuePlayIndex { index: index.ok_or(ParseError::BadBody("index"))? })
    }
    other => Err(ParseError::Unknown(other.chars().take(32).collect())),
  }
}

fn parse_play(body: &Value) -> Result<Incoming, ParseError> {
  let wave = body.get("wave").and_then(Value::as_bool).unwrap_or(false);
  let has_ref = body.get("ref").is_some_and(|r| !r.is_null());
  if wave == has_ref {
    // ровно одно из двух: волна или трек
    return Err(ParseError::BadBody("play"));
  }
  if wave {
    return Ok(Incoming::Command(Command::Play { wave: true, ref_: None, track: None }));
  }
  let (ref_, track) = track_arg(body)?;
  Ok(Incoming::Command(Command::Play { wave: false, ref_: Some(ref_), track }))
}

fn sync_push(body: &Value) -> Result<Incoming, ParseError> {
  let raw = body.get("ops").and_then(Value::as_array).filter(|a| a.len() <= MAX_SYNC_BATCH).ok_or(ParseError::BadBody("ops"))?;
  let mut ops = Vec::with_capacity(raw.len());
  for o in raw {
    let op: Op = serde_json::from_value(o.clone()).map_err(|_| ParseError::BadBody("op"))?;
    let ok = !op.op_id.is_empty()
      && op.op_id.len() <= MAX_OP_ID
      && !op.key.is_empty()
      && op.key.len() <= MAX_OP_KEY
      && SYNC_KINDS.contains(&op.kind.as_str());
    if !ok {
      return Err(ParseError::BadBody("op"));
    }
    ops.push(op);
  }
  Ok(Incoming::Sync(SyncRequest::Push(ops)))
}

fn sync_plays(body: &Value) -> Result<Incoming, ParseError> {
  let raw = body.get("plays").and_then(Value::as_array).filter(|a| a.len() <= MAX_SYNC_BATCH).ok_or(ParseError::BadBody("plays"))?;
  let mut plays = Vec::with_capacity(raw.len());
  for p in raw {
    let play: HubPlay = serde_json::from_value(p.clone()).map_err(|_| ParseError::BadBody("play"))?;
    let ok = is_track_ref(&play.ref_) && play.played_at >= 0 && play.listened_ms >= 0 && play.context.as_ref().is_none_or(|c| c.len() <= MAX_REF);
    if !ok {
      return Err(ParseError::BadBody("play"));
    }
    plays.push(play);
  }
  Ok(Incoming::Sync(SyncRequest::Plays(plays)))
}

/// Влезает ли сообщение в предел своего типа: синк — до `MAX_SYNC_MESSAGE` (это держит сокет), остальное — до
/// `MAX_MESSAGE`.
pub fn fits(text: &str, incoming: &Incoming) -> bool {
  matches!(incoming, Incoming::Sync(_)) || text.len() <= MAX_MESSAGE
}

fn str_field<'a>(body: &'a Value, key: &str) -> Option<&'a str> {
  body.get(key).and_then(Value::as_str)
}

fn device(body: &Value) -> Result<DeviceHello, ParseError> {
  let d = body.get("device").ok_or(ParseError::BadBody("device"))?;
  let id = str_field(d, "id").filter(|i| is_device_id(i)).ok_or(ParseError::BadBody("device.id"))?;
  let name = clean_name(str_field(d, "name").unwrap_or(""));
  Ok(DeviceHello { id: id.to_owned(), name })
}

/// ref трека из реестра сервисов (любой, в том числе `local:` — его телефон видит в очереди ПК).
pub fn is_track_ref(r: &str) -> bool {
  r.len() <= MAX_REF && matches!(parse_ref(r), Some((_, RefKind::Track)))
}

fn optional_ref(body: &Value) -> Result<Option<String>, ParseError> {
  match body.get("ref") {
    None | Some(Value::Null) => Ok(None),
    Some(Value::String(r)) if is_track_ref(r) => Ok(Some(r.clone())),
    Some(_) => Err(ParseError::BadBody("ref")),
  }
}

/// `ref` трека и, если есть, сам трек — с тем же ref.
fn track_arg(body: &Value) -> Result<(String, Option<Track>), ParseError> {
  let ref_ = optional_ref(body)?.ok_or(ParseError::BadBody("ref"))?;
  let track = match body.get("track") {
    None | Some(Value::Null) => None,
    Some(t) => {
      let track: Track = serde_json::from_value(t.clone()).map_err(|_| ParseError::BadBody("track"))?;
      if track.ref_ != ref_ {
        return Err(ParseError::BadBody("track.ref"));
      }
      Some(track)
    }
  };
  Ok((ref_, track))
}

/// id телефона: латиница, цифры, `-`, `_`, `.` — до 64 знаков (UUID из Keychain подходит).
pub fn is_device_id(s: &str) -> bool {
  !s.is_empty() && s.len() <= MAX_DEVICE_ID && s.bytes().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.'))
}

/// Код привязки — ровно 6 цифр.
pub fn is_code(s: &str) -> bool {
  s.len() == CODE_LEN && s.bytes().all(|b| b.is_ascii_digit())
}

/// Ключ устройства — base64url без `=`, 16..128 знаков.
pub fn is_key(s: &str) -> bool {
  (KEY_MIN..=KEY_MAX).contains(&s.len()) && s.bytes().all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_'))
}

/// Имя телефона для списка: без управляющих знаков, до 64 символов; пустое — «iPhone».
pub fn clean_name(s: &str) -> String {
  let name: String = s.chars().filter(|c| !c.is_control()).collect::<String>().trim().chars().take(MAX_DEVICE_NAME).collect();
  if name.is_empty() { "iPhone".into() } else { name }
}

// ——— сборка ———

static NEXT_ID: AtomicU64 = AtomicU64::new(1);

fn next_id() -> String {
  format!("pc{}", NEXT_ID.fetch_add(1, Ordering::Relaxed))
}

/// Сообщение ПК: конверт со свежим id.
pub fn message(kind: &str, body: Value, re: Option<&str>) -> String {
  let env = Envelope { v: VERSION, kind: kind.to_owned(), id: next_id(), re: re.map(str::to_owned), body };
  serde_json::to_string(&env).unwrap_or_default()
}

/// Кто этот ПК: id (постоянный, из keyring) и имя компьютера.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct PcInfo {
  pub id: String,
  pub name: String,
}

pub fn welcome(pc: &PcInfo, re: Option<&str>) -> String {
  message("welcome", json!({ "pc": pc }), re)
}

/// Привязка прошла: постоянный ключ — телефон кладёт его в Keychain. Ключ живёт только в этом ответе.
pub fn paired(pc: &PcInfo, key: &str, re: Option<&str>) -> String {
  message("paired", json!({ "pc": pc, "key": key }), re)
}

pub fn error(code: &str, re: Option<&str>) -> String {
  message("error", json!({ "code": code }), re)
}

pub fn pong(re: Option<&str>) -> String {
  message("pong", Value::Null, re)
}

/// ПК закрывает связь: `unpaired` — устройство отвязали, `disabled` — пульт выключили.
pub fn bye(reason: &str) -> String {
  message("bye", json!({ "reason": reason }), None)
}

/// Тело `state` от интерфейса: только объект, очередь — не длиннее 50, `device` — этот ПК.
pub fn state_body(raw: Value, pc: &PcInfo) -> Value {
  let mut body = match raw {
    Value::Object(m) => m,
    _ => Map::new(),
  };
  if let Some(Value::Array(q)) = body.get_mut("queue") {
    q.truncate(QUEUE_LIMIT);
  }
  body.insert("device".into(), json!({ "id": pc.id, "name": pc.name, "kind": "pc" }));
  Value::Object(body)
}

pub fn state(body: &Value) -> String {
  message("state", body.clone(), None)
}

#[cfg(test)]
mod tests {
  use super::*;

  fn env(kind: &str, body: Value) -> String {
    json!({ "v": 1, "type": kind, "id": "m1", "body": body }).to_string()
  }

  fn cmd(kind: &str, body: Value) -> Result<Command, ParseError> {
    match parse(&env(kind, body))?.1 {
      Incoming::Command(c) => Ok(c),
      other => panic!("не команда: {other:?}"),
    }
  }

  fn track_json(r: &str) -> Value {
    json!({
      "ref": r, "title": "Song", "artist": "Band", "artists": [], "album": null, "duration_ms": 180000,
      "cover_url": null, "url": null, "explicit": false, "available": true
    })
  }

  fn sync(kind: &str, body: Value) -> Result<SyncRequest, ParseError> {
    match parse(&env(kind, body))?.1 {
      Incoming::Sync(r) => Ok(r),
      other => panic!("не синк: {other:?}"),
    }
  }

  fn sync_op(kind: &str) -> Value {
    json!({ "op_id": "o1", "type": kind, "key": "sc:1", "value": { "added_at": 1 }, "client_ts": 5 })
  }

  #[test]
  fn sync_push_takes_known_ops_only() {
    let SyncRequest::Push(ops) = sync("sync_push", json!({ "ops": [sync_op("like")] })).unwrap() else { panic!() };
    assert_eq!((ops[0].op_id.as_str(), ops[0].kind.as_str(), ops[0].client_ts), ("o1", "like", 5));
    assert_eq!(sync("sync_push", json!({ "ops": [sync_op("password")] })).unwrap_err(), ParseError::BadBody("op"));
    assert_eq!(sync("sync_push", json!({ "ops": "нет" })).unwrap_err(), ParseError::BadBody("ops"));
    let mut empty_key = sync_op("like");
    empty_key["key"] = json!("");
    assert_eq!(sync("sync_push", json!({ "ops": [empty_key] })).unwrap_err(), ParseError::BadBody("op"));
    let many: Vec<Value> = (0..=MAX_SYNC_BATCH).map(|_| sync_op("like")).collect();
    assert_eq!(sync("sync_push", json!({ "ops": many })).unwrap_err(), ParseError::BadBody("ops"));
  }

  #[test]
  fn sync_pull_since_defaults_to_zero() {
    assert_eq!(sync("sync_pull", json!({})).unwrap(), SyncRequest::Pull { since: 0 });
    assert_eq!(sync("sync_pull", json!({ "since": 42 })).unwrap(), SyncRequest::Pull { since: 42 });
    assert_eq!(sync("sync_pull", json!({ "since": -1 })).unwrap_err(), ParseError::BadBody("since"));
  }

  #[test]
  fn plays_need_track_ref_and_sane_numbers() {
    let ok = json!({ "plays": [{ "ref": "sc:1", "played_at": 10, "listened_ms": 5000 }] });
    let SyncRequest::Plays(p) = sync("plays", ok).unwrap() else { panic!() };
    assert_eq!(p[0].ref_, "sc:1");
    let bad = json!({ "plays": [{ "ref": "не трек", "played_at": 10, "listened_ms": 5000 }] });
    assert_eq!(sync("plays", bad).unwrap_err(), ParseError::BadBody("play"));
    let negative = json!({ "plays": [{ "ref": "sc:1", "played_at": 10, "listened_ms": -1 }] });
    assert_eq!(sync("plays", negative).unwrap_err(), ParseError::BadBody("play"));
  }

  #[test]
  fn only_sync_may_exceed_message_limit() {
    let big = "x".repeat(MAX_MESSAGE + 1);
    let (_, pull) = parse(&env("sync_pull", json!({}))).unwrap();
    assert!(fits(&big, &pull));
    assert!(!fits(&big, &Incoming::Ping));
    assert!(fits("{}", &Incoming::Ping));
  }

  #[test]
  fn envelope_needs_version_and_type() {
    assert_eq!(parse("не json").unwrap_err(), ParseError::BadJson);
    assert_eq!(parse(r#"{"type":"toggle"}"#).unwrap_err(), ParseError::BadJson);
    assert_eq!(parse(r#"{"v":2,"type":"toggle"}"#).unwrap_err(), ParseError::BadVersion(2));
    assert_eq!(parse(r#"{"v":1,"type":"dance"}"#).unwrap_err(), ParseError::Unknown("dance".into()));
    let (e, i) = parse(r#"{"v":1,"type":"toggle","id":"a"}"#).unwrap();
    assert_eq!(e.id, "a");
    assert_eq!(i, Incoming::Command(Command::Toggle));
    // лишние поля (будущие `from` / `to` сервера) не мешают
    assert!(parse(r#"{"v":1,"type":"next","id":"b","from":"x","to":"y"}"#).is_ok());
  }

  #[test]
  fn hello_and_pair() {
    let hello = parse(&env("hello", json!({ "device": { "id": "AB-12", "name": " Мой iPhone " }, "key": "k".repeat(43) }))).unwrap().1;
    assert_eq!(hello, Incoming::Hello { device: DeviceHello { id: "AB-12".into(), name: "Мой iPhone".into() }, key: "k".repeat(43) });
    let pair = parse(&env("pair", json!({ "device": { "id": "AB-12" }, "code": "012345" }))).unwrap().1;
    assert_eq!(pair, Incoming::Pair { device: DeviceHello { id: "AB-12".into(), name: "iPhone".into() }, code: "012345".into() });
    for code in ["12345", "1234567", "12a456", ""] {
      assert_eq!(parse(&env("pair", json!({ "device": { "id": "x" }, "code": code }))).unwrap_err(), ParseError::BadBody("code"), "{code}");
    }
    assert_eq!(parse(&env("hello", json!({ "device": { "id": "bad id" }, "key": "k".repeat(43) }))).unwrap_err(), ParseError::BadBody("device.id"));
    assert_eq!(parse(&env("hello", json!({ "device": { "id": "x" }, "key": "short" }))).unwrap_err(), ParseError::BadBody("key"));
  }

  #[test]
  fn simple_commands() {
    assert_eq!(cmd("next", Value::Null).unwrap(), Command::Next);
    assert_eq!(cmd("prev", json!({})).unwrap(), Command::Prev);
    assert_eq!(cmd("seek", json!({ "ms": 61000 })).unwrap(), Command::Seek { ms: 61000 });
    assert_eq!(cmd("seek", json!({ "ms": -5 })).unwrap_err(), ParseError::BadBody("ms"));
    assert_eq!(cmd("volume", json!({ "value": 1.7 })).unwrap(), Command::Volume { value: 1.0 });
    assert_eq!(cmd("volume", json!({ "value": "громко" })).unwrap_err(), ParseError::BadBody("value"));
    assert_eq!(cmd("queue_play_index", json!({ "index": 3 })).unwrap(), Command::QueuePlayIndex { index: 3 });
    assert_eq!(cmd("queue_play_index", json!({ "index": 50 })).unwrap_err(), ParseError::BadBody("index"));
  }

  #[test]
  fn like_play_and_queue() {
    assert_eq!(cmd("like", json!({})).unwrap(), Command::Like { ref_: None, value: None });
    assert_eq!(cmd("like", json!({ "ref": "sc:1", "value": true })).unwrap(), Command::Like { ref_: Some("sc:1".into()), value: Some(true) });
    assert_eq!(cmd("like", json!({ "ref": "pl_1" })).unwrap_err(), ParseError::BadBody("ref"));
    assert_eq!(cmd("play", json!({ "wave": true })).unwrap(), Command::Play { wave: true, ref_: None, track: None });
    assert_eq!(cmd("play", json!({ "ref": "ym:5" })).unwrap(), Command::Play { wave: false, ref_: Some("ym:5".into()), track: None });
    assert_eq!(cmd("play", json!({})).unwrap_err(), ParseError::BadBody("play"));
    assert_eq!(cmd("play", json!({ "wave": true, "ref": "ym:5" })).unwrap_err(), ParseError::BadBody("play"));
    assert_eq!(cmd("play", json!({ "ref": "ymalb:5" })).unwrap_err(), ParseError::BadBody("ref"), "альбом — не трек");
    let with_track = cmd("queue_add", json!({ "ref": "sc:7", "track": track_json("sc:7"), "next": true })).unwrap();
    match with_track {
      Command::QueueAdd { ref_, track: Some(t), next: true } => assert_eq!((ref_.as_str(), t.title.as_str()), ("sc:7", "Song")),
      other => panic!("{other:?}"),
    }
    assert_eq!(cmd("queue_add", json!({ "ref": "sc:7", "track": track_json("sc:8") })).unwrap_err(), ParseError::BadBody("track.ref"));
    assert_eq!(cmd("queue_add", json!({ "ref": "sc:7", "track": { "ref": "sc:7" } })).unwrap_err(), ParseError::BadBody("track"));
  }

  #[test]
  fn commands_go_to_interface_flat() {
    let v = serde_json::to_value(Command::QueueAdd { ref_: "sc:7".into(), track: None, next: false }).unwrap();
    assert_eq!(v, json!({ "type": "queue_add", "ref": "sc:7", "next": false }));
    let v = serde_json::to_value(Command::Play { wave: true, ref_: None, track: None }).unwrap();
    assert_eq!(v, json!({ "type": "play", "wave": true }));
    assert_eq!(serde_json::to_value(Command::QueuePlayIndex { index: 2 }).unwrap(), json!({ "type": "queue_play_index", "index": 2 }));
  }

  #[test]
  fn builds_pc_messages() {
    let pc = PcInfo { id: "pc_1".into(), name: "DESKTOP".into() };
    let w: Envelope = serde_json::from_str(&welcome(&pc, Some("m1"))).unwrap();
    assert_eq!((w.v, w.kind.as_str(), w.re.as_deref()), (1, "welcome", Some("m1")));
    assert_eq!(w.body["pc"]["name"], "DESKTOP");
    let e: Envelope = serde_json::from_str(&error("bad_code", None)).unwrap();
    assert_eq!(e.body, json!({ "code": "bad_code" }));
    assert!(e.re.is_none());
    let a: Envelope = serde_json::from_str(&pong(None)).unwrap();
    let b: Envelope = serde_json::from_str(&pong(None)).unwrap();
    assert_ne!(a.id, b.id, "у каждого сообщения свой id");
    assert!(a.body.is_null());
  }

  #[test]
  fn state_is_capped_and_signed_by_pc() {
    let pc = PcInfo { id: "pc_1".into(), name: "DESKTOP".into() };
    let queue: Vec<Value> = (0..80).map(|i| track_json(&format!("sc:{i}"))).collect();
    let body = state_body(json!({ "playing": true, "queue": queue, "device": "подмена" }), &pc);
    assert_eq!(body["queue"].as_array().unwrap().len(), QUEUE_LIMIT);
    assert_eq!(body["device"], json!({ "id": "pc_1", "name": "DESKTOP", "kind": "pc" }));
    assert_eq!(state_body(json!("мусор"), &pc)["device"]["kind"], "pc");
    let s: Envelope = serde_json::from_str(&state(&body)).unwrap();
    assert_eq!(s.kind, "state");
    assert_eq!(s.body["playing"], true);
  }

  #[test]
  fn names_and_ids() {
    assert_eq!(clean_name("  \u{7}Folzy\n iPhone "), "Folzy iPhone");
    assert_eq!(clean_name(&"я".repeat(100)).chars().count(), 64);
    assert!(is_device_id("6F9619FF-8B86-D011-B42D-00C04FC964FF"));
    assert!(!is_device_id(""));
    assert!(!is_device_id(&"a".repeat(65)));
    assert!(is_key(&"A-z_9".repeat(9)));
    assert!(!is_key("abc=="));
  }
}
