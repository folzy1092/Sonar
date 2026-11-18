//! Объявление ПК в локальной сети: Bonjour/mDNS `_sonar._tcp` — iPhone находит его через NWBrowser.
//! TXT: `id` (id ПК), `v` (версия протокола), `name` (имя компьютера).

use super::protocol::{PcInfo, VERSION};
use mdns_sd::{ServiceDaemon, ServiceInfo};
use std::collections::HashMap;
use std::net::{IpAddr, UdpSocket};

pub const SERVICE_TYPE: &str = "_sonar._tcp.local.";
/// Метка DNS — не длиннее 63 байт.
const MAX_LABEL: usize = 63;

/// Пока живёт — ПК виден в сети.
pub struct Announce {
  daemon: ServiceDaemon,
  fullname: String,
}

impl Drop for Announce {
  fn drop(&mut self) {
    let _ = self.daemon.unregister(&self.fullname);
    let _ = self.daemon.shutdown();
  }
}

/// Объявить ПК; не вышло (нет сети, порт 5353 занят) — телефон всё равно подключится по QR.
pub fn announce(pc: &PcInfo, port: u16) -> Result<Announce, String> {
  let daemon = ServiceDaemon::new().map_err(|e| e.to_string())?;
  let props: HashMap<String, String> =
    [("id".to_owned(), pc.id.clone()), ("v".to_owned(), VERSION.to_string()), ("name".to_owned(), truncate(&pc.name, 200))].into();
  let host = format!("{}.local.", host_label(&pc.name));
  let info = ServiceInfo::new(SERVICE_TYPE, &truncate(&pc.name, MAX_LABEL), &host, (), port, props)
    .map_err(|e| e.to_string())?
    .enable_addr_auto();
  let fullname = info.get_fullname().to_owned();
  daemon.register(info).map_err(|e| e.to_string())?;
  Ok(Announce { daemon, fullname })
}

/// Имя компьютера, как его видно в сети Windows.
pub fn pc_name() -> String {
  let raw = std::env::var("COMPUTERNAME").or_else(|_| std::env::var("HOSTNAME")).unwrap_or_default();
  let name = raw.trim();
  if name.is_empty() { "Sonar PC".into() } else { name.to_owned() }
}

/// Имя хоста для mDNS: только латиница, цифры и `-`.
pub fn host_label(name: &str) -> String {
  let mut label: String = name
    .chars()
    .map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_lowercase() } else { '-' })
    .collect::<String>()
    .trim_matches('-')
    .to_owned();
  label.truncate(MAX_LABEL - "-sonar".len());
  if label.is_empty() { "sonar".into() } else { format!("{label}-sonar") }
}

/// Обрезать по границе символа, не длиннее `max` байт.
pub fn truncate(s: &str, max: usize) -> String {
  let mut end = s.len().min(max);
  while !s.is_char_boundary(end) {
    end -= 1;
  }
  s[..end].to_owned()
}

/// Адрес ПК в локальной сети (для QR): UDP-«подключение» только выбирает маршрут, пакеты не уходят.
pub fn lan_ip() -> Option<IpAddr> {
  let s = UdpSocket::bind("0.0.0.0:0").ok()?;
  s.connect("192.0.2.1:9").ok()?;
  let ip = s.local_addr().ok()?.ip();
  (!ip.is_unspecified() && !ip.is_loopback()).then_some(ip)
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn host_labels() {
    assert_eq!(host_label("DESKTOP-AB12"), "desktop-ab12-sonar");
    assert_eq!(host_label("Мой ПК"), "sonar");
    assert_eq!(host_label("Folzy's PC"), "folzy-s-pc-sonar");
    assert!(host_label(&"x".repeat(100)).len() <= MAX_LABEL);
  }

  #[test]
  fn truncates_on_char_boundary() {
    assert_eq!(truncate("Привет", 5), "Пр");
    assert_eq!(truncate("abc", 10), "abc");
  }
}
