<script lang="ts">
  // Вход в аккаунт Sonar (API.md §1): логин и пароль, регистрация, вход через Telegram (бот подтверждает,
  // если Telegram привязан) и вход с другого устройства (ссылку открывают там, где уже вошли). Одна форма —
  // и в воротах при запуске (app/AuthGate), и в «Аккаунт → Вход».
  import { onDestroy } from 'svelte'
  import Icon from '../Icon.svelte'
  import { account, loginProblem, passwordProblem, type PollStatus } from '../../lib/account.svelte'
  import { api, errorText } from '../../lib/api'
  import { toast } from '../../lib/toast.svelte'
  import { slide, xfade } from '../../lib/motion'
  import { t } from '../../lib/i18n.svelte'

  let mode = $state<'login' | 'register'>('login')
  let login = $state('')
  let password = $state('')
  let again = $state('')
  let busy = $state(false)
  let error = $state('')

  /** Ждём подтверждения: в боте (`telegram`) или на другом устройстве (`link`). */
  let waiting = $state<{ kind: 'telegram' | 'link'; id: string; url: string; bot: string; until: number } | null>(null)
  let leftMs = $state(0)
  let timer: ReturnType<typeof setInterval> | null = null
  let copied = $state(false)

  const problem = $derived.by(() => {
    if (!login.trim() || !password) return null
    if (mode === 'register') {
      const p = loginProblem(login) ?? passwordProblem(password)
      if (p) return p
      if (again && again !== password) return 'Пароли не совпадают'
    }
    return null
  })
  const ready = $derived(!!login.trim() && !!password && !problem && (mode === 'login' || again === password))

  async function submit() {
    if (!ready || busy) return
    busy = true
    error = ''
    try {
      if (mode === 'login') await account.login(login, password)
      else await account.register(login, password)
      password = again = ''
    } catch (e) {
      error = errorText(e)
    } finally {
      busy = false
    }
  }

  function stop() {
    if (timer) clearInterval(timer)
    timer = null
    waiting = null
  }

  function wait(kind: 'telegram' | 'link', id: string, url: string, bot: string, until: number) {
    stop()
    waiting = { kind, id, url, bot, until }
    leftMs = until - Date.now()
    let polling = false
    timer = setInterval(async () => {
      leftMs = Math.max(0, until - Date.now())
      if (!leftMs) {
        stop()
        error = t('Ссылка истекла — попробуй ещё раз')
        return
      }
      if (polling) return
      polling = true
      try {
        const st: PollStatus = await account.poll(kind, id)
        if (st === 'approved') stop()
        else if (st === 'rejected' || st === 'expired') {
          stop()
          error = st === 'rejected' ? t('Вход отклонён') : t('Ссылка истекла — попробуй ещё раз')
        }
      } catch {
        // сеть мигнула — следующий опрос через 2 с
      } finally {
        polling = false
      }
    }, 2000)
  }

  async function viaTelegram() {
    error = ''
    try {
      const s = await account.telegramStart('login')
      wait('telegram', s.request_id, '', s.link, s.expires_at)
      void api.openUrl(s.link).catch(() => {})
    } catch (e) {
      error = errorText(e)
    }
  }

  async function viaDevice() {
    error = ''
    try {
      const l = await account.quickLink()
      wait('link', l.code, l.url, l.bot_url, l.expires_at)
    } catch (e) {
      error = errorText(e)
    }
  }

  async function copy(text: string) {
    try {
      await navigator.clipboard.writeText(text)
      copied = true
      setTimeout(() => (copied = false), 1500)
    } catch {
      toast.show(text)
    }
  }

  const countdown = (ms: number) => {
    const s = Math.ceil(ms / 1000)
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
  }

  onDestroy(stop)
</script>

<div class="signin">
  {#if waiting}
    <div class="wait" in:xfade={{ duration: 220 }}>
      <span class="spin" aria-hidden="true"></span>
      {#if waiting.kind === 'telegram'}
        <b>{t('Подтверди вход в боте')}</b>
        <p>{t('Открыли @SonarMusicApp в Telegram — нажми там «Разрешить». Telegram должен быть привязан к аккаунту.')}</p>
        <button class="ghost" onclick={() => waiting && api.openUrl(waiting.bot)}><Icon name="telegram" size={15} />{t('Открыть бота ещё раз')}</button>
      {:else}
        <b>{t('Открой ссылку там, где уже вошёл')}</b>
        <p>{t('На телефоне или другом компьютере с Sonar: «Аккаунт → Вход» → «Подтвердить вход». Или отправь ссылку боту.')}</p>
        <div class="linkbox">
          <code>{waiting.url}</code>
          <button class="ghost" onclick={() => waiting && copy(waiting.url)}><Icon name={copied ? 'check' : 'copy'} size={14} />{copied ? t('Скопировано') : t('Скопировать')}</button>
        </div>
        <button class="ghost" onclick={() => waiting && api.openUrl(waiting.bot)}><Icon name="telegram" size={15} />{t('Подтвердить в боте')}</button>
      {/if}
      <small>{t('Ссылка действует ещё {time}', { time: countdown(leftMs) })}</small>
      <button class="text-btn" onclick={stop}>{t('Отмена')}</button>
    </div>
  {:else}
    <div class="seg" role="tablist">
      <button role="tab" class:on={mode === 'login'} aria-selected={mode === 'login'} onclick={() => ((mode = 'login'), (error = ''))}>{t('Вход')}</button>
      <button role="tab" class:on={mode === 'register'} aria-selected={mode === 'register'} onclick={() => ((mode = 'register'), (error = ''))}>{t('Регистрация')}</button>
    </div>
    <form onsubmit={(e) => (e.preventDefault(), submit())}>
      <label>
        <span>{t('Логин')}</span>
        <input autocomplete="username" maxlength="25" spellcheck="false" bind:value={login} placeholder="folzy" />
      </label>
      <label>
        <span>{t('Пароль')}</span>
        <input type="password" autocomplete={mode === 'login' ? 'current-password' : 'new-password'} maxlength="256" bind:value={password} />
      </label>
      {#if mode === 'register'}
        <label transition:slide={{ duration: 200 }}>
          <span>{t('Пароль ещё раз')}</span>
          <input type="password" autocomplete="new-password" maxlength="256" bind:value={again} />
        </label>
      {/if}
      {#if problem || error}
        <p class="err" transition:slide={{ duration: 180 }}>{problem ? t(problem) : error}</p>
      {/if}
      <button class="primary" type="submit" disabled={!ready || busy}>
        {busy ? t('Секунду…') : mode === 'login' ? t('аккаунт::Войти') : t('Создать аккаунт')}
      </button>
    </form>
    <div class="or"><i></i><span>{t('или')}</span><i></i></div>
    <div class="alt">
      <button class="ghost" onclick={viaTelegram}><Icon name="telegram" size={16} />{t('Войти через Telegram')}</button>
      <button class="ghost" onclick={viaDevice}><Icon name="phone" size={16} />{t('С другого устройства')}</button>
    </div>
  {/if}
</div>

<style>
  .signin {
    display: flex;
    flex-direction: column;
    gap: var(--sp-4);
    width: 100%;
    max-width: 360px;
  }
  .seg {
    display: flex;
    padding: 3px;
    border-radius: 12px;
    background: var(--surface-3);
  }
  .seg button {
    flex: 1;
    height: var(--ctl-s);
    border-radius: 9px;
    font-weight: 600;
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .seg button.on {
    background: var(--plate);
    color: var(--text);
    box-shadow: var(--sheen);
  }
  form {
    display: flex;
    flex-direction: column;
    gap: var(--sp-3);
  }
  label {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  label span {
    font-size: var(--fs-meta);
    color: var(--text-3);
  }
  input {
    height: var(--ctl-m);
    padding: 0 12px;
    border-radius: var(--radius-m);
    border: 1px solid var(--border);
    background: var(--surface-1);
    color: var(--text);
    font: inherit;
    transition: border-color var(--fast) var(--ease);
  }
  input:focus {
    outline: none;
    border-color: var(--accent);
  }
  .err {
    margin: 0;
    font-size: var(--fs-meta);
    color: var(--danger, #e5484d);
  }
  .primary {
    height: var(--ctl-m);
    border-radius: var(--radius-m);
    background: var(--text);
    color: var(--bg, #000);
    font-weight: 700;
    transition:
      opacity var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .primary:disabled {
    opacity: 0.45;
    cursor: default;
  }
  .primary:active:not(:disabled) {
    transform: scale(0.98);
  }
  .or {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    font-size: var(--fs-meta);
    color: var(--text-3);
  }
  .or i {
    flex: 1;
    height: 1px;
    background: var(--border);
  }
  .alt {
    display: flex;
    flex-direction: column;
    gap: var(--sp-2);
  }
  .ghost {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    height: var(--ctl-m);
    padding: 0 14px;
    border-radius: var(--radius-m);
    background: var(--surface-3);
    font-weight: 600;
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .ghost:hover {
    background: var(--hover);
    color: var(--text);
  }
  .ghost:active {
    transform: scale(0.98);
  }
  .wait {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: var(--sp-3);
    text-align: center;
  }
  .wait p {
    margin: 0;
    font-size: var(--fs-meta);
    line-height: 1.5;
    color: var(--text-3);
  }
  .wait small {
    font-size: var(--fs-meta);
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  .linkbox {
    display: flex;
    align-items: center;
    gap: var(--sp-2);
    width: 100%;
  }
  .linkbox code {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    padding: 8px 10px;
    border-radius: 8px;
    background: var(--surface-3);
    font-size: var(--fs-meta);
    user-select: text;
  }
  .linkbox .ghost {
    height: var(--ctl-s);
  }
  .text-btn {
    font-size: var(--fs-meta);
    color: var(--text-3);
  }
  .text-btn:hover {
    color: var(--text);
  }
  .spin {
    width: 28px;
    height: 28px;
    border-radius: 50%;
    border: 2px solid var(--surface-3);
    border-top-color: var(--text);
    animation: spin 0.9s linear infinite;
  }
  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .spin {
      animation: none;
    }
  }
</style>
