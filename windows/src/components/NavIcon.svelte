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
  {:else if name === 'home'}
    <svg class="cu" viewBox="0 0 24 24">
      <path class="body" d="M4 10.2a1.5 1.5 0 0 1 .6-1.2l6.5-4.9a1.5 1.5 0 0 1 1.8 0l6.5 4.9a1.5 1.5 0 0 1 .6 1.2V19a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2Z" />
      <!-- проём двери (виден, когда дверь открыта) и сама створка на левой петле -->
      <path class="opening" d="M9.8 21v-6.2a2.2 2.2 0 0 1 4.4 0V21Z" />
      <path class="leaf" d="M9.8 21v-6.2a2.2 2.2 0 0 1 4.4 0V21Z" />
    </svg>
  {:else if name === 'player'}
    <svg class="cu" viewBox="0 0 24 24">
      <path class="tri" d="M7.4 4.6a1.4 1.4 0 0 1 2.1-1.2l10.2 6.4a2.5 2.5 0 0 1 0 4.4L9.5 20.6a1.4 1.4 0 0 1-2.1-1.2Z" transform="translate(-0.4 0)" />
    </svg>
  {:else if name === 'search'}
    <svg class="cu" viewBox="0 0 24 24">
      <g class="tool">
        <circle class="glass" cx="10" cy="10" r="6.3" />
        <path class="handle" d="m15 15 5.2 5.2" />
      </g>
    </svg>
  {:else if name === 'user'}
    <svg class="cu" viewBox="0 0 24 24">
      <circle class="head" cx="12" cy="7.5" r="4" />
      <path class="shoulders" d="M4 19.6v-.1A4.5 4.5 0 0 1 8.5 15h7a4.5 4.5 0 0 1 4.5 4.5v.1a1.4 1.4 0 0 1-1.4 1.4H5.4A1.4 1.4 0 0 1 4 19.6Z" />
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

  /* ---- свои двухчастные иконки: дом, play, лупа, профиль ---- */
  .cu {
    color: currentColor;
  }
  .cu path,
  .cu circle {
    fill: transparent;
    stroke: currentColor;
    stroke-width: 1.8;
    stroke-linejoin: round;
    stroke-linecap: round;
    transition:
      fill 0.45s var(--ease),
      stroke 0.45s var(--ease),
      opacity 0.45s var(--ease),
      transform 0.55s cubic-bezier(0.32, 0.72, 0, 1);
  }
  .cu .body,
  .cu .tri,
  .cu .glass,
  .cu .head,
  .cu .shoulders,
  .cu .leaf,
  .cu .opening,
  .cu .handle,
  .cu .tool {
    transform-box: fill-box;
  }
  .cu .tool {
    transform-box: view-box;
    transform-origin: 10px 10px;
    transition: transform 0.55s cubic-bezier(0.32, 0.72, 0, 1);
  }
  .active .cu path,
  .active .cu circle {
    stroke: var(--accent);
  }

  /* дом: стены заливаются, дверь отходит на левой петле, в проёме тёмный оттенок темы */
  .cu .opening {
    opacity: 0;
    stroke: transparent;
  }
  .cu .leaf {
    transform-origin: 0% 100%;
  }
  .active .cu .body {
    fill: var(--accent);
  }
  .active .cu .opening {
    opacity: 1;
    fill: color-mix(in srgb, var(--accent) 45%, #000);
    stroke: transparent;
  }
  .active .cu .leaf {
    fill: var(--accent);
    stroke: color-mix(in srgb, var(--accent) 60%, #000);
    stroke-width: 0.8;
    transform: scaleX(0.34) skewY(-9deg);
  }

  /* play: наливается и чуть уходит вперёд и наклоняется, как нажатая кнопка */
  .cu .tri {
    transform-origin: 40% 50%;
  }
  .active .cu .tri {
    fill: var(--accent);
    transform: translateX(1px) rotate(-7deg) scale(1.05);
  }

  /* лупа: поворот на -15° вокруг стекла, стекло наполняется */
  .active .cu .tool {
    transform: rotate(-15deg);
  }
  .active .cu .glass {
    fill: color-mix(in srgb, var(--accent) 55%, transparent);
  }
  .active .cu .handle {
    stroke-width: 2.4;
  }

  /* шестерёнка: поворот на 60° (шестиугольник совпадает сам с собой), контур перетекает в заливку */
  .n-settings .line {
    transition:
      opacity 0.4s var(--ease),
      transform 0.6s cubic-bezier(0.32, 0.72, 0, 1);
  }
  .n-settings .fill {
    transform: rotate(-60deg) scale(0.9);
    transition:
      opacity 0.4s var(--ease),
      transform 0.6s cubic-bezier(0.32, 0.72, 0, 1);
  }
  .n-settings.active .fill {
    transform: none;
  }
  .n-settings.active .line {
    transform: rotate(60deg) scale(1.04);
  }

  /* профиль: плечи заливаются, голова один раз мягко кивает */
  .active .cu .shoulders {
    fill: color-mix(in srgb, var(--accent) 70%, transparent);
  }
  .active .cu .head {
    fill: var(--accent);
    animation: ni-nod 0.7s cubic-bezier(0.32, 0.72, 0, 1) 1;
  }
  @keyframes ni-nod {
    40% {
      transform: translateY(1.3px);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .cu path,
    .cu circle,
    .cu .tool {
      transition: fill 0.3s linear, stroke 0.3s linear, opacity 0.3s linear;
    }
    .active .cu .leaf,
    .active .cu .tri,
    .active .cu .tool {
      transform: none;
    }
    .active .cu .head {
      animation: none;
    }
    .n-settings .line,
    .n-settings .fill,
    .n-settings.active .line,
    .n-settings.active .fill {
      transform: none;
      transition: opacity 0.3s linear;
    }
  }
</style>
