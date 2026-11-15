<script lang="ts">
  // Интеграции → Приложения (pc/Screenshot_14): Discord RPC — «Слушает Sonar» в профиле Discord.
  // ID приложения Discord пользователь не вводит: он вшит в сборку, потом приходит с сервера (`GET /config`).
  // Last.fm и ключ API — вместе с сервером.
  import Switch from '../../components/settings/Switch.svelte'
  import Group from '../../components/settings/Group.svelte'
  import { settings } from '../../lib/settings.svelte'
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


<p class="later">Last.fm и ключ API («сейчас играет» для своих сервисов) появятся вместе с сервером.</p>

<style>
  .later {
    margin: 20px 0 0;
    font-size: 12px;
    color: var(--text-3);
  }
</style>
