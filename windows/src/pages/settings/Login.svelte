<script lang="ts">
  // Аккаунт → Вход (API.md §1): кто вошёл, пароль, Telegram, подтверждение входа с другого устройства,
  // список устройств (правило 24 ч) и выход. Без входа — та же форма, что в воротах.
  import { onDestroy } from 'svelte'
  import Group from '../../components/settings/Group.svelte'
  import Icon from '../../components/Icon.svelte'
  import SignIn from '../../components/account/SignIn.svelte'
  import { account, canRevokeOthers, passwordProblem, type AccountDevice } from '../../lib/account.svelte'
  import { api, errorText } from '../../lib/api'
  import { confirm } from '../../lib/confirm.svelte'
  import { toast } from '../../lib/toast.svelte'
  import { cascade } from '../../lib/cascade'
  import { slide } from '../../lib/motion'
  import { dateLong } from '../../lib/format'
  import { t } from '../../lib/i18n.svelte'

  const user = $derived(account.user)
  let devices = $state<AccountDevice[]>([])
  let loaded = $state(false)

  let oldPass = $state('')
  let newPass = $state('')
  let savingPass = $state(false)
  let pasted = $state('')
  let tgTimer: ReturnType<typeof setInterval> | null = null
  let tgWaiting = $state(false)

  const mayRevoke = $derived(canRevokeOthers(devices))

  async function loadDevices() {
    try {
      devices = await account.devices()
    } catch (e) {
      if (String(e) !== 'signed_out') toast.show(errorText(e))
    } finally {
      loaded = true
    }
  }

  $effect(() => {
    if (account.signedIn) {
      void account.refresh()
      void loadDevices()
    }
  })

  const day = (ms: number) => {
    const d = new Date(ms)
    return dateLong(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`)
  }

  async function savePassword() {
    const p = passwordProblem(newPass)
    if (p) return toast.show(t(p))
    savingPass = true
    try {
      await account.changePassword(user?.has_password ? oldPass : null, newPass)
      oldPass = newPass = ''
      toast.show(t('Пароль сменён'))
      void account.refresh()
    } catch (e) {
      toast.show(errorText(e))
    } finally {
      savingPass = false
    }
  }

  function stopTg() {
    if (tgTimer) clearInterval(tgTimer)
    tgTimer = null
    tgWaiting = false
  }

  async function linkTelegram() {
    try {
      const s = await account.telegramStart('link')
      void api.openUrl(s.link).catch(() => toast.show(s.link))
      tgWaiting = true
      tgTimer = setInterval(async () => {
        if (Date.now() > s.expires_at) return stopTg()
        const st = await account.poll('telegram', s.request_id).catch(() => 'pending' as const)
        if (st !== 'pending') {
          stopTg()
          if (st === 'approved') toast.show(t('Telegram привязан'))
        }
      }, 2000)
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  async function unlinkTelegram() {
    const ok = await confirm.ask({
      title: t('Отвязать Telegram?'),
      text: t('Войти через бота больше не получится, пока не привяжешь снова.'),
      yes: t('аккаунт::Отвязать'),
      no: t('Отмена'),
      danger: true,
    })
    if (!ok) return
    try {
      await account.unlinkTelegram()
      await account.refresh()
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  /** Вставили ссылку входа с другого устройства: показать, кто просит, «Разрешить» — через 3 секунды. */
  async function approvePasted() {
    try {
      const info = await account.linkInfo(pasted)
      const ok = await confirm.ask({
        title: t('⚠️ Авторизация в аккаунт'),
        text:
          t('Разрешить доступ к аккаунту @{login} для: {who}', { login: user?.login ?? '', who: info.for.name }) +
          '\n\n' +
          t('Если тебе прислали эту ссылку и просят нажать — не разрешай. Так получают доступ к чужим аккаунтам.'),
        yes: t('Разрешить'),
        no: t('Отклонить'),
        danger: true,
        delay: 3,
      })
      await account.decideLink(info.code, ok)
      pasted = ''
      toast.show(ok ? t('Вход разрешён') : t('Вход отклонён'))
      if (ok) void loadDevices()
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  let editing = $state<string | null>(null)
  let draft = $state('')

  function startRename(d: AccountDevice) {
    editing = d.id
    draft = d.name
  }

  async function rename(d: AccountDevice) {
    const name = draft.trim()
    editing = null
    if (!name || name === d.name) return
    try {
      await account.renameDevice(d.id, name.slice(0, 48))
      await loadDevices()
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  async function revoke(d: AccountDevice) {
    const ok = await confirm.ask({
      title: t('Завершить сессию на «{name}»?', { name: d.name }),
      text: t('На этом устройстве придётся войти заново.'),
      yes: t('Завершить'),
      no: t('Отмена'),
      danger: true,
    })
    if (!ok) return
    try {
      await account.revokeDevice(d.id)
      await loadDevices()
    } catch (e) {
      toast.show(errorText(e))
    }
  }

  async function logout() {
    const ok = await confirm.ask({
      title: t('Выйти из аккаунта?'),
      text: t('Музыка и медиатека на этом компьютере останутся, синхронизация остановится.'),
      yes: t('Выйти'),
      no: t('Отмена'),
    })
    if (ok) await account.logout()
  }

  const icon = (p: string) => (p === 'windows' ? 'monitor' : 'phone')

  onDestroy(stopTg)
</script>

{#if !account.signedIn}
  <Group title={t('Аккаунт Sonar')} hint={t('Лайки, плейлисты и настройки — на всех твоих устройствах')}>
    {#if account.checked && !account.reachable}
      <p class="note"><Icon name="wifi" size={15} /><span>{t('Сервер Sonar сейчас недоступен — войти можно, когда он ответит.')}</span></p>
    {/if}
    <div class="form"><SignIn /></div>
  </Group>
{:else if user}
  <Group title={t('Аккаунт')}>
    <div class="who">
      <span class="ava"><Icon name="user" size={22} /></span>
      <span class="text">
        <b>{user.display_name}</b>
        <small>@{user.username}{#if user.number} · #{user.number}{/if} · {t('логин {login}', { login: user.login })}</small>
      </span>
      <button class="ghost" onclick={logout}><Icon name="login" size={15} />{t('Выйти')}</button>
    </div>
  </Group>

  <Group title={t('Пароль')} hint={user.has_password ? t('Сменить пароль для входа') : t('Пароля ещё нет — задай, чтобы входить без Telegram')}>
    <div class="pass">
      {#if user.has_password}
        <input type="password" autocomplete="current-password" placeholder={t('Старый пароль')} bind:value={oldPass} />
      {/if}
      <input type="password" autocomplete="new-password" placeholder={t('Новый пароль')} bind:value={newPass} />
      <button class="ghost" disabled={savingPass || !newPass || (user.has_password && !oldPass)} onclick={savePassword}>{t('Сохранить')}</button>
    </div>
  </Group>

  <Group title="Telegram">
    <div class="who">
      <span class="ava"><Icon name="telegram" size={20} /></span>
      <span class="text">
        {#if user.telegram}
          <b>{user.telegram.username ? `@${user.telegram.username}` : t('Привязан')}</b>
          <small>{t('Можно входить через @SonarMusicApp')}</small>
        {:else}
          <b>{t('Не привязан')}</b>
          <small>{tgWaiting ? t('Нажми «Привязать» в боте…') : t('Вход в один тап и подтверждение входа в боте')}</small>
        {/if}
      </span>
      {#if user.telegram}
        <button class="ghost" disabled={!user.has_password} title={user.has_password ? '' : t('Сначала задай пароль')} onclick={unlinkTelegram}>
          <Icon name="unlink" size={15} />{t('аккаунт::Отвязать')}
        </button>
      {:else}
        <button class="ghost" disabled={tgWaiting} onclick={linkTelegram}><Icon name="link" size={15} />{t('Привязать')}</button>
      {/if}
    </div>
  </Group>

  <Group title={t('Подтвердить вход')} hint={t('Вход на новом устройстве: вставь ссылку, которую оно показало')}>
    <div class="pass">
      <input class="wide" placeholder="https://try-sonar.ru/auth/…" bind:value={pasted} onkeydown={(e) => e.key === 'Enter' && pasted.trim() && approvePasted()} />
      <button class="ghost" disabled={!pasted.trim()} onclick={approvePasted}>{t('Проверить')}</button>
    </div>
  </Group>

  <Group title={t('Устройства')}>
    {#if !mayRevoke && devices.length > 1}
      <p class="note" transition:slide={{ duration: 200 }}>
        <Icon name="shield" size={15} /><span>{t('Вход был недавно — завершать другие сессии можно через 24 часа')}</span>
      </p>
    {/if}
    {#if devices.length}
      <div class="list" use:cascade={devices.length}>
        {#each devices as d (d.id)}
          <div class="row" transition:slide={{ duration: 200 }}>
            <span class="ava small" class:current={d.current}><Icon name={icon(d.platform)} size={18} /></span>
            <span class="text">
              {#if editing === d.id}
                <!-- svelte-ignore a11y_autofocus -->
                <input class="rename" maxlength="48" autofocus bind:value={draft} onblur={() => rename(d)}
                  onkeydown={(e) => (e.key === 'Enter' ? rename(d) : e.key === 'Escape' && (editing = null))} />
              {:else}
                <b>{d.name}{#if d.current}<em>{t('это устройство')}</em>{/if}</b>
              {/if}
              <small>
                {[d.os, d.app_version ? `Sonar ${d.app_version}` : null].filter(Boolean).join(' · ')}
                · {t('вход {date}', { date: day(d.created_at) })}
              </small>
            </span>
            <button class="icon" aria-label={t('Переименовать')} onclick={() => startRename(d)}><Icon name="pencil" size={15} /></button>
            {#if !d.current}
              <button class="ghost" disabled={!mayRevoke} onclick={() => revoke(d)}>{t('Завершить')}</button>
            {/if}
          </div>
        {/each}
      </div>
    {:else if loaded}
      <p class="note">{t('Не получилось загрузить устройства')}</p>
    {/if}
  </Group>
{/if}

<style>
  .form {
    display: flex;
    justify-content: flex-start;
    margin-top: var(--sp-3);
  }
  .note {
    display: flex;
    gap: 8px;
    align-items: flex-start;
    margin: 6px 0 var(--sp-2);
    font-size: var(--fs-meta);
    line-height: 1.45;
    color: var(--text-3);
  }
  .note :global(svg) {
    flex: none;
    margin-top: 1px;
  }
  .who,
  .row {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    padding: var(--sp-2) 0;
  }
  .ava {
    display: grid;
    place-items: center;
    width: var(--ctl-m);
    height: var(--ctl-m);
    border-radius: 12px;
    background: var(--surface-3);
    color: var(--text-2);
  }
  .ava.small {
    width: 36px;
    height: 36px;
    border-radius: 10px;
    color: var(--text-3);
  }
  .ava.current {
    color: var(--text);
  }
  .text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .text b {
    display: flex;
    align-items: center;
    gap: 8px;
    font-weight: 600;
  }
  .text em {
    font-style: normal;
    font-size: var(--fs-meta);
    font-weight: 500;
    color: var(--text-3);
  }
  .text small {
    font-size: var(--fs-meta);
    color: var(--text-3);
  }
  .pass {
    display: flex;
    flex-wrap: wrap;
    gap: var(--sp-2);
    margin-top: var(--sp-2);
  }
  input {
    width: 200px;
    height: var(--ctl-s);
    padding: 0 12px;
    border-radius: var(--radius-m);
    border: 1px solid var(--border);
    background: var(--surface-1);
    color: var(--text);
    font: inherit;
    transition: border-color var(--fast) var(--ease);
  }
  input.rename {
    width: 100%;
    max-width: 280px;
  }
  input.wide {
    flex: 1;
    min-width: 240px;
  }
  input:focus {
    outline: none;
    border-color: var(--accent);
  }
  .ghost {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: var(--ctl-s);
    padding: 0 12px;
    border-radius: 9px;
    background: var(--surface-3);
    font-size: var(--fs-meta);
    font-weight: 600;
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .ghost:hover:not(:disabled) {
    background: var(--hover);
    color: var(--text);
  }
  .ghost:active:not(:disabled) {
    transform: scale(0.97);
  }
  .ghost:disabled {
    opacity: 0.5;
    cursor: default;
  }
  .icon {
    display: grid;
    place-items: center;
    width: var(--ctl-s);
    height: var(--ctl-s);
    border-radius: 9px;
    color: var(--text-3);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .icon:hover {
    background: var(--hover);
    color: var(--text);
  }
  .list {
    display: flex;
    flex-direction: column;
  }
</style>
