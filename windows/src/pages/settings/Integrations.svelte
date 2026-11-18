<script lang="ts">
  // Интеграции → Приложения (переделано по референсу владельца 2026-11-16): у каждой группы — знак
  // сервиса. Discord: состояние (подключён / ожидание Discord), главный переключатель, параметры
  // отображения вместе с кнопками профиля «Слушать в Sonar» и «Скачать Sonar». OBS — ссылка с токеном:
  // скопировать, новая ссылка, выключить плашку.
  import Icon from '../../components/Icon.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Select from '../../components/settings/Select.svelte'
  import Group from '../../components/settings/Group.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { api, errorText } from '../../lib/api'
  import { toast } from '../../lib/toast.svelte'
  import { onMount } from 'svelte'
  import { t } from '../../lib/i18n.svelte'

  let obs = $state<{ url: string; ok: boolean }>({ url: '', ok: true })
  let copied = $state(false)
  let discord = $state<{ enabled: boolean; connected: boolean } | null>(null)
  let tokenSpin = $state(0)

  const discordOn = $derived(settings.get('integrations.discord.enabled'))

  onMount(() => {
    api.obsStatus().then((s) => (obs = s)).catch(() => {})
    // состояние Discord — раз в 2 с, пока открыт раздел (Discord могут запустить прямо сейчас)
    const poll = () => api.discordStatus().then((s) => (discord = s)).catch(() => {})
    void poll()
    const timer = setInterval(poll, 2000)
    return () => clearInterval(timer)
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

  async function newToken() {
    tokenSpin++
    try {
      obs = await api.obsNewToken()
      toast.show(t('Новая ссылка — старая больше не работает'))
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  function dropToken() {
    settings.set('obs.token', '')
    obs = { ...obs, url: '' }
    toast.show(t('Плашка выключена — нажми ↻, чтобы получить новую ссылку'))
  }
</script>

{#snippet discordIcon()}<span class="brand discord"><Icon name="discord" size={18} filled /></span>{/snippet}
{#snippet obsIcon()}<span class="brand obs"><Icon name="obs" size={18} /></span>{/snippet}

<Group title="Discord RPC" icon={discordIcon}>
  <div class="state" class:on={discord?.connected && discordOn} class:wait={discordOn && !discord?.connected}>
    <span class="dot"></span>
    <div>
      <b>
        {#if !discordOn}{t('Выключено')}{:else if discord?.connected}{t('Discord подключён')}{:else}{t('Ожидание Discord…')}{/if}
      </b>
      <small>
        {#if !discordOn}{t('Включи активность, чтобы друзья видели, что ты слушаешь')}{:else if discord?.connected}{t('Статус «Слушает» обновляется вместе с треком')}{:else}{t('Запусти Discord на этом компьютере — Sonar подключится сам')}{/if}
      </small>
    </div>
  </div>
  <Switch title={t('Активность в Discord')} hint={t('Показывать в профиле, что ты слушаешь')} on={discordOn} onchange={(v) => settings.set('integrations.discord.enabled', v)} />
</Group>

<div class="sub" class:dim={!discordOn}>
  <Group title={t('Параметры отображения')}>
    <div class="card">
      <Select
        title={t('Формат статуса')}
        hint={t('Что видно в заголовке «Слушает …»')}
        value={settings.get('integrations.discord.status_format')}
        options={[
          { id: 'artist', label: t('Исполнитель (по умолчанию)') },
          { id: 'title', label: t('Название трека') },
          { id: 'artist_title', label: t('Исполнитель — Трек') },
          { id: 'title_artist', label: t('Трек — Исполнитель') },
          { id: 'app', label: 'Sonar' },
        ]}
        onchange={(v) => settings.set('integrations.discord.status_format', v)}
      />
      <Switch title={t('Шкала времени трека')} hint={t('Прошедшее и оставшееся время')} on={settings.get('integrations.discord.progress')} onchange={(v) => settings.set('integrations.discord.progress', v)} />
      <Switch title={t('Обложка трека')} hint={t('Обложка альбома в карточке активности')} on={settings.get('integrations.discord.cover')} onchange={(v) => settings.set('integrations.discord.cover', v)} />
      <Switch title={t('Мини-фото артиста')} hint={t('Маленький значок в углу обложки')} on={settings.get('integrations.discord.artist_photo')} onchange={(v) => settings.set('integrations.discord.artist_photo', v)} />
      <Switch title={t('Показывать при паузе')} hint={t('Статус остаётся со значком паузы')} on={settings.get('integrations.discord.show_paused')} onchange={(v) => settings.set('integrations.discord.show_paused', v)} />
      <Switch title={t('Кнопка «Слушать в Sonar»')} hint={t('Ссылка на этот трек в Sonar')} on={settings.get('integrations.discord.button_listen')} onchange={(v) => settings.set('integrations.discord.button_listen', v)} />
      <Switch title={t('Кнопка «Скачать Sonar»')} hint={t('Ссылка на последнюю версию приложения')} on={settings.get('integrations.discord.button_download')} onchange={(v) => settings.set('integrations.discord.button_download', v)} />
    </div>
  </Group>
</div>

<Group title="OBS Studio" icon={obsIcon}>
  {#if obs.url}
    <div class="link selectable">{obs.url}</div>
  {:else}
    <div class="link off">{t('Плашка выключена — нажми ↻, чтобы получить ссылку')}</div>
  {/if}
  {#if !obs.ok}
    <p class="warn">{t('Порт 53119 занят другой программой — закрой её и перезапусти Sonar.')}</p>
  {/if}
  <div class="tools">
    <button class="copy" class:done={copied} disabled={!obs.url} onclick={copyObs}>
      {#key copied}<span class="swap">{copied ? t('Скопировано') : t('Скопировать')} <Icon name={copied ? 'check' : 'copy'} size={15} /></span>{/key}
    </button>
    <button class="sq" aria-label={t('Новая ссылка')} title={t('Новая ссылка (старая перестанет работать)')} onclick={newToken}>
      <span class="spin" style:rotate="{tokenSpin * 360}deg"><Icon name="refresh" size={15} /></span>
    </button>
    <button class="sq" aria-label={t('Выключить плашку')} title={t('Выключить плашку')} disabled={!obs.url} onclick={dropToken}>
      <Icon name="trash" size={15} />
    </button>
  </div>
  <Choice
    title={t('Размер плашки')}
    hint={t('Габариты на экране стрима')}
    wide
    value={settings.get('obs.size')}
    options={[
      { id: 'standard', label: t('Стандартный') },
      { id: 'compact', label: t('Компактный') },
    ]}
    onchange={(v) => settings.set('obs.size', v)}
  />
  <Switch
    title={t('Скрывать при паузе')}
    hint={t('Плавно убирать плашку со стрима, когда трек остановлен')}
    on={settings.get('obs.hide_paused')}
    onchange={(v) => settings.set('obs.hide_paused', v)}
  />
</Group>

<Group title={t('Как подключить в OBS?')}>
  <ol>
    <li><i>1</i> {t('В OBS добавьте источник «Браузер»')}</li>
    <li><i>2</i> {t('Вставьте скопированную ссылку в поле «URL»')}</li>
    <li><i>3</i> {t('Укажите размер: ширина {w}, высота {h}', settings.get('obs.size') === 'compact' ? { w: 320, h: 72 } : { w: 450, h: 130 })}</li>
  </ol>
</Group>

<style>
  .brand {
    display: grid;
    place-items: center;
  }
  .brand.discord {
    color: #5865f2;
  }
  .brand.obs {
    color: var(--text-2);
  }
  .state {
    display: flex;
    align-items: center;
    gap: 12px;
    margin: 4px 0 6px;
    padding: 12px 14px;
    border-radius: 14px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    transition: border-color var(--normal) var(--ease);
  }
  .state div {
    display: grid;
  }
  .state b {
    font-size: calc(13px * var(--fs, 1));
  }
  .state small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .dot {
    flex: none;
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: var(--text-3);
    transition: background var(--normal) var(--ease);
  }
  .state.on {
    border-color: color-mix(in srgb, var(--online) 35%, transparent);
  }
  .state.on .dot {
    background: var(--online);
    box-shadow: 0 0 10px var(--online);
  }
  .state.wait .dot {
    background: #f5b942;
    animation: wait 1.4s ease-in-out infinite;
  }
  @keyframes wait {
    50% {
      opacity: 0.3;
      scale: 0.7;
    }
  }
  .sub {
    transition: opacity var(--normal) var(--ease);
  }
  .sub.dim {
    opacity: 0.45;
  }
  .card {
    padding: 4px 14px;
    border-radius: 16px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  .link.off {
    color: var(--text-3);
    font-style: italic;
  }
  .spin {
    display: grid;
    transition: rotate 0.6s var(--ease);
  }
  .link {
    padding: 11px 14px;
    border-radius: 10px;
    background: var(--plate);
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .tools {
    display: flex;
    flex-wrap: wrap;
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
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    font-size: calc(13px * var(--fs, 1));
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
    font-size: calc(12px * var(--fs, 1));
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
    font-size: calc(12px * var(--fs, 1));
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
    font-size: calc(11px * var(--fs, 1));
    font-weight: 600;
  }
</style>
