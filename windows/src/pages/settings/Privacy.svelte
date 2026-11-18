<script lang="ts">
  // Аккаунт → Приватность (решение владельца 2026-11-18): что гость видит по ссылке на профиль.
  // Скрытое не попадает в `PublicProfile` вовсе (lib/public-profile.ts); сервер потом — по тем же ключам.
  import Switch from '../../components/settings/Switch.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Icon from '../../components/Icon.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { t } from '../../lib/i18n.svelte'
  import { router } from '../../app/router.svelte'
  import { settingsPanel } from '../settings-section.svelte'

  function preview() {
    settingsPanel.close()
    router.go('profile')
  }
</script>

<Switch
  title={t('Что играет сейчас')}
  hint={t('Трек, который звучит прямо сейчас')}
  on={settings.get('privacy.now_playing')}
  onchange={(v) => settings.set('privacy.now_playing', v)}
/>
<Switch
  title={t('Статистика')}
  hint={t('Прослушивания, часы и любимые артисты')}
  on={settings.get('privacy.stats')}
  onchange={(v) => settings.set('privacy.stats', v)}
/>
<Switch
  title={t('Любимые')}
  hint={t('Треки с лайком')}
  on={settings.get('privacy.likes')}
  onchange={(v) => settings.set('privacy.likes', v)}
/>
<Choice
  title={t('Плейлисты')}
  hint={t('Какие плейлисты Sonar видно')}
  value={settings.get('privacy.playlists')}
  options={[
    { id: 'all' as const, label: t('Все') },
    { id: 'visible' as const, label: t('Кроме скрытых') },
    { id: 'none' as const, label: t('Никакие') },
  ]}
  onchange={(v) => settings.set('privacy.playlists', v)}
/>

<button class="see press" onclick={preview}>
  <Icon name="eye" size={16} />{t('Как видят мой профиль')}
</button>

<style>
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
