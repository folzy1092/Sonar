//! Ворота сети офлайн-режима (`docs/OFFLINE.md` §5.2): каждый `reqwest::Client` Sonar строится здесь.
//! Слой на уровне соединения (`connector_layer`) отказывает в любом новом соединении, пока `offline::is_on()`.
//! Уже открытое keep-alive соединение слой не видит — поэтому `Core::http()` в офлайне отдаёт второй клиент
//! без пула (`client(true)`): ему нечего переиспользовать, каждое соединение идёт через ворота.
use std::future::Future;
use std::pin::Pin;
use std::task::{Context, Poll};
use std::time::Duration;

use tower::{Layer, Service};

type BoxError = Box<dyn std::error::Error + Send + Sync>;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);

/// Клиент Sonar. `no_pool` — без keep-alive (клиент офлайна).
pub fn client(no_pool: bool) -> reqwest::Client {
  let mut b = reqwest::Client::builder().connect_timeout(CONNECT_TIMEOUT).gzip(true).connector_layer(OfflineLayer);
  if no_pool {
    b = b.pool_max_idle_per_host(0);
  }
  b.build().expect("http client")
}

#[derive(Debug)]
struct OfflineError;

impl std::fmt::Display for OfflineError {
  fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
    f.write_str(crate::offline::MESSAGE)
  }
}

impl std::error::Error for OfflineError {}

#[derive(Clone, Copy)]
struct OfflineLayer;

impl<S> Layer<S> for OfflineLayer {
  type Service = OfflineGate<S>;
  fn layer(&self, inner: S) -> Self::Service {
    OfflineGate(inner)
  }
}

#[derive(Clone)]
struct OfflineGate<S>(S);

impl<S, R> Service<R> for OfflineGate<S>
where
  S: Service<R, Error = BoxError>,
  S::Response: Send + 'static,
  S::Future: Send + 'static,
{
  type Response = S::Response;
  type Error = BoxError;
  type Future = Pin<Box<dyn Future<Output = Result<S::Response, BoxError>> + Send>>;

  fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), BoxError>> {
    self.0.poll_ready(cx)
  }

  fn call(&mut self, req: R) -> Self::Future {
    if crate::offline::is_on() {
      return Box::pin(std::future::ready(Err(Box::new(OfflineError) as BoxError)));
    }
    Box::pin(self.0.call(req))
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::offline::{set_on, tests::FLAG};
  use std::sync::atomic::{AtomicUsize, Ordering};
  use std::sync::Arc;
  use tokio::io::{AsyncReadExt, AsyncWriteExt};

  /// Сервер на 127.0.0.1: считает принятые соединения, на каждый запрос отвечает «ok» и держит keep-alive.
  async fn counting_server() -> (String, Arc<AtomicUsize>) {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}/", listener.local_addr().unwrap());
    let accepted = Arc::new(AtomicUsize::new(0));
    let count = accepted.clone();
    tokio::spawn(async move {
      while let Ok((mut sock, _)) = listener.accept().await {
        count.fetch_add(1, Ordering::SeqCst);
        tokio::spawn(async move {
          let mut buf = [0u8; 2048];
          while let Ok(n) = sock.read(&mut buf).await {
            if n == 0 {
              break;
            }
            let reply = b"HTTP/1.1 200 OK\r\ncontent-length: 2\r\nconnection: keep-alive\r\n\r\nok";
            if sock.write_all(reply).await.is_err() {
              break;
            }
          }
        });
      }
    });
    (url, accepted)
  }

  /// Как `Core::http()`: в офлайне — клиент без пула.
  fn pick<'a>(live: &'a reqwest::Client, dead: &'a reqwest::Client) -> &'a reqwest::Client {
    if crate::offline::is_on() { dead } else { live }
  }

  #[tokio::test]
  async fn offline_opens_no_connections_even_over_keep_alive() {
    let _lock = FLAG.lock().unwrap_or_else(|p| p.into_inner());
    let (url, accepted) = counting_server().await;
    let (live, dead) = (client(false), client(true));

    set_on(false);
    assert_eq!(pick(&live, &dead).get(&url).send().await.unwrap().text().await.unwrap(), "ok");
    assert_eq!(accepted.load(Ordering::SeqCst), 1, "в сети — одно соединение, дальше оно в пуле");

    set_on(true);
    let err = pick(&live, &dead).get(&url).send().await.unwrap_err();
    let chain = std::iter::successors(Some(&err as &dyn std::error::Error), |e| e.source());
    assert!(chain.map(|e| e.to_string()).any(|t| t == crate::offline::MESSAGE), "ошибка офлайна, а не сети: {err:?}");
    assert!(dead.get(&url).send().await.is_err());

    set_on(false);
    assert_eq!(live.get(&url).send().await.unwrap().text().await.unwrap(), "ok");
    assert_eq!(accepted.load(Ordering::SeqCst), 1, "пока режим был включён, к серверу не ходили");
  }
}
