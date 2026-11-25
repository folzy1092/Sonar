<script lang="ts">
  // «Вы вошли как» в медиатеке: аватарки и ники подключённых аккаунтов. Клик — список под ними:
  // аватар, ник, значок и название сервиса; где сервис отдал адрес профиля — строка открывает его
  // в браузере. Открывается и закрывается только кликом (по кнопке, мимо списка) или Escape.
  import Icon from './Icon.svelte'
  import SourceIcon from './SourceIcon.svelte'
  import { api } from '../lib/api'
  import { byId } from '../lib/services'
  import type { AccountRow } from '../lib/accounts'
  import { offline } from '../lib/offline.svelte'
  import { pop } from '../lib/motion'
  import { cascade } from '../lib/cascade'
  import { toast } from '../lib/toast.svelte'
  import { t } from '../lib/i18n.svelte'

  let { rows, onopen }: { rows: AccountRow[]; onopen?: () => void } = $props()

  let open = $state(false)
  let root: HTMLElement | undefined = $state()

  function toggle() {
    open = !open
    if (open) onopen?.()
  }

  function outside(e: PointerEvent) {
    if (open && root && !root.contains(e.target as Node)) open = false
  }

  function go(url: string) {
    api.openUrl(url).catch(() => toast.show(url))
  }

  const nameOf = (r: AccountRow) => r.name ?? t('аккаунт')
</script>

<svelte:window onpointerdown={outside} onkeydown={(e) => e.key === 'Escape' && (open = false)} />

<div class="wrap" bind:this={root}>
  <button class="who-btn" class:on={open} aria-expanded={open} aria-haspopup="true" title={t('Показать аккаунты')} onclick={toggle}>
    <span class="avatars">
      {#each rows as r, i (i)}
        <span class="av">{#if r.avatar}<img src={offline.src(r.avatar)} alt="" />{:else}{(r.name ?? '?').slice(0, 1).toUpperCase()}{/if}</span>
      {/each}
    </span>
    <b>{rows.map(nameOf).join(', ')}</b>
    <span class="chev" class:up={open}><Icon name="chevronDown" size={16} /></span>
  </button>

  {#if open}
    <div class="pop" role="menu" in:pop={{ y: -6 }} out:pop={{ y: -6 }}>
      <div class="rows" use:cascade>
        {#each rows as r, i (i)}
          {@const svc = byId(r.service)}
          {#snippet face()}
            <span class="av big">{#if r.avatar}<img src={offline.src(r.avatar)} alt="" />{:else}{(r.name ?? '?').slice(0, 1).toUpperCase()}{/if}</span>
            <span class="nick">{nameOf(r)}</span>
            <span class="svc"><SourceIcon service={r.service} size={16} plain />{svc ? t(svc.name) : ''}</span>
          {/snippet}
          {#if r.url}
            {@const url = r.url}
            <button class="row link" role="menuitem" title={t('Открыть профиль')} onclick={() => go(url)}>
              {@render face()}
              <span class="go"><Icon name="link" size={16} /></span>
            </button>
          {:else}
            <div class="row" role="menuitem" aria-disabled="true">{@render face()}</div>
          {/if}
        {/each}
      </div>
    </div>
  {/if}
</div>

<style>
  .wrap {
    position: relative;
  }
  .who-btn {
    display: inline-flex;
    align-items: center;
    gap: var(--sp-2);
    padding: var(--sp-1) var(--sp-2) var(--sp-1) var(--sp-1);
    margin: calc(var(--sp-1) * -1) 0 calc(var(--sp-1) * -1) calc(var(--sp-1) * -1);
    border-radius: var(--ctl-s);
    font: inherit;
    color: var(--text);
    transition: background var(--fast) var(--ease);
  }
  .who-btn:hover,
  .who-btn.on {
    background: var(--hover);
  }
  .who-btn b {
    color: var(--text);
  }
  .chev {
    display: grid;
    color: var(--text-3);
    transition: transform var(--fast) var(--ease);
  }
  .chev.up {
    transform: rotate(180deg);
  }
  .avatars {
    display: flex;
  }
  .av {
    display: grid;
    place-items: center;
    flex: none;
    width: 30px;
    height: 30px;
    margin-left: -8px;
    overflow: hidden;
    border-radius: 50%;
    border: 2px solid var(--surface-0);
    background: var(--surface-3);
    color: var(--text);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 700;
  }
  .avatars .av:first-child {
    margin-left: 0;
  }
  .av img {
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
  .pop {
    position: absolute;
    top: calc(100% + var(--sp-2));
    left: 0;
    z-index: 40;
    min-width: 280px;
    max-width: 360px;
    padding: var(--sp-2);
    border-radius: var(--radius-l);
    background: var(--surface-2);
    border: 1px solid var(--border-strong);
    box-shadow: 0 16px 40px rgba(0, 0, 0, 0.45);
    transform-origin: top left;
  }
  .rows {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }
  .row {
    display: flex;
    align-items: center;
    gap: var(--sp-3);
    width: 100%;
    padding: var(--sp-2) var(--sp-3) var(--sp-2) var(--sp-2);
    border-radius: var(--radius-m, 12px);
    text-align: left;
    font-size: var(--fs-2);
    color: var(--text);
  }
  .row.link {
    transition: background var(--fast) var(--ease);
  }
  .row.link:hover {
    background: var(--hover);
  }
  .av.big {
    width: var(--ctl-s);
    height: var(--ctl-s);
    margin: 0;
    border: 0;
  }
  .nick {
    flex: 0 1 auto;
    min-width: 0;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
    font-weight: 700;
  }
  .svc {
    display: inline-flex;
    align-items: center;
    gap: var(--sp-2);
    flex: none;
    font-size: var(--fs-meta);
    color: var(--text-2);
  }
  .go {
    display: grid;
    flex: none;
    margin-left: auto;
    color: var(--text-3);
    transition: color var(--fast) var(--ease);
  }
  .row.link:hover .go {
    color: var(--text);
  }
</style>
