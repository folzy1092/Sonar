<script lang="ts">
  // Флаг языка (flag-icons, MIT): прямоугольник 4:3 со скруглёнными углами и лёгким бликом —
  // живая картинка вместо эмодзи Windows и подписей «RU / EN».
  import { flags } from './flags'
  let { lang, size = 18 }: { lang: string; size?: number } = $props()
  const f = $derived(flags[lang])
</script>

{#if f}
  <span class="flag" style:--w="{size}px" aria-hidden="true">
    <svg viewBox={f.view} preserveAspectRatio="xMidYMid slice">{@html f.body}</svg>
  </span>
{/if}

<style>
  .flag {
    position: relative;
    display: block;
    flex-shrink: 0;
    width: var(--w);
    height: calc(var(--w) * 0.75);
    border-radius: 3px;
    overflow: hidden;
    box-shadow: 0 1px 3px rgba(0, 0, 0, 0.4);
  }
  svg {
    display: block;
    width: 100%;
    height: 100%;
  }
  /* мягкий блик сверху и тонкая рамка — флаг выглядит «живым», а не плоским прямоугольником */
  .flag::after {
    content: '';
    position: absolute;
    inset: 0;
    border-radius: inherit;
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.22), transparent 45%, rgba(0, 0, 0, 0.12));
    box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.12);
  }
</style>
