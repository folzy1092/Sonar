//! Пульт: iPhone управляет Sonar на этом ПК по Wi-Fi (Система → Пульт, по умолчанию выключен).
//! ПК — WebSocket-сервер в локальной сети и объявление mDNS `_sonar._tcp`; телефон привязывается
//! 6-значным кодом (или QR) и получает постоянный ключ. Звук не передаётся — только команды и `state`.
//! Команды телефона уходят в интерфейс событием `remote-command` (их выполняет player.svelte.ts),
//! интерфейс шлёт состояние плеера в `remote_state` — оно расходится всем подключённым телефонам.
//! Протокол — docs/API.md «Пульт».

mod devices;
mod mdns;
mod pairing;
pub mod protocol;
mod server;
mod sync_hub;

use devices::{DeviceView, Vault};
use pairing::PairCode;
use protocol::{DeviceHello, Incoming, PcInfo};
use serde::Serialize;
use serde_json::Value;
use server::Out;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tauri::{AppHandle, Emitter, Manager, State};
use tokio::sync::{mpsc, watch};

/// Подключённый телефон.
struct Client {
  device_id: String,
  tx: mpsc::UnboundedSender<Out>,
}

struct Running {
  port: u16,
  stop: watch::Sender<bool>,
  /// `None` — объявить в сети не вышло (`mdns_error`), подключиться можно по QR.
  _announce: Option<mdns::Announce>,
  mdns_error: Option<String>,
}

#[derive(Default)]
struct Inner {
  vault: Option<Vault>,
  pair: Option<PairCode>,
  clients: HashMap<u64, Client>,
  next_conn: u64,
  /// Последнее `state` (уже с `device`) — новому телефону сразу.
  state: Option<Value>,
  running: Option<Running>,
  error: Option<String>,
}

pub struct Remote {
  app: AppHandle,
  inner: Mutex<Inner>,
}

fn now_ms() -> u64 {
  crate::store::now_ms().max(0) as u64
}

impl Inner {
  fn vault(&mut self) -> &Vault {
    self.vault.get_or_insert_with(|| {
      let v = Vault::load();
      // id ПК создан только что — сохраняем, чтобы телефоны узнавали его и после перезапуска
      let _ = v.save();
      v
    })
  }

  fn set_vault(&mut self, v: Vault) {
    if let Err(e) = v.save() {
      self.error = Some(format!("keyring: {e}"));
    }
    self.vault = Some(v);
  }

  fn pc(&mut self) -> PcInfo {
    PcInfo { id: self.vault().pc_id.clone(), name: mdns::pc_name() }
  }

  fn broadcast(&self, text: &str) {
    for c in self.clients.values() {
      let _ = c.tx.send(Out::Text(text.to_owned()));
    }
  }

  fn online(&self) -> Vec<String> {
    self.clients.values().map(|c| c.device_id.clone()).collect()
  }
}

impl Remote {
  pub fn new(app: AppHandle) -> Arc<Self> {
    Arc::new(Self { app, inner: Mutex::new(Inner::default()) })
  }

  fn changed(&self) {
    let _ = self.app.emit("remote-changed", ());
  }

  /// `hello`: телефон привязан и ключ верный.
  fn login(&self, d: &DeviceHello, key: &str) -> Option<PcInfo> {
    let mut g = self.inner.lock().unwrap();
    if !g.vault().verify(&d.id, key) {
      return None;
    }
    let v = g.vault().seen(d, crate::store::now_ms());
    g.set_vault(v);
    Some(g.pc())
  }

  /// `pair`: код с экрана → новый ключ (возвращается один раз, телефону).
  fn pair(&self, d: &DeviceHello, code: &str) -> Result<(PcInfo, String), &'static str> {
    let mut g = self.inner.lock().unwrap();
    let check = pairing::check(&mut g.pair, code, now_ms());
    if check != pairing::Check::Ok {
      drop(g);
      self.changed();
      return Err(check.error_code());
    }
    let key = pairing::new_key();
    let v = g.vault().paired(d, &key, crate::store::now_ms());
    g.set_vault(v);
    let pc = g.pc();
    drop(g);
    let _ = self.app.emit("remote-paired", d.name.clone());
    Ok((pc, key))
  }

  fn connect(&self, d: &DeviceHello, tx: mpsc::UnboundedSender<Out>) -> u64 {
    let mut g = self.inner.lock().unwrap();
    if let Some(s) = &g.state {
      let _ = tx.send(Out::Text(protocol::state(s)));
    }
    g.next_conn += 1;
    let id = g.next_conn;
    g.clients.insert(id, Client { device_id: d.id.clone(), tx });
    drop(g);
    self.changed();
    id
  }

  fn disconnect(&self, conn: u64) {
    self.inner.lock().unwrap().clients.remove(&conn);
    self.changed();
  }

  /// Сообщение вошедшего телефона → ответ ему (если нужен).
  async fn handle(&self, device_id: &str, text: &str) -> Option<String> {
    let (env, incoming) = match protocol::parse(text) {
      Ok(x) => x,
      Err(e) => return Some(protocol::error(e.code(), None)),
    };
    let re = Some(env.id.as_str()).filter(|s| !s.is_empty());
    if !protocol::fits(text, &incoming) {
      return Some(protocol::error("too_big", re));
    }
    match incoming {
      Incoming::Ping => Some(protocol::pong(re)),
      Incoming::Hello { .. } | Incoming::Pair { .. } => Some(protocol::error("already_paired", re)),
      Incoming::Command(c) => {
        let _ = self.app.emit("remote-command", &c);
        None
      }
      Incoming::Sync(req) => Some(self.sync(device_id, req, re).await),
    }
  }

  /// Синк по Wi‑Fi (`sync_hub.rs`): только привязанным, не в офлайне и пока нет сервера Sonar.
  async fn sync(&self, device_id: &str, req: protocol::SyncRequest, re: Option<&str>) -> String {
    // телефон могли отвязать, пока связь висела
    if !self.inner.lock().unwrap().vault().has(device_id) {
      return protocol::error("not_paired", re);
    }
    if crate::offline::is_on() {
      return protocol::error("offline", re);
    }
    let Some(db) = self.app.try_state::<crate::commands::Db>() else { return protocol::error("sync_failed", re) };
    if crate::sync::configured(&db.0).is_some() {
      return protocol::error("server_sync", re);
    }
    match sync_hub::answer(&db.0, device_id, req, re, crate::store::now_ms() / 1000).await {
      Ok(a) => {
        if a.applied_on_pc > 0 {
          let _ = self.app.emit("sync-applied", a.applied_on_pc);
        }
        self.changed();
        a.reply
      }
      Err(e) => {
        log::warn!("синк по Wi‑Fi: {e:#}");
        protocol::error("sync_failed", re)
      }
    }
  }

  async fn start(self: &Arc<Self>) -> Result<(), String> {
    if self.inner.lock().unwrap().running.is_some() {
      return Ok(());
    }
    let listener = server::bind().await.map_err(|e| e.to_string())?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    let (stop, rx) = watch::channel(false);
    let mut g = self.inner.lock().unwrap();
    if g.running.is_some() {
      return Ok(()); // успел запустить параллельный вызов
    }
    let pc = g.pc();
    let (announce, mdns_error) = match mdns::announce(&pc, port) {
      Ok(a) => (Some(a), None),
      Err(e) => (None, Some(e)),
    };
    g.running = Some(Running { port, stop, _announce: announce, mdns_error });
    g.error = None;
    drop(g);
    tauri::async_runtime::spawn(server::serve(self.clone(), listener, rx));
    self.changed();
    Ok(())
  }

  fn stop(&self) {
    let mut g = self.inner.lock().unwrap();
    g.broadcast(&protocol::bye("disabled"));
    for c in g.clients.values() {
      let _ = c.tx.send(Out::Close);
    }
    if let Some(r) = g.running.take() {
      let _ = r.stop.send(true);
    }
    g.pair = None;
    drop(g);
    self.changed();
  }
}

// ——— команды интерфейса ———

#[derive(Serialize)]
pub struct Status {
  running: bool,
  port: u16,
  host: Option<String>,
  name: String,
  /// Не удалось объявить ПК в сети — телефон не увидит его в списке, но подключится по QR.
  mdns_error: Option<String>,
  error: Option<String>,
  pairing: bool,
  devices: Vec<DeviceView>,
  /// Синк по Wi‑Fi идёт (сервера Sonar нет): лайки, плейлисты и настройки телефоны берут у ПК.
  lan_sync: bool,
  /// Когда телефон последний раз синхронизировался с ПК (unix, секунды).
  synced: HashMap<String, i64>,
}

#[derive(Serialize)]
pub struct PairStart {
  code: String,
  expires_in_ms: u64,
  /// QR со ссылкой `sonar://remote/pair?...` — SVG, чёрные модули на белом (камера читает и в тёмной теме).
  qr_svg: String,
}

#[tauri::command]
pub async fn remote_set_enabled(remote: State<'_, Arc<Remote>>, on: bool) -> Result<(), String> {
  let r = remote.inner().clone();
  if on {
    r.start().await.inspect_err(|e| {
      r.inner.lock().unwrap().error = Some(e.clone());
      r.changed();
    })
  } else {
    r.stop();
    Ok(())
  }
}

#[tauri::command]
pub fn remote_status(remote: State<'_, Arc<Remote>>, db: State<'_, crate::commands::Db>) -> Status {
  let lan_sync = crate::sync::configured(&db.0).is_none();
  let synced = db.0.lock().unwrap().hub_peers().unwrap_or_default();
  let mut g = remote.inner.lock().unwrap();
  let online = g.online();
  let devices = g.vault().views(&online);
  let pairing = g.pair.as_ref().is_some_and(|p| p.expires_at_ms > now_ms());
  let running = g.running.as_ref();
  Status {
    running: running.is_some(),
    port: running.map_or(0, |r| r.port),
    host: running.and_then(|_| mdns::lan_ip()).map(|ip| ip.to_string()),
    name: mdns::pc_name(),
    mdns_error: running.and_then(|r| r.mdns_error.clone()),
    error: g.error.clone(),
    pairing,
    devices,
    lan_sync,
    synced,
  }
}

/// Ссылка в QR: всё, чтобы телефон подключился без поиска в сети.
pub fn pair_link(pc: &PcInfo, host: &str, port: u16, code: &str) -> String {
  let e = |s: &str| urlencoding::encode(s).into_owned();
  format!("sonar://remote/pair?pc={}&name={}&host={}&port={port}&code={code}", e(&pc.id), e(&pc.name), e(host))
}

fn qr_svg(text: &str) -> Result<String, String> {
  use qrcode::render::svg;
  let code = qrcode::QrCode::new(text.as_bytes()).map_err(|e| e.to_string())?;
  Ok(code.render::<svg::Color>().dark_color(svg::Color("#000000")).light_color(svg::Color("#ffffff")).quiet_zone(true).min_dimensions(200, 200).build())
}

#[tauri::command]
pub fn remote_pair_start(remote: State<'_, Arc<Remote>>) -> Result<PairStart, String> {
  let mut g = remote.inner.lock().unwrap();
  let port = g.running.as_ref().map(|r| r.port).ok_or("Пульт выключен")?;
  let pair = PairCode::new(now_ms());
  let host = mdns::lan_ip().map(|ip| ip.to_string()).unwrap_or_default();
  let pc = g.pc();
  let qr = qr_svg(&pair_link(&pc, &host, port, &pair.code))?;
  let out = PairStart { code: pair.code.clone(), expires_in_ms: pairing::CODE_TTL_MS, qr_svg: qr };
  g.pair = Some(pair);
  drop(g);
  remote.changed();
  Ok(out)
}

#[tauri::command]
pub fn remote_pair_cancel(remote: State<'_, Arc<Remote>>) {
  remote.inner.lock().unwrap().pair = None;
  remote.changed();
}

#[tauri::command]
pub fn remote_unpair(remote: State<'_, Arc<Remote>>, id: String) {
  let mut g = remote.inner.lock().unwrap();
  let v = g.vault().without(&id);
  g.set_vault(v);
  for c in g.clients.values().filter(|c| c.device_id == id) {
    let _ = c.tx.send(Out::Text(protocol::bye("unpaired")));
    let _ = c.tx.send(Out::Close);
  }
  drop(g);
  remote.changed();
}

/// Состояние плеера от интерфейса → всем телефонам.
#[tauri::command]
pub fn remote_state(remote: State<'_, Arc<Remote>>, state: Value) {
  let mut g = remote.inner.lock().unwrap();
  if g.running.is_none() {
    return;
  }
  let pc = g.pc();
  let body = protocol::state_body(state, &pc);
  if g.state.as_ref() == Some(&body) {
    return;
  }
  if !g.clients.is_empty() {
    g.broadcast(&protocol::state(&body));
  }
  g.state = Some(body);
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn pair_link_is_escaped() {
    let pc = PcInfo { id: "pc_ab".into(), name: "Мой ПК & co".into() };
    let link = pair_link(&pc, "192.168.1.5", 53120, "012345");
    assert!(link.starts_with("sonar://remote/pair?pc=pc_ab&name=%D0%9C"));
    assert!(link.ends_with("&host=192.168.1.5&port=53120&code=012345"));
    assert!(!link.contains(' '));
  }

  #[test]
  fn qr_is_svg() {
    let svg = qr_svg("sonar://remote/pair?pc=pc_1&code=000000").unwrap();
    assert!(svg.contains("<svg") && svg.contains("#000000"));
  }
}
