<script lang="ts">
  // Интеграции → Приложения (pc/Screenshot_14): Discord RPC — «Слушает Sonar» в профиле Discord.
  // Last.fm и ключ API — вместе с сервером.
  import Switch from '../../components/settings/Switch.svelte'
  import Group from '../../components/settings/Group.svelte'
  import { settings } from '../../lib/settings.svelte'

  let appId = $state(settings.get('integrations.discord.app_id'))
  const saveId = () => settings.set('integrations.discord.app_id', appId.trim())
</script>

<Group title="Discord RPC">
  <Switch
    title="Активность в Discord"
    hint="Показывать в Discord, что ты слушаешь (нужен запущенный Discord)"
    on={settings.get('integrations.discord.enabled')}
    onchange={(v) => settings.set('integrations.discord.enabled', v)}
  />
  <Switch
    title="Обложка трека"
    hint="Показывать обложку трека в статусе"
    on={settings.get('integrations.discord.cover')}
    onchange={(v) => settings.set('integrations.discord.cover', v)}
  />
  <Switch
    title="Прогресс воспроизведения"
    hint="Показывать, сколько осталось до конца трека"
    on={settings.get('integrations.discord.progress')}
    onchange={(v) => settings.set('integrations.discord.progress', v)}
  />
</Group>

<label class="field">
  <b>ID приложения Discord</b>
  <small>Создай приложение «Sonar» на discord.com/developers и вставь его Application ID — имя приложения Discord пишет в статусе.</small>
  <input bind:value={appId} onchange={saveId} placeholder="1234567890123456789" inputmode="numeric" spellcheck="false" />
</label>

<p class="later">Last.fm и ключ API («сейчас играет» для своих сервисов) появятся вместе с сервером.</p>

<style>
  .field {
    display: flex;
    flex-direction: column;
    gap: 3px;
    margin-top: 12px;
  }
  .field b {
    font-size: 14px;
    font-weight: 600;
  }
  .field small {
    font-size: 12px;
    line-height: 1.45;
    color: var(--text-3);
  }
  .field input {
    height: 38px;
    margin-top: 8px;
    padding: 0 12px;
    border-radius: 10px;
    background: var(--plate);
    border: 1px solid var(--border);
    outline: none;
    transition: border-color var(--fast) var(--ease);
  }
  .field input:focus {
    border-color: var(--border-strong);
  }
  .later {
    margin: 20px 0 0;
    font-size: 12px;
    color: var(--text-3);
  }
</style>
