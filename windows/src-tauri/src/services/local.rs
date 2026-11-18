//! Локальные файлы за общим видом сервиса (Хранилище → «Папки с музыкой»). Своих страниц,
//! похожих и плейлистов у них нет; поток — файл с диска, только из индекса (`crate::local::Index`).
//! Поиск по файлам — отдельной командой `local_search` (он идёт по базе, а не в сеть).

use super::provider::Provider;
use super::{Core, PlaylistPage};
use crate::providers::registry::ServiceId;
use crate::providers::{Album, AlbumPage, ArtistPage, ArtistTrack, SearchResults, ServicePlaylist, Source, Track};
use anyhow::{bail, Result};

const NO_PAGE: &str = "Локальные файлы: нет такой страницы";
pub const NOT_FOUND: &str = "Файл не найден";

pub struct LocalProvider<'a> {
  pub(super) core: &'a Core,
}

impl Provider for LocalProvider<'_> {
  fn id(&self) -> ServiceId {
    ServiceId::Local
  }

  async fn search(&self, _q: &str, _limit: u32) -> Result<Vec<Track>> {
    Ok(vec![])
  }

  async fn search_more(&self, _q: &str, _limit: u32) -> Result<SearchResults> {
    Ok(SearchResults::default())
  }

  async fn artist_page(&self, _id: &str) -> Result<ArtistPage> {
    bail!(NO_PAGE)
  }

  async fn artist_tracks(&self, _id: &str) -> Result<Vec<ArtistTrack>> {
    Ok(vec![])
  }

  async fn artist_top(&self, _id: &str, _limit: u32) -> Result<Vec<Track>> {
    Ok(vec![])
  }

  async fn artist_albums(&self, _id: &str) -> Result<Vec<Album>> {
    Ok(vec![])
  }

  async fn album_page(&self, _id: &str) -> Result<AlbumPage> {
    bail!(NO_PAGE)
  }

  async fn similar(&self, _id: &str, _limit: u32) -> Result<Vec<Track>> {
    Ok(vec![])
  }

  /// Путь — только из индекса: в `url` лежит путь к файлу, его отдаёт `/file` аудио-сервера.
  async fn stream(&self, id: &str, _fresh: bool) -> Result<Source> {
    let r = format!("{}:{id}", crate::local::PREFIX);
    match self.core.local.get(&r).filter(|p| p.is_file()) {
      Some(path) => Ok(Source::File { quality: crate::local::quality_label(&path), url: path.to_string_lossy().into_owned() }),
      None => bail!(NOT_FOUND),
    }
  }

  async fn playlists(&self) -> Result<Vec<ServicePlaylist>> {
    Ok(vec![])
  }

  async fn playlist(&self, _id: &str) -> Result<PlaylistPage> {
    bail!(NO_PAGE)
  }
}
