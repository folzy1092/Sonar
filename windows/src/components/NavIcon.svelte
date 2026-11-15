<script lang="ts">
  // Иконка раздела в левой панели (как у Dotify): контур, а выбранный раздел — та же иконка, залитая
  // цветом темы (под обложку, AMOLED — белым). Контур и заливка плавно перетекают друг в друга.
  import { navIcons, type NavIconName } from './nav-icons'

  let { name, active = false, size = 24 }: { name: NavIconName; active?: boolean; size?: number } = $props()
</script>

<span class="ni" class:active style:--s="{size}px" aria-hidden="true">
  <svg class="line" viewBox="0 0 24 24">{@html navIcons[name].line}</svg>
  <svg class="fill" viewBox="0 0 24 24">{@html navIcons[name].fill}</svg>
</span>

<style>
  .ni {
    position: relative;
    display: block;
    width: var(--s);
    height: var(--s);
  }
  svg {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    transition:
      opacity 0.28s var(--ease),
      transform 0.36s var(--ease);
  }
  .fill {
    opacity: 0;
    transform: scale(0.82);
    color: var(--accent);
  }
  .active .fill {
    opacity: 1;
    transform: none;
  }
  .active .line {
    opacity: 0;
    transform: scale(1.12);
  }
</style>
