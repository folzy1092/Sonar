<script lang="ts">
  // Система → О приложении: знак, версия, канал новостей, «Сбросить настройки».
  import Icon from '../../components/Icon.svelte'
  import Group from '../../components/settings/Group.svelte'
  import logo from '../../assets/logo-mark.svg'
  import { api } from '../../lib/api'
  import { settings } from '../../lib/settings.svelte'
  import { toast } from '../../lib/toast.svelte'
  import { updater } from '../../lib/updater.svelte'
  import { settingsPanel } from '../settings-section.svelte'

  const CHANNEL = 'https://t.me/SonarUpdates'
  let confirm = $state(false)

  async function reset() {
    try {
      await api.resetSettings()
      await settings.reload()
      toast.show('Настройки сброшены')
    } catch (e) {
      toast.show(String(e))
    }
    confirm = false
  }
</script>

<div class="head">
  <img src={logo} alt="" />
  <div>
    <b>Sonar</b>
    <small>Версия {updater.current} · автономный режим</small>
  </div>
</div>

<Group title="Обновления">
  <button class="btn" onclick={() => settingsPanel.show('system', 'update')}>
    <Icon name="download" size={16} />
    {updater.phase === 'available' || updater.phase === 'ready' ? `Доступна версия ${updater.version}` : 'Проверить обновления'}
  </button>
</Group>

<Group title="Новости">
  <button class="btn" onclick={() => api.openUrl(CHANNEL).catch(() => toast.show(CHANNEL))}>
    <Icon name="share" size={16} /> Телеграм-канал @SonarUpdates
  </button>
</Group>

<Group title="Сброс">
  <p class="hint">Все настройки вернутся к значениям по умолчанию. Лайки, плейлисты, история и подключённые сервисы останутся.</p>
  {#if confirm}
    <div class="confirm">
      <button class="btn danger" onclick={reset}>Да, сбросить</button>
      <button class="btn" onclick={() => (confirm = false)}>Отмена</button>
    </div>
  {:else}
    <button class="btn" onclick={() => (confirm = true)}><Icon name="refresh" size={16} /> Сбросить настройки</button>
  {/if}
</Group>

<style>
  .head {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 6px 0 4px;
  }
  .head img {
    width: 52px;
    height: 52px;
  }
  .head div {
    display: flex;
    flex-direction: column;
  }
  .head b {
    font-family: var(--font-display);
    font-size: 22px;
    font-weight: 800;
  }
  .head small,
  .hint {
    font-size: 12px;
    color: var(--text-3);
  }
  .hint {
    margin: 0 0 10px;
    line-height: 1.5;
  }
  .btn {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 38px;
    padding: 0 16px;
    border-radius: 12px;
    background: var(--plate);
    border: 1px solid var(--border);
    font-size: 13px;
    font-weight: 600;
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .btn:hover {
    background: var(--hover);
  }
  .btn:active {
    transform: scale(0.96);
  }
  .btn.danger {
    color: var(--danger);
    border-color: color-mix(in srgb, var(--danger) 40%, transparent);
  }
  .confirm {
    display: flex;
    gap: 8px;
    animation: tab-in var(--normal) var(--ease);
  }
</style>
