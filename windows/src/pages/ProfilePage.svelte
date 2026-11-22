<script lang="ts">
  // «Как видят мой профиль» (Аккаунт → Профиль): предпросмотр публичной страницы прямо в Sonar.
  // Сверху — плашка предпросмотра (ссылка, «Копировать ссылку на профиль», «Изменить профиль»),
  // ниже — сама страница `ProfileView`, как её нарисует сайт. До сервера профиль собирается здесь из
  // настроек, Любимых, плейлистов и статистики (`buildPublicProfile`) с учётом Аккаунт → Приватность.
  import CopyProfileLink from '../components/CopyProfileLink.svelte'
  import Icon from '../components/Icon.svelte'
  import ProfileView from './profile/ProfileView.svelte'
  import { api, type ListTrack, type Playlist, type Stats } from '../lib/api'
  import { t } from '../lib/i18n.svelte'
  import { audienceOf, buildPublicProfile, profileUrl, type Viewer } from '../lib/public-profile'
  import { indicator } from '../lib/indicator'
  import { settings } from '../lib/settings.svelte'
  import { player } from '../player/player.svelte'
  import { settingsPanel } from './settings-section.svelte'
  import { colorHex, readLinks, readShowcase, visibleShowcase } from '../lib/profile-look'
  import type { ProfileLook } from './profile/ProfileView.svelte'

  let favorites = $state<ListTrack[] | null>(null)
  let playlists = $state<Playlist[] | null>(null)
  let stats = $state<Stats | null>(null)
  let loading = $state(true)
  /** Чьими глазами смотреть: гость по ссылке или друг. */
  let viewer = $state<Viewer>('guest')

  const username = $derived(settings.get('profile.username'))
  const url = $derived(profileUrl(username))
  const profile = $derived(
    buildPublicProfile({
      name: settings.get('profile.name'),
      username,
      avatar: settings.get('profile.avatar'),
      favorites,
      playlists,
      stats,
      current: player.current,
      playing: player.playing,
      privacy: {
        now_playing: audienceOf(settings.get('privacy.now_playing')),
        stats: audienceOf(settings.get('privacy.stats')),
        likes: audienceOf(settings.get('privacy.likes')),
        playlists: audienceOf(settings.get('privacy.playlists')),
        hidden_playlists: settings.get('privacy.hidden_playlists') ?? [],
      },
      viewer,
    }),
  )

  // Вид профиля (Аккаунт → Профиль): раскладка, баннер, ник, ссылки, витрина — гость и друг видят его
  // так же, как превью в настройках (раньше здесь всегда была шапка по умолчанию)
  const look = $derived<ProfileLook>({
    banner: settings.get('profile.banner'),
    background: settings.get('profile.background'),
    color: colorHex(settings.get('profile.color')),
    status: settings.get('profile.status'),
    bio: settings.get('profile.bio'),
    links: readLinks(settings.get('profile.links')),
    layout: settings.get('profile.layout'),
    nickFont: settings.get('profile.nick_font'),
    nickEffect: settings.get('profile.nick_effect'),
    nickColor2: colorHex(settings.get('profile.nick_color2')),
    showcase: visibleShowcase(readShowcase(settings.get('profile.showcase')), settings.get('privacy.hidden_playlists') ?? []),
  })

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
      <b>{viewer === 'friend' ? t('Так твой профиль увидят друзья') : t('Так твой профиль увидят по ссылке')}</b>
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

  <div class="chips" role="radiogroup" aria-label={t('Чьими глазами')} use:indicator={{ key: viewer, kind: 'pill' }}>
    {#each [['guest', 'Гость'], ['friend', 'Друг']] as const as [id, label] (id)}
      <button class="chip" class:on={viewer === id} role="radio" aria-checked={viewer === id} onclick={() => (viewer = id)}>{t(label)}</button>
    {/each}
  </div>

  <ProfileView {profile} {loading} {look} />
</div>

<style>
  .chips {
    display: flex;
    gap: 8px;
    margin-bottom: -12px;
  }
  .chip {
    height: 34px;
    padding: 0 16px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    color: var(--text-2);
    font-weight: 600;
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .chip:hover {
    color: var(--text);
    background: var(--hover);
  }
  .chip.on {
    background: transparent;
    border-color: transparent;
    color: var(--accent-ink);
  }
  .chips :global(.tab-ind.pill) {
    background: var(--accent);
  }
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
