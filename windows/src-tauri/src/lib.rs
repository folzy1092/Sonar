mod commands;
mod crashlog;
mod discord;
mod export;
mod lastfm;
mod login;
mod local;
mod lyrics;
mod media;
mod calls;
mod glass;
mod gvideo;
mod hotkeys;
mod track_cache;
mod mini;
mod obs;
mod providers;
mod secrets;
mod services;
#[cfg(feature = "spotify-playback")]
mod spotify_play;
mod store;
mod stream;
mod sync;
#[cfg(windows)]
mod thumbbar;
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
    // автообновление из GitHub Releases (ROADMAP W6): проверка и установка — из интерфейса
    .plugin(tauri_plugin_updater::Builder::new().build())
    .plugin(tauri_plugin_process::init())
    // горячие клавиши по всей системе (hotkeys.rs); сочетания ставит интерфейс через `set_hotkeys`
    .plugin(hotkeys::plugin())
    // окно «Сохранить как» для экспорта плейлистов (export.rs) и выбор папки для «Папок с музыкой»
    // (local/commands.rs); из интерфейса его не открыть
    .plugin(tauri_plugin_dialog::init())
    // обложки локальных файлов: адрес не зависит от порта аудио-сервера, отдаются только
    // `local-<sha1>.<ext>` из кэша обложек
    .register_uri_scheme_protocol(local::COVER_SCHEME, |_ctx, req| local_cover_response(req.uri().path()))
    .setup(|app| {
      // журнал ошибок сессии и отчёт после сбоя (в отладке логгер ставит tauri-plugin-log)
      if let Ok(dir) = app.path().app_log_dir() {
        crashlog::init(&dir, !cfg!(debug_assertions));
      }
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
      // access_key треков VK: без него чужой трек VK после перезапуска не играет
      core.open_vk_keys(dir.join("vk-keys.json"));
      if let Ok(Some(v)) = db.setting("audio.sc_via_yandex") {
        core.sc_via_yandex.store(v.as_bool().unwrap_or(false), std::sync::atomic::Ordering::Relaxed);
      }
      if let Ok(Some(v)) = db.setting("audio.fallback") {
        core.fallback.enabled.store(v.as_bool().unwrap_or(true), std::sync::atomic::Ordering::Relaxed);
      }
      if let Ok(order) = db.setting("audio.fallback_order") {
        core.fallback.set_order(services::fallback::parse_order(order.as_ref()));
      }
      if let Ok(Some(q)) = db.setting("audio.quality") {
        core.max_kbps.store(services::quality_kbps(q.as_str()), std::sync::atomic::Ordering::Relaxed);
      }
      if let Ok(Some(q)) = db.setting("audio.yt_quality") {
        core.yt_high.store(services::yt_high(q.as_str()), std::sync::atomic::Ordering::Relaxed);
      }
      if let Ok(cache) = app.path().app_cache_dir() {
        stream::set_cover_dir(cache.join("covers"));
        track_cache::set_dir(cache.join("tracks"));
      }
      let port = tauri::async_runtime::block_on(stream::start(core.clone()))?;

      // трей: крестик прячет окно или закрывает (`system.tray`)
      if let Ok(Some(v)) = db.setting("system.tray") {
        tray::HIDE_ON_CLOSE.store(v.as_bool().unwrap_or(true), std::sync::atomic::Ordering::Relaxed);
      }
      tray::setup(app)?;
      // Windows 10: у окна без рамки тень рисует белую рамку в 1 px по краю — там тень выключаем
      // (на Windows 11 вместо неё скруглённые углы, тень остаётся)
      #[cfg(windows)]
      if windows_version::OsVersion::current().build < 22000 {
        if let Some(w) = app.get_webview_window("main") {
          let _ = w.set_shadow(false);
        }
      }
      // «Тише во время звонков»: следим, занят ли микрофон другим приложением
      calls::start(app.handle().clone());
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
      rpc.artist_photo.store(flag("integrations.discord.artist_photo"), std::sync::atomic::Ordering::Relaxed);
      rpc.button_listen.store(flag("integrations.discord.button_listen"), std::sync::atomic::Ordering::Relaxed);
      rpc.button_download.store(flag("integrations.discord.button_download"), std::sync::atomic::Ordering::Relaxed);
      let off = |k: &str| db.setting(k).ok().flatten().and_then(|v| v.as_bool()).unwrap_or(false);
      rpc.show_paused.store(off("integrations.discord.show_paused"), std::sync::atomic::Ordering::Relaxed);
      if let Some(f) = db.setting("integrations.discord.status_format").ok().flatten() {
        let i = discord::FORMATS.iter().position(|x| Some(*x) == f.as_str()).unwrap_or(0);
        rpc.format.store(i as u8, std::sync::atomic::Ordering::Relaxed);
      }
      app.manage(rpc);

      // плашка для OBS на постоянном адресе 127.0.0.1:53119/obs
      // токен плашки OBS: создаётся один раз и хранится в настройках устройства
      let obs_token = match db.setting("obs.token").ok().flatten().and_then(|v| v.as_str().map(str::to_owned)) {
        Some(t) => t,
        None => {
          let t = obs::new_token();
          let _ = db.set_setting("obs.token", &serde_json::json!(t));
          t
        }
      };
      let obs = obs::Obs::new(
        db.setting("obs.size").ok().flatten().and_then(|v| v.as_str().map(str::to_owned)),
        flag("obs.hide_paused"),
        obs_token,
      );
      tauri::async_runtime::spawn(obs::start(obs.clone()));
      app.manage(obs);

      // масштаб в окне и на весь экран — сразу, без «прыжка» после загрузки
      let pct = |k: &str| db.setting(k).ok().flatten().and_then(|v| v.as_f64());
      zoom::setup(app, pct("appearance.scale_window"), pct("appearance.scale_fullscreen"));

      let controls = app.get_webview_window("main").and_then(|w| media::attach(app.handle(), &w));

      app.manage(core);
      app.manage(Db(Mutex::new(db)));
      app.manage(StreamPort(port));
      app.manage(media::Media(Mutex::new(controls)));
      // папки с музыкой: индекс из базы, фоновый скан и слежка
      local::commands::init(app.handle());
      // синхронизация аккаунта: молчит, пока не подключён сервер Sonar
      tauri::async_runtime::spawn(sync::background(app.handle().clone()));
      Ok(())
    })
    .invoke_handler(tauri::generate_handler![
      glass::set_glass,
      hotkeys::set_hotkeys,
      export::export_playlist,
      commands::prefetch_tracks,
      commands::set_track_cache,
      commands::add_search_history,
      commands::search_history,
      commands::search_history_count,
      commands::clear_search_history,
      commands::services_status,
      commands::services_list,
      commands::sync_now,
      commands::artist_tracks,
      commands::mini_window,
      commands::thumbbar_init,
      commands::thumbbar_state,
      commands::show_main,
      commands::obs_new_token,
      commands::lastfm_status,
      commands::lastfm_login,
      commands::cancel_login,
      commands::lastfm_logout,
      commands::discord_status,
      commands::resolve_link,
      commands::report_pending,
      commands::report_send,
      commands::report_dismiss,
      commands::log_frontend,
      commands::connect_soundcloud,
      commands::connect_yandex,
      commands::connect_service_key,
      commands::obs_status,
      commands::login_service,
      commands::disconnect_service,
      commands::search,
      commands::stream_url,
      commands::stream_fallback,
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
      commands::clear_favorites,
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
      commands::lyrics_annotations,
      commands::lyrics_translate,
      commands::set_lyrics_offset,
      commands::track_eq,
      commands::set_track_eq,
      commands::wave_portion,
      commands::wave_feedback,
      commands::wave_stats,
      commands::disliked_refs,
      commands::similar_tracks,
      commands::recent_tracks,
      commands::home_releases,
      commands::daypart_mix,
      commands::stats,
      commands::cached_tracks,
      commands::stream_port,
      commands::all_settings,
      commands::reset_settings,
      commands::storage_usage,
      commands::clear_storage,
      commands::open_url,
      commands::add_to_start_menu,
      commands::reveal_start_shortcut,
      commands::set_zoom,
      commands::set_autostart,
      commands::autostart_enabled,
      commands::set_tray_mode,
      local::commands::local_pick_folder,
      local::commands::local_rescan,
      local::commands::local_tracks,
      local::commands::local_search,
    ])
    .run(tauri::generate_context!())
    .expect("error while building tauri application");
}

/// Ответ схемы `sonarcover`: обложка из кэша или 404.
fn local_cover_response(path: &str) -> tauri::http::Response<Vec<u8>> {
  let found = stream::cover_dir().and_then(|d| local::read_cover(d, path.trim_start_matches('/')));
  let builder = tauri::http::Response::builder().header("Access-Control-Allow-Origin", "*");
  let res = match found {
    Some((bytes, mime)) => builder.header("Content-Type", mime).header("Cache-Control", "max-age=604800").body(bytes),
    None => builder.status(404).body(Vec::new()),
  };
  res.unwrap_or_else(|_| tauri::http::Response::new(Vec::new()))
}
