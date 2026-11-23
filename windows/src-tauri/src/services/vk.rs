//! VK Музыка за общим видом сервиса: `vk`/`vka`/`vkalb`/`vkpl`.
//! Ссылку на поток VK отдаёт вместе с треком — ядро держит её в памяти (`Core::vk_seen`) до
//! `STREAM_TTL`, чтобы не спрашивать VK второй раз. access_key трека — на диске (`vk_keys.rs`):
//! с ним `audio.getById` отдаёт трек и после перезапуска.

use super::provider::Provider;
use super::{Core, PlaylistPage, Stored, STREAM_TTL};
use crate::providers::registry::ServiceId;
use crate::providers::vk::{self, VkAudio};
use crate::providers::{Album, AlbumPage, ArtistPage, ArtistTrack, SearchResults, ServicePlaylist, Source, Track};
use anyhow::{anyhow, Result};
use std::path::PathBuf;
use std::time::Instant;

/// Все треки исполнителя для вкладки «Треки» (VK отдаёт по 200, каждый запрос — 350 мс).
const MAX: usize = 600;
/// Треки альбома или плейлиста.
const MAX_LIST: usize = 1000;
/// «Моя музыка» как плейлист.
const MAX_LIKES: usize = 2000;
/// Популярное на странице исполнителя.
const TOP: usize = 10;
/// Сколько ссылок на поток держать в памяти; сверх — выкидываем протухшие.
const SEEN_MAX: usize = 5000;
const NOT_CONNECTED: &str = "VK Музыка не подключена — открой Настройки → Сервисы";
const NOT_CONNECTED_SHORT: &str = "VK Музыка не подключена";
const LIKES_TITLE: &str = "Моя музыка";

pub struct VkProvider<'a> {
  pub(super) core: &'a Core,
}

impl Core {
  async fn vk_creds(&self) -> Result<Stored<vk::Creds>> {
    self.vk.read().await.clone().ok_or_else(|| anyhow!(NOT_CONNECTED))
  }

  /// access_key треков VK — с диска (`<папка данных>/vk-keys.json`), при запуске приложения.
  pub fn open_vk_keys(&self, file: PathBuf) {
    *self.vk_keys.lock().unwrap() = super::vk_keys::VkKeys::open(file);
  }

  /// Треки VK → модели; ссылку запоминаем в памяти, access_key — на диске.
  pub(super) fn vk_keep(&self, list: Vec<VkAudio>) -> Vec<Track> {
    let now = Instant::now();
    {
      let mut seen = self.vk_seen.lock().unwrap();
      if seen.len() > SEEN_MAX {
        seen.retain(|_, (_, at)| at.elapsed() < STREAM_TTL);
      }
      for a in &list {
        if let Some(url) = &a.stream_url {
          seen.insert(a.track.ref_.clone(), (url.clone(), now));
        }
      }
    }
    let keys = list.iter().filter_map(|a| Some((a.track.ref_.clone(), a.access_key.clone()?)));
    self.vk_keys.lock().unwrap().remember(keys);
    list.into_iter().map(|a| a.track).collect()
  }

  /// Ссылка, которую VK отдал вместе с треком, пока она не протухла.
  fn vk_seen_url(&self, track_ref: &str) -> Option<String> {
    let seen = self.vk_seen.lock().unwrap();
    seen.get(track_ref).filter(|(_, at)| at.elapsed() < STREAM_TTL).map(|(url, _)| url.clone())
  }

  /// id для `audio.getById`: `owner_id_id` и запомненный access_key, если он есть.
  pub(super) fn vk_full_id(&self, id: &str) -> String {
    match self.vk_keys.lock().unwrap().get(&format!("vk:{id}")) {
      Some(k) => format!("{id}_{k}"),
      None => id.to_owned(),
    }
  }

  /// id своего аккаунта VK: из сохранённого, иначе спросить у VK.
  async fn vk_uid(&self) -> Result<Option<(vk::Creds, String)>> {
    let Some(s) = self.vk.read().await.clone() else { return Ok(None) };
    let uid = match s.account.uid.clone() {
      Some(u) => u,
      None => vk::Vk { http: &self.http(), creds: &s.creds }
        .account()
        .await?
        .uid
        .ok_or_else(|| anyhow!("VK Музыка: не узнал id аккаунта"))?,
    };
    Ok(Some((s.creds, uid)))
  }

  fn vk_owner_name(&self, s: &Option<Stored<vk::Creds>>) -> String {
    s.as_ref().and_then(|s| s.account.name.clone()).unwrap_or_default()
  }
}

impl Provider for VkProvider<'_> {
  fn id(&self) -> ServiceId {
    ServiceId::Vk
  }

  async fn search(&self, q: &str, limit: u32) -> Result<Vec<Track>> {
    let s = self.core.vk_creds().await?;
    let found = vk::Vk { http: &self.core.http(), creds: &s.creds }.search(q, limit).await?;
    Ok(self.core.vk_keep(found))
  }

  async fn search_more(&self, q: &str, limit: u32) -> Result<SearchResults> {
    let s = self.core.vk_creds().await?;
    let (artists, albums, playlists) = vk::Vk { http: &self.core.http(), creds: &s.creds }.search_more(q, limit).await?;
    Ok(SearchResults { tracks: vec![], artists, albums, playlists })
  }

  async fn artist_page(&self, id: &str) -> Result<ArtistPage> {
    let s = self.core.vk_creds().await?;
    let v = vk::Vk { http: &self.core.http(), creds: &s.creds };
    let artist = v.artist(id).await?;
    let top = v.artist_tracks(id, TOP).await?;
    let albums = v.artist_albums(id, 50).await?;
    Ok(ArtistPage { artist, top: self.core.vk_keep(top), albums })
  }

  async fn artist_tracks(&self, id: &str) -> Result<Vec<ArtistTrack>> {
    let s = self.core.vk_creds().await?;
    let list = vk::Vk { http: &self.core.http(), creds: &s.creds }.artist_tracks(id, MAX).await?;
    Ok(self.core.vk_keep(list).into_iter().map(|track| ArtistTrack { track, likes: None, released: None }).collect())
  }

  async fn artist_top(&self, id: &str, limit: u32) -> Result<Vec<Track>> {
    let s = self.core.vk_creds().await?;
    let list = vk::Vk { http: &self.core.http(), creds: &s.creds }.artist_tracks(id, limit as usize).await?;
    Ok(self.core.vk_keep(list))
  }

  async fn artist_albums(&self, id: &str) -> Result<Vec<Album>> {
    let s = self.core.vk_creds().await?;
    vk::Vk { http: &self.core.http(), creds: &s.creds }.artist_albums(id, 100).await
  }

  async fn album_page(&self, id: &str) -> Result<AlbumPage> {
    let s = self.core.vk_creds().await?;
    let (head, list) = vk::Vk { http: &self.core.http(), creds: &s.creds }.playlist(id, MAX_LIST).await?;
    let album = vk::album_from_json(&head).ok_or_else(|| anyhow!("VK Музыка: альбом не найден"))?;
    Ok(AlbumPage { album, tracks: self.core.vk_keep(list) })
  }

  async fn similar(&self, id: &str, limit: u32) -> Result<Vec<Track>> {
    let s = self.core.vk_creds().await?;
    let list = vk::Vk { http: &self.core.http(), creds: &s.creds }.similar(id, limit).await?;
    Ok(self.core.vk_keep(list))
  }

  /// Ссылка из поиска, пока она свежая; иначе (`fresh`, протухла или не видели) — `audio.getById`
  /// с access_key с диска.
  async fn stream(&self, id: &str, fresh: bool) -> Result<Source> {
    if !vk::is_audio_id(id) {
      return Err(anyhow!("плохой ref vk:{id}"));
    }
    if let Some(url) = (!fresh).then(|| self.core.vk_seen_url(&format!("vk:{id}"))).flatten() {
      return vk::source_from_url(&url);
    }
    let s = self.core.vk.read().await.clone().ok_or_else(|| anyhow!(NOT_CONNECTED_SHORT))?;
    let full = self.core.vk_full_id(id);
    let found = vk::Vk { http: &self.core.http(), creds: &s.creds }.by_id(&[full]).await?;
    let audio = found.into_iter().next().ok_or_else(|| crate::providers::unplayable::unavailable("VK Музыка: трек не найден"))?;
    let url = audio.stream_url.clone().unwrap_or_default();
    self.core.vk_keep(vec![audio]);
    vk::source_from_url(&url)
  }

  async fn playlists(&self) -> Result<Vec<ServicePlaylist>> {
    let core = self.core;
    let Some((creds, uid)) = core.vk_uid().await? else { return Ok(vec![]) };
    let mut out = vec![ServicePlaylist {
      ref_: "vkpl:likes".into(),
      title: LIKES_TITLE.into(),
      owner: core.vk_owner_name(&*core.vk.read().await),
      cover_url: None,
      track_count: 0,
    }];
    out.extend(vk::Vk { http: &core.http(), creds: &creds }.playlists(&uid).await?);
    Ok(out)
  }

  async fn playlist(&self, id: &str) -> Result<PlaylistPage> {
    let core = self.core;
    if id == "likes" {
      let (creds, uid) = core.vk_uid().await?.ok_or_else(|| anyhow!(NOT_CONNECTED_SHORT))?;
      let list = vk::Vk { http: &core.http(), creds: &creds }.likes(&uid, MAX_LIKES).await?;
      let tracks = core.vk_keep(list);
      let playlist = ServicePlaylist {
        ref_: "vkpl:likes".into(),
        title: LIKES_TITLE.into(),
        owner: core.vk_owner_name(&*core.vk.read().await),
        cover_url: tracks.first().and_then(|t| t.cover_url.clone()),
        track_count: tracks.len() as u32,
      };
      return Ok(PlaylistPage { playlist, tracks });
    }
    if vk::PlaylistId::parse(id).is_none() {
      return Err(anyhow!("плохой ref vkpl:{id}"));
    }
    let s = core.vk_creds().await?;
    let (head, list) = vk::Vk { http: &core.http(), creds: &s.creds }.playlist(id, MAX_LIST).await?;
    let playlist = vk::playlist_from_json(&head).ok_or_else(|| anyhow!("VK Музыка: плейлист не найден"))?;
    Ok(PlaylistPage { playlist, tracks: core.vk_keep(list) })
  }
}
