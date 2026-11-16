<script lang="ts">
  // Система → Обновления (ROADMAP W6). Тексты состояний — как у Dotify («Проверка…»,
  // «Обновлений нет», «Доступно обновление», «Что нового», «Обновить» / «Установить»).
  // Сверху — карточка версии с кнопкой по состоянию, ниже переключатели и история версий.
  import { onMount } from 'svelte'
  import Icon from '../../components/Icon.svelte'
  import Group from '../../components/settings/Group.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import logo from '../../assets/logo-mark.svg'
  import { settings } from '../../lib/settings.svelte'
  import { updater } from '../../lib/updater.svelte'
  import { agoText, sizeText } from '../../lib/update-core'
  import { cascade } from '../../lib/cascade'
  import { api } from '../../lib/api'
  import { toast } from '../../lib/toast.svelte'
  import { lang, t } from '../../lib/i18n.svelte'

  let now = $state(Date.now())
  onMount(() => {
    void updater.loadChangelog()
    const timer = setInterval(() => (now = Date.now()), 30_000)
    return () => clearInterval(timer)
  })

  const p = $derived(updater.phase)
  const status = $derived.by(() => {
    if (p === 'checking') return t('Поиск обновлений…')
    if (p === 'available') return t('Доступна версия {version}', { version: updater.version })
    if (p === 'downloading') return t('Загрузка… {size}', { size: sizeText(updater.got, updater.total) })
    if (p === 'ready') return t('Версия {version} скачана', { version: updater.version })
    if (p === 'installing') return t('Устанавливаю и перезапускаю…')
    if (p === 'error') return updater.error
    if (p === 'none') return t('Вы используете актуальную версию · проверено {ago}', { ago: agoText(updater.checkedAt ?? now, now) })
    return updater.checkedAt ? t('Проверено {ago}', { ago: agoText(updater.checkedAt, now) }) : t('Ещё не проверяли')
  })
  const fresh = $derived(p === 'available' || p === 'downloading' || p === 'ready' || p === 'installing')
  const LOCALES = { ru: 'ru-RU', en: 'en-US', uk: 'uk-UA' } as const
  const dateText = (d: string) => {
    const ms = Date.parse(d)
    return Number.isNaN(ms) ? d : new Date(ms).toLocaleDateString(LOCALES[lang()], { day: 'numeric', month: 'long', year: 'numeric' })
  }

  async function addToStart() {
    try {
      toast.show((await api.addToStartMenu()) ? t('Sonar добавлен в меню «Пуск»') : t('Sonar уже есть в меню «Пуск»'))
    } catch (e) {
      toast.show(String(e))
    }
  }
  async function pinToTaskbar() {
    try {
      await api.revealStartShortcut()
      toast.show(t('ПКМ по Sonar → «Закрепить на панели задач» (в Windows 11 — «Показать дополнительные параметры»)'))
    } catch (e) {
      toast.show(String(e))
    }
  }
</script>

<div class="card" class:fresh>
  <div class="mark" class:spin={p === 'checking' || p === 'installing'}>
    <img src={logo} alt="" />
  </div>
  <div class="info">
    <b>
      {#if fresh}{t('Доступно обновление')}{:else if p === 'none'}{t('Обновлений нет')}{:else}Sonar {updater.current}{/if}
    </b>
    {#key status}
      <small class="status" class:err={p === 'error'}>{status}</small>
    {/key}
  </div>
  <div class="act">
    {#if p === 'available'}
      <button class="btn primary" onclick={() => updater.download()}><Icon name="download" size={16} /> {t('Обновить')}</button>
    {:else if p === 'ready'}
      <button class="btn primary" onclick={() => updater.install()}><Icon name="refresh" size={16} /> {t('Установить')}</button>
    {:else if p === 'error'}
      <button class="btn" onclick={() => updater.retry()}><Icon name="refresh" size={16} /> {t('Повторить')}</button>
    {:else}
      <button class="btn" disabled={updater.busy} onclick={() => updater.check()}>
        <Icon name="refresh" size={16} />
        {p === 'checking' ? t('Проверка…') : t('Проверить')}
      </button>
    {/if}
  </div>
  {#if p === 'downloading' || p === 'ready' || p === 'installing'}
    <div class="bar"><i style:transform="scaleX({p === 'downloading' ? updater.progress : 1})"></i></div>
  {/if}
</div>

{#if fresh && updater.notes.length}
  <Group title={t('Что нового в {version}', { version: updater.version })}>
    <ul class="notes" use:cascade={updater.version}>
      {#each updater.notes as n, i (i)}
        <li>{n}</li>
      {/each}
    </ul>
  </Group>
{/if}

<Group title={t('Быстрый доступ')}>
  <p class="pin-hint">
    {t('Windows не даёт программе закрепить себя тихо, поэтому панель задач — в два клика: покажем ярлык, останется нажать «Закрепить».')}
  </p>
  <div class="pins">
    <button class="btn" onclick={addToStart}><Icon name="grid" size={16} /> {t('Добавить в меню «Пуск»')}</button>
    <button class="btn" onclick={pinToTaskbar}><Icon name="layoutBottom" size={16} /> {t('Закрепить на панели задач')}</button>
  </div>
</Group>

<Group title={t('Проверка')}>
  <Switch
    title={t('Проверять обновления')}
    hint={t('При запуске и раз в 6 часов. Найдётся новая версия — появится окно с изменениями')}
    on={settings.get('update.auto_check')}
    onchange={(v) => settings.set('update.auto_check', v)}
  />
  <Switch
    title={t('Скачивать в фоне')}
    hint={t('Обновление скачается само, установится только по кнопке «Установить»')}
    on={settings.get('update.auto_download')}
    onchange={(v) => settings.set('update.auto_download', v)}
  />
</Group>

<Group title={t('История версий')}>
  {#if updater.changelog === null}
    <div class="skel ph"></div>
  {:else if updater.changelog.length === 0}
    <p class="empty">{t('Здесь появятся изменения каждой версии — вместе с первым обновлением.')}</p>
  {:else}
    <div class="history" use:cascade>
      {#each updater.changelog as e (e.version)}
        <article class:current={e.version === updater.current}>
          <header>
            <b>{e.version}</b>
            {#if e.version === updater.current}<span class="tag">{t('У вас')}</span>{/if}
            {#if e.title}<span class="title">{e.title}</span>{/if}
            <small>{dateText(e.date)}</small>
          </header>
          <ul>
            {#each e.changes as c, i (i)}<li>{c}</li>{/each}
          </ul>
        </article>
      {/each}
    </div>
  {/if}
</Group>

<style>
  .pin-hint {
    margin: 0 0 10px;
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.5;
    color: var(--text-3);
  }
  .pins {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .card {
    position: relative;
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 14px 16px;
    border-radius: 16px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    overflow: hidden;
    transition:
      border-color var(--normal) var(--ease),
      background var(--normal) var(--ease);
  }
  .card.fresh {
    border-color: color-mix(in srgb, var(--accent) 45%, transparent);
    background: color-mix(in srgb, var(--accent) 8%, var(--plate));
  }
  .mark {
    display: grid;
    place-items: center;
    width: 48px;
    height: 48px;
    flex: none;
  }
  .mark img {
    width: 44px;
    height: 44px;
    transition: transform var(--normal) var(--ease);
  }
  .card:hover .mark img {
    transform: scale(1.05) rotate(-4deg);
  }
  .mark.spin img {
    animation: upd-spin 1.1s linear infinite;
  }
  @keyframes upd-spin {
    to {
      transform: rotate(360deg);
    }
  }
  .info {
    flex: 1;
    min-width: 0;
    display: grid;
  }
  .info b {
    font-family: var(--font-display);
    font-size: calc(17px * var(--fs, 1));
    font-weight: 700;
  }
  .status {
    grid-row: 2;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    animation: tab-in var(--normal) var(--ease);
  }
  .status.err {
    color: var(--danger);
  }
  .btn {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 38px;
    padding: 0 16px;
    border-radius: 12px;
    background: var(--surface-3);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    white-space: nowrap;
    animation: tab-in var(--normal) var(--ease);
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease),
      opacity var(--fast) var(--ease);
  }
  .btn:hover:not(:disabled) {
    background: var(--hover);
  }
  .btn:active:not(:disabled) {
    transform: scale(0.96);
  }
  .btn:disabled {
    opacity: 0.55;
    cursor: default;
  }
  .btn.primary {
    background: var(--accent);
    color: var(--accent-ink);
    border-color: transparent;
  }
  .btn.primary:hover {
    background: color-mix(in srgb, var(--accent) 88%, white);
  }
  .bar {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    height: 3px;
    background: color-mix(in srgb, var(--accent) 18%, transparent);
    animation: tab-in var(--normal) var(--ease);
  }
  .bar i {
    display: block;
    height: 100%;
    background: var(--accent);
    transform-origin: left;
    transition: transform 0.25s var(--ease);
  }
  .notes,
  article ul {
    margin: 0;
    padding: 0;
    list-style: none;
  }
  .notes li {
    position: relative;
    padding: 4px 0 4px 14px;
    font-size: calc(13px * var(--fs, 1));
    line-height: 1.45;
  }
  .notes li::before {
    content: '';
    position: absolute;
    left: 2px;
    top: 12px;
    width: 4px;
    height: 4px;
    border-radius: 50%;
    background: var(--accent);
  }
  .empty {
    margin: 4px 0;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .history {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  article {
    padding: 12px 14px;
    border-radius: 14px;
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    transition: border-color var(--fast) var(--ease);
  }
  article:hover {
    border-color: var(--border-strong);
  }
  article header {
    display: flex;
    align-items: baseline;
    gap: 8px;
    margin-bottom: 6px;
  }
  article header b {
    font-family: var(--font-display);
    font-size: calc(15px * var(--fs, 1));
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
  .tag {
    padding: 2px 8px;
    border-radius: 999px;
    background: var(--accent);
    color: var(--accent-ink);
    font-size: calc(11px * var(--fs, 1));
    font-weight: 700;
  }
  .title {
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
  }
  article header small {
    margin-left: auto;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  article li {
    position: relative;
    padding: 3px 0 3px 14px;
    font-size: calc(13px * var(--fs, 1));
    line-height: 1.45;
    color: var(--text-2);
  }
  article li::before {
    content: '';
    position: absolute;
    left: 2px;
    top: 11px;
    width: 4px;
    height: 4px;
    border-radius: 50%;
    background: var(--text-3);
  }
  .ph {
    height: 90px;
    border-radius: 14px;
  }
</style>
