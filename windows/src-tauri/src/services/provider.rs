//! Общий вид сервиса музыки. Реализации — `sc.rs`, `ym.rs`, `yt.rs`, `sp.rs` и `local.rs`; Core выбирает
//! нужную через `AnyProvider` (перечисление, а не `dyn`: набор сервисов известен заранее).

use super::{local, sc, sp, ym, yt, PlaylistPage};
use crate::providers::registry::ServiceId;
use crate::providers::{Album, AlbumPage, ArtistPage, ArtistTrack, SearchResults, ServicePlaylist, Source, Track};
use anyhow::Result;
use std::future::Future;

/// Аргументы `id` — часть ref ПОСЛЕ префикса (`sc:123` → "123", `ympl:42:1003` → "42:1003").
pub trait Provider {
  fn id(&self) -> ServiceId;
  fn search(&self, q: &str, limit: u32) -> impl Future<Output = Result<Vec<Track>>> + Send;
  fn search_more(&self, q: &str, limit: u32) -> impl Future<Output = Result<SearchResults>> + Send;
  fn artist_page(&self, id: &str) -> impl Future<Output = Result<ArtistPage>> + Send;
  fn artist_tracks(&self, id: &str) -> impl Future<Output = Result<Vec<ArtistTrack>>> + Send;
  fn artist_top(&self, id: &str, limit: u32) -> impl Future<Output = Result<Vec<Track>>> + Send;
  fn artist_albums(&self, id: &str) -> impl Future<Output = Result<Vec<Album>>> + Send;
  fn album_page(&self, id: &str) -> impl Future<Output = Result<AlbumPage>> + Send;
  fn similar(&self, id: &str, limit: u32) -> impl Future<Output = Result<Vec<Track>>> + Send;
  /// Поток самого сервиса: без кэша и без двойника с другого сервиса (они в `Core::resolve`).
  fn stream(&self, id: &str, fresh: bool) -> impl Future<Output = Result<Source>> + Send;
  /// Плейлисты аккаунта: первой строкой «Лайки» сервиса. Не подключён — пусто.
  fn playlists(&self) -> impl Future<Output = Result<Vec<ServicePlaylist>>> + Send;
  fn playlist(&self, id: &str) -> impl Future<Output = Result<PlaylistPage>> + Send;
}

/// Работающие в Sonar сервисы. Новый сервис — новый вариант, компилятор покажет все `match`.
pub enum AnyProvider<'a> {
  Sc(sc::ScProvider<'a>),
  Ym(ym::YmProvider<'a>),
  Yt(yt::YtProvider<'a>),
  Sp(sp::SpProvider<'a>),
  Local(local::LocalProvider<'a>),
}

impl Provider for AnyProvider<'_> {
  fn id(&self) -> ServiceId {
    match self {
      AnyProvider::Sc(p) => p.id(),
      AnyProvider::Ym(p) => p.id(),
      AnyProvider::Yt(p) => p.id(),
      AnyProvider::Sp(p) => p.id(),
      AnyProvider::Local(p) => p.id(),
    }
  }

  async fn search(&self, q: &str, limit: u32) -> Result<Vec<Track>> {
    match self {
      AnyProvider::Sc(p) => p.search(q, limit).await,
      AnyProvider::Ym(p) => p.search(q, limit).await,
      AnyProvider::Yt(p) => p.search(q, limit).await,
      AnyProvider::Sp(p) => p.search(q, limit).await,
      AnyProvider::Local(p) => p.search(q, limit).await,
    }
  }

  async fn search_more(&self, q: &str, limit: u32) -> Result<SearchResults> {
    match self {
      AnyProvider::Sc(p) => p.search_more(q, limit).await,
      AnyProvider::Ym(p) => p.search_more(q, limit).await,
      AnyProvider::Yt(p) => p.search_more(q, limit).await,
      AnyProvider::Sp(p) => p.search_more(q, limit).await,
      AnyProvider::Local(p) => p.search_more(q, limit).await,
    }
  }

  async fn artist_page(&self, id: &str) -> Result<ArtistPage> {
    match self {
      AnyProvider::Sc(p) => p.artist_page(id).await,
      AnyProvider::Ym(p) => p.artist_page(id).await,
      AnyProvider::Yt(p) => p.artist_page(id).await,
      AnyProvider::Sp(p) => p.artist_page(id).await,
      AnyProvider::Local(p) => p.artist_page(id).await,
    }
  }

  async fn artist_tracks(&self, id: &str) -> Result<Vec<ArtistTrack>> {
    match self {
      AnyProvider::Sc(p) => p.artist_tracks(id).await,
      AnyProvider::Ym(p) => p.artist_tracks(id).await,
      AnyProvider::Yt(p) => p.artist_tracks(id).await,
      AnyProvider::Sp(p) => p.artist_tracks(id).await,
      AnyProvider::Local(p) => p.artist_tracks(id).await,
    }
  }

  async fn artist_top(&self, id: &str, limit: u32) -> Result<Vec<Track>> {
    match self {
      AnyProvider::Sc(p) => p.artist_top(id, limit).await,
      AnyProvider::Ym(p) => p.artist_top(id, limit).await,
      AnyProvider::Yt(p) => p.artist_top(id, limit).await,
      AnyProvider::Sp(p) => p.artist_top(id, limit).await,
      AnyProvider::Local(p) => p.artist_top(id, limit).await,
    }
  }

  async fn artist_albums(&self, id: &str) -> Result<Vec<Album>> {
    match self {
      AnyProvider::Sc(p) => p.artist_albums(id).await,
      AnyProvider::Ym(p) => p.artist_albums(id).await,
      AnyProvider::Yt(p) => p.artist_albums(id).await,
      AnyProvider::Sp(p) => p.artist_albums(id).await,
      AnyProvider::Local(p) => p.artist_albums(id).await,
    }
  }

  async fn album_page(&self, id: &str) -> Result<AlbumPage> {
    match self {
      AnyProvider::Sc(p) => p.album_page(id).await,
      AnyProvider::Ym(p) => p.album_page(id).await,
      AnyProvider::Yt(p) => p.album_page(id).await,
      AnyProvider::Sp(p) => p.album_page(id).await,
      AnyProvider::Local(p) => p.album_page(id).await,
    }
  }

  async fn similar(&self, id: &str, limit: u32) -> Result<Vec<Track>> {
    match self {
      AnyProvider::Sc(p) => p.similar(id, limit).await,
      AnyProvider::Ym(p) => p.similar(id, limit).await,
      AnyProvider::Yt(p) => p.similar(id, limit).await,
      AnyProvider::Sp(p) => p.similar(id, limit).await,
      AnyProvider::Local(p) => p.similar(id, limit).await,
    }
  }

  async fn stream(&self, id: &str, fresh: bool) -> Result<Source> {
    match self {
      AnyProvider::Sc(p) => p.stream(id, fresh).await,
      AnyProvider::Ym(p) => p.stream(id, fresh).await,
      AnyProvider::Yt(p) => p.stream(id, fresh).await,
      AnyProvider::Sp(p) => p.stream(id, fresh).await,
      AnyProvider::Local(p) => p.stream(id, fresh).await,
    }
  }

  async fn playlists(&self) -> Result<Vec<ServicePlaylist>> {
    match self {
      AnyProvider::Sc(p) => p.playlists().await,
      AnyProvider::Ym(p) => p.playlists().await,
      AnyProvider::Yt(p) => p.playlists().await,
      AnyProvider::Sp(p) => p.playlists().await,
      AnyProvider::Local(p) => p.playlists().await,
    }
  }

  async fn playlist(&self, id: &str) -> Result<PlaylistPage> {
    match self {
      AnyProvider::Sc(p) => p.playlist(id).await,
      AnyProvider::Ym(p) => p.playlist(id).await,
      AnyProvider::Yt(p) => p.playlist(id).await,
      AnyProvider::Sp(p) => p.playlist(id).await,
      AnyProvider::Local(p) => p.playlist(id).await,
    }
  }
}
