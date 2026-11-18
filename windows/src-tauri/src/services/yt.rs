//! YouTube Music за общим видом сервиса. Каталог и поток работают и без входа (гостем),
//! «Лайки» и плейлисты аккаунта — только с cookie (вход в окне или cookie вручную).

use super::provider::Provider;
use super::{Core, PlaylistPage};
use crate::providers::registry::ServiceId;
use crate::providers::youtube::{self, YouTube};
use crate::providers::{Album, AlbumPage, ArtistPage, ArtistTrack, SearchResults, ServicePlaylist, Source, Track};
use anyhow::{anyhow, Result};
use std::sync::atomic::Ordering;

/// Все треки исполнителя для вкладки «Треки».
const MAX: usize = 1000;
/// «Понравившиеся» как плейлист.
const MAX_LIKES: usize = 2000;
/// Обычный плейлист.
const MAX_PLAYLIST: usize = 1000;
/// ref «Лайков» YouTube Music.
pub const LIKES_REF: &str = "ytpl:likes";

pub struct YtProvider<'a> {
  pub(super) core: &'a Core,
}

impl YtProvider<'_> {
  async fn creds(&self) -> Option<youtube::Creds> {
    self.core.yt.read().await.as_ref().map(|s| s.creds.clone())
  }

  async fn owner(&self) -> String {
    self.core.yt.read().await.as_ref().and_then(|s| s.account.name.clone()).unwrap_or_default()
  }

  /// `visitorData` гостя: одна на сессию, `fresh` — взять новую (поток не открылся).
  async fn visitor(&self, fresh: bool) -> Result<String> {
    if !fresh {
      if let Some(v) = self.core.yt_visitor.read().await.clone() {
        return Ok(v);
      }
    }
    let v = youtube::visitor_data(&self.core.http).await?;
    *self.core.yt_visitor.write().await = Some(v.clone());
    Ok(v)
  }
}

impl Provider for YtProvider<'_> {
  fn id(&self) -> ServiceId {
    ServiceId::Yt
  }

  async fn search(&self, q: &str, limit: u32) -> Result<Vec<Track>> {
    let c = self.creds().await;
    YouTube { http: &self.core.http, creds: c.as_ref() }.search(q, limit).await
  }

  async fn search_more(&self, q: &str, limit: u32) -> Result<SearchResults> {
    let c = self.creds().await;
    let (artists, albums, playlists) = YouTube { http: &self.core.http, creds: c.as_ref() }.search_more(q, limit).await?;
    Ok(SearchResults { tracks: vec![], artists, albums, playlists })
  }

  async fn artist_page(&self, id: &str) -> Result<ArtistPage> {
    let c = self.creds().await;
    let p = YouTube { http: &self.core.http, creds: c.as_ref() }.artist(id).await?;
    Ok(ArtistPage { artist: p.artist, top: p.top, albums: p.albums })
  }

  /// Вкладка «Треки»: плейлист «Все песни» исполнителя, если он есть, иначе популярные.
  async fn artist_tracks(&self, id: &str) -> Result<Vec<ArtistTrack>> {
    let c = self.creds().await;
    let yt = YouTube { http: &self.core.http, creds: c.as_ref() };
    let page = yt.artist(id).await?;
    let tracks = match page.all_tracks {
      Some(list) => yt.playlist(&list, MAX).await?.1,
      None => page.top,
    };
    Ok(tracks.into_iter().map(|track| ArtistTrack { track, likes: None, released: None }).collect())
  }

  async fn artist_top(&self, id: &str, limit: u32) -> Result<Vec<Track>> {
    let mut top = self.artist_page(id).await?.top;
    top.truncate(limit as usize);
    Ok(top)
  }

  async fn artist_albums(&self, id: &str) -> Result<Vec<Album>> {
    Ok(self.artist_page(id).await?.albums)
  }

  async fn album_page(&self, id: &str) -> Result<AlbumPage> {
    let c = self.creds().await;
    let (album, tracks) = YouTube { http: &self.core.http, creds: c.as_ref() }.album(id).await?;
    Ok(AlbumPage { album, tracks })
  }

  async fn similar(&self, id: &str, limit: u32) -> Result<Vec<Track>> {
    let c = self.creds().await;
    let mut t = YouTube { http: &self.core.http, creds: c.as_ref() }.similar(id).await?;
    t.truncate(limit as usize);
    Ok(t)
  }

  /// Поток берётся гостем (клиент VISIONOS cookie не принимает); `fresh` — новая visitorData.
  async fn stream(&self, id: &str, fresh: bool) -> Result<Source> {
    let visitor = self.visitor(fresh).await?;
    let high = self.core.yt_high.load(Ordering::Relaxed);
    YouTube { http: &self.core.http, creds: None }.stream(id, &visitor, high).await
  }

  async fn playlists(&self) -> Result<Vec<ServicePlaylist>> {
    let Some(c) = self.creds().await else { return Ok(vec![]) };
    let mut out = vec![ServicePlaylist {
      ref_: LIKES_REF.into(),
      title: youtube::LIKES_TITLE.into(),
      owner: self.owner().await,
      cover_url: None,
      track_count: 0,
    }];
    out.extend(YouTube { http: &self.core.http, creds: Some(&c) }.library_playlists().await?);
    Ok(out)
  }

  async fn playlist(&self, id: &str) -> Result<PlaylistPage> {
    let c = self.creds().await;
    if id == "likes" {
      let c = c.ok_or_else(|| anyhow!("YouTube Music не подключена — открой Настройки → Сервисы"))?;
      let (mut playlist, tracks) = YouTube { http: &self.core.http, creds: Some(&c) }.playlist(id, MAX_LIKES).await?;
      playlist.owner = self.owner().await;
      if playlist.cover_url.is_none() {
        playlist.cover_url = tracks.first().and_then(|t| t.cover_url.clone());
      }
      return Ok(PlaylistPage { playlist, tracks });
    }
    let (playlist, tracks) = YouTube { http: &self.core.http, creds: c.as_ref() }.playlist(id, MAX_PLAYLIST).await?;
    Ok(PlaylistPage { playlist, tracks })
  }
}
