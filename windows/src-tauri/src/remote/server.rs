//! WebSocket-сервер пульта в локальной сети. Первое сообщение телефона — `hello` (уже привязан)
//! или `pair` (код с экрана); до этого никакие команды не принимаются. Ключи в журнал не пишем.

use super::protocol::{self, Incoming, ParseError, MAX_SYNC_MESSAGE};
use super::Remote;
use futures_util::{SinkExt, StreamExt};
use std::sync::Arc;
use std::time::Duration;
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, watch};
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::WebSocketStream;

/// Постоянный порт (рядом с плашкой OBS 53119); занят — любой свободный.
pub const PREFERRED_PORT: u16 = 53120;
/// Сколько ждём `hello` / верный `pair` после подключения (код вводят руками).
const HANDSHAKE: Duration = Duration::from_secs(90);
/// Тишина дольше — телефон пропал (он шлёт `ping` раз в ~20 с).
const IDLE: Duration = Duration::from_secs(60);

/// Что уходит в сокет телефона.
#[derive(Debug)]
pub enum Out {
  Text(String),
  /// Закрыть после отправленного (`bye`).
  Close,
}

pub async fn bind() -> std::io::Result<TcpListener> {
  match TcpListener::bind(("0.0.0.0", PREFERRED_PORT)).await {
    Ok(l) => Ok(l),
    Err(_) => TcpListener::bind(("0.0.0.0", 0)).await,
  }
}

pub async fn serve(remote: Arc<Remote>, listener: TcpListener, mut stop: watch::Receiver<bool>) {
  loop {
    tokio::select! {
      _ = stop.changed() => break,
      accepted = listener.accept() => match accepted {
        Ok((stream, _)) => {
          let _ = stream.set_nodelay(true);
          tauri::async_runtime::spawn(connection(remote.clone(), stream, stop.clone()));
        }
        Err(_) => tokio::time::sleep(Duration::from_millis(200)).await,
      },
    }
  }
}

fn ws_config() -> WebSocketConfig {
  // синк шлёт пачки побольше; остальные типы режутся на `MAX_MESSAGE` после разбора (`protocol::fits`)
  WebSocketConfig::default().max_message_size(Some(MAX_SYNC_MESSAGE)).max_frame_size(Some(MAX_SYNC_MESSAGE))
}

type Ws = WebSocketStream<TcpStream>;

async fn connection(remote: Arc<Remote>, stream: TcpStream, mut stop: watch::Receiver<bool>) {
  let Ok(mut ws) = tokio_tungstenite::accept_async_with_config(stream, Some(ws_config())).await else { return };
  let device = match tokio::time::timeout(HANDSHAKE, handshake(&remote, &mut ws)).await {
    Ok(Some(d)) => d,
    _ => {
      let _ = ws.close(None).await;
      return;
    }
  };
  let (tx, mut rx) = mpsc::unbounded_channel::<Out>();
  let conn = remote.connect(&device, tx);
  // Срок тишины считаем только по входящим: исходящие `state` идут постоянно и не должны
  // продлевать жизнь пропавшему телефону.
  let mut deadline = tokio::time::Instant::now() + IDLE;
  loop {
    tokio::select! {
      // сначала очередь: `bye` должен уйти до закрытия
      biased;
      out = rx.recv() => match out {
        Some(Out::Text(t)) => if ws.send(Message::text(t)).await.is_err() { break },
        Some(Out::Close) | None => break,
      },
      msg = ws.next() => {
        deadline = tokio::time::Instant::now() + IDLE;
        match msg {
          Some(Ok(Message::Text(t))) => {
            if let Some(reply) = remote.handle(&device.id, t.as_str()).await {
              if ws.send(Message::text(reply)).await.is_err() { break }
            }
          }
          Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
          Some(Ok(_)) => {}
        }
      },
      _ = tokio::time::sleep_until(deadline) => break,
      _ = stop.changed() => break,
    }
  }
  let _ = ws.close(None).await;
  remote.disconnect(conn);
}

/// До входа: только `hello` / `pair` / `ping`. Возвращает телефон, который вошёл.
async fn handshake(remote: &Remote, ws: &mut Ws) -> Option<protocol::DeviceHello> {
  while let Some(msg) = ws.next().await {
    let text = match msg.ok()? {
      Message::Text(t) => t,
      Message::Close(_) => return None,
      _ => continue,
    };
    let (env, incoming) = match protocol::parse(text.as_str()) {
      Ok(x) => x,
      Err(e) => {
        ws.send(Message::text(protocol::error(e.code(), None))).await.ok()?;
        if matches!(e, ParseError::BadVersion(_)) {
          return None;
        }
        continue;
      }
    };
    let re = Some(env.id.as_str()).filter(|s| !s.is_empty());
    if !protocol::fits(text.as_str(), &incoming) {
      ws.send(Message::text(protocol::error("too_big", re))).await.ok()?;
      continue;
    }
    let (reply, done) = match incoming {
      Incoming::Ping => (protocol::pong(re), None),
      Incoming::Hello { device, key } => match remote.login(&device, &key) {
        Some(pc) => (protocol::welcome(&pc, re), Some(device)),
        None => {
          // не привязан или ключ не тот — одинаковый ответ, телефон предлагает привязать заново
          ws.send(Message::text(protocol::error("not_paired", re))).await.ok()?;
          return None;
        }
      },
      Incoming::Pair { device, code } => match remote.pair(&device, &code) {
        Ok((pc, key)) => (protocol::paired(&pc, &key, re), Some(device)),
        Err(code) => (protocol::error(code, re), None),
      },
      Incoming::Command(_) | Incoming::Sync(_) => (protocol::error("not_paired", re), None),
    };
    ws.send(Message::text(reply)).await.ok()?;
    if done.is_some() {
      return done;
    }
  }
  None
}
