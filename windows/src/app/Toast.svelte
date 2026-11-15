<script lang="ts">
  // Тост выезжает снизу и уезжает вниз (PLATFORMS.md «Анимации»).
  import { toast } from '../lib/toast.svelte'
  import { pop } from '../lib/motion'
</script>

{#if toast.text}
  {#key toast.text}
    <div class="toast" role="status" in:pop={{ y: 14, scale: 0.94, duration: 260 }} out:pop={{ y: 14, scale: 0.94, duration: 260 }}>{toast.text}</div>
  {/key}
{/if}

<style>
  .toast {
    position: fixed;
    left: 50%;
    bottom: calc(var(--player-h) + 22px);
    translate: -50% 0;
    z-index: 60;
    max-width: min(520px, 80vw);
    padding: 10px 18px;
    border-radius: 999px;
    background: var(--surface-3);
    border: 1px solid var(--border-strong);
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.45);
    font-weight: 600;
  }
</style>
