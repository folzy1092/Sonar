<script lang="ts">
  // «Как видят мой профиль» (Аккаунт → Профиль): предпросмотр публичной страницы прямо в Sonar.
  // Сверху — плашка предпросмотра (ссылка, «Копировать ссылку на профиль», «Изменить профиль»),
  // ниже — сама страница `ProfileView`, как её нарисует сайт. До сервера профиль собирается здесь из
  // настроек, Любимых, плейлистов и статистики (`buildPublicProfile`); приватности пока нет — видно всё.
  import CopyProfileLink from '../components/CopyProfileLink.svelte'
  import Icon from '../components/Icon.svelte'
  import ProfileView from './profile/ProfileView.svelte'
  import { api, type ListTrack, type Playlist, type Stats } from '../lib/api'
  import { t } from '../lib/i18n.svelte'
  import { buildPublicProfile, profileUrl } from '../lib/public-profile'
  import { settings } from '../lib/settings.svelte'
  import { player } from '../player/player.svelte'
  import { home } from './home-data.svelte'
  import { settingsPanel } from './settings-section.svelte'

  let favorites = $state<ListTrack[] | null>(null)
  let playlists = $state<Playlist[] | null>(null)
  let stats = $state<Stats | null>(null)
  let loading = $state(true)

  const username = $derived(settings.get('profile.username'))
  const url = $derived(profileUrl(username))
  const profile = $derived(
    buildPublicProfile({
      name: settings.get('profile.name'),
      username,
      avatar: settings.get('profile.avatar'),
      account: home.account,
      favorites,
      playlists,
      stats,
      current: player.current,
    }),
  )

  const valueOf = <T,>(r: PromiseSettledResult<T>): T | null => (r.status === 'fulfilled' ? r.value : null)

  void Promise.allSettled([api.favorites(), api.playlists(), api.stats('all')]).then(([f, p, s]) => {
    // не загрузилось (вне приложения, нет базы) — раздел просто пустой, как у гостя
    favorites = valueOf(f)
    playlists = valueOf(p)
    stats = valueOf(s)
    loading = false
  })
</script>

<div class="preview">
  <div class="bar">
    <span class="badge"><Icon name="eye" size={18} /></span>
    <span class="text">
      <b>{t('Так твой профиль увидят по ссылке')}</b>
      <small>{url ?? t('Задай @username в Аккаунт → Профиль — тогда появится ссылка')}</small>
      <small>{t('Страница по ссылке заработает, когда у Sonar появится сервер.')}</small>
    </span>
    <span class="actions">
      <CopyProfileLink {username} />
      <button class="edit press" onclick={() => settingsPanel.show('account', 'profile')}>
        <Icon name="pencil" size={16} />{t('Изменить профиль')}
      </button>
    </span>
  </div>

  <ProfileView {profile} {loading} />
</div>

<style>
  .preview {
    display: flex;
    flex-direction: column;
    gap: 28px;
    /* строки поиска на этой странице нет — плашка ниже «чёлки» с кнопками окна */
    padding-top: 34px;
  }
  .bar {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 12px 14px;
    border-radius: var(--radius-l);
    border: 1px dashed var(--border-strong);
    background: var(--plate);
  }
  .badge {
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    flex-shrink: 0;
    border-radius: 50%;
    background: color-mix(in srgb, var(--accent) 18%, transparent);
    color: var(--accent);
  }
  .text {
    display: flex;
    flex-direction: column;
    gap: 1px;
    min-width: 0;
    flex: 1;
  }
  .text b {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  .text small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 8px;
  }
  .edit {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 36px;
    padding: 0 16px;
    border-radius: 10px;
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .edit:hover {
    background: var(--hover);
    color: var(--text);
  }
</style>
