//! Теги и обложка одного файла (lofty). Ничего не роняет: файл без тегов или битый — название из
//! имени файла («Исполнитель - Название.mp3»), длительность 0.

use lofty::picture::{MimeType, PictureType};
use lofty::prelude::*;
use std::path::Path;

/// Картинки папки, если в тегах обложки нет (как у плееров: cover.jpg, folder.jpg…).
const FOLDER_COVERS: &[&str] = &["cover", "folder", "front", "album"];
const FOLDER_COVER_EXTS: &[&str] = &["jpg", "jpeg", "png"];
/// Обложки крупнее не берём — это не обложка, а что-то странное.
const MAX_COVER_BYTES: usize = 20 * 1024 * 1024;

#[derive(Debug, Default, PartialEq)]
pub struct Meta {
  pub title: String,
  pub artist: String,
  pub album: Option<String>,
  pub duration_ms: i64,
  /// Байты обложки и расширение файла для неё.
  pub cover: Option<(Vec<u8>, &'static str)>,
}

fn clean(s: Option<std::borrow::Cow<'_, str>>) -> Option<String> {
  s.map(|v| v.trim().to_owned()).filter(|v| !v.is_empty())
}

fn picture_ext(mime: Option<&MimeType>) -> &'static str {
  match mime {
    Some(MimeType::Png) => "png",
    Some(MimeType::Gif) => "gif",
    Some(MimeType::Bmp) => "bmp",
    Some(MimeType::Tiff) => "tiff",
    _ => "jpg",
  }
}

/// Что лофти прочитал из файла (без запасных вариантов).
fn read_tags(path: &Path) -> Option<Meta> {
  let tagged = lofty::read_from_path(path).ok()?;
  let duration_ms = tagged.properties().duration().as_millis() as i64;
  let Some(tag) = tagged.primary_tag().or_else(|| tagged.first_tag()) else {
    return Some(Meta { duration_ms, ..Meta::default() });
  };
  let pics = tag.pictures();
  let pic = pics.iter().find(|p| p.pic_type() == PictureType::CoverFront).or_else(|| pics.first());
  let cover = pic
    .filter(|p| !p.data().is_empty() && p.data().len() <= MAX_COVER_BYTES)
    .map(|p| (p.data().to_vec(), picture_ext(p.mime_type())));
  Some(Meta {
    title: clean(tag.title()).unwrap_or_default(),
    artist: clean(tag.artist()).unwrap_or_default(),
    album: clean(tag.album()),
    duration_ms,
    cover,
  })
}

/// «Исполнитель - Название» из имени файла; без « - » — всё имя как название.
fn from_stem(path: &Path) -> (String, String) {
  let stem = path.file_stem().map(|s| s.to_string_lossy().trim().to_owned()).unwrap_or_default();
  match stem.split_once(" - ") {
    Some((a, t)) if !a.trim().is_empty() && !t.trim().is_empty() => (a.trim().to_owned(), t.trim().to_owned()),
    _ => (String::new(), stem),
  }
}

fn folder_cover(path: &Path) -> Option<(Vec<u8>, &'static str)> {
  let dir = path.parent()?;
  for name in FOLDER_COVERS {
    for ext in FOLDER_COVER_EXTS {
      for candidate in [format!("{name}.{ext}"), format!("{}.{ext}", capitalize(name))] {
        let p = dir.join(&candidate);
        if !p.is_file() {
          continue;
        }
        let bytes = std::fs::read(&p).ok().filter(|b| !b.is_empty() && b.len() <= MAX_COVER_BYTES)?;
        return Some((bytes, if *ext == "png" { "png" } else { "jpg" }));
      }
    }
  }
  None
}

fn capitalize(s: &str) -> String {
  let mut c = s.chars();
  c.next().map(|f| f.to_uppercase().chain(c).collect()).unwrap_or_default()
}

/// Теги файла с запасными вариантами: название и исполнитель из имени, обложка из папки.
pub fn read(path: &Path) -> Meta {
  // lofty на битом файле может и запаниковать — тогда это просто файл без тегов
  let tags = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| read_tags(path))).ok().flatten();
  let mut meta = tags.unwrap_or_default();
  let (stem_artist, stem_title) = from_stem(path);
  if meta.title.is_empty() {
    meta.title = stem_title;
    if meta.artist.is_empty() {
      meta.artist = stem_artist;
    }
  }
  if meta.cover.is_none() {
    meta.cover = folder_cover(path);
  }
  meta
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::local::fixtures::{tag_wav, temp_dir, write_wav, PNG};

  #[test]
  fn reads_id3_tags_and_cover() {
    let dir = temp_dir("tags");
    let p = dir.join("track.wav");
    write_wav(&p, 1500);
    tag_wav(&p, "Ночь", "Артист", Some("Альбом"), Some(PNG));
    let m = read(&p);
    assert_eq!(m.title, "Ночь");
    assert_eq!(m.artist, "Артист");
    assert_eq!(m.album.as_deref(), Some("Альбом"));
    assert!((1400..=1600).contains(&m.duration_ms), "{}", m.duration_ms);
    assert_eq!(m.cover, Some((PNG.to_vec(), "png")));
    let _ = std::fs::remove_dir_all(dir);
  }

  #[test]
  fn untagged_falls_back_to_file_name() {
    let dir = temp_dir("stem");
    let p = dir.join("Some Artist - Some Song.wav");
    write_wav(&p, 500);
    let m = read(&p);
    assert_eq!((m.artist.as_str(), m.title.as_str()), ("Some Artist", "Some Song"));
    assert_eq!(m.album, None);
    assert_eq!(m.cover, None);

    let q = dir.join("just a title.wav");
    write_wav(&q, 500);
    let m = read(&q);
    assert_eq!((m.artist.as_str(), m.title.as_str()), ("", "just a title"));
    let _ = std::fs::remove_dir_all(dir);
  }

  #[test]
  fn broken_file_does_not_fail() {
    let dir = temp_dir("broken");
    let p = dir.join("Broken - File.mp3");
    std::fs::write(&p, b"not really an mp3").unwrap();
    let m = read(&p);
    assert_eq!((m.artist.as_str(), m.title.as_str(), m.duration_ms), ("Broken", "File", 0));
    let _ = std::fs::remove_dir_all(dir);
  }

  #[test]
  fn folder_image_is_cover_when_tags_have_none() {
    let dir = temp_dir("folder-cover");
    let p = dir.join("a.wav");
    write_wav(&p, 300);
    std::fs::write(dir.join("cover.png"), PNG).unwrap();
    assert_eq!(read(&p).cover, Some((PNG.to_vec(), "png")));
    let _ = std::fs::remove_dir_all(dir);
  }
}
