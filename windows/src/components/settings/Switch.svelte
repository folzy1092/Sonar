<script lang="ts">
  // Строка настройки с переключателем (pc/Screenshot_14, 16): название, подсказка, тумблер справа.
  let { title, hint, on, onchange }: { title: string; hint?: string; on: boolean; onchange: (v: boolean) => void } = $props()
</script>

<button class="row" role="switch" aria-checked={on} onclick={() => onchange(!on)}>
  <span class="text">
    <b>{title}</b>
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
    padding: 10px 0;
    text-align: left;
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
    width: 42px;
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
  .row:active .switch::after {
    width: 22px;
  }
  .switch.on {
    background: var(--accent);
  }
  .switch.on::after {
    transform: translateX(18px);
    background: var(--accent-ink);
  }
  .row:active .switch.on::after {
    transform: translateX(14px);
  }
</style>
