//! Spotify за общим видом сервиса: метаданные Web API на токене веб-плеера (providers/spotify.rs).
//! Поток — только Premium и только со сборкой `spotify-playback`; иначе «нужен резервный сервис».

use super::provider::Provider;
use super::{status, Core, PlaylistPage, ServiceStatus, Stored};
use crate::providers::registry::ServiceId;
use crate::providers::spotify::{self, Spotify};
use crate::providers::unplayable::{Reason, Unplayable};
use crate::providers::{Album, AlbumPage, ArtistPage, ArtistTrack, SearchResults, ServicePlaylist, Source, Track};
use crate::secrets;
use anyhow::{anyhow, Result};

/// Все треки исполнителя для вкладки «Треки».
const MAX: usize = 1000;
/// «Любимые треки» как плейлист.
const MAX_LIKES: usize = 2000;
/// Треков в плейлисте сервиса.
const MAX_PLAYLIST: usize = 2000;

pub struct SpProvider<'a> {
  pub(super) core: &'a Core,
}

impl Core {
  async fn sp_stored(&self) -> Result<Stored<spotify::Creds>> {
    self.sp.read().await.clone().ok_or_else(|| anyhow!(spotify::NOT_CONNECTED))
  }

  /// Подключить Spotify по `sp_dc` (вставленному или из окна входа): токен, `/me`, keyring.
  pub async fn connect_spotify(&self, raw_sp_dc: &str) -> Result<ServiceStatus> {
    let sp_dc = spotify::normalize_sp_dc(raw_sp_dc).ok_or_else(|| anyhow!("Вставь значение cookie sp_dc с open.spotify.com"))?;
    let creds = spotify::Creds { sp_dc };
    // новый ключ — старый токен не годится
    *self.sp_token.lock().await = None;
    let account = Spotify { http: &self.http(), creds: &creds, secret: &self.sp_totp, cache: &self.sp_token }.account().await;
    let account = match account {
      Ok(a) => a,
      Err(e) => {
        *self.sp_token.lock().await = None;
        return Err(e);
      }
    };
    let stored = Stored { creds, account };
    secrets::save(ServiceId::Sp.key(), &stored)?;
    *self.sp.write().await = Some(stored.clone());
    self.streams.lock().unwrap().clear();
    Ok(status(&Some(stored)))
  }

  /// Трек Premium целиком в Ogg (фича `spotify-playback`): токен веб-плеера → librespot.
  #[cfg(feature = "spotify-playback")]
  pub async fn spotify_ogg(&self, id: &str) -> Result<(std::sync::Arc<Vec<u8>>, String)> {
    let s = self.sp_stored().await?;
    let token = Spotify { http: &self.http(), creds: &s.creds, secret: &self.sp_totp, cache: &self.sp_token }.token(false).await?;
    crate::spotify_play::ogg(&token, id, self.max_kbps.load(std::sync::atomic::Ordering::Relaxed)).await
  }

  /// Отключение: ключ и токен забыть.
  pub(super) async fn forget_spotify(&self) {
    *self.sp.write().await = None;
    *self.sp_token.lock().await = None;
  }
}

impl SpProvider<'_> {
  /// Клиент Web API на сохранённом ключе (токен — общий кэш ядра).
  fn api<'s>(&'s self, s: &'s Stored<spotify::Creds>) -> Spotify<'s> {
    let core = self.core;
    Spotify { http: &core.http(), creds: &s.creds, secret: &core.sp_totp, cache: &core.sp_token }
  }

  async fn likes_page(&self) -> Result<PlaylistPage> {
    let s = self.core.sp_stored().await?;
    let owner = s.account.name.clone().unwrap_or_default();
    let tracks = self.api(&s).likes(MAX_LIKES).await?;
    let playlist = ServicePlaylist {
      ref_: "sppl:likes".into(),
      title: "Любимые треки".into(),
      owner,
      cover_url: tracks.first().and_then(|t| t.cover_url.clone()),
      track_count: tracks.len() as u32,
    };
    Ok(PlaylistPage { playlist, tracks })
  }
}

impl Provider for SpProvider<'_> {
  fn id(&self) -> ServiceId {
    ServiceId::Sp
  }

  async fn search(&self, q: &str, limit: u32) -> Result<Vec<Track>> {
    self.api(&self.core.sp_stored().await?).search(q, limit).await
  }

  async fn search_more(&self, q: &str, limit: u32) -> Result<SearchResults> {
    let (artists, albums, playlists) = self.api(&self.core.sp_stored().await?).search_more(q, limit).await?;
    Ok(SearchResults { tracks: vec![], artists, albums, playlists })
  }

  async fn artist_page(&self, id: &str) -> Result<ArtistPage> {
    let (artist, top, albums) = self.api(&self.core.sp_stored().await?).artist(id).await?;
    Ok(ArtistPage { artist, top, albums })
  }

  async fn artist_tracks(&self, id: &str) -> Result<Vec<ArtistTrack>> {
    let list = self.api(&self.core.sp_stored().await?).artist_tracks(id, MAX).await?;
    Ok(list.into_iter().map(|(track, released)| ArtistTrack { track, likes: None, released }).collect())
  }

  async fn artist_top(&self, id: &str, limit: u32) -> Result<Vec<Track>> {
    let (_, mut top, _) = self.api(&self.core.sp_stored().await?).artist(id).await?;
    top.truncate(limit as usize);
    Ok(top)
  }

  async fn artist_albums(&self, id: &str) -> Result<Vec<Album>> {
    self.api(&self.core.sp_stored().await?).artist_albums(id).await
  }

  async fn album_page(&self, id: &str) -> Result<AlbumPage> {
    let (album, tracks) = self.api(&self.core.sp_stored().await?).album(id).await?;
    Ok(AlbumPage { album, tracks })
  }

  /// Рекомендаций Spotify не берём (caps.similar = false): похожее волне дают SC и Яндекс.
  async fn similar(&self, _id: &str, _limit: u32) -> Result<Vec<Track>> {
    Ok(vec![])
  }

  /// Без Premium (или без сборки `spotify-playback`) — понятная ошибка: играет резервный сервис.
  async fn stream(&self, id: &str, _fresh: bool) -> Result<Source> {
    #[cfg(feature = "spotify-playback")]
    if self.core.sp_stored().await?.account.premium == Some(true) {
      // метка: stream.rs не проксирует её, а качает трек librespot'ом (Core::spotify_ogg)
      return Ok(Source::File { url: format!("{}{id}", crate::spotify_play::SCHEME), quality: "Ogg Vorbis · Spotify".into() });
    }
    let _ = id;
    Err(Unplayable::new(Reason::Premium, spotify::NEEDS_FALLBACK).into())
  }

  async fn playlists(&self) -> Result<Vec<ServicePlaylist>> {
    let Some(s) = self.core.sp.read().await.clone() else { return Ok(vec![]) };
    let mut out = vec![ServicePlaylist {
      ref_: "sppl:likes".into(),
      title: "Любимые треки".into(),
      owner: s.account.name.clone().unwrap_or_default(),
      cover_url: None,
      track_count: 0,
    }];
    out.extend(self.api(&s).playlists().await?);
    Ok(out)
  }

  async fn playlist(&self, id: &str) -> Result<PlaylistPage> {
    if id == "likes" {
      return self.likes_page().await;
    }
    let (playlist, tracks) = self.api(&self.core.sp_stored().await?).playlist(id, MAX_PLAYLIST).await?;
    Ok(PlaylistPage { playlist, tracks })
  }
}
