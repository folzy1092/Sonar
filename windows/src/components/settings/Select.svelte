<script lang="ts" generics="T extends string">
  // Выпадающий список настройки (как «Формат статуса» у Discord): название и подсказка слева,
  // справа кнопка с выбранным; список открывается и закрывается только кликом. Узкое окно — кнопка
  // уходит под название во всю ширину (общая раскладка settings-row.css).
  import { onMount } from 'svelte'
  import './settings-row.css'
  import Icon from '../Icon.svelte'
  import { pop } from '../../lib/motion'
  import Flag from '../Flag.svelte'
  import { t } from '../../lib/i18n.svelte'

  interface Props {
    title: string
    hint?: string
    value: T
    /** `flag` — флаг языка слева, `soon` — пункт виден, но выбрать нельзя. */
    options: { id: T; label: string; flag?: string; soon?: boolean }[]
    onchange: (v: T) => void
  }
  let { title, hint, value, options, onchange }: Props = $props()
  let open = $state(false)
  let root: HTMLDivElement | undefined = $state()
  const cur = $derived(options.find((o) => o.id === value))
  const current = $derived(cur?.label ?? '')

  onMount(() => {
    const outside = (e: MouseEvent) => {
      if (open && root && !root.contains(e.target as Node)) open = false
    }
    window.addEventListener('mousedown', outside, true)
    return () => window.removeEventListener('mousedown', outside, true)
  })
</script>

<div class="set-row row" class:open>
  <span class="set-text">
    <b>{title}</b>
    {#if hint}<small>{hint}</small>{/if}
  </span>
  <div class="wrap" bind:this={root}>
    <button class="btn" class:open aria-haspopup="listbox" aria-expanded={open} onclick={() => (open = !open)}>
      {#if cur?.flag}<Flag lang={cur.flag} size={18} />{/if}
      <span class="cur">{current}</span>
      <span class="chev"><Icon name="chevronDown" size={15} /></span>
    </button>
    {#if open}
      <div class="list" role="listbox" in:pop={{ y: -6 }} out:pop={{ y: -6 }}>
        {#each options as o (o.id)}
          <button
            class="opt"
            class:on={o.id === value}
            role="option"
            aria-selected={o.id === value}
            disabled={o.soon}
            title={o.soon ? t('{label} — скоро', { label: o.label }) : undefined}
            onclick={() => {
              onchange(o.id)
              open = false
            }}
            >{#if o.flag}<Flag lang={o.flag} size={18} />{/if}<span>{o.label}</span>{#if o.soon}<i class="soon">{t('скоро')}</i>{/if}</button
          >
        {/each}
      </div>
    {/if}
  </div>
</div>

<style>
  .row {
    position: relative;
  }
  /* открытый список — поверх следующих строк настроек */
  .row.open {
    z-index: 50;
  }
  .wrap {
    position: relative;
    flex: 1 0 auto;
    display: flex;
    max-width: 100%;
    min-width: 0;
  }
  .btn {
    flex: 1 1 auto;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
    max-width: 100%;
    height: 34px;
    padding: 0 10px 0 12px;
    border-radius: 11px;
    background: var(--surface-2);
    border: 1px solid var(--border);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    transition: background var(--fast) var(--ease);
  }
  .btn:hover,
  .btn.open {
    background: var(--surface-3);
  }
  .cur {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .chev {
    display: grid;
    margin-left: auto;
    color: var(--text-3);
    transition: transform var(--normal) var(--ease);
  }
  .open .chev {
    transform: rotate(180deg);
  }
  .list {
    position: absolute;
    top: calc(100% + 6px);
    right: 0;
    z-index: 30;
    display: flex;
    flex-direction: column;
    min-width: max(100%, 210px);
    padding: 5px;
    border-radius: 14px;
    background: var(--surface-2);
    border: 1px solid var(--border-strong);
    box-shadow: 0 18px 40px rgba(0, 0, 0, 0.5);
    transform-origin: top right;
  }
  .opt {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 10px;
    border-radius: 9px;
    text-align: left;
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .opt:hover {
    background: var(--hover);
    color: var(--text);
  }
  .opt:disabled {
    cursor: default;
    opacity: 0.55;
  }
  .opt:disabled:hover {
    background: none;
    color: var(--text-2);
  }
  .soon {
    margin-left: auto;
    font-style: normal;
    font-size: calc(11px * var(--fs, 1));
    color: var(--text-3);
  }
  .opt.on {
    background: var(--surface-3);
    color: var(--text);
    font-weight: 600;
  }
</style>
