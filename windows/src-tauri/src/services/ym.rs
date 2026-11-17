//! Яндекс Музыка за общим видом сервиса. Тела — прежние ветки `ym`/`yma`/`ymalb`/`ympl` из Core.

use super::provider::Provider;
use super::{Core, PlaylistPage};
use crate::providers::registry::ServiceId;
use crate::providers::{yandex, Album, AlbumPage, ArtistPage, ArtistTrack, SearchResults, ServicePlaylist, Source, Track};
use anyhow::{anyhow, Result};
use std::sync::atomic::Ordering;

/// Все треки исполнителя для вкладки «Треки».
const MAX: usize = 1000;
/// «Мне нравится» как плейлист.
const MAX_LIKES: usize = 2000;

pub struct YmProvider<'a> {
  pub(super) core: &'a Core,
}

impl Provider for YmProvider<'_> {
  fn id(&self) -> ServiceId {
    ServiceId::Ym
  }

  async fn search(&self, q: &str, limit: u32) -> Result<Vec<Track>> {
    let guard = self.core.ym.read().await;
    let s = guard.as_ref().ok_or_else(|| anyhow!("Яндекс Музыка не подключена — открой Настройки → Сервисы"))?;
    yandex::Yandex { http: &self.core.http, creds: &s.creds }.search(q, limit).await
  }

  async fn search_more(&self, q: &str, limit: u32) -> Result<SearchResults> {
    let s = self.core.ym_creds().await?;
    let (artists, albums, playlists) = yandex::Yandex { http: &self.core.http, creds: &s.creds }.search_more(q, limit).await?;
    Ok(SearchResults { tracks: vec![], artists, albums, playlists })
  }

  async fn artist_page(&self, id: &str) -> Result<ArtistPage> {
    let s = self.core.ym_creds().await?;
    let (artist, top, albums) = yandex::Yandex { http: &self.core.http, creds: &s.creds }.artist(id).await?;
    Ok(ArtistPage { artist, top, albums })
  }

  async fn artist_tracks(&self, id: &str) -> Result<Vec<ArtistTrack>> {
    let s = self.core.ym_creds().await?;
    let list = yandex::Yandex { http: &self.core.http, creds: &s.creds }.artist_tracks(id, MAX).await?;
    Ok(list.into_iter().map(|(track, released)| ArtistTrack { track, likes: None, released }).collect())
  }

  async fn artist_top(&self, id: &str, limit: u32) -> Result<Vec<Track>> {
    let s = self.core.ym_creds().await?;
    let (_, mut top, _) = yandex::Yandex { http: &self.core.http, creds: &s.creds }.artist(id).await?;
    top.truncate(limit as usize);
    Ok(top)
  }

  async fn artist_albums(&self, id: &str) -> Result<Vec<Album>> {
    let s = self.core.ym_creds().await?;
    Ok(yandex::Yandex { http: &self.core.http, creds: &s.creds }.artist(id).await?.2)
  }

  async fn album_page(&self, id: &str) -> Result<AlbumPage> {
    let s = self.core.ym_creds().await?;
    let (album, tracks) = yandex::Yandex { http: &self.core.http, creds: &s.creds }.album(id).await?;
    Ok(AlbumPage { album, tracks })
  }

  async fn similar(&self, id: &str, limit: u32) -> Result<Vec<Track>> {
    let s = self.core.ym_creds().await?;
    let mut t = yandex::Yandex { http: &self.core.http, creds: &s.creds }.similar(id).await?;
    t.truncate(limit as usize);
    Ok(t)
  }

  /// `fresh` Яндексу не нужен: сырого JSON он не кэширует, ссылку каждый раз берёт заново.
  async fn stream(&self, id: &str, _fresh: bool) -> Result<Source> {
    let guard = self.core.ym.read().await;
    let s = guard.as_ref().ok_or_else(|| anyhow!("Яндекс Музыка не подключена"))?;
    yandex::Yandex { http: &self.core.http, creds: &s.creds }.stream(id, self.core.max_kbps.load(Ordering::Relaxed)).await
  }

  async fn playlists(&self) -> Result<Vec<ServicePlaylist>> {
    let core = self.core;
    let Some((creds, uid)) = core.ym_uid().await? else { return Ok(vec![]) };
    let mut out = vec![ServicePlaylist {
      ref_: "ympl:likes".into(),
      title: "Мне нравится".into(),
      owner: core.ym.read().await.as_ref().and_then(|s| s.account.name.clone()).unwrap_or_default(),
      cover_url: None,
      track_count: 0,
    }];
    let lists = yandex::Yandex { http: &core.http, creds: &creds }.user_playlists(&uid).await?;
    // «Мне нравится» в Яндексе — kind 3, он уже есть первой строкой
    out.extend(lists.into_iter().filter(|p| !p.ref_.ends_with(":3")));
    Ok(out)
  }

  async fn playlist(&self, id: &str) -> Result<PlaylistPage> {
    let core = self.core;
    if id == "likes" {
      let (creds, uid) = core.ym_uid().await?.ok_or_else(|| anyhow!("Яндекс Музыка не подключена"))?;
      let tracks = yandex::Yandex { http: &core.http, creds: &creds }.likes(&uid, MAX_LIKES).await?;
      let owner = core.ym.read().await.as_ref().and_then(|s| s.account.name.clone()).unwrap_or_default();
      let playlist = ServicePlaylist {
        ref_: "ympl:likes".into(),
        title: "Мне нравится".into(),
        owner,
        cover_url: tracks.first().and_then(|t| t.cover_url.clone()),
        track_count: tracks.len() as u32,
      };
      return Ok(PlaylistPage { playlist, tracks });
    }
    let (uid, kind) = id.split_once(':').ok_or_else(|| anyhow!("плохой ref ympl:{id}"))?;
    let s = core.ym_creds().await?;
    let (playlist, tracks) = yandex::Yandex { http: &core.http, creds: &s.creds }.playlist(uid, kind).await?;
    Ok(PlaylistPage { playlist, tracks })
  }
}
