<script lang="ts">
  // Аккаунт → Профиль: отображаемое имя, @username и аватар — из них приветствие на главной и
  // аватар в левой панели. До сервера — локально в настройках (`profile.*`, синхронизируются как
  // остальные); с сервером профиль приходит из GET /me и меняется PATCH /me (docs/API.md).
  // Пусто — как раньше: имя и аватар из подключённого сервиса.
  import CopyProfileLink from '../../components/CopyProfileLink.svelte'
  import Icon from '../../components/Icon.svelte'
  import { t } from '../../lib/i18n.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { avatarFromFile, cleanUsername, USERNAME_RE } from '../../lib/avatar'
  import { toast } from '../../lib/toast.svelte'
  import { profileUrl } from '../../lib/public-profile'
  import { router } from '../../app/router.svelte'
  import { home } from '../home-data.svelte'
  import { settingsPanel } from '../settings-section.svelte'

  let name = $state(settings.get('profile.name'))
  let username = $state(settings.get('profile.username'))
  const avatar = $derived(settings.get('profile.avatar'))
  const fallback = $derived(home.account)
  const userOk = $derived(!username.trim() || USERNAME_RE.test(cleanUsername(username)))

  let pick: HTMLInputElement | undefined = $state()
  async function onFile(e: Event) {
    const input = e.currentTarget as HTMLInputElement
    const file = input.files?.[0]
    input.value = ''
    if (!file) return
    try {
      settings.set('profile.avatar', await avatarFromFile(file))
      toast.show(t('Аватар обновлён'))
    } catch {
      toast.show(t('Не получилось открыть картинку'))
    }
  }
  function saveName() {
    settings.set('profile.name', name.trim().slice(0, 40))
  }
  function saveUser() {
    if (!userOk) return
    settings.set('profile.username', cleanUsername(username))
  }
  /** «Как видят мой профиль»: сохранить поля, закрыть настройки и открыть предпросмотр (ProfilePage). */
  function preview() {
    saveName()
    saveUser()
    settingsPanel.close()
    router.go('profile')
  }
</script>

<div class="head">
  <button class="ava" title={t('Выбрать аватар')} onclick={() => pick?.click()}>
    {#if avatar}
      <img src={avatar} alt="" />
    {:else if fallback?.avatar_url}
      <img src={fallback.avatar_url} alt="" class="dim" />
    {:else}
      <Icon name="user" size={34} />
    {/if}
    <span class="edit"><Icon name="pencil" size={14} /></span>
  </button>
  <div class="who">
    <b>{name.trim() || fallback?.name || t('Без имени')}</b>
    <small>{username.trim() ? `@${cleanUsername(username)}` : t('без @username')}</small>
    {#if avatar}<button class="link" onclick={() => settings.set('profile.avatar', '')}>{t('Убрать аватар')}</button>{/if}
  </div>
  <input bind:this={pick} type="file" accept="image/*" hidden onchange={onFile} />
</div>

<label class="field">
  <span class="text"><b>{t('Отображаемое имя')}</b><small>{#if fallback?.name}{t('Его видно на главной: «Добрый вечер, …» · пусто — «{name}» из сервиса', { name: fallback.name })}{:else}{t('Его видно на главной: «Добрый вечер, …»')}{/if}</small></span>
  <input maxlength="40" placeholder={fallback?.name ?? t('Как тебя называть')} bind:value={name} onblur={saveName} onkeydown={(e) => e.key === 'Enter' && saveName()} />
</label>
<label class="field" class:bad={!userOk}>
  <span class="text"><b>{t('Имя пользователя')}</b><small>{userOk ? t('Латиница, цифры и «_», 3–32 знака') : t('Только латиница, цифры и «_», от 3 до 32 знаков')}</small></span>
  <span class="at"><i>@</i><input maxlength="33" placeholder="username" bind:value={username} onblur={saveUser} onkeydown={(e) => e.key === 'Enter' && saveUser()} /></span>
</label>

<div class="share">
  <span class="text">
    <b>{t('Публичный профиль')}</b>
    <small class="url">{profileUrl(settings.get('profile.username')) ?? t('Задай @username — тогда появится ссылка')}</small>
  </span>
  <span class="buttons">
    <CopyProfileLink username={settings.get('profile.username')} />
    <button class="look" onclick={preview}><Icon name="eye" size={16} />{t('Как видят мой профиль')}</button>
  </span>
  <small class="hint">{t('Страница по ссылке заработает, когда у Sonar появится сервер.')}</small>
</div>

<p class="note">{t('Сейчас профиль хранится на этом компьютере и в синхронизации настроек. С сервером Sonar он станет общим для всех устройств и друзей.')}</p>

<style>
  .head {
    display: flex;
    align-items: center;
    gap: 16px;
    margin: 4px 0 18px;
  }
  .ava {
    position: relative;
    display: grid;
    place-items: center;
    width: 76px;
    height: 76px;
    border-radius: 50%;
    background: var(--surface-3);
    color: var(--text-3);
    flex-shrink: 0;
    transition: transform var(--fast) var(--ease);
  }
  .ava:hover {
    transform: scale(1.04);
  }
  .ava img {
    width: 100%;
    height: 100%;
    border-radius: 50%;
    object-fit: cover;
  }
  .ava img.dim {
    opacity: 0.55;
  }
  .edit {
    position: absolute;
    right: -2px;
    bottom: -2px;
    display: grid;
    place-items: center;
    width: 26px;
    height: 26px;
    border-radius: 50%;
    background: var(--accent);
    color: var(--accent-ink);
    border: 2px solid var(--bg);
  }
  .who {
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }
  .who b {
    font-size: calc(18px * var(--fs, 1));
  }
  .who small {
    color: var(--text-3);
  }
  .link {
    align-self: flex-start;
    margin-top: 4px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-2);
  }
  .link:hover {
    color: var(--text);
  }
  .field {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    padding: 10px 0;
  }
  .text {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .text b {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  .text small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .bad small {
    color: var(--danger);
  }
  input {
    width: 190px;
    height: 34px;
    padding: 0 12px;
    border-radius: var(--radius-m);
    border: 1px solid var(--border);
    background: var(--surface-1);
    color: var(--text);
    font: inherit;
  }
  input:focus {
    outline: none;
    border-color: var(--accent);
  }
  .bad input {
    border-color: var(--danger);
  }
  .at {
    position: relative;
    display: flex;
    align-items: center;
  }
  .at i {
    position: absolute;
    left: 11px;
    font-style: normal;
    color: var(--text-3);
  }
  .at input {
    padding-left: 26px;
  }
  .share {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 10px 16px;
    margin-top: 8px;
    padding: 14px 0 0;
    border-top: 1px solid var(--border);
  }
  .url {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .buttons {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .look {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    height: 36px;
    padding: 0 16px;
    border-radius: 10px;
    background: var(--accent);
    color: var(--accent-ink);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    transition:
      filter var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .look:hover {
    filter: brightness(1.08);
  }
  .look:active {
    transform: scale(0.97);
  }
  .hint {
    flex-basis: 100%;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .note {
    margin: 14px 0 0;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
</style>
