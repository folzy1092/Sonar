<script lang="ts">
  // Круглый флаг языка (circle-flags, MIT) — живая картинка вместо эмодзи Windows.
  import { flags } from './flags'
  let { lang, size = 18 }: { lang: string; size?: number } = $props()
</script>

{#if flags[lang]}
  <svg class="flag" width={size} height={size} viewBox="0 0 512 512" aria-hidden="true">{@html flags[lang]}</svg>
{/if}

<style>
  .flag {
    display: block;
    flex-shrink: 0;
    border-radius: 50%;
    box-shadow:
      0 0 0 1px rgba(255, 255, 255, 0.12),
      0 2px 6px rgba(0, 0, 0, 0.35);
  }
</style>
