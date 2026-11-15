<script lang="ts">
  // Интеграции → Приложения по pc/Screenshot_14, 15: Discord RPC, плашка OBS (Sonar сам отдаёт её на
  // 127.0.0.1:53119/obs — obs.rs), Last.fm — с сервером («Скоро»). ID приложения Discord пользователь не вводит: он вшит в сборку, потом
  // приходит с сервера (`GET /config`).
  import Icon from '../../components/Icon.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Group from '../../components/settings/Group.svelte'
  import Soon from '../../components/settings/Soon.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { api } from '../../lib/api'
  import { toast } from '../../lib/toast.svelte'
  import { onMount } from 'svelte'

  const OBS_FALLBACK = 'http://127.0.0.1:53119/obs'
  let obs = $state<{ url: string; ok: boolean }>({ url: OBS_FALLBACK, ok: true })
  let copied = $state(false)

  onMount(() => {
    api.obsStatus().then((s) => (obs = s)).catch(() => {})
  })

  async function copyObs() {
    try {
      await navigator.clipboard.writeText(obs.url)
      copied = true
      setTimeout(() => (copied = false), 1600)
    } catch {
      toast.show(obs.url)
    }
  }
</script>

<Group title="Discord RPC">
  <Switch
    title="Активность в Discord"
    hint="Показывать в Discord, что вы слушаете"
    on={settings.get('integrations.discord.enabled')}
    onchange={(v) => settings.set('integrations.discord.enabled', v)}
  />
  <Switch
    title="Кастомная обложка"
    hint="Отображать оригинальную обложку трека в статусе"
    on={settings.get('integrations.discord.cover')}
    onchange={(v) => settings.set('integrations.discord.cover', v)}
  />
  <Switch
    title="Прогресс воспроизведения"
    hint="Показывать оставшееся время прослушивания трека"
    on={settings.get('integrations.discord.progress')}
    onchange={(v) => settings.set('integrations.discord.progress', v)}
  />
</Group>

<Group title="Last.fm">
  <div class="account">
    <span class="av"><Icon name="brandLastfm" size={26} /></span>
    <b>Подключить Last.fm <Soon /></b>
    <small>Вход появится вместе с сервером Sonar</small>
  </div>
  <Switch title="История прослушиваний" hint="Сохранять прослушанные треки" on={true} soon />
  <Switch title="Сейчас играет" hint="Показывать текущий трек в профиле" on={true} soon />
</Group>

<Group title="OBS Studio">
  <div class="link selectable">{obs.url}</div>
  {#if !obs.ok}
    <p class="warn">Порт 53119 занят другой программой — закрой её и перезапусти Sonar.</p>
  {/if}
  <div class="tools">
    <button class="copy" class:done={copied} onclick={copyObs}>
      {#key copied}<span class="swap"><Icon name={copied ? 'check' : 'copy'} size={15} /> {copied ? 'Скопировано' : 'Скопировать'}</span>{/key}
    </button>
    <button class="sq" aria-label="Открыть в браузере" title="Посмотреть плашку в браузере" onclick={() => api.openUrl(obs.url).catch(() => toast.show(obs.url))}>
      <Icon name="share" size={15} />
    </button>
  </div>
  <Choice
    title="Размер плашки"
    hint="Габариты на экране стрима"
    wide
    value={settings.get('obs.size')}
    options={[
      { id: 'standard', label: 'Стандартный' },
      { id: 'compact', label: 'Компактный' },
    ]}
    onchange={(v) => settings.set('obs.size', v)}
  />
  <Switch
    title="Скрывать при паузе"
    hint="Плавно убирать плашку со стрима, когда трек остановлен"
    on={settings.get('obs.hide_paused')}
    onchange={(v) => settings.set('obs.hide_paused', v)}
  />
</Group>

<Group title="Как подключить в OBS?">
  <ol>
    <li><i>1</i> В OBS добавьте источник «Браузер»</li>
    <li><i>2</i> Вставьте скопированную ссылку в поле «URL»</li>
    <li><i>3</i> Укажите размер: {settings.get('obs.size') === 'compact' ? 'ширина 320, высота 72' : 'ширина 450, высота 130'}</li>
  </ol>
</Group>

<style>
  .account {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    padding: 22px 12px 18px;
    margin-bottom: 6px;
    border-radius: 16px;
    background: linear-gradient(180deg, var(--surface-2) 50%, var(--plate) 50%);
    text-align: center;
  }
  .av {
    display: grid;
    place-items: center;
    width: 64px;
    height: 64px;
    margin-bottom: 6px;
    border-radius: 50%;
    background: var(--surface-3);
    color: #d51007;
  }
  .account b {
    font-size: 14px;
  }
  .account small {
    font-size: 12px;
    color: var(--text-3);
  }
  .link {
    padding: 11px 14px;
    border-radius: 10px;
    background: var(--plate);
    font-size: 12px;
    color: var(--text-3);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .tools {
    display: flex;
    gap: 6px;
    margin: 6px 0 4px;
  }
  .copy,
  .sq {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    height: 36px;
    border-radius: 10px;
    border: 1px solid var(--border);
    font-size: 13px;
    color: var(--text-2);
  }
  .copy {
    flex: 1;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .copy:hover,
  .sq:hover {
    background: var(--hover);
    color: var(--text);
  }
  .copy:active,
  .sq:active {
    transform: scale(0.97);
  }
  .copy.done {
    color: var(--text);
  }
  .swap {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    animation: tab-in var(--normal) var(--ease);
  }
  .warn {
    margin: 6px 0 0;
    font-size: 12px;
    color: var(--danger);
  }
  .sq {
    width: 36px;
  }
  button:disabled {
    cursor: default;
    opacity: 0.6;
  }
  ol {
    margin: 4px 0 0;
    padding: 0;
    list-style: none;
    display: flex;
    flex-direction: column;
    gap: 10px;
    font-size: 12px;
    color: var(--text-2);
  }
  li {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  li i {
    display: grid;
    place-items: center;
    width: 20px;
    height: 20px;
    border-radius: 50%;
    background: var(--surface-3);
    font-style: normal;
    font-size: 11px;
    font-weight: 600;
  }
</style>
