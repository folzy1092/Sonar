//! «Свой поток не играет» — ошибка с причиной, по которой ядро ищет тот же трек на другом сервисе
//! (резервный сервис, `services/fallback.rs`). Текст ошибки — прежний: его видят журнал и интерфейс.

use super::Source;
use serde::Serialize;
use std::fmt;

/// Почему трек сыграл с другого сервиса (поле `via.reason` в ответе `stream_url`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Reason {
  /// Трек недоступен на сервисе (`available: false`, нет потока, сервис не подключён).
  Unavailable,
  /// Только отрывок: превью / `policy: SNIP` SoundCloud, превью вместо полного трека Яндекса.
  Preview,
  /// Сервис отдаёт поток только с подпиской (Spotify без Premium).
  Premium,
  /// Поток не открылся и после повтора.
  Failed,
  /// Не беда, а настройка: «SoundCloud через Яндекс» (`audio.sc_via_yandex`).
  Preferred,
}

/// Ошибка потока с причиной; `preview` — отрывок, который можно сыграть, если замены нет.
#[derive(Debug)]
pub struct Unplayable {
  pub reason: Reason,
  pub message: String,
  pub preview: Option<Source>,
}

impl Unplayable {
  pub fn new(reason: Reason, message: impl Into<String>) -> Self {
    Self { reason, message: message.into(), preview: None }
  }

  /// Только отрывок: играть его, если тот же трек больше нигде не нашёлся.
  pub fn preview(message: impl Into<String>, src: Source) -> Self {
    Self { reason: Reason::Preview, message: message.into(), preview: Some(src) }
  }
}

impl fmt::Display for Unplayable {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    f.write_str(&self.message)
  }
}

impl std::error::Error for Unplayable {}

/// Трека на сервисе нет (или он закрыт): ошибка с причиной `Unavailable`, текст — прежний.
pub fn unavailable(message: impl Into<String>) -> anyhow::Error {
  Unplayable::new(Reason::Unavailable, message).into()
}

/// Причина ошибки потока: своя у `Unplayable`, остальное — «не открылся».
pub fn reason_of(e: &anyhow::Error) -> Reason {
  e.downcast_ref::<Unplayable>().map_or(Reason::Failed, |u| u.reason)
}

/// Отрывок из ошибки, если он есть.
pub fn preview_of(e: &anyhow::Error) -> Option<Source> {
  e.downcast_ref::<Unplayable>().and_then(|u| u.preview.clone())
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn keeps_text_and_reason_through_anyhow() {
    let e = anyhow::Error::new(Unplayable::new(Reason::Premium, "Spotify: нужен резервный сервис"));
    assert_eq!(e.to_string(), "Spotify: нужен резервный сервис");
    assert_eq!(reason_of(&e), Reason::Premium);
    assert!(preview_of(&e).is_none());
    assert_eq!(reason_of(&anyhow::anyhow!("HTTP 500")), Reason::Failed);
    let e = unavailable("нет трека");
    assert_eq!((reason_of(&e), e.to_string()), (Reason::Unavailable, "нет трека".to_owned()));
  }

  #[test]
  fn carries_preview_source() {
    let src = Source::File { url: "u".into(), quality: "MP3 128".into() };
    let e = anyhow::Error::new(Unplayable::preview("только отрывок", src.clone()));
    assert_eq!(reason_of(&e), Reason::Preview);
    assert_eq!(preview_of(&e), Some(src));
  }
}
