//! Поток Spotify Premium через librespot — только со сборкой `cargo build --features spotify-playback`
//! (по умолчанию выключено, почему — docs/API.md «Spotify»). Вход в точку доступа Spotify — тем же
//! токеном веб-плеера, что и метаданные; трек — Ogg Vorbis, расшифрованный целиком в память и
//! отданный локальным аудио-сервером (stream.rs) как `audio/ogg`.

use anyhow::{anyhow, Context, Result};
use librespot_audio::{AudioDecrypt, AudioFile};
use librespot_core::{authentication::Credentials, Session, SessionConfig, SpotifyId, SpotifyUri};
use librespot_metadata::{audio::AudioFileFormat, Metadata, Track};
use std::io::Read;
use std::sync::{Arc, Mutex};

/// Адрес-метка в `Source::File`: stream.rs не проксирует его, а зовёт [`ogg`].
pub const SCHEME: &str = "librespot:";
/// Свой заголовок Spotify перед настоящим Ogg (как в librespot-playback).
const OGG_HEADER: usize = 0xa7;
/// Скорость докачки для librespot (байт/с) — с запасом под 320 кбит/с.
const BYTES_PER_SECOND: usize = 320 * 1024 / 8 * 4;

/// Одна сессия на токен: новый токен — новая сессия.
static SESSION: Mutex<Option<(String, Session)>> = Mutex::new(None);
/// Последний трек в памяти: `<audio>` перематывает запросами Range — не качать заново.
static LAST: Mutex<Option<(String, Arc<Vec<u8>>, String)>> = Mutex::new(None);

/// Форматы по убыванию качества, не выше потолка `audio.quality`.
pub fn formats(max_kbps: u32) -> Vec<AudioFileFormat> {
  [(320, AudioFileFormat::OGG_VORBIS_320), (160, AudioFileFormat::OGG_VORBIS_160), (96, AudioFileFormat::OGG_VORBIS_96)]
    .into_iter()
    .filter(|(kbps, _)| *kbps <= max_kbps.max(96))
    .map(|(_, f)| f)
    .collect()
}

fn kbps(f: AudioFileFormat) -> u32 {
  match f {
    AudioFileFormat::OGG_VORBIS_320 => 320,
    AudioFileFormat::OGG_VORBIS_160 => 160,
    _ => 96,
  }
}

async fn session(token: &str) -> Result<Session> {
  let cached = SESSION.lock().unwrap().clone();
  if let Some((t, s)) = cached
    && t == token
    && !s.is_invalid()
  {
    return Ok(s);
  }
  let s = Session::new(SessionConfig::default(), None);
  s.connect(Credentials::with_access_token(token), false).await.map_err(|_| anyhow!("Spotify: вход в поток не удался"))?;
  *SESSION.lock().unwrap() = Some((token.to_owned(), s.clone()));
  Ok(s)
}

/// Трек `id` (base62) целиком: байты Ogg и подпись качества.
pub async fn ogg(token: &str, id: &str, max_kbps: u32) -> Result<(Arc<Vec<u8>>, String)> {
  let last = LAST.lock().unwrap().clone();
  if let Some((last_id, bytes, quality)) = last
    && last_id == id
  {
    return Ok((bytes, quality));
  }
  let (bytes, quality) = download(token, id, max_kbps).await?;
  let bytes = Arc::new(bytes);
  *LAST.lock().unwrap() = Some((id.to_owned(), bytes.clone(), quality.clone()));
  Ok((bytes, quality))
}

async fn download(token: &str, id: &str, max_kbps: u32) -> Result<(Vec<u8>, String)> {
  let sid = SpotifyId::from_base62(id).map_err(|_| anyhow!("Spotify: неверный id трека"))?;
  let session = session(token).await?;
  let track = Track::get(&session, &SpotifyUri::Track { id: sid }).await.map_err(|_| anyhow!("Spotify: трек не найден"))?;
  let (format, file_id) = formats(max_kbps)
    .into_iter()
    .find_map(|f| track.files.get(&f).map(|id| (f, *id)))
    .ok_or_else(|| anyhow!("Spotify: у трека нет Ogg Vorbis"))?;
  let key = session.audio_key().request(sid, file_id).await.map_err(|_| anyhow!("Spotify: нет ключа трека"))?;
  let file = AudioFile::open(&session, file_id, BYTES_PER_SECOND).await.map_err(|_| anyhow!("Spotify: файл трека недоступен"))?;
  let bytes = tokio::task::spawn_blocking(move || -> Result<Vec<u8>> {
    let mut out = Vec::new();
    AudioDecrypt::new(Some(key), file).read_to_end(&mut out).context("Spotify: поток оборвался")?;
    Ok(out)
  })
  .await??;
  if bytes.len() <= OGG_HEADER {
    return Err(anyhow!("Spotify: пустой файл трека"));
  }
  Ok((bytes[OGG_HEADER..].to_vec(), format!("Ogg Vorbis {} · Spotify", kbps(format))))
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn formats_follow_quality_ceiling() {
    assert_eq!(formats(1411).len(), 3);
    assert_eq!(formats(320)[0], AudioFileFormat::OGG_VORBIS_320);
    assert_eq!(formats(256), [AudioFileFormat::OGG_VORBIS_160, AudioFileFormat::OGG_VORBIS_96]);
    assert_eq!(formats(64), [AudioFileFormat::OGG_VORBIS_96]);
  }

  /// `SP_DC=… SP_TRACK=<base62> cargo test --features spotify-playback -- --ignored live_premium_ogg`
  #[tokio::test]
  #[ignore = "живой Spotify Premium: нужен SP_DC (и по желанию SP_TRACK) в окружении"]
  async fn live_premium_ogg() {
    use crate::providers::spotify::{normalize_sp_dc, Creds, Spotify, TotpStore};
    let Some(sp_dc) = std::env::var("SP_DC").ok().and_then(|v| normalize_sp_dc(&v)) else { return eprintln!("SP_DC не задан — пропуск") };
    let id = std::env::var("SP_TRACK").unwrap_or_else(|_| "0DiWol3AO6WpXZgp0goxAV".into());
    let (http, creds, secret, cache) = (reqwest::Client::new(), Creds { sp_dc }, TotpStore::default(), tokio::sync::Mutex::new(None));
    let token = Spotify { http: &http, creds: &creds, secret: &secret, cache: &cache }.token(false).await.unwrap();
    let (bytes, quality) = ogg(&token, &id, 320).await.unwrap();
    assert_eq!(&bytes[..4], b"OggS", "после заголовка Spotify — Ogg");
    println!("{quality}: {} КБ", bytes.len() / 1024);
  }
}
