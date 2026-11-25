<script lang="ts">
  // Аккаунт → Профиль (SETTINGS_NEXT «Профиль»): сверху живое превью «как увидят другие», ниже карточки —
  // картинки (аватар, баннер, фон), цвет профиля, имя и описание, ссылки, вид шапки, шрифт и эффект ника,
  // витрина до 6 мест. До сервера всё в `profile.*` настройках (синхронизируются), с сервером — GET/PATCH
  // /me (docs/API.md). Пусто — имя и аватар из подключённого сервиса. Уровней и значков нет.
  import { slide } from '../../lib/motion'
  import Card from '../../components/settings/Card.svelte'
  import PreviewTiles from '../../components/settings/PreviewTiles.svelte'
  import CopyProfileLink from '../../components/CopyProfileLink.svelte'
  import Icon from '../../components/Icon.svelte'
  import Nick from '../../components/profile/Nick.svelte'
  import ProfileCard from '../../components/profile/ProfileCard.svelte'
  import ShowcasePicker from './ShowcasePicker.svelte'
  import { t } from '../../lib/i18n.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { avatarFromFile, cleanUsername, coverFromFile, USERNAME_RE } from '../../lib/avatar'
  import { toast } from '../../lib/toast.svelte'
  import { profileUrl } from '../../lib/public-profile'
  import {
    addLink,
    addShowcase,
    colorHex,
    LINKS_MAX,
    linkLabel,
    NICK_EFFECTS,
    NICK_FONTS,
    parseLink,
    PROFILE_COLORS,
    PROFILE_LAYOUTS,
    readLinks,
    readShowcase,
    removeLink,
    removeShowcase,
    SHOWCASE_MAX,
    visibleShowcase,
    type ShowcaseItem,
  } from '../../lib/profile-look'
  import { router } from '../../app/router.svelte'
  import { home } from '../home-data.svelte'
  import { settingsPanel } from '../settings-section.svelte'
  import { offline } from '../../lib/offline.svelte'
  import { account } from '../../lib/account.svelte'
  import { errorText } from '../../lib/api'

  const NAME_MAX = 40
  const STATUS_MAX = 80
  const BIO_MAX = 190
  const BANNER = { w: 900, h: 300 }
  const BACKGROUND = { w: 960, h: 540 }
  const KIND_LABEL = { playlist: 'Плейлист', album: 'Альбом', artist: 'Исполнитель', track: 'Трек' } as const
  type Picture = 'profile.avatar' | 'profile.banner' | 'profile.background'

  let name = $state(settings.get('profile.name'))
  let username = $state(settings.get('profile.username'))
  let status = $state(settings.get('profile.status'))
  let bio = $state(settings.get('profile.bio'))
  let linkInput = $state('')
  let picking = $state(false)

  const fallback = $derived(home.account)
  const userOk = $derived(!username.trim() || USERNAME_RE.test(cleanUsername(username)))
  const color = $derived(colorHex(settings.get('profile.color')))
  /** Второй цвет переливающегося ника (null — по умолчанию). */
  const color2 = $derived(colorHex(settings.get('profile.nick_color2')))
  const links = $derived(readLinks(settings.get('profile.links')))
  const showcase = $derived(readShowcase(settings.get('profile.showcase')))
  const hidden = $derived(settings.get('privacy.hidden_playlists'))
  const linkOk = $derived(!linkInput.trim() || parseLink(linkInput) !== null)

  const PICTURES: { key: Picture; label: string; hint: string }[] = [
    { key: 'profile.avatar', label: 'Аватар', hint: 'Круглый, в панели вкладок и на главной' },
    { key: 'profile.banner', label: 'Баннер', hint: 'Полоса над аватаром, 3 : 1' },
    { key: 'profile.background', label: 'Фон', hint: 'За всей карточкой профиля, 16 : 9' },
  ]

  let fileFor = $state<Picture>('profile.avatar')
  let fileInput: HTMLInputElement | undefined = $state()
  function choose(key: Picture) {
    fileFor = key
    fileInput?.click()
  }
  async function onFile(e: Event) {
    const input = e.currentTarget as HTMLInputElement
    const file = input.files?.[0]
    input.value = ''
    if (!file) return
    try {
      const url =
        fileFor === 'profile.avatar'
          ? await avatarFromFile(file)
          : fileFor === 'profile.banner'
            ? await coverFromFile(file, BANNER.w, BANNER.h)
            : await coverFromFile(file, BACKGROUND.w, BACKGROUND.h, 0.72)
      settings.set(fileFor, url)
      toast.show(t('Картинка обновлена'))
    } catch (err) {
      console.warn('профиль: картинка не открылась', err)
      toast.show(t('Не получилось открыть картинку'))
    }
  }

  // Вошли в аккаунт Sonar — имя и @username живут на сервере (PATCH /me); без входа — только в настройках.
  async function pushAccount(patch: { username?: string; display_name?: string }) {
    try {
      await account.update(patch)
    } catch (e) {
      toast.show(errorText(e))
      name = settings.get('profile.name')
      username = settings.get('profile.username')
    }
  }
  function saveName() {
    const v = name.trim().slice(0, NAME_MAX)
    if (account.signedIn) {
      if (v && v !== account.user?.display_name) void pushAccount({ display_name: v })
    } else settings.set('profile.name', v)
  }
  const saveStatus = () => settings.set('profile.status', status.trim().slice(0, STATUS_MAX))
  const saveBio = () => settings.set('profile.bio', bio.trim().slice(0, BIO_MAX))
  function saveUser() {
    if (!userOk) return
    const v = cleanUsername(username)
    if (account.signedIn) {
      if (v && v !== account.user?.username) void pushAccount({ username: v })
    } else settings.set('profile.username', v)
  }

  function onLinkKey(e: KeyboardEvent) {
    if (e.key === 'Enter') addTypedLink()
  }
  function addTypedLink() {
    const link = parseLink(linkInput)
    if (!link) return
    if (links.some((l) => l.url === link.url)) {
      toast.show(t('Эта ссылка уже есть'))
      return
    }
    settings.set('profile.links', addLink(links, link))
    linkInput = ''
  }

  function pickShowcase(item: ShowcaseItem) {
    const next = addShowcase(showcase, item, hidden)
    settings.set('profile.showcase', next)
    if (next.length >= SHOWCASE_MAX) picking = false
  }

  /** «Как видят мой профиль»: сохранить поля, закрыть настройки и открыть предпросмотр (ProfilePage). */
  function preview() {
    saveName()
    saveUser()
    settingsPanel.close()
    router.go('profile')
  }
</script>

{#snippet layoutTile(id: string)}
  <span class="mock lay-{id}" style:--pc={color ?? '#8b7cff'}>
    <i class="b"></i>
    <span class="h"><i class="a"></i><span class="l"><i></i><i></i></span></span>
  </span>
{/snippet}

{#snippet fontTile(id: string)}
  <span class="sample"><Nick text={name.trim() || fallback?.name || 'Sonar'} font={id} effect="none" {color} size={17} /></span>
{/snippet}

{#snippet effectTile(id: string)}
  <span class="sample"><Nick text="Sonar" font={settings.get('profile.nick_font')} effect={id as never} {color} {color2} size={19} /></span>
{/snippet}

<div class="preview">
  <ProfileCard
    name={name.trim() || fallback?.name || ''}
    username={userOk ? cleanUsername(username) : settings.get('profile.username')}
    avatar={settings.get('profile.avatar') || fallback?.avatar_url || null}
    banner={settings.get('profile.banner')}
    background={settings.get('profile.background')}
    {color}
    {status}
    {bio}
    {links}
    layout={settings.get('profile.layout')}
    nickFont={settings.get('profile.nick_font')}
    nickEffect={settings.get('profile.nick_effect')}
    nickColor2={color2}
    showcase={visibleShowcase(showcase, hidden)}
  />
</div>

<Card title={t('Картинки')}>
  {#each PICTURES as pic (pic.key)}
    {@const url = settings.get(pic.key)}
    <div class="pic-row">
      <span class="thumb {pic.key.slice(8)}">{#if url}<img src={offline.src(url)} alt="" />{:else}<Icon name={pic.key === 'profile.avatar' ? 'user' : 'photo'} size={16} />{/if}</span>
      <span class="text"><b>{t(pic.label)}</b><small>{t(pic.hint)}</small></span>
      <span class="acts">
        <button class="btn" onclick={() => choose(pic.key)}>{url ? t('Заменить') : t('Выбрать')}</button>
        {#if url}<button class="btn ghost" onclick={() => settings.set(pic.key, '')}>{t('Убрать')}</button>{/if}
      </span>
    </div>
  {/each}
  <input bind:this={fileInput} type="file" accept="image/*" hidden onchange={onFile} />
</Card>

<Card title={t('Цвет профиля')} hint={t('Красит ник, кольцо аватара и акценты профиля')}>
  <div class="colors" role="radiogroup" aria-label={t('Цвет профиля')}>
    <button class="dot none" class:on={!settings.get('profile.color')} role="radio" aria-checked={!settings.get('profile.color')} title={t('Без цвета')} onclick={() => settings.set('profile.color', '')}>
      <Icon name="x" size={14} />
    </button>
    {#each PROFILE_COLORS as c (c.id)}
      {@const on = settings.get('profile.color') === c.id}
      <button class="dot" class:on role="radio" aria-checked={on} aria-label={c.id} style:--c={c.hex} onclick={() => settings.set('profile.color', c.id)}></button>
    {/each}
  </div>
</Card>

<Card title={t('Имя и описание')}>
  <label class="field">
    <span class="text"><b>{t('Отображаемое имя')}</b><small>{#if fallback?.name}{t('Его видно на главной: «Добрый вечер, …» · пусто — «{name}» из сервиса', { name: fallback.name })}{:else}{t('Его видно на главной: «Добрый вечер, …»')}{/if}</small></span>
    <input maxlength={NAME_MAX} placeholder={fallback?.name ?? t('Как тебя называть')} bind:value={name} onblur={saveName} onkeydown={(e) => e.key === 'Enter' && saveName()} />
  </label>
  <label class="field" class:bad={!userOk}>
    <span class="text"><b>{t('Имя пользователя')}</b><small>{userOk ? t('Латиница, цифры и «_», 3–32 знака') : t('Только латиница, цифры и «_», от 3 до 32 знаков')}</small></span>
    <span class="at"><i>@</i><input maxlength="33" placeholder="username" bind:value={username} onblur={saveUser} onkeydown={(e) => e.key === 'Enter' && saveUser()} /></span>
  </label>
  <label class="field">
    <span class="text"><b>{t('Статус')}</b><small>{t('Короткая строка под ником')}</small></span>
    <input maxlength={STATUS_MAX} placeholder={t('Что у тебя нового?')} bind:value={status} onblur={saveStatus} onkeydown={(e) => e.key === 'Enter' && saveStatus()} />
  </label>
  <label class="field col">
    <span class="text"><b>{t('О себе')}</b><small>{bio.length} / {BIO_MAX}</small></span>
    <textarea maxlength={BIO_MAX} rows="3" placeholder={t('Пара слов о себе и своей музыке')} bind:value={bio} onblur={saveBio}></textarea>
  </label>
</Card>

<Card title={t('Ссылки')} hint={t('Telegram, Discord или сайт — до {n}', { n: LINKS_MAX })}>
  {#if links.length}
    <div class="chips">
      {#each links as l (l.url)}
        <span class="chip" transition:slide={{ axis: 'x', duration: 160 }}>
          <Icon name={l.kind === 'telegram' ? 'telegram' : l.kind === 'discord' ? 'discord' : 'world'} size={14} />
          <span>{linkLabel(l)}</span>
          <button title={t('Убрать')} onclick={() => settings.set('profile.links', removeLink(links, l.url))}><Icon name="x" size={12} /></button>
        </span>
      {/each}
    </div>
  {/if}
  {#if links.length < LINKS_MAX}
    <div class="add-link" class:bad={!linkOk}>
      <input placeholder={t('@ник в Telegram или ссылка')} bind:value={linkInput} onkeydown={onLinkKey} />
      <button class="btn" disabled={!linkInput.trim() || !linkOk} onclick={addTypedLink}><Icon name="plus" size={14} />{t('Добавить')}</button>
    </div>
  {/if}
</Card>

<Card title={t('Вид профиля')}>
  <PreviewTiles
    value={settings.get('profile.layout')}
    options={PROFILE_LAYOUTS.map((l) => ({ id: l.id, label: t(l.label) }))}
    onchange={(v) => settings.set('profile.layout', v)}
    tile={layoutTile}
  />
  <PreviewTiles
    title={t('Шрифт ника')}
    cols={3}
    value={settings.get('profile.nick_font')}
    options={NICK_FONTS.map((f) => ({ id: f.id, label: f.id === 'default' ? t(f.label) : f.label }))}
    onchange={(v) => settings.set('profile.nick_font', v)}
    tile={fontTile}
  />
  <PreviewTiles
    title={t('Эффект ника')}
    value={settings.get('profile.nick_effect')}
    options={NICK_EFFECTS.map((e) => ({ id: e.id, label: t(e.label) }))}
    onchange={(v) => settings.set('profile.nick_effect', v)}
    tile={effectTile}
  />
  {#if settings.get('profile.nick_effect') === 'shimmer'}
    <div class="second" transition:slide={{ duration: 200 }}>
      <span class="text"><b>{t('Второй цвет перелива')}</b><small>{t('Первый — цвет профиля')}</small></span>
      <div class="colors" role="radiogroup" aria-label={t('Второй цвет перелива')}>
        <button class="dot none" class:on={!settings.get('profile.nick_color2')} role="radio" aria-checked={!settings.get('profile.nick_color2')} title={t('По умолчанию')} onclick={() => settings.set('profile.nick_color2', '')}>
          <Icon name="x" size={14} />
        </button>
        {#each PROFILE_COLORS as c (c.id)}
          {@const on = settings.get('profile.nick_color2') === c.id}
          <button class="dot" class:on role="radio" aria-checked={on} aria-label={c.id} style:--c={c.hex} onclick={() => settings.set('profile.nick_color2', c.id)}></button>
        {/each}
      </div>
    </div>
  {/if}
</Card>

<Card title={t('Витрина')} hint={t('Покажи в профиле то, что любишь: плейлист, альбом, исполнителя или трек')}>
  <div class="slots">
    {#each showcase as s (s.kind + s.ref)}
      <span class="slot" class:hidden-pl={!visibleShowcase([s], hidden).length} transition:slide={{ duration: 160 }}>
        <span class="art" class:round={s.kind === 'artist'}>
          {#if s.cover_url}<img src={offline.src(s.cover_url)} alt="" loading="lazy" />{:else}<Icon name={s.kind === 'playlist' ? 'playlist' : 'music'} size={18} />{/if}
        </span>
        <span class="meta"><b>{s.title}</b><small>{s.subtitle || t(KIND_LABEL[s.kind])}</small></span>
        <button class="rm" title={t('Убрать из витрины')} onclick={() => settings.set('profile.showcase', removeShowcase(showcase, s.kind, s.ref))}><Icon name="x" size={12} /></button>
      </span>
    {/each}
    {#if showcase.length < SHOWCASE_MAX}
      <button class="slot add" class:open={picking} onclick={() => (picking = !picking)}>
        <span class="art"><Icon name={picking ? 'minus' : 'plus'} size={18} /></span>
        <span class="meta"><b>{picking ? t('Готово') : t('Добавить')}</b><small>{t('ещё {n} из {max}', { n: SHOWCASE_MAX - showcase.length, max: SHOWCASE_MAX })}</small></span>
      </button>
    {/if}
  </div>
  {#if picking && showcase.length < SHOWCASE_MAX}<ShowcasePicker taken={showcase} onpick={pickShowcase} />{/if}
</Card>

<Card title={t('Публичный профиль')}>
  <div class="share">
    <span class="text">
      <small class="url">{profileUrl(settings.get('profile.username')) ?? t('Задай @username — тогда появится ссылка')}</small>
    </span>
    <span class="buttons">
      <CopyProfileLink username={settings.get('profile.username')} />
      <button class="look" onclick={preview}><Icon name="eye" size={16} />{t('Как видят мой профиль')}</button>
    </span>
    <small class="hint">{t('Страница по ссылке заработает, когда у Sonar появится сервер. Сейчас профиль хранится на этом компьютере и в синхронизации настроек.')}</small>
  </div>
</Card>

<style>
  .preview {
    margin: 2px 0 6px;
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
  .btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 30px;
    padding: 0 12px;
    border-radius: 9px;
    background: var(--surface-3);
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease),
      opacity var(--fast) var(--ease);
  }
  .btn:hover:not(:disabled) {
    background: color-mix(in srgb, var(--text) 14%, var(--surface-3));
  }
  .btn:active:not(:disabled) {
    transform: scale(0.96);
  }
  .btn:disabled {
    opacity: 0.45;
  }
  .btn.ghost {
    background: none;
    color: var(--text-2);
  }
  /* узкое окно: кнопки уходят под подпись (правило строк настроек, settings-row.css) */
  .pic-row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px 12px;
    padding: 8px 0;
  }
  .pic-row .text {
    flex: 999 1 10rem;
  }
  .thumb {
    flex-shrink: 0;
    display: grid;
    place-items: center;
    width: 54px;
    height: 36px;
    border-radius: 8px;
    overflow: hidden;
    background: var(--surface-3);
    color: var(--text-3);
  }
  .thumb.avatar {
    width: 36px;
    border-radius: 50%;
  }
  .thumb img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    animation: fade var(--normal) var(--ease);
  }
  .acts {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    margin-left: auto;
  }
  .colors {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    padding: 10px 0;
  }
  .dot {
    flex: none;
    width: 32px;
    aspect-ratio: 1;
    border-radius: 50%;
    background: var(--c);
    box-shadow: 0 0 0 0 var(--c);
    transition:
      transform var(--fast) var(--ease),
      box-shadow var(--fast) var(--ease);
  }
  .dot:hover {
    transform: scale(1.08);
  }
  .dot.on {
    box-shadow:
      0 0 0 3px var(--surface-1),
      0 0 0 5px var(--c, var(--text));
  }
  .dot.none {
    display: grid;
    place-items: center;
    background: var(--surface-3);
    color: var(--text-3);
  }
  /* поле рядом с подписью, пока влезает; иначе — под подписью во всю ширину */
  .field {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px 16px;
    padding: 9px 0;
  }
  .field:not(.col) > .text {
    flex: 999 1 13rem;
  }
  .field:not(.col) > input,
  .field > .at {
    flex: 1 0 14rem;
    max-width: 100%;
    min-width: 0;
  }
  .field:not(.col) > input,
  .at input {
    width: 100%;
  }
  .field.col {
    flex-wrap: nowrap;
    flex-direction: column;
    align-items: stretch;
    gap: 8px;
  }
  .field.col .text {
    flex-direction: row;
    justify-content: space-between;
  }
  input,
  textarea {
    width: 220px;
    height: 34px;
    padding: 0 12px;
    border-radius: var(--radius-m);
    border: 1px solid var(--border);
    background: var(--surface-1);
    color: var(--text);
    font: inherit;
    transition: border-color var(--fast) var(--ease);
  }
  textarea {
    width: auto;
    height: auto;
    padding: 8px 12px;
    resize: vertical;
    line-height: 1.45;
  }
  input:focus,
  textarea:focus {
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
  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    padding: 10px 0 2px;
  }
  .chip {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    max-width: 100%;
    height: 30px;
    padding: 0 6px 0 10px;
    border-radius: 999px;
    background: var(--surface-3);
    font-size: calc(12px * var(--fs, 1));
    white-space: nowrap;
  }
  .chip span {
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .chip button {
    display: grid;
    place-items: center;
    width: 20px;
    height: 20px;
    border-radius: 50%;
    color: var(--text-3);
    transition: background var(--fast) var(--ease);
  }
  .chip button:hover {
    background: color-mix(in srgb, var(--text) 14%, transparent);
    color: var(--text);
  }
  .add-link {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    padding: 10px 0;
  }
  .add-link input {
    flex: 1 1 12rem;
    width: auto;
    min-width: 0;
  }
  .sample {
    width: 100%;
    display: grid;
    place-items: center;
    height: 54px;
    padding: 0 8px;
    overflow: hidden;
  }
  .mock {
    display: flex;
    flex-direction: column;
    align-self: flex-end;
    width: 62%;
    height: 46px;
    padding: 0 6px 6px;
    border-radius: 8px 8px 0 0;
    background: var(--surface-3);
    overflow: hidden;
  }
  .mock .b {
    height: 20px;
    margin: 0 -6px;
    background: linear-gradient(120deg, var(--pc), color-mix(in srgb, var(--pc) 35%, var(--surface-3)));
  }
  .mock .h {
    display: flex;
    align-items: flex-end;
    gap: 5px;
    margin-top: -9px;
  }
  .mock .a {
    width: 18px;
    height: 18px;
    flex-shrink: 0;
    border-radius: 50%;
    background: var(--text-3);
    box-shadow: 0 0 0 2px var(--surface-3);
  }
  .mock .l {
    display: flex;
    flex-direction: column;
    gap: 3px;
    flex: 1;
  }
  .mock .l i {
    height: 4px;
    width: 70%;
    border-radius: 2px;
    background: var(--text-2);
  }
  .mock .l i + i {
    width: 45%;
    background: var(--text-3);
  }
  .mock.lay-big_name .b {
    height: 14px;
  }
  .mock.lay-big_name .h {
    align-items: center;
    margin-top: 7px;
  }
  .mock.lay-big_name .a {
    width: 11px;
    height: 11px;
  }
  .mock.lay-big_name .l i:first-child {
    height: 9px;
    width: 90%;
  }
  .mock.lay-banner .b {
    height: 38px;
  }
  .mock.lay-banner .h {
    margin-top: -16px;
  }
  .mock.lay-center .h {
    flex-direction: column;
    align-items: center;
  }
  .mock.lay-center .l {
    align-items: center;
    width: 100%;
  }
  /* до трёх в ряд, не уже 170px */
  .slots {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(min(100%, max(170px, (100% - 16px) / 3)), 1fr));
    gap: 8px;
    padding: 10px 0;
  }
  .slot {
    position: relative;
    display: flex;
    align-items: center;
    gap: 10px;
    min-width: 0;
    padding: 8px;
    border-radius: var(--radius-m);
    background: var(--surface-3);
    text-align: left;
  }
  .slot.hidden-pl {
    opacity: 0.5;
  }
  .slot.add {
    background: none;
    border: 1.5px dashed var(--border);
    transition:
      border-color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .slot.add:hover,
  .slot.add.open {
    border-color: var(--accent);
  }
  .slot.add:active {
    transform: scale(0.98);
  }
  .slot .art {
    flex-shrink: 0;
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    border-radius: 7px;
    overflow: hidden;
    background: color-mix(in srgb, var(--text) 8%, var(--surface-1));
    color: var(--text-3);
  }
  .slot .art.round {
    border-radius: 50%;
  }
  .slot .art img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .slot .meta {
    display: flex;
    flex-direction: column;
    min-width: 0;
    flex: 1;
  }
  .slot .meta b,
  .slot .meta small {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .slot .meta b {
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
  }
  .slot .meta small {
    font-size: calc(11px * var(--fs, 1));
    color: var(--text-3);
  }
  .rm {
    position: absolute;
    top: 4px;
    right: 4px;
    display: grid;
    place-items: center;
    width: 20px;
    height: 20px;
    border-radius: 50%;
    background: var(--surface-1);
    color: var(--text-3);
    opacity: 0;
    transition: opacity var(--fast) var(--ease);
  }
  .slot:hover .rm,
  .rm:focus-visible {
    opacity: 1;
  }
  .share {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 10px 16px;
    padding: 10px 0;
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
  @keyframes fade {
    from {
      opacity: 0;
    }
  }
  .second {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-top: 12px;
  }
  .second .text {
    display: flex;
    flex-direction: column;
  }
  .second small {
    color: var(--text-3);
    font-size: calc(12px * var(--fs, 1));
  }
</style>
