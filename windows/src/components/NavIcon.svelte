<script lang="ts">
  // Иконка раздела в левой панели (как у Dotify): контур, а выбранный раздел — та же иконка, залитая
  // цветом темы (под обложку, AMOLED — белым). Контур и заливка плавно перетекают друг в друга.
  // Медиатека — своя папка из двух частей: выбрали — передняя стенка плавно отходит от задней и
  // откидывается вперёд (петля внизу), папка открыта; ушли — так же плавно закрывается.
  import { navIcons, type NavIconName } from './nav-icons'

  let { name, active = false, size = 24 }: { name: NavIconName; active?: boolean; size?: number } = $props()
</script>

<span class="ni n-{name}" class:active style:--s="{size}px" aria-hidden="true">
  {#if name === 'library'}
    <svg class="folder" viewBox="0 0 24 24">
      <!-- задняя стенка с ярлычком -->
      <path class="back" d="M3.2 7.2a2 2 0 0 1 2-2h3.7c.5 0 1 .2 1.4.6l1.3 1.3h7.2a2 2 0 0 1 2 2v8.7a2 2 0 0 1-2 2H5.2a2 2 0 0 1-2-2Z" />
      <!-- передняя стенка: петля по нижнему краю, при открытии откидывается вперёд -->
      <g class="flap">
        <path d="M3.2 10.4a1.6 1.6 0 0 1 1.6-1.6h14.4a1.6 1.6 0 0 1 1.6 1.6v7.4a2 2 0 0 1-2 2H5.2a2 2 0 0 1-2-2Z" />
      </g>
    </svg>
  {:else}
    <svg class="line" viewBox="0 0 24 24">{@html navIcons[name].line}</svg>
    <svg class="fill" viewBox="0 0 24 24">{@html navIcons[name].fill}</svg>
  {/if}
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

  /* папка медиатеки: в покое — контур закрытой папки, выбрана — заливка цвета темы, передняя
     стенка плавно откидывается (без подскоков) */
  .folder path {
    fill: transparent;
    stroke: currentColor;
    stroke-width: 1.8;
    stroke-linejoin: round;
    transition:
      fill 0.4s var(--ease),
      stroke 0.4s var(--ease);
  }
  .folder .flap {
    transform-box: fill-box;
    transform-origin: 50% 100%;
    transition: transform 0.55s cubic-bezier(0.32, 0.72, 0, 1);
  }
  .active .folder {
    color: var(--accent);
  }
  .active .folder .back {
    fill: color-mix(in srgb, var(--accent) 45%, transparent);
    stroke: transparent;
  }
  .active .folder .flap path {
    fill: var(--accent);
    stroke: color-mix(in srgb, var(--accent) 60%, #000);
    stroke-width: 0.6;
  }
  /* стенка «падает» вперёд на петле: становится ниже и наклоняется — видно, что папка раскрылась */
  .active .folder .flap {
    transform: translateX(1.2px) skewX(-16deg) scaleY(0.72);
  }
  @media (prefers-reduced-motion: reduce) {
    .folder .flap {
      transition: none;
    }
  }
</style>
