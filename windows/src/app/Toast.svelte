<script lang="ts">
  import { toast } from '../lib/toast.svelte'
</script>

{#if toast.text}
  {#key toast.text}
    <div class="toast" role="status">{toast.text}</div>
  {/key}
{/if}

<style>
  .toast {
    position: fixed;
    left: 50%;
    bottom: calc(var(--player-h) + 22px);
    transform: translateX(-50%);
    z-index: 60;
    max-width: min(520px, 80vw);
    padding: 10px 18px;
    border-radius: 999px;
    background: var(--surface-3);
    border: 1px solid var(--border-strong);
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.45);
    font-weight: 600;
    animation: toast-in var(--normal) var(--ease);
  }
  @keyframes toast-in {
    from {
      opacity: 0;
      transform: translate(-50%, 8px);
    }
  }
</style>
