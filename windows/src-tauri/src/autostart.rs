//! Автозапуск вместе с Windows (`system.autostart`, docs/POLISH_PROMPT.md п. 4).
//!
//! Запись `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\Sonar` = `"<папка установки>\Sonar.exe" --autostart`
//! (путь в кавычках: в «Program Files» есть пробел). При запуске `reconcile` один раз приводит реестр к
//! настройке — раньше запись появлялась только после щелчка по тумблеру, и после чистой установки
//! автозапуск «включён», а записи нет. Галочка установщика («Ярлыки» → «Запускать вместе с Windows»)
//! пишет метку `HKCU\Software\Folzy\Sonar\Autostart`; при запуске она переезжает в настройку.

use std::path::{Path, PathBuf};

/// Аргумент запуска «сразу в трей, без окна» (`lib.rs`, `tray.rs`).
pub const ARG: &str = "--autostart";
/// Ключ настройки.
pub const SETTING: &str = "system.autostart";
/// Имя значения в `…\Run` — как у установщика и деинсталлятора (`installer.nsi`).
#[cfg_attr(not(windows), allow(dead_code))]
pub const RUN_VALUE: &str = "Sonar";

/// Что сейчас в реестре.
#[cfg_attr(not(windows), allow(dead_code))]
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Registry {
  Missing,
  /// `approved = false` — пользователь выключил Sonar в «Диспетчер задач → Автозагрузка».
  Registered { command: String, approved: bool },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
  Nothing,
  /// Записать (или переписать) значение `Run`.
  Enable,
  /// Удалить значение `Run`.
  Disable,
  /// Запись есть, но выключена в Диспетчере задач — выбор пользователя важнее: настройку — в «выкл».
  AdoptOff,
}

/// Команда для `Run`: exe в кавычках и `--autostart`.
pub fn command_for(exe: &Path) -> String {
  format!("\"{}\" {ARG}", exe.display())
}

/// Что сделать, чтобы реестр совпал с настройкой.
pub fn decide(want: bool, reg: &Registry, expected: &str) -> Action {
  match (want, reg) {
    (true, Registry::Missing) => Action::Enable,
    (true, Registry::Registered { approved: false, .. }) => Action::AdoptOff,
    (true, Registry::Registered { command, .. }) if !command.trim().eq_ignore_ascii_case(expected) => Action::Enable,
    (false, Registry::Registered { .. }) => Action::Disable,
    _ => Action::Nothing,
  }
}

/// exe, на который ведёт запись: из папки установки, если она известна, иначе — текущий.
pub fn target_exe(installed_dir: Option<&Path>, current: &Path) -> PathBuf {
  match (installed_dir, current.file_name()) {
    (Some(dir), Some(name)) => dir.join(name),
    _ => current.to_path_buf(),
  }
}

/// Сверять при запуске только установленный Sonar: проверочная сборка (`target-check`) или отладка
/// не должны переписать автозапуск на себя.
pub fn is_installed_copy(installed_dir: Option<&Path>, current: &Path) -> bool {
  let (Some(dir), Some(parent)) = (installed_dir, current.parent()) else { return false };
  let norm = |p: &Path| p.to_string_lossy().trim_end_matches(['\\', '/']).to_lowercase();
  norm(dir) == norm(parent)
}

/// Значение для тумблера: запись есть и не выключена в Диспетчере задач.
pub fn is_on(reg: &Registry) -> bool {
  matches!(reg, Registry::Registered { approved: true, .. })
}

/// Включить или выключить автозапуск (тумблер в настройках).
pub fn set(on: bool) -> anyhow::Result<()> {
  if !on {
    return sys::remove();
  }
  let current = std::env::current_exe()?;
  sys::write(&command_for(&target_exe(sys::installed_dir().as_deref(), &current)))
}

pub fn enabled() -> anyhow::Result<bool> {
  Ok(is_on(&sys::read()?))
}

/// Один раз при запуске: метка установщика → настройка, затем реестр → по настройке.
/// Возвращает новое значение настройки, если его надо сохранить.
pub fn reconcile(setting: Option<bool>) -> Option<bool> {
  let from_installer = sys::take_installer_choice();
  let want = from_installer.or(setting).unwrap_or(true);
  let Ok(current) = std::env::current_exe() else { return from_installer };
  let installed = sys::installed_dir();
  if cfg!(debug_assertions) || !is_installed_copy(installed.as_deref(), &current) {
    return from_installer;
  }
  let reg = match sys::read() {
    Ok(r) => r,
    Err(e) => {
      log::warn!("[autostart] реестр не прочитан: {e}");
      return from_installer;
    }
  };
  let expected = command_for(&target_exe(installed.as_deref(), &current));
  let action = decide(want, &reg, &expected);
  let res = match action {
    Action::Nothing => return from_installer,
    Action::AdoptOff => return Some(false),
    Action::Enable => sys::write(&expected),
    Action::Disable => sys::remove(),
  };
  match res {
    Ok(()) => log::info!("[autostart] сверка: {action:?}"),
    Err(e) => log::warn!("[autostart] {action:?} не удалось: {e}"),
  }
  from_installer
}

#[cfg(windows)]
mod sys {
  use super::{Registry, RUN_VALUE};
  use std::path::PathBuf;
  use windows_registry::{CURRENT_USER, LOCAL_MACHINE};

  const RUN: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
  const APPROVED: &str = r"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
  const PRODUCT: &str = r"Software\Folzy\Sonar";
  const MARKER: &str = "Autostart";
  /// «Включено» в StartupApproved: первый байт 2, остальные нули (так пишет Диспетчер задач).
  const APPROVED_ON: [u8; 12] = [2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

  pub fn read() -> anyhow::Result<Registry> {
    let Ok(key) = CURRENT_USER.open(RUN) else { return Ok(Registry::Missing) };
    let Ok(command) = key.get_string(RUN_VALUE) else { return Ok(Registry::Missing) };
    // Диспетчер задач выключает запись нечётным первым байтом (3); нет значения — «вкл»
    let approved = CURRENT_USER
      .open(APPROVED)
      .and_then(|k| k.get_value(RUN_VALUE))
      .map(|v| v.first().map_or(true, |b| b % 2 == 0))
      .unwrap_or(true);
    Ok(Registry::Registered { command, approved })
  }

  pub fn write(command: &str) -> anyhow::Result<()> {
    CURRENT_USER.create(RUN)?.set_string(RUN_VALUE, command)?;
    // включение из Sonar снимает и запрет из Диспетчера задач — иначе тумблер «вкл», а запуска нет
    if let Ok(k) = CURRENT_USER.create(APPROVED) {
      let _ = k.set_bytes(RUN_VALUE, windows_registry::Type::Bytes, &APPROVED_ON);
    }
    Ok(())
  }

  pub fn remove() -> anyhow::Result<()> {
    if let Ok(k) = CURRENT_USER.open(RUN) {
      if k.get_string(RUN_VALUE).is_ok() {
        k.remove_value(RUN_VALUE)?;
      }
    }
    Ok(())
  }

  /// Папка установки — её пишет установщик (`SHCTX\Software\Folzy\Sonar`, значение по умолчанию).
  pub fn installed_dir() -> Option<PathBuf> {
    [CURRENT_USER, LOCAL_MACHINE]
      .into_iter()
      .find_map(|root| root.open(PRODUCT).and_then(|k| k.get_string("")).ok())
      .map(|s| PathBuf::from(s.trim_matches('"')))
      .filter(|p| !p.as_os_str().is_empty())
  }

  /// Галочка установщика: прочитать и стереть метку (одна установка — одно решение).
  pub fn take_installer_choice() -> Option<bool> {
    let key = CURRENT_USER.open(PRODUCT).ok()?;
    let v = key.get_u32(MARKER).ok()?;
    if let Ok(w) = CURRENT_USER.create(PRODUCT) {
      let _ = w.remove_value(MARKER);
    }
    Some(v != 0)
  }
}

/// Не Windows (тесты на Mac/Linux): реестра нет.
#[cfg(not(windows))]
mod sys {
  use super::Registry;
  use std::path::PathBuf;

  pub fn read() -> anyhow::Result<Registry> {
    Ok(Registry::Missing)
  }
  pub fn write(_command: &str) -> anyhow::Result<()> {
    anyhow::bail!("автозапуск есть только в Windows")
  }
  pub fn remove() -> anyhow::Result<()> {
    Ok(())
  }
  pub fn installed_dir() -> Option<PathBuf> {
    None
  }
  pub fn take_installer_choice() -> Option<bool> {
    None
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  const EXE: &str = r#""C:\Program Files\Sonar\Sonar.exe" --autostart"#;

  fn reg(command: &str, approved: bool) -> Registry {
    Registry::Registered { command: command.into(), approved }
  }

  #[test]
  fn fresh_install_with_setting_on_writes_registry() {
    assert_eq!(decide(true, &Registry::Missing, EXE), Action::Enable);
  }

  #[test]
  fn setting_off_removes_entry() {
    assert_eq!(decide(false, &reg(EXE, true), EXE), Action::Disable);
    assert_eq!(decide(false, &Registry::Missing, EXE), Action::Nothing);
  }

  #[test]
  fn stale_or_unquoted_path_is_rewritten() {
    // так писал прежний плагин: путь без кавычек
    assert_eq!(decide(true, &reg(r"C:\Program Files\Sonar\Sonar.exe --autostart", true), EXE), Action::Enable);
    assert_eq!(decide(true, &reg(r#""D:\old\Sonar.exe" --autostart"#, true), EXE), Action::Enable);
    // тот же путь другим регистром — не трогаем
    assert_eq!(decide(true, &reg(&EXE.to_uppercase(), true), EXE), Action::Nothing);
  }

  #[test]
  fn task_manager_disable_wins_over_setting() {
    assert_eq!(decide(true, &reg(EXE, false), EXE), Action::AdoptOff);
    assert!(!is_on(&reg(EXE, false)));
    assert!(is_on(&reg(EXE, true)));
  }

  #[test]
  fn command_is_quoted_with_flag() {
    let p = Path::new(r"C:\Program Files\Sonar\Sonar.exe");
    assert_eq!(command_for(p), format!("\"{}\" --autostart", p.display()));
  }

  #[test]
  fn target_prefers_install_folder() {
    let cur = Path::new("/build/target-check/release/Sonar.exe");
    let dir = Path::new("/apps/Sonar");
    assert_eq!(target_exe(Some(dir), cur), dir.join("Sonar.exe"));
    assert_eq!(target_exe(None, cur), cur.to_path_buf());
  }

  #[test]
  fn only_installed_copy_reconciles() {
    let dir = Path::new("/apps/Sonar");
    assert!(is_installed_copy(Some(dir), Path::new("/apps/Sonar/Sonar.exe")));
    assert!(is_installed_copy(Some(Path::new("/Apps/sonar/")), Path::new("/apps/Sonar/Sonar.exe")));
    assert!(!is_installed_copy(Some(dir), Path::new("/build/target-check/release/Sonar.exe")));
    assert!(!is_installed_copy(None, Path::new("/apps/Sonar/Sonar.exe")));
  }
}
