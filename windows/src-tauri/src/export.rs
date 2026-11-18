//! Экспорт плейлиста в файл (NEXT_PROMPT, этап 8): интерфейс сам собирает текст файла
//! (`src/lib/export.ts` — M3U8, CSV или JSON), а здесь — только окно «Сохранить как» и запись.
//! Окно открывает Rust, а не JS: у интерфейса нет права писать файлы куда угодно, он
//! передаёт готовый текст, а путь выбирает сам пользователь в системном окне.

use std::io::Write;
use std::path::{Path, PathBuf};
use tauri_plugin_dialog::DialogExt;

/// Имя файла длиннее — обрезаем (Windows держит 255 символов на имя, оставляем запас на расширение).
const MAX_NAME_CHARS: usize = 100;
/// Заголовок окна сохранения приходит из интерфейса — не даём прислать что угодно.
const MAX_TITLE_CHARS: usize = 200;
/// Больше этого текста плейлист не бывает (десятки тысяч треков в JSON — единицы МБ).
const MAX_CONTENTS_BYTES: usize = 64 * 1024 * 1024;
/// Имя, если от названия плейлиста ничего не осталось.
const FALLBACK_NAME: &str = "Sonar";
/// Знаки, которых не бывает в именах файлов Windows (и `/` на macOS).
const FORBIDDEN: [char; 9] = ['<', '>', ':', '"', '/', '\\', '|', '?', '*'];
/// Имена устройств Windows: файл «CON.m3u8» не создать.
const RESERVED: [&str; 22] = [
  "CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1",
  "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
];

/// Формат файла экспорта.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Format {
  M3u8,
  Csv,
  Json,
}

impl Format {
  pub fn parse(s: &str) -> Option<Self> {
    match s {
      "m3u8" => Some(Self::M3u8),
      "csv" => Some(Self::Csv),
      "json" => Some(Self::Json),
      _ => None,
    }
  }

  pub fn ext(self) -> &'static str {
    match self {
      Self::M3u8 => "m3u8",
      Self::Csv => "csv",
      Self::Json => "json",
    }
  }

  /// Подпись фильтра в окне сохранения — название формата, его не переводят.
  fn label(self) -> &'static str {
    match self {
      Self::M3u8 => "M3U8",
      Self::Csv => "CSV",
      Self::Json => "JSON",
    }
  }
}

/// Название плейлиста → безопасное имя файла без расширения (на ПК — только здесь; на iPhone то же
/// правило — `PlaylistExport.safeFileName`): запрещённые знаки и управляющие символы — пробел,
/// пробелы схлопываются, точки и пробелы по краям убираются, длина — до `MAX_NAME_CHARS`,
/// имя устройства Windows получает `_` в начале, пустое — `Sonar`.
pub fn sanitize_file_name(name: &str) -> String {
  let replaced: String = name
    .chars()
    .map(|c| if c.is_control() || FORBIDDEN.contains(&c) { ' ' } else { c })
    .collect();
  let collapsed = replaced.split_whitespace().collect::<Vec<_>>().join(" ");
  let cut: String = collapsed.chars().take(MAX_NAME_CHARS).collect();
  let trimmed = cut.trim_matches(|c: char| c == '.' || c.is_whitespace());
  if trimmed.is_empty() {
    return FALLBACK_NAME.to_string();
  }
  let stem = trimmed.split('.').next().unwrap_or(trimmed).trim();
  if RESERVED.iter().any(|r| r.eq_ignore_ascii_case(stem)) {
    return format!("_{trimmed}");
  }
  trimmed.to_string()
}

/// Окно сохранения на некоторых системах отдаёт путь без нужного расширения — дописываем.
/// Второе значение — `true`, если расширение дописано: такого пути пользователь в окне не подтверждал.
fn with_extension(path: PathBuf, format: Format) -> (PathBuf, bool) {
  let has_ext = path
    .extension()
    .and_then(|e| e.to_str())
    .is_some_and(|e| e.eq_ignore_ascii_case(format.ext()));
  if has_ext {
    return (path, false);
  }
  let mut name = path.file_name().map(|n| n.to_os_string()).unwrap_or_default();
  name.push(".");
  name.push(format.ext());
  (path.with_file_name(name), true)
}

/// Записать файл. `replace` — путь подтверждён в окне сохранения (оно само спросило про замену);
/// иначе (расширение дописали мы) чужой файл с тем же именем не трогаем: ошибка `AlreadyExists`.
fn write_export(path: &Path, contents: &[u8], replace: bool) -> std::io::Result<()> {
  let mut options = std::fs::OpenOptions::new();
  options.write(true);
  if replace {
    options.create(true).truncate(true);
  } else {
    options.create_new(true);
  }
  let mut file = options.open(path)?;
  file.write_all(contents)?;
  file.flush()
}

/// Спросить, куда сохранить, и записать готовый текст. `None` — пользователь закрыл окно,
/// иначе — имя сохранённого файла (для всплывашки «Сохранено»).
#[tauri::command]
pub async fn export_playlist(
  window: tauri::WebviewWindow,
  name: String,
  format: String,
  title: String,
  contents: String,
) -> Result<Option<String>, String> {
  let format = Format::parse(&format).ok_or("Неизвестный формат экспорта")?;
  if contents.len() > MAX_CONTENTS_BYTES {
    return Err("Плейлист слишком большой для экспорта".into());
  }
  let title: String = title.chars().take(MAX_TITLE_CHARS).collect();
  let file_name = format!("{}.{}", sanitize_file_name(&name), format.ext());

  let (tx, rx) = tokio::sync::oneshot::channel();
  window
    .dialog()
    .file()
    .set_parent(&window)
    .set_title(title)
    .set_file_name(file_name)
    .add_filter(format.label(), &[format.ext()])
    .save_file(move |picked| {
      let _ = tx.send(picked);
    });
  let Some(picked) = rx.await.map_err(|_| "Окно сохранения закрылось")? else {
    return Ok(None);
  };
  let path = picked.into_path().map_err(|_| "Не удалось сохранить файл")?;
  let (path, ext_added) = with_extension(path, format);
  let target = path.clone();
  let written = tokio::task::spawn_blocking(move || write_export(&target, contents.as_bytes(), !ext_added))
    .await
    .map_err(|_| "Не удалось сохранить файл")?;
  match written {
    Ok(()) => Ok(path.file_name().map(|n| n.to_string_lossy().into_owned())),
    Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => Err("Файл с таким именем уже есть".into()),
    Err(e) => {
      // путь в журнал не пишем: в нём имя пользователя системы
      log::warn!("экспорт плейлиста: запись не удалась ({:?})", e.kind());
      Err("Не удалось сохранить файл".into())
    }
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  #[test]
  fn format_parses_only_known_names() {
    assert_eq!(Format::parse("m3u8"), Some(Format::M3u8));
    assert_eq!(Format::parse("csv"), Some(Format::Csv));
    assert_eq!(Format::parse("json"), Some(Format::Json));
    assert_eq!(Format::parse("exe"), None);
    assert_eq!(Format::parse("CSV"), None);
    assert_eq!(Format::parse(""), None);
  }

  #[test]
  fn sanitize_keeps_ordinary_and_unicode_names() {
    assert_eq!(sanitize_file_name("Мой плейлист"), "Мой плейлист");
    assert_eq!(sanitize_file_name("Café ☕ 2024"), "Café ☕ 2024");
    assert_eq!(sanitize_file_name("日本の歌"), "日本の歌");
  }

  #[test]
  fn sanitize_replaces_forbidden_and_control_chars() {
    assert_eq!(sanitize_file_name("AC/DC: Best?"), "AC DC Best");
    assert_eq!(sanitize_file_name(r#"a<b>c"d\e|f*g"#), "a b c d e f g");
    assert_eq!(sanitize_file_name("line\nbreak\ttab\u{0}nul"), "line break tab nul");
  }

  #[test]
  fn sanitize_trims_dots_and_spaces() {
    assert_eq!(sanitize_file_name("  ..hidden.. "), "hidden");
    assert_eq!(sanitize_file_name("end."), "end");
  }

  #[test]
  fn sanitize_falls_back_when_empty() {
    assert_eq!(sanitize_file_name(""), "Sonar");
    assert_eq!(sanitize_file_name("???"), "Sonar");
    assert_eq!(sanitize_file_name(" . . "), "Sonar");
  }

  #[test]
  fn sanitize_guards_windows_device_names() {
    assert_eq!(sanitize_file_name("CON"), "_CON");
    assert_eq!(sanitize_file_name("nul"), "_nul");
    assert_eq!(sanitize_file_name("com1.backup"), "_com1.backup");
    assert_eq!(sanitize_file_name("Console"), "Console");
  }

  #[test]
  fn sanitize_limits_length_by_chars() {
    let long = "я".repeat(300);
    let out = sanitize_file_name(&long);
    assert_eq!(out.chars().count(), MAX_NAME_CHARS);
  }

  #[test]
  fn extension_is_added_only_when_missing() {
    let base = PathBuf::from("dir").join("list");
    assert_eq!(with_extension(base.clone(), Format::Csv), (PathBuf::from("dir").join("list.csv"), true));
    let done = PathBuf::from("dir").join("list.CSV");
    assert_eq!(with_extension(done.clone(), Format::Csv), (done, false));
    let other = PathBuf::from("dir").join("list.txt");
    assert_eq!(with_extension(other, Format::Json), (PathBuf::from("dir").join("list.txt.json"), true));
  }

  /// Своя пустая папка во временной — тесты не мешают друг другу.
  fn temp_dir(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("sonar-export-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
  }

  #[test]
  fn write_replaces_only_a_confirmed_path() {
    let dir = temp_dir("replace");
    let path = dir.join("list.csv");
    std::fs::write(&path, "old old old").unwrap();
    write_export(&path, b"new", true).unwrap();
    assert_eq!(std::fs::read(&path).unwrap(), b"new");
    std::fs::remove_dir_all(&dir).unwrap();
  }

  #[test]
  fn write_keeps_existing_file_when_extension_was_added() {
    let dir = temp_dir("keep");
    let path = dir.join("notes.txt.csv");
    std::fs::write(&path, "someone else").unwrap();
    let err = write_export(&path, b"new", false).unwrap_err();
    assert_eq!(err.kind(), std::io::ErrorKind::AlreadyExists);
    assert_eq!(std::fs::read(&path).unwrap(), b"someone else");
    let fresh = dir.join("fresh.csv");
    write_export(&fresh, b"new", false).unwrap();
    assert_eq!(std::fs::read(&fresh).unwrap(), b"new");
    std::fs::remove_dir_all(&dir).unwrap();
  }
}
