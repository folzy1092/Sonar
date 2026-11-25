<script lang="ts">
  // Аккаунт → Приватность (решение владельца 2026-11-18): что гость видит по ссылке на профиль.
  // Скрытое не попадает в `PublicProfile` вовсе (lib/public-profile.ts); сервер потом — по тем же ключам.
  import Group from '../../components/settings/Group.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Icon from '../../components/Icon.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { t, tn } from '../../lib/i18n.svelte'
  import { audienceOf } from '../../lib/public-profile'
  import { router } from '../../app/router.svelte'
  import { settingsPanel } from '../settings-section.svelte'

  const audiences = $derived([
    { id: 'everyone' as const, label: t('Все') },
    { id: 'friends' as const, label: t('Друзья') },
    { id: 'nobody' as const, label: t('Никто') },
  ])
  const rows = [
    { key: 'privacy.playlists', title: 'Плейлисты', hint: 'Все плейлисты разом; один — «Скрыть от других» в его меню' },
    { key: 'privacy.likes', title: 'Любимые', hint: 'Треки с лайком' },
    { key: 'privacy.now_playing', title: 'Что играет сейчас', hint: 'Трек, который звучит прямо сейчас' },
    { key: 'privacy.stats', title: 'Статистика', hint: 'Прослушивания, часы и любимые артисты' },
  ] as const
  const social = [
    // писать — только друзьям (антиспам, ROADMAP «Личные сообщения»): «Все» здесь нет
    { key: 'privacy.messages', title: 'Кто может писать мне', hint: 'Личные сообщения и треки от других', friendsOnly: true },
    { key: 'privacy.room_invites', title: 'Кто может звать в комнату', hint: 'Приглашения слушать вместе', friendsOnly: false },
    { key: 'privacy.room_visible', title: 'Кто видит мою комнату', hint: 'Можно зайти без приглашения', friendsOnly: false },
  ] as const
  const hiddenCount = $derived((settings.get('privacy.hidden_playlists') ?? []).length)

  function preview() {
    settingsPanel.close()
    router.go('profile')
  }
</script>

<Group title={t('Друзья')} hint={t('Друзья и заявки заработают вместе с сервером')}>
  <Choice
    title={t('Кто может добавить в друзья')}
    hint={t('Остальные не смогут отправить заявку')}
    value={settings.get('privacy.friend_requests')}
    options={[
      { id: 'everyone' as const, label: t('Все') },
      { id: 'fof' as const, label: t('Друзья друзей') },
      { id: 'nobody' as const, label: t('Никто') },
    ]}
    onchange={(v) => settings.set('privacy.friend_requests', v)}
  />
</Group>

<Group title={t('Комнаты и сообщения')} hint={t('Заработают вместе с сервером и друзьями')}>
  {#each social as r (r.key)}
    <Choice
      title={t(r.title)}
      hint={t(r.hint)}
      value={r.friendsOnly && audienceOf(settings.get(r.key)) === 'everyone' ? 'friends' : audienceOf(settings.get(r.key))}
      options={r.friendsOnly ? audiences.filter((a) => a.id !== 'everyone') : audiences}
      onchange={(v) => settings.set(r.key, v)}
    />
  {/each}
  <button class="link-row" onclick={() => (settingsPanel.close(), router.go('social'))}>{t('Как это будет выглядеть')}</button>
</Group>

<Group title={t('Профиль')} hint={t('Кто что видит по ссылке на твой профиль')}>
  {#each rows as r (r.key)}
    <Choice
      title={t(r.title)}
      hint={t(r.hint)}
      value={audienceOf(settings.get(r.key))}
      options={audiences}
      onchange={(v) => settings.set(r.key, v)}
    />
  {/each}
  {#if hiddenCount}
    <p class="note">
      {tn(hiddenCount, ['{n} плейлист скрыт ото всех', '{n} плейлиста скрыты ото всех', '{n} плейлистов скрыты ото всех']).replace('{n}', String(hiddenCount))}
      <button class="link" onclick={() => settings.set('privacy.hidden_playlists', [])}>{t('Открыть все')}</button>
    </p>
  {/if}
</Group>

<button class="see press" onclick={preview}>
  <Icon name="eye" size={16} />{t('Как видят мой профиль')}
</button>

<style>
  .note {
    margin: 4px 0 0;
    color: var(--text-2);
    font-size: calc(13px * var(--fs, 1));
  }
  .link {
    margin-left: 6px;
    color: var(--accent);
    font-weight: 600;
  }
  .link:hover {
    text-decoration: underline;
  }
  .link-row {
    align-self: flex-start;
    margin-top: 4px;
    color: var(--accent);
    font-weight: 600;
    font-size: calc(13px * var(--fs, 1));
  }
  .link-row:hover {
    text-decoration: underline;
  }
  .see {
    display: inline-flex;
    align-items: center;
    align-self: flex-start;
    gap: 8px;
    height: 36px;
    margin-top: 8px;
    padding: 0 16px;
    border-radius: 10px;
    background: var(--accent);
    color: var(--accent-ink);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    transition:
      filter var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .see:hover {
    filter: brightness(1.08);
  }
  .see:active {
    transform: scale(0.97);
  }
</style>
