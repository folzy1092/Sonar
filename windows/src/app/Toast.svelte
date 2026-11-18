<script lang="ts">
  // Тост выезжает снизу и уезжает вниз (PLATFORMS.md «Анимации»). Кнопка действия («Отменить») —
  // только по клику.
  import { toast } from '../lib/toast.svelte'
  import { pop } from '../lib/motion'
</script>

{#if toast.text}
  {#key toast.text}
    <div class="toast" class:with-action={toast.action} role="status" in:pop={{ y: 14, scale: 0.94, duration: 260 }} out:pop={{ y: 14, scale: 0.94, duration: 260 }}>
      <span>{toast.text}</span>
      {#if toast.action}
        <button class="act" onclick={() => toast.act()}>{toast.action.label}</button>
      {/if}
    </div>
  {/key}
{/if}

<style>
  .toast {
    position: fixed;
    left: 50%;
    bottom: calc(var(--player-h) + 22px);
    translate: -50% 0;
    z-index: 60;
    display: flex;
    align-items: center;
    gap: 14px;
    max-width: min(520px, 80vw);
    padding: 10px 18px;
    border-radius: 999px;
    background: var(--surface-3);
    border: 1px solid var(--border-strong);
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.45);
    font-weight: 600;
  }
  .toast.with-action {
    padding-right: 8px;
  }
  .act {
    flex: none;
    height: 28px;
    padding: 0 12px;
    border-radius: 999px;
    color: var(--accent);
    font-weight: 700;
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .act:hover {
    background: var(--hover);
  }
  .act:active {
    transform: scale(0.95);
  }
</style>
