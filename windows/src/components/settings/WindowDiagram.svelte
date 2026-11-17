<script lang="ts">
  // Схема окна на плитке выбора (NEXT_PROMPT «Этап 0» п. 5): панель вкладок, страница, мини плеер
  // и очередь — где они встанут. Раскладка — lib/window-diagram.ts, здесь только рисунок.
  import { windowDiagram, type DiagramInput, type Rect } from '../../lib/window-diagram'

  let { input, active = false }: { input: DiagramInput; active?: boolean } = $props()
  const d = $derived(windowDiagram(input))
  const place = (r: Rect) => `left:${r.x}%;top:${r.y}%;width:${r.w}%;height:${r.h}%`
</script>

<span class="win" class:active aria-hidden="true">
  <span class="part page" style={place(d.page)}></span>
  {#if d.queue}<span class="part queue" style={place(d.queue)}></span>{/if}
  {#if d.mini}<span class="part mini" style={place(d.mini)}></span>{/if}
  <span class="part rail" class:round={d.round} style={place(d.rail)}></span>
</span>

<style>
  .win {
    position: relative;
    display: block;
    width: 100%;
    aspect-ratio: 16 / 10;
    border-radius: 8px;
    background: var(--surface-0);
    border: 1px solid var(--card-line);
    overflow: hidden;
  }
  .part {
    position: absolute;
    border-radius: 4px;
    transition:
      left var(--normal) var(--ease),
      top var(--normal) var(--ease),
      width var(--normal) var(--ease),
      height var(--normal) var(--ease),
      background-color var(--fast) var(--ease);
  }
  .page {
    background: var(--plate);
  }
  .queue {
    background: var(--surface-3);
    opacity: 0.9;
  }
  .mini {
    border-radius: 999px;
    background: var(--text-3);
  }
  .rail {
    background: var(--text-2);
  }
  /* круглые значки — точечный пунктир вместо полосы */
  .rail.round {
    background: radial-gradient(circle, var(--text-2) 32%, transparent 36%) center / 100% 22% repeat-y;
  }
  .active .rail,
  .active .mini {
    background-color: var(--accent);
  }
  .active .rail.round {
    background: radial-gradient(circle, var(--accent) 32%, transparent 36%) center / 100% 22% repeat-y;
  }
</style>
