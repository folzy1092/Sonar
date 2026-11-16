<script lang="ts" generics="T extends string">
  // Выпадающий список настройки (как «Формат статуса» у Discord): название и подсказка слева,
  // справа кнопка с выбранным; список открывается и закрывается только кликом.
  import { onMount } from 'svelte'
  import Icon from '../Icon.svelte'
  import { pop } from '../../lib/motion'

  interface Props {
    title: string
    hint?: string
    value: T
    options: { id: T; label: string }[]
    onchange: (v: T) => void
  }
  let { title, hint, value, options, onchange }: Props = $props()
  let open = $state(false)
  let root: HTMLDivElement | undefined = $state()
  const current = $derived(options.find((o) => o.id === value)?.label ?? '')

  onMount(() => {
    const outside = (e: MouseEvent) => {
      if (open && root && !root.contains(e.target as Node)) open = false
    }
    window.addEventListener('mousedown', outside, true)
    return () => window.removeEventListener('mousedown', outside, true)
  })
</script>

<div class="row">
  <span class="text">
    <b>{title}</b>
    {#if hint}<small>{hint}</small>{/if}
  </span>
  <div class="wrap" bind:this={root}>
    <button class="btn" class:open aria-haspopup="listbox" aria-expanded={open} onclick={() => (open = !open)}>
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
            onclick={() => {
              onchange(o.id)
              open = false
            }}>{o.label}</button
          >
        {/each}
      </div>
    {/if}
  </div>
</div>

<style>
  .row {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 9px 0;
  }
  .text {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }
  b {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .wrap {
    position: relative;
    flex: none;
  }
  .btn {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    max-width: 190px;
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
    min-width: 210px;
    padding: 5px;
    border-radius: 14px;
    background: var(--surface-2);
    border: 1px solid var(--border-strong);
    box-shadow: 0 18px 40px rgba(0, 0, 0, 0.5);
    transform-origin: top right;
  }
  .opt {
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
  .opt.on {
    background: var(--surface-3);
    color: var(--text);
    font-weight: 600;
  }
</style>
