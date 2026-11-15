<script lang="ts">
  // Строка настройки с переключателем (pc/Screenshot_4, 14, 16): название, подсказка, тумблер справа.
  // `soon` — пункт есть на референсе, но ещё не работает: неактивен и с пометкой «Скоро».
  import Soon from './Soon.svelte'
  interface Props {
    title: string
    hint?: string
    on: boolean
    onchange?: (v: boolean) => void
    soon?: boolean
  }
  let { title, hint, on, onchange, soon = false }: Props = $props()
</script>

<button class="row" class:soon role="switch" aria-checked={on} disabled={soon} onclick={() => onchange?.(!on)}>
  <span class="text">
    <b>{title}{#if soon}<Soon />{/if}</b>
    {#if hint}<small>{hint}</small>{/if}
  </span>
  <i class="switch" class:on aria-hidden="true"></i>
</button>

<style>
  .row {
    display: flex;
    align-items: center;
    gap: 16px;
    width: 100%;
    padding: 9px 0;
    text-align: left;
  }
  .row:disabled {
    cursor: default;
  }
  .row.soon .switch,
  .row.soon small {
    opacity: 0.45;
  }
  .text {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }
  b {
    font-size: 14px;
    font-weight: 600;
  }
  small {
    font-size: 12px;
    line-height: 1.45;
    color: var(--text-3);
  }
  .switch {
    position: relative;
    flex-shrink: 0;
    width: 44px;
    height: 24px;
    border-radius: 999px;
    background: var(--surface-3);
    transition: background var(--normal) var(--ease);
  }
  .switch::after {
    content: '';
    position: absolute;
    top: 3px;
    left: 3px;
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background: var(--text-2);
    transition:
      transform var(--normal) var(--ease),
      background var(--normal) var(--ease),
      width var(--fast) var(--ease);
  }
  .row:active:not(:disabled) .switch::after {
    width: 22px;
  }
  .switch.on {
    background: var(--accent);
  }
  .switch.on::after {
    transform: translateX(20px);
    background: var(--accent-ink);
  }
  .row:active:not(:disabled) .switch.on::after {
    transform: translateX(16px);
  }
</style>
