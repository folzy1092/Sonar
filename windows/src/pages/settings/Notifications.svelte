<script lang="ts">
  // Аккаунт → Уведомления (SETTINGS_NEXT «Уведомления», с сервером). Пока сервера нет — честная заглушка:
  // фильтры уже работают и показывают, что сюда придёт; сам список (по дням, точка «не прочитано»,
  // «Принять / Отклонить» у заявки) появится вместе с API Sonar.
  import Icon from '../../components/Icon.svelte'
  import type { IconName } from '../../components/icons'
  import { indicator } from '../../lib/indicator'
  import { cascade } from '../../lib/cascade'
  import { t } from '../../lib/i18n.svelte'
  import Group from '../../components/settings/Group.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { newReleases } from '../../lib/new-releases.svelte'

  type Filter = 'all' | 'friends' | 'other'
  const FILTERS: { id: Filter; label: string }[] = [
    { id: 'all', label: 'Все' },
    { id: 'friends', label: 'Друзья' },
    { id: 'other', label: 'Другое' },
  ]
  /** Какие уведомления придут — по SETTINGS_NEXT; `group` — в какой фильтр попадают. */
  const KINDS: { icon: IconName; title: string; text: string; group: Exclude<Filter, 'all'> }[] = [
    { icon: 'user2', title: 'Заявки в друзья', text: 'Принять или отклонить — прямо здесь', group: 'friends' },
    { icon: 'music', title: 'Треки от друзей', text: 'Что тебе скинули в личные сообщения', group: 'friends' },
    { icon: 'sparkles', title: 'Sonar Deep', text: 'Подписка включилась или скоро закончится', group: 'other' },
    { icon: 'download', title: 'Обновления Sonar', text: 'Что нового в свежей версии', group: 'other' },
  ]

  let filter = $state<Filter>('all')
  const shown = $derived(filter === 'all' ? KINDS : KINDS.filter((k) => k.group === filter))
</script>

<!-- работает уже без сервера: ядро само проверяет любимых исполнителей -->
<Group title={t('Новинки исполнителей')} hint={t('Колокольчик справа сверху')}>
  <Switch
    title={t('Новинки исполнителей')}
    hint={t('Вышел трек, сингл или альбом у исполнителя, на которого ты подписан или чьи треки лайкаешь, — покажем при запуске и раз в 3 часа')}
    on={settings.get('notify.releases')}
    onchange={(v) => {
      settings.set('notify.releases', v)
      if (v) void newReleases.check()
    }}
  />
</Group>

<div class="chips" role="radiogroup" aria-label={t('Уведомления')} use:indicator={{ key: filter, kind: 'pill' }}>
  {#each FILTERS as f (f.id)}
    <button class:on={filter === f.id} role="radio" aria-checked={filter === f.id} onclick={() => (filter = f.id)}>
      {t(f.label)}
    </button>
  {/each}
</div>

<div class="empty">
  <span class="bell" aria-hidden="true"><Icon name="bell" size={26} /></span>
  <b>{t('Пока тихо')}</b>
  <small>{t('Уведомления появятся вместе с сервером Sonar — здесь, по дням, с точкой у непрочитанных')}</small>
</div>

<p class="what">{t('Что сюда придёт')}</p>
{#key filter}
  <div class="kinds" use:cascade>
    {#each shown as k (k.title)}
      <div class="kind">
        <span class="ic"><Icon name={k.icon} size={17} /></span>
        <span class="txt">
          <b>{t(k.title)}</b>
          <small>{t(k.text)}</small>
        </span>
      </div>
    {/each}
  </div>
{/key}

<style>
  .chips {
    position: relative;
    display: flex;
    gap: 4px;
    width: fit-content;
    padding: 3px;
    border-radius: 999px;
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  .chips :global(.tab-ind.pill) {
    border-radius: 999px;
    background: var(--surface-3);
  }
  .chips button {
    position: relative;
    z-index: 1;
    height: 28px;
    padding: 0 14px;
    border-radius: 999px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    transition: color var(--fast) var(--ease);
  }
  .chips button:hover {
    color: var(--text-2);
  }
  .chips button.on {
    color: var(--text);
    font-weight: 600;
  }
  .empty {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    margin-top: 18px;
    padding: 28px 20px 26px;
    border-radius: 14px;
    background: var(--surface-2);
    text-align: center;
  }
  .bell {
    display: grid;
    place-items: center;
    width: 54px;
    height: 54px;
    margin-bottom: 6px;
    border-radius: 50%;
    background: var(--surface-3);
    color: var(--text-2);
    animation: ring 2.6s var(--ease) 0.4s 1 both;
  }
  .empty b {
    font-size: calc(15px * var(--fs, 1));
  }
  .empty small {
    max-width: 380px;
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.45;
    color: var(--text-3);
  }
  .what {
    margin: 18px 0 8px;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-3);
  }
  .kinds {
    display: grid;
    /* две колонки, в узкой панели — одна */
    grid-template-columns: repeat(auto-fill, minmax(min(100%, max(210px, (100% - 1 * 8px) / 2)), 1fr));
    gap: 8px;
  }
  .kind {
    display: flex;
    align-items: center;
    gap: 11px;
    min-width: 0;
    padding: 11px 12px;
    border-radius: 12px;
    background: var(--surface-2);
    transition: background var(--fast) var(--ease);
  }
  .kind:hover {
    background: var(--hover);
  }
  .ic {
    display: grid;
    flex: none;
    place-items: center;
    width: 34px;
    height: 34px;
    border-radius: 50%;
    background: var(--surface-3);
    color: var(--text-2);
  }
  .txt {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }
  .txt b {
    font-size: calc(13px * var(--fs, 1));
  }
  .txt small {
    font-size: calc(11.5px * var(--fs, 1));
    line-height: 1.35;
    color: var(--text-3);
  }
  @keyframes ring {
    0%,
    100% {
      transform: rotate(0);
    }
    8% {
      transform: rotate(14deg);
    }
    16% {
      transform: rotate(-12deg);
    }
    24% {
      transform: rotate(8deg);
    }
    32% {
      transform: rotate(-5deg);
    }
    40% {
      transform: rotate(0);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .bell {
      animation: none;
    }
  }
</style>
