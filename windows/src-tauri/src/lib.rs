mod commands;
mod discord;
mod lyrics;
mod media;
mod providers;
mod secrets;
mod services;
mod store;
mod stream;
mod tray;
mod wave;
mod zoom;

use commands::{Db, StreamPort};
use services::Core;
use std::sync::{Arc, Mutex};
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
  tauri::Builder::default()
    // Только одно окно Sonar: повторный запуск сразу завершается, а уже открытое окно
    // разворачивается и выходит вперёд. Плагин должен стоять первым.
    .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| tray::show_main(app)))
    // автозапуск с Windows; `--autostart` — стартовать сразу в трее, без окна
    .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, Some(vec!["--autostart"])))
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

      // тексты: неделя с прослушивания, у Любимых — две
      if let Ok(n) = db.prune_lyrics(store::now_ms()) {
        if n > 0 {
          log::info!("[lyrics] удалено старых текстов: {n}");
        }
      }

      let core = Arc::new(Core::new());
      if let Ok(Some(v)) = db.setting("audio.sc_via_yandex") {
        core.sc_via_yandex.store(v.as_bool().unwrap_or(true), std::sync::atomic::Ordering::Relaxed);
      }
      if let Ok(Some(q)) = db.setting("audio.quality") {
        core.max_kbps.store(services::quality_kbps(q.as_str()), std::sync::atomic::Ordering::Relaxed);
      }
      if let Ok(cache) = app.path().app_cache_dir() {
        stream::set_cover_dir(cache.join("covers"));
      }
      let port = tauri::async_runtime::block_on(stream::start(core.clone()))?;

      // трей: крестик прячет окно или закрывает (`system.tray`)
      if let Ok(Some(v)) = db.setting("system.tray") {
        tray::HIDE_ON_CLOSE.store(v.as_bool().unwrap_or(true), std::sync::atomic::Ordering::Relaxed);
      }
      tray::setup(app)?;
      if std::env::args().any(|a| a == "--autostart") {
        if let Some(w) = app.get_webview_window("main") {
          let _ = w.hide();
        }
      }

      // Discord RPC
      let flag = |k: &str| db.setting(k).ok().flatten().and_then(|v| v.as_bool()).unwrap_or(true);
      let rpc = discord::Discord::start();
      rpc.enabled.store(flag("integrations.discord.enabled"), std::sync::atomic::Ordering::Relaxed);
      rpc.cover.store(flag("integrations.discord.cover"), std::sync::atomic::Ordering::Relaxed);
      rpc.progress.store(flag("integrations.discord.progress"), std::sync::atomic::Ordering::Relaxed);
      app.manage(rpc);

      // масштаб в окне и на весь экран — сразу, без «прыжка» после загрузки
      let pct = |k: &str| db.setting(k).ok().flatten().and_then(|v| v.as_f64());
      zoom::setup(app, pct("appearance.scale_window"), pct("appearance.scale_fullscreen"));

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
      commands::search_more,
      commands::artist_page,
      commands::album_page,
      commands::service_playlists,
      commands::service_playlist,
      commands::import_playlist,
      commands::set_like,
      commands::liked_refs,
      commands::favorites,
      commands::liked_catalog,
      commands::playlists,
      commands::playlist,
      commands::create_playlist,
      commands::update_playlist,
      commands::delete_playlist,
      commands::add_to_playlist,
      commands::remove_from_playlist,
      commands::reorder_playlist,
      commands::lyrics,
      commands::lyrics_offset,
      commands::set_lyrics_offset,
      commands::track_eq,
      commands::set_track_eq,
      commands::wave_portion,
      commands::wave_feedback,
      commands::disliked_refs,
      commands::similar_tracks,
      commands::recent_tracks,
      commands::home_releases,
      commands::stats,
      commands::cached_tracks,
      commands::stream_port,
      commands::all_settings,
      commands::reset_settings,
      commands::storage_usage,
      commands::clear_storage,
      commands::open_url,
      commands::set_zoom,
      commands::set_autostart,
      commands::autostart_enabled,
      commands::set_tray_mode,
    ])
    .run(tauri::generate_context!())
    .expect("error while building tauri application");
}
