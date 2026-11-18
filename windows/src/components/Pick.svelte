<script lang="ts" generics="T extends string">
  // Маленький выпадающий выбор внутри строки (конструктор умного плейлиста): кнопка с текущим
  // значением, список открывается и закрывается только кликом (клик мимо — закрывает).
  import { onMount } from 'svelte'
  import Icon from './Icon.svelte'
  import { pop } from '../lib/motion'

  interface Props {
    value: T
    options: { id: T; label: string }[]
    onchange: (v: T) => void
    /** Подпись для чтения с экрана. */
    label?: string
  }
  let { value, options, onchange, label }: Props = $props()
  let open = $state(false)
  let root: HTMLSpanElement | undefined = $state()
  const current = $derived(options.find((o) => o.id === value)?.label ?? '')

  onMount(() => {
    const outside = (e: MouseEvent) => {
      if (open && root && !root.contains(e.target as Node)) open = false
    }
    window.addEventListener('mousedown', outside, true)
    return () => window.removeEventListener('mousedown', outside, true)
  })
</script>

<span class="pick" class:open bind:this={root}>
  <button type="button" class="btn" aria-haspopup="listbox" aria-expanded={open} aria-label={label} onclick={() => (open = !open)}>
    <span class="cur">{current}</span>
    <span class="chev"><Icon name="chevronDown" size={13} /></span>
  </button>
  {#if open}
    <span class="list" role="listbox" in:pop={{ y: -6 }} out:pop={{ y: -6 }}>
      {#each options as o (o.id)}
        <button
          type="button"
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
    </span>
  {/if}
</span>

<style>
  .pick {
    position: relative;
    display: inline-flex;
  }
  .pick.open {
    z-index: 5;
  }
  .btn {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 30px;
    padding: 0 10px 0 12px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    font-weight: 600;
    white-space: nowrap;
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .btn:hover {
    background: var(--hover);
  }
  .btn:active {
    transform: scale(0.97);
  }
  .chev {
    display: inline-flex;
    color: var(--text-3);
    transition: transform var(--fast) var(--ease);
  }
  .open .chev {
    transform: rotate(180deg);
  }
  .list {
    position: absolute;
    top: calc(100% + 6px);
    left: 0;
    display: flex;
    flex-direction: column;
    min-width: 100%;
    max-height: 260px;
    overflow-y: auto;
    padding: 6px;
    border-radius: var(--radius-m);
    background: var(--surface-2);
    border: 1px solid var(--border-strong);
    box-shadow: 0 16px 40px rgba(0, 0, 0, 0.45);
  }
  .opt {
    padding: 7px 10px;
    border-radius: var(--radius-s, 8px);
    text-align: left;
    white-space: nowrap;
    transition: background var(--fast) var(--ease);
  }
  .opt:hover {
    background: var(--hover);
  }
  .opt.on {
    color: var(--accent);
    font-weight: 600;
  }
</style>
