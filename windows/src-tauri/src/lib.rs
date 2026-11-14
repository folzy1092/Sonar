mod commands;
mod media;
mod providers;
mod secrets;
mod services;
mod store;
mod stream;

use commands::{Db, StreamPort};
use services::Core;
use std::sync::{Arc, Mutex};
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    // Только одно окно Sonar: повторный запуск сразу завершается, а уже открытое окно
    // разворачивается и выходит вперёд. Плагин должен стоять первым.
    .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
      if let Some(w) = app.get_webview_window("main") {
        let _ = w.unminimize();
        let _ = w.show();
        let _ = w.set_focus();
      }
    }))
    .setup(|app| {
      if cfg!(debug_assertions) {
        app.handle().plugin(
          tauri_plugin_log::Builder::default()
            .level(log::LevelFilter::Info)
            .build(),
        )?;
      }

      // Локальная база: %APPDATA%/com.folzy.sonar/sonar.db
      let dir = app.path().app_data_dir()?;
      std::fs::create_dir_all(&dir)?;
      let db = store::Store::open(&dir.join("sonar.db"))?;

      let core = Arc::new(Core::new());
      if let Ok(Some(q)) = db.setting("audio.quality") {
        let kbps = match q.as_str() {
          Some("low") => 192,
          Some("medium") => 256,
          _ => 320,
        };
        core.max_kbps.store(kbps, std::sync::atomic::Ordering::Relaxed);
      }
      let port = tauri::async_runtime::block_on(stream::start(core.clone()))?;

      let controls = app.get_webview_window("main").and_then(|w| media::attach(app.handle(), &w));

      app.manage(core);
      app.manage(Db(Mutex::new(db)));
      app.manage(StreamPort(port));
      app.manage(media::Media(Mutex::new(controls)));
      Ok(())
    })
    .invoke_handler(tauri::generate_handler![
      commands::services_status,
      commands::connect_soundcloud,
      commands::connect_yandex,
      commands::disconnect_service,
      commands::search,
      commands::stream_url,
      commands::cache_tracks,
      commands::save_player_state,
      commands::load_player_state,
      commands::record_play,
      commands::get_setting,
      commands::set_setting,
      commands::media_update,
    ])
    .run(tauri::generate_context!())
    .expect("error while building tauri application");
}
