<script module lang="ts">
  import type { ServiceId } from '../../lib/services'

  /** Общая на все карточки «занятость»: пока идёт вход или проверка ключа, кнопки остальных тоже ждут. */
  export interface ServiceLock {
    /** Вход в браузере/окне идёт у этого сервиса. */
    waiting: ServiceId | null
    /** Проверяются ключи этого сервиса. */
    busy: ServiceId | null
    /** Код для страницы входа (событие `login:code`), пока ждём вход. */
    code: { service: string; code: string; url: string } | null
  }

  export const FREE_LOCK: ServiceLock = Object.freeze({ waiting: null, busy: null, code: null })
</script>

<script lang="ts">
  // Карточка сервиса в Настройки → Сервисы: шапка (значок, имя, статус, «Отключить»), вход в один клик
  // и ручной ввод ключей — всё из реестра lib/services.ts. Значения полей не уходят ни в ошибки, ни в
  // интерфейс: после успеха поля очищаются, ошибку показываем ту, что вернул Rust.
  import { slide } from 'svelte/transition'
  import SourceIcon from '../../components/SourceIcon.svelte'
  import { t } from '../../lib/i18n.svelte'
  import { api, errorText, type ServiceState, type ServiceStatus } from '../../lib/api'
  import { ICONS } from '../../lib/service-icons'
  import { pop, reducedMotion, xfade } from '../../lib/motion'
  import { toast } from '../../lib/toast.svelte'
  import type { ServiceInfo } from '../../lib/services'

  let {
    info,
    state: current,
    onchange,
    lock = $bindable(FREE_LOCK),
  }: {
    info: ServiceInfo
    state: ServiceState | ServiceStatus | null
    /** Новый статус после входа, ключей или отключения (родитель кладёт его к себе, как раньше). */
    onchange: (next: ServiceStatus) => void
    lock?: ServiceLock
  } = $props()

  const DISCONNECTED: ServiceStatus = Object.freeze({ connected: false, name: null, avatar_url: null })

  const blankValues = (): Record<string, string> => Object.fromEntries(info.keyFields.map((f) => [f.name, '']))

  let values = $state<Record<string, string>>(blankValues())
  let err = $state<string | null>(null)
  /** Ручной ввод ключей раскрыт. */
  let manual = $state(false)

  const isConnected = $derived(!!current?.connected)
  const accountName = $derived(current ? ('account_name' in current ? current.account_name : current.name) : null)
  const premium = $derived(current?.premium === true)
  const statusText = $derived(
    isConnected ? (accountName ? t(info.status.connectedAs, { name: accountName }) : t(info.status.connected)) : t(info.status.disconnected),
  )
  const relogin = $derived(info.reloginLabel !== null && (info.reloginWhen === 'named' ? !!accountName : isConnected))
  const canLogin = $derived(info.caps.login && info.loginLabel !== null)
  const canKey = $derived(info.caps.key && info.keyFields.length > 0)
  const loginText = $derived(
    lock.waiting === info.id ? t(info.loginBusyLabel ?? '') : relogin ? t(info.reloginLabel ?? '') : t(info.loginLabel ?? ''),
  )
  const submitText = $derived(
    lock.busy === info.id ? t('Проверяю…') : isConnected && info.keyReplaceLabel ? t(info.keyReplaceLabel) : t('Подключить'),
  )
  const missingRequired = $derived(info.keyFields.some((f) => !f.optional && !(values[f.name] ?? '').trim()))
  const code = $derived(lock.waiting === info.id && lock.code?.service === info.key ? lock.code : null)
  const iconSize = $derived(ICONS[info.id]?.cardSize ?? 24)

  /** Раскрытие: как раньше slide, при «Меньше движения» — только прозрачность. */
  function reveal(node: Element, params: { duration: number }) {
    return reducedMotion() ? xfade(node, params) : slide(node, params)
  }

  async function copyCode() {
    if (!code) return
    try {
      await navigator.clipboard.writeText(code.code)
      toast.show(t('Код скопирован'))
    } catch {
      toast.show(t('Не получилось скопировать'))
    }
  }

  function cancelLogin() {
    void api.cancelLogin().catch(() => {})
  }

  async function login() {
    lock = { ...lock, waiting: info.id }
    err = null
    try {
      onchange(await api.loginService(info.key))
    } catch (e) {
      err = errorText(e)
    } finally {
      lock = { ...lock, waiting: null, code: null }
    }
  }

  async function connectKey(e: SubmitEvent) {
    e.preventDefault()
    lock = { ...lock, busy: info.id }
    err = null
    try {
      onchange(await api.connectServiceKey(info.id, { ...values }))
      values = blankValues()
    } catch (e2) {
      err = errorText(e2)
    } finally {
      lock = { ...lock, busy: null }
    }
  }

  async function disconnect() {
    await api.disconnectService(info.key).catch(() => {})
    onchange(DISCONNECTED)
  }
</script>

<section class="svc">
  <header>
    <span class="logo {info.id}"><SourceIcon service={info.id} size={iconSize} plain /></span>
    <div>
      <h2>
        {t(info.name)}
        {#if premium}<span class="pill" transition:pop>{t('Премиум')}</span>{/if}
      </h2>
      <p>{statusText}</p>
    </div>
    {#if isConnected}
      <button class="ghost" onclick={disconnect}>{t('Отключить')}</button>
    {/if}
  </header>

  {#if canLogin || canKey}
    <div class="one">
      {#if canLogin}
        <button class="primary big" disabled={lock.waiting !== null} onclick={login}>{loginText}</button>
      {/if}
      {#if canKey}
        <button class="toggle" class:on={manual} onclick={() => (manual = !manual)}>{t('Вручную')}</button>
      {/if}
    </div>
  {/if}
  {#if code}
    <!-- вход в браузере по умолчанию: код вводится на странице сервиса, токен Sonar заберёт сам -->
    <div class="device" transition:reveal={{ duration: 220 }}>
      <p>{t('В браузере открылась страница Яндекса — войди и введи код:')}</p>
      <button class="code" title={t('Скопировать код')} onclick={copyCode}>{code.code}</button>
      <div class="device-actions">
        <button class="ghost" onclick={() => code && api.openUrl(code.url)}>{t('Открыть страницу снова')}</button>
        <button class="ghost" onclick={cancelLogin}>{t('Отмена')}</button>
      </div>
    </div>
  {/if}
  {#if err && !manual}<p class="error">{err}</p>{/if}
  {#if manual && canKey}
    <div transition:reveal={{ duration: 260 }}>
      <form onsubmit={connectKey}>
        {#each info.keyFields as f (f.name)}
          <label>
            <span>{t(f.label)}{#if f.optional}{' '}<em>{t('необязательно')}</em>{/if}</span>
            <input
              bind:value={values[f.name]}
              type={f.secret ? 'password' : 'text'}
              placeholder={f.placeholder ? t(f.placeholder) : undefined}
              autocomplete="off"
              spellcheck="false"
              required={!f.optional}
            />
          </label>
        {/each}
        {#if info.keyHint}
          <p class="hint">{#each info.keyHint as part, i (i)}{#if 'code' in part}<code>{part.code}</code>{:else if 'text' in part}{t(part.text)}{:else}{part.raw}{/if}{/each}</p>
        {/if}
        {#if err}<p class="error">{err}</p>{/if}
        <button class="primary" disabled={lock.busy !== null || missingRequired}>{submitText}</button>
      </form>
    </div>
  {/if}
</section>

<style>
  .one {
    display: flex;
    align-items: center;
    gap: 8px;
    margin-top: 16px;
  }
  .primary.big {
    height: 40px;
    padding: 0 20px;
  }
  .toggle {
    height: 40px;
    padding: 0 14px;
    border-radius: 12px;
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-3);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .toggle:hover,
  .toggle.on {
    color: var(--text);
    background: var(--hover);
  }
  .svc {
    max-width: 620px;
    padding: 18px 20px 20px;
    margin-bottom: 12px;
    border-radius: var(--radius-l);
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  header {
    display: flex;
    align-items: center;
    gap: 14px;
  }
  header > div {
    flex: 1;
    min-width: 0;
  }
  h2 {
    font-size: calc(17px * var(--fs, 1));
    font-weight: 700;
  }
  .pill {
    display: inline-block;
    margin-left: 8px;
    padding: 2px 8px;
    border-radius: 999px;
    background: var(--surface-3);
    color: var(--text-2);
    font-size: calc(11px * var(--fs, 1));
    font-weight: 700;
    vertical-align: middle;
  }
  header p {
    margin: 2px 0 0;
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-3);
  }
  .logo {
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    border-radius: var(--radius-m);
    font-weight: 800;
    font-size: calc(13px * var(--fs, 1));
    background: var(--surface-3);
  }
  form {
    display: flex;
    flex-direction: column;
    gap: 12px;
    margin-top: 16px;
  }
  label {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  label span {
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
  }
  em {
    font-style: normal;
    font-weight: 400;
    color: var(--text-3);
  }
  input {
    height: 40px;
    padding: 0 14px;
    border-radius: var(--radius-m);
    background: var(--surface-1);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    color: var(--text);
    outline: none;
    user-select: text;
    transition: border-color var(--fast) var(--ease);
  }
  input:focus {
    border-color: var(--border-strong);
  }
  .hint {
    margin: 0;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  code {
    padding: 0 4px;
    border-radius: 4px;
    background: var(--surface-2);
    color: var(--text-2);
  }
  .error {
    margin: 0;
    font-size: calc(13px * var(--fs, 1));
    color: var(--danger);
  }
  .primary {
    align-self: flex-start;
    height: 38px;
    padding: 0 18px;
    border-radius: 999px;
    background: var(--accent);
    color: var(--accent-ink);
    font-weight: 700;
    transition: opacity var(--fast) var(--ease);
  }
  .primary:disabled {
    opacity: 0.4;
    cursor: default;
  }
  .ghost {
    height: 34px;
    padding: 0 14px;
    border-radius: 999px;
    border: 1px solid var(--border-strong);
    color: var(--text-2);
  }
  .ghost:hover {
    color: var(--text);
    background: var(--hover);
  }
  .device {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 10px;
    margin-top: 12px;
    padding: 14px;
    border-radius: var(--radius-l);
    background: var(--surface-2);
    border: 1px solid var(--card-line);
  }
  .device p {
    margin: 0;
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-2);
  }
  .code {
    padding: 8px 16px;
    border-radius: var(--radius-m);
    background: var(--surface-3);
    font-family: var(--font-display);
    font-size: calc(26px * var(--fs, 1));
    font-weight: 700;
    letter-spacing: 0.18em;
    text-transform: uppercase;
    user-select: all;
    transition: transform var(--fast) var(--ease);
  }
  .code:active {
    transform: scale(0.97);
  }
  .device-actions {
    display: flex;
    gap: 8px;
  }
</style>
