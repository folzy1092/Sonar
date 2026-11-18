<script lang="ts">
  // Превью профиля «как увидят другие» (Аккаунт → Профиль, SETTINGS_NEXT «Профиль»): фон, баннер, аватар
  // с точкой «в сети» и кольцом цвета профиля, ник в своём шрифте и эффекте, @username, статус, о себе,
  // ссылки и витрина. Четыре раскладки шапки (`layout`) переключаются плавно. Только рисует — данные
  // приходят готовыми (lib/profile-look.ts).
  import Icon from '../Icon.svelte'
  import Nick from './Nick.svelte'
  import { t } from '../../lib/i18n.svelte'
  import { linkLabel, type NickEffect, type ProfileLayout, type ProfileLink, type ShowcaseItem } from '../../lib/profile-look'

  interface Props {
    name: string
    username: string
    avatar: string | null
    banner: string
    background: string
    color: string | null
    status: string
    bio: string
    links: readonly ProfileLink[]
    layout: ProfileLayout
    nickFont: string
    nickEffect: NickEffect
    showcase: readonly ShowcaseItem[]
  }
  let p: Props = $props()

  const LINK_ICON = { telegram: 'telegram', discord: 'discord', site: 'world' } as const
  const KIND_ICON = { playlist: 'playlist', album: 'disc', artist: 'user', track: 'music' } as const
  const initial = $derived((p.name.trim() || p.username || '?').slice(0, 1).toUpperCase())
</script>

<article class="card lay-{p.layout}" style:--pc={p.color ?? 'var(--accent)'}>
  {#if p.background}<div class="bg" style:background-image="url({p.background})"></div>{/if}
  <div class="banner" class:empty={!p.banner}>
    {#if p.banner}<img src={p.banner} alt="" draggable="false" />{/if}
  </div>
  <header class="head">
    <span class="ava">
      {#if p.avatar}<img src={p.avatar} alt="" draggable="false" />{:else}<b>{initial}</b>{/if}
      <i class="online" title={t('В сети')}></i>
    </span>
    <div class="who">
      <Nick text={p.name.trim() || t('Без имени')} font={p.nickFont} effect={p.nickEffect} color={p.color} size={p.layout === 'big_name' ? 34 : 22} />
      <small>{p.username ? `@${p.username}` : t('без @username')}</small>
    </div>
  </header>
  {#if p.status.trim()}<p class="status">{p.status}</p>{/if}
  {#if p.bio.trim()}<p class="bio">{p.bio}</p>{/if}
  {#if p.links.length}
    <div class="links">
      {#each p.links as l (l.url)}<span class="chip"><Icon name={LINK_ICON[l.kind]} size={14} />{linkLabel(l)}</span>{/each}
    </div>
  {/if}
  {#if p.showcase.length}
    <div class="show">
      {#each p.showcase as s (s.kind + s.ref)}
        <span class="tile" title={s.subtitle ? `${s.title} — ${s.subtitle}` : s.title}>
          <span class="art" class:round={s.kind === 'artist'}>
            {#if s.cover_url}<img src={s.cover_url} alt="" loading="lazy" draggable="false" />{:else}<Icon name={KIND_ICON[s.kind]} size={18} />{/if}
          </span>
          <b>{s.title}</b>
        </span>
      {/each}
    </div>
  {/if}
</article>

<style>
  .card {
    position: relative;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    gap: 8px;
    padding: 0 16px 16px;
    border-radius: var(--radius-l, 16px);
    background: var(--surface-1);
    border: 1px solid var(--border);
    isolation: isolate;
  }
  .bg {
    position: absolute;
    inset: 0;
    z-index: -1;
    background: center / cover no-repeat;
    opacity: 0.32;
    filter: blur(2px);
    transform: scale(1.04);
    animation: fade var(--normal) var(--ease);
  }
  .banner {
    height: 104px;
    margin: 0 -16px;
    overflow: hidden;
    background: linear-gradient(135deg, color-mix(in srgb, var(--pc) 70%, #000), color-mix(in srgb, var(--pc) 25%, var(--surface-3)));
    transition:
      height var(--normal) var(--ease),
      background var(--normal) var(--ease);
  }
  .banner img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
    animation: fade var(--normal) var(--ease);
  }
  .head {
    display: flex;
    align-items: flex-end;
    gap: 12px;
    margin-top: -34px;
    min-width: 0;
    transition: margin var(--normal) var(--ease);
  }
  .ava {
    position: relative;
    flex-shrink: 0;
    display: grid;
    place-items: center;
    width: 76px;
    height: 76px;
    border-radius: 50%;
    background: var(--surface-3);
    box-shadow:
      0 0 0 3px var(--surface-1),
      0 0 0 5px var(--pc);
    transition:
      width var(--normal) var(--ease),
      height var(--normal) var(--ease),
      box-shadow var(--normal) var(--ease);
  }
  .ava img {
    width: 100%;
    height: 100%;
    border-radius: 50%;
    object-fit: cover;
  }
  .ava b {
    font-size: calc(26px * var(--fs, 1));
    color: var(--text-2);
  }
  .online {
    position: absolute;
    right: 2px;
    bottom: 2px;
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: #2ecc71;
    border: 3px solid var(--surface-1);
  }
  .who {
    display: flex;
    flex-direction: column;
    min-width: 0;
    padding-bottom: 4px;
  }
  .who small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .status {
    align-self: flex-start;
    max-width: 100%;
    margin: 2px 0 0;
    padding: 5px 10px;
    border-radius: 10px;
    background: var(--surface-3);
    font-size: calc(12px * var(--fs, 1));
    overflow-wrap: anywhere;
  }
  .bio {
    margin: 0;
    font-size: calc(13px * var(--fs, 1));
    line-height: 1.45;
    color: var(--text-2);
    white-space: pre-line;
    overflow-wrap: anywhere;
  }
  .links {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .chip {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    max-width: 100%;
    height: 28px;
    padding: 0 10px;
    border-radius: 999px;
    background: color-mix(in srgb, var(--pc) 16%, var(--surface-3));
    font-size: calc(12px * var(--fs, 1));
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .show {
    display: grid;
    grid-template-columns: repeat(6, minmax(0, 1fr));
    gap: 8px;
    margin-top: 4px;
  }
  .tile {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
    animation: fade var(--normal) var(--ease);
  }
  .art {
    display: grid;
    place-items: center;
    aspect-ratio: 1;
    border-radius: 8px;
    overflow: hidden;
    background: var(--surface-3);
    color: var(--text-3);
  }
  .art.round {
    border-radius: 50%;
  }
  .art img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .tile b {
    font-size: calc(11px * var(--fs, 1));
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  /* Большой ник: аватар маленький, ник крупно */
  .lay-big_name .banner {
    height: 76px;
  }
  .lay-big_name .head {
    align-items: center;
    margin-top: 10px;
  }
  .lay-big_name .ava {
    width: 44px;
    height: 44px;
  }
  .lay-big_name .ava b {
    font-size: calc(16px * var(--fs, 1));
  }
  .lay-big_name .online {
    width: 11px;
    height: 11px;
    border-width: 2px;
    right: 0;
    bottom: 0;
  }
  /* Баннер-обложка: высокий баннер, шапка поверх его низа */
  .lay-banner .banner {
    height: 168px;
    mask-image: linear-gradient(#000 55%, transparent);
  }
  .lay-banner .head {
    margin-top: -70px;
  }
  /* По центру */
  .lay-center .head {
    flex-direction: column;
    align-items: center;
    text-align: center;
    gap: 6px;
  }
  .lay-center .who {
    align-items: center;
  }
  .lay-center .status {
    align-self: center;
  }
  .lay-center .bio {
    text-align: center;
  }
  .lay-center .links {
    justify-content: center;
  }
  @keyframes fade {
    from {
      opacity: 0;
    }
  }
</style>
