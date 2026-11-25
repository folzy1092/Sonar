mod account;
mod app_icon;
mod artist_graph;
mod autostart;
mod blend;
mod commands;
mod crashlog;
mod cred_sync;
mod discord;
mod downloads;
mod dupes;
mod export;
mod login;
mod local;
mod lyrics;
mod media;
mod calls;
mod glass;
mod gvideo;
mod hotkeys;
mod import_link;
mod track_cache;
mod mini;
mod net;
mod offline;
mod offline_index;
mod monitors;
mod obs;
mod providers;
mod remote;
mod secrets;
mod services;
mod smart;
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

      // Last.fm убран (docs/LASTFM_EXIT.md): прежний вход из keyring стираем, чтобы не копить мусор
      secrets::forget_retired();

      // Локальная база: %APPDATA%/com.folzy.sonar/sonar.db
      let dir = app.path().app_data_dir()?;
      std::fs::create_dir_all(&dir)?;
      let db = store::Store::open(&dir.join("sonar.db"))?;
      // офлайн-режим — первым, до любой сетевой задачи (docs/OFFLINE.md §4.1)
      offline::set_on(offline::from_setting(db.setting(offline::KEY)));

      // тексты: неделя с прослушивания, у Любимых — две; в офлайне не чистим — нового текста не взять
      let pruned = if offline::is_on() { Ok(0) } else { db.prune_lyrics(store::now_ms()) };
      if let Ok(n) = pruned {
        if n > 0 {
          log::info!("[lyrics] удалено старых текстов: {n}");
        }
      }

      let core = Arc::new(Core::new());
      set_sc_hooks(&core, app.handle());
      // VK убран (2026-11-25): access_key его треков больше не нужны
      let _ = std::fs::remove_file(dir.join("vk-keys.json"));
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
        track_cache::set_pinned_dir(cache.join("pinned"));
        track_cache::set_blend_dir(cache.join("blend-tmp"));
      }
      let port = tauri::async_runtime::block_on(stream::start(core.clone()))?;

      // трей: крестик прячет окно или закрывает (`system.tray`)
      if let Ok(Some(v)) = db.setting("system.tray") {
        tray::HIDE_ON_CLOSE.store(v.as_bool().unwrap_or(true), std::sync::atomic::Ordering::Relaxed);
      }
      tray::setup(app)?;
      // значок приложения (`appearance.app_icon`): основной уже в exe, другой ставим сразу, до показа окна
      app_icon::apply_saved(app.handle(), db.setting(app_icon::KEY).ok().flatten().as_ref());
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
      // автозапуск: метка установщика → настройка, реестр → по настройке (один раз за запуск)
      let autostart_setting = db.setting(autostart::SETTING).ok().flatten().and_then(|v| v.as_bool());
      if let Some(on) = autostart::reconcile(autostart_setting) {
        let _ = db.set_setting(autostart::SETTING, &serde_json::json!(on));
      }
      if std::env::args().any(|a| a == autostart::ARG) {
        tray::START_HIDDEN.store(true, std::sync::atomic::Ordering::Relaxed);
        if let Some(w) = app.get_webview_window("main") {
          let _ = w.hide();
        }
      } else {
        // страховка: заставка не дала знать о первом кадре — всё равно показать окно
        let handle = app.handle().clone();
        std::thread::spawn(move || {
          std::thread::sleep(std::time::Duration::from_secs(3));
          tray::show_first(&handle);
        });
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
      // пульт с iPhone: сервер стартует, когда интерфейс включит `remote.enabled`
      app.manage(remote::Remote::new(app.handle().clone()));
      // папки с музыкой: индекс из базы, фоновый скан и слежка
      local::commands::init(app.handle());
      // офлайн-индекс: сверка кэша треков с базой и подписка на его изменения
      offline_index::init(app.handle());
      // синхронизация аккаунта: молчит, пока не подключён сервер Sonar
      tauri::async_runtime::spawn(sync::background(app.handle().clone()));
      // карта исполнителей: лайки сервисов и подписки SoundCloud — в фоне, пачками
      tauri::async_runtime::spawn(artist_graph::follows::background(app.handle().clone()));
      Ok(())
    })
    .invoke_handler(tauri::generate_handler![
      account::account_status,
      account::account_ping,
      account::account_login,
      account::account_register,
      account::account_logout,
      account::account_me,
      account::account_update,
      account::account_password,
      account::account_devices,
      account::account_report_device,
      account::account_sync,
      account::account_rename_device,
      account::account_revoke_device,
      account::account_tg_start,
      account::account_tg_poll,
      account::account_tg_unlink,
      account::account_link_create,
      account::account_link_poll,
      account::account_link_info,
      account::account_link_decide,
      blend::blend_source,
      blend::blend_release,
      blend::blend_get,
      blend::blend_put,
      blend::blend_rate,
      blend::blend_balance,
      downloads::download_tracks,
      downloads::downloads_state,
      downloads::downloaded_refs,
      downloads::downloads_pause,
      downloads::downloads_retry,
      downloads::downloads_cancel,
      downloads::downloads_remove,
      downloads::downloads_clear,
      downloads::downloads_reveal,
      downloads::disk_free,
      glass::set_glass,
      hotkeys::set_hotkeys,
      remote::remote_set_enabled,
      remote::remote_status,
      remote::remote_pair_start,
      remote::remote_pair_cancel,
      remote::remote_unpair,
      remote::remote_state,
      export::export_playlist,
      export::save_image,
      commands::prefetch_tracks,
      commands::set_track_cache,
      commands::add_search_history,
      commands::search_history,
      commands::search_history_count,
      commands::clear_search_history,
      commands::services_status,
      commands::services_fill_links,
      commands::check_services,
      commands::services_list,
      commands::sync_now,
      commands::artist_tracks,
      commands::artist_reposts,
      commands::mini_window,
      commands::overlay_window,
      commands::list_monitors,
      commands::thumbbar_init,
      commands::thumbbar_state,
      commands::show_main,
      commands::obs_new_token,
      commands::cancel_login,
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
      commands::share_twins,
      commands::cache_tracks,
      commands::save_player_state,
      commands::load_player_state,
      commands::record_play,
      commands::get_setting,
      commands::set_setting,
      commands::offline_state,
      commands::offline_refs,
      commands::offline_tracks,
      commands::offline_blocked,
      commands::offline_mix_signals,
      commands::media_update,
      commands::search_more,
      commands::artist_page,
      commands::album_page,
      commands::service_playlists,
      commands::service_playlist,
      commands::import_playlist,
      import_link::import_link,
      import_link::import_cancel,
      import_link::import_create,
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
      smart::smart_playlists,
      smart::smart_playlist,
      smart::smart_preview,
      smart::create_smart_playlist,
      smart::update_smart_playlist,
      smart::delete_smart_playlist,
      artist_graph::artist_graph,
      artist_graph::artist_neighbors,
      artist_graph::artist_cluster_tracks,
      artist_graph::follows::artist_graph_refresh,
      commands::lyrics,
      commands::lyrics_offset,
      commands::lyrics_annotations,
      commands::lyrics_translate,
      commands::set_lyrics_offset,
      commands::track_sound,
      commands::set_track_sound,
      commands::track_sound_refs,
      commands::track_sources,
      commands::set_track_source,
      commands::wave_portion,
      commands::wave_feedback,
      commands::wave_stats,
      commands::disliked_refs,
      commands::similar_tracks,
      commands::recent_tracks,
      commands::home_releases,
      commands::release_feed,
      commands::daypart_mix,
      commands::stats,
      commands::recap,
      commands::recap_periods,
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
      commands::first_paint,
      commands::autostart_enabled,
      commands::set_tray_mode,
      local::commands::local_pick_folder,
      local::commands::local_rescan,
      local::commands::local_tracks,
      local::commands::local_search,
      dupes::commands::find_duplicates,
      dupes::commands::remove_duplicates,
      dupes::commands::restore_duplicates,
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

/// Починка входа SoundCloud (services/sc_repair.rs): тихий вход — скрытое окно, плашка «Войди
/// заново» — событие `soundcloud:relogin` в главное окно.
fn set_sc_hooks(core: &Core, app: &tauri::AppHandle) {
  let relogin_app = app.clone();
  let notice_app = app.clone();
  let _ = core.sc_hooks.set(services::ScHooks {
    relogin: Box::new(move |old| Box::pin(login::soundcloud_silent(relogin_app.clone(), old))),
    notice: Box::new(move || {
      let _ = tauri::Emitter::emit(&notice_app, "soundcloud:relogin", ());
    }),
  });
}
