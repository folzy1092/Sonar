//! SoundCloud за общим видом сервиса. Тела — прежние ветки `sc`/`sca`/`scalb`/`scpl` из Core.

use super::provider::Provider;
use super::{Core, PlaylistPage};
use crate::providers::registry::ServiceId;
use crate::providers::{soundcloud, Album, AlbumPage, ArtistPage, ArtistTrack, SearchResults, ServicePlaylist, Source, Track};
use anyhow::{anyhow, Result};

/// Все треки исполнителя для вкладки «Треки».
const MAX: usize = 1000;
/// Лайки аккаунта как плейлист.
const MAX_LIKES: usize = 2000;

pub struct ScProvider<'a> {
  pub(super) core: &'a Core,
}

impl Provider for ScProvider<'_> {
  fn id(&self) -> ServiceId {
    ServiceId::Sc
  }

  async fn search(&self, q: &str, limit: u32) -> Result<Vec<Track>> {
    let core = self.core;
    let (creds, public) = core.sc_creds(false).await?;
    let found = match core.sc_search(&creds, q, limit).await {
      Err(e) if public && super::is_auth_error(&e) => core.sc_search(&core.sc_creds(true).await?.0, q, limit).await?,
      r => r?,
    };
    let mut raw = core.sc_raw.lock().unwrap();
    if raw.len() > 2000 {
      raw.clear();
    }
    Ok(found
      .into_iter()
      .map(|(t, j)| {
        raw.insert(t.ref_.clone(), j);
        t
      })
      .collect())
  }

  async fn search_more(&self, q: &str, limit: u32) -> Result<SearchResults> {
    let http = &self.core.http;
    let (artists, albums, playlists) =
      self.core.with_sc(|c| async move { soundcloud::SoundCloud { http, creds: &c }.search_more(q, limit).await }).await?;
    Ok(SearchResults { tracks: vec![], artists, albums, playlists })
  }

  async fn artist_page(&self, id: &str) -> Result<ArtistPage> {
    let http = &self.core.http;
    let (user, top, albums) = self
      .core
      .with_sc(|c| async move {
        let sc = soundcloud::SoundCloud { http, creds: &c };
        let (user, top, albums) = futures_util::join!(sc.user(id), sc.top_tracks(id, 10), sc.user_albums(id));
        Ok((user?, top.unwrap_or_default(), albums.unwrap_or_default()))
      })
      .await?;
    let artist = soundcloud::artist_from_json(&user).ok_or_else(|| anyhow!("SoundCloud: исполнитель не найден"))?;
    Ok(ArtistPage { artist, top: self.core.sc_keep(top), albums })
  }

  async fn artist_tracks(&self, id: &str) -> Result<Vec<ArtistTrack>> {
    let http = &self.core.http;
    let raw = self.core.with_sc(|c| async move { soundcloud::SoundCloud { http, creds: &c }.user_tracks(id, MAX).await }).await?;
    let extra: Vec<(Option<u64>, Option<String>)> = raw
      .iter()
      .map(|j| {
        let date = j["release_date"].as_str().or(j["display_date"].as_str()).or(j["created_at"].as_str());
        (j["likes_count"].as_u64(), date.map(|d| d.chars().take(10).collect()))
      })
      .collect();
    let ids: Vec<Option<u64>> = raw.iter().map(|j| j["id"].as_u64()).collect();
    let tracks = self.core.sc_keep(raw);
    // sc_keep может отбросить недоступные — сопоставляем по id
    let mut out: Vec<ArtistTrack> = tracks
      .into_iter()
      .map(|t| {
        let i = ids.iter().position(|x| x.map(|v| format!("sc:{v}")).as_deref() == Some(t.ref_.as_str()));
        let (likes, released) = i.and_then(|i| extra.get(i).cloned()).unwrap_or((None, None));
        ArtistTrack { track: t, likes, released }
      })
      .collect();
    out.sort_by(|a, b| b.track.plays.unwrap_or(0).cmp(&a.track.plays.unwrap_or(0)));
    Ok(out)
  }

  async fn artist_top(&self, id: &str, limit: u32) -> Result<Vec<Track>> {
    let http = &self.core.http;
    let raw = self.core.with_sc(|c| async move { soundcloud::SoundCloud { http, creds: &c }.top_tracks(id, limit).await }).await?;
    Ok(self.core.sc_keep(raw))
  }

  async fn artist_albums(&self, id: &str) -> Result<Vec<Album>> {
    let http = &self.core.http;
    self.core.with_sc(|c| async move { soundcloud::SoundCloud { http, creds: &c }.user_albums(id).await }).await
  }

  async fn album_page(&self, id: &str) -> Result<AlbumPage> {
    let http = &self.core.http;
    let (head, raw) = self.core.with_sc(|c| async move { soundcloud::SoundCloud { http, creds: &c }.playlist(id).await }).await?;
    let album = soundcloud::album_from_json(&head).ok_or_else(|| anyhow!("SoundCloud: альбом не найден"))?;
    Ok(AlbumPage { album, tracks: self.core.sc_keep(raw) })
  }

  async fn similar(&self, id: &str, limit: u32) -> Result<Vec<Track>> {
    let http = &self.core.http;
    let raw = self.core.with_sc(|c| async move { soundcloud::SoundCloud { http, creds: &c }.related(id, limit).await }).await?;
    Ok(self.core.sc_keep(raw))
  }

  async fn stream(&self, id: &str, fresh: bool) -> Result<Source> {
    // ключ кэша сырого JSON — полный ref трека
    self.core.sc_resolve(&format!("sc:{id}"), id, fresh).await
  }

  async fn playlists(&self) -> Result<Vec<ServicePlaylist>> {
    let core = self.core;
    let Some((creds, uid)) = core.sc_uid().await? else { return Ok(vec![]) };
    let mut out = vec![ServicePlaylist {
      ref_: "scpl:likes".into(),
      title: "Лайки SoundCloud".into(),
      owner: core.sc.read().await.as_ref().and_then(|s| s.account.name.clone()).unwrap_or_default(),
      cover_url: None,
      track_count: 0,
    }];
    out.extend(soundcloud::SoundCloud { http: &core.http, creds: &creds }.user_playlists(&uid).await?);
    Ok(out)
  }

  async fn playlist(&self, id: &str) -> Result<PlaylistPage> {
    let core = self.core;
    if id == "likes" {
      let (creds, uid) = core.sc_uid().await?.ok_or_else(|| anyhow!("Нужен OAuth-токен SoundCloud"))?;
      let raw = soundcloud::SoundCloud { http: &core.http, creds: &creds }.user_likes(&uid, MAX_LIKES).await?;
      let tracks = core.sc_keep(raw);
      let mut head = self.playlists().await.ok().and_then(|l| l.into_iter().next()).unwrap_or(ServicePlaylist {
        ref_: "scpl:likes".into(),
        title: "Лайки SoundCloud".into(),
        owner: String::new(),
        cover_url: None,
        track_count: 0,
      });
      head.track_count = tracks.len() as u32;
      head.cover_url = tracks.first().and_then(|t| t.cover_url.clone());
      return Ok(PlaylistPage { playlist: head, tracks });
    }
    let http = &core.http;
    let (head, raw) = core.with_sc(|c| async move { soundcloud::SoundCloud { http, creds: &c }.playlist(id).await }).await?;
    let playlist = soundcloud::playlist_from_json(&head).ok_or_else(|| anyhow!("SoundCloud: плейлист не найден"))?;
    Ok(PlaylistPage { playlist, tracks: core.sc_keep(raw) })
  }
}
