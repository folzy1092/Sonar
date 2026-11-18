//! Тестовые файлы локальной музыки: короткие WAV (тишина), теги ID3v2 и обложка — всё
//! генерируется на лету во временной папке.

use lofty::config::WriteOptions;
use lofty::picture::{MimeType, Picture, PictureType};
use lofty::prelude::*;
use lofty::tag::{Tag, TagType};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, Ordering};

/// Картинка 1×1 PNG.
pub const PNG: &[u8] = &[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00,
  0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78,
  0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, 0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

static SEQ: AtomicU32 = AtomicU32::new(0);

/// Новая пустая папка во временном каталоге.
pub fn temp_dir(tag: &str) -> PathBuf {
  let n = SEQ.fetch_add(1, Ordering::SeqCst);
  let dir = std::env::temp_dir().join(format!("sonar-local-{tag}-{}-{n}", std::process::id()));
  let _ = std::fs::remove_dir_all(&dir);
  std::fs::create_dir_all(&dir).unwrap();
  dir
}

/// WAV: 8 кГц, моно, 16 бит, тишина длиной `ms`.
pub fn wav_bytes(ms: u32) -> Vec<u8> {
  const RATE: u32 = 8000;
  let samples = RATE * ms / 1000;
  let data_len = samples * 2;
  let mut v = Vec::with_capacity(44 + data_len as usize);
  v.extend_from_slice(b"RIFF");
  v.extend_from_slice(&(36 + data_len).to_le_bytes());
  v.extend_from_slice(b"WAVEfmt ");
  v.extend_from_slice(&16u32.to_le_bytes());
  v.extend_from_slice(&1u16.to_le_bytes()); // PCM
  v.extend_from_slice(&1u16.to_le_bytes()); // моно
  v.extend_from_slice(&RATE.to_le_bytes());
  v.extend_from_slice(&(RATE * 2).to_le_bytes());
  v.extend_from_slice(&2u16.to_le_bytes());
  v.extend_from_slice(&16u16.to_le_bytes());
  v.extend_from_slice(b"data");
  v.extend_from_slice(&data_len.to_le_bytes());
  v.resize(44 + data_len as usize, 0);
  v
}

pub fn write_wav(path: &Path, ms: u32) {
  if let Some(parent) = path.parent() {
    std::fs::create_dir_all(parent).unwrap();
  }
  std::fs::write(path, wav_bytes(ms)).unwrap();
}

/// Теги ID3v2 в WAV: название, исполнитель, альбом и (если есть) обложка.
pub fn tag_wav(path: &Path, title: &str, artist: &str, album: Option<&str>, cover: Option<&[u8]>) {
  let mut tag = Tag::new(TagType::Id3v2);
  tag.set_title(title.into());
  tag.set_artist(artist.into());
  if let Some(a) = album {
    tag.set_album(a.into());
  }
  if let Some(bytes) = cover {
    tag.push_picture(Picture::new_unchecked(PictureType::CoverFront, Some(MimeType::Png), None, bytes.to_vec()));
  }
  tag.save_to_path(path, WriteOptions::default()).unwrap();
}
