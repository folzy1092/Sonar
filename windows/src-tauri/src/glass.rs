//! Прозрачность окна (Интерфейс → Вид → «Прозрачность»): системный эффект под окном — Mica на
//! Windows 11, Acrylic на Windows 10. Окно создано прозрачным (`tauri.conf.json` `transparent`), а
//! непрозрачность фона и карточек задаёт интерфейс (альфа цветов, theme.svelte.ts). Выключено —
//! эффекта нет, фон интерфейса непрозрачный, как раньше.

/// Включить / выключить эффект; вернёт, какой включился: `mica`, `acrylic` или `off`.
#[tauri::command]
pub fn set_glass(window: tauri::WebviewWindow, on: bool) -> Result<String, String> {
  #[cfg(windows)]
  {
    use tauri::window::{Effect, EffectsBuilder};
    if !on {
      window.set_effects(None).map_err(|e| e.to_string())?;
      return Ok("off".into());
    }
    let win11 = windows_version::OsVersion::current().build >= 22000;
    let effect = if win11 { Effect::Mica } else { Effect::Acrylic };
    window.set_effects(EffectsBuilder::new().effect(effect).build()).map_err(|e| e.to_string())?;
    Ok(if win11 { "mica" } else { "acrylic" }.into())
  }
  #[cfg(not(windows))]
  {
    let _ = (window, on);
    Ok("off".into())
  }
}
