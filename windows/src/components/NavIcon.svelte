<script lang="ts">
  // Иконка раздела левой панели (Интерфейс → Стиль, STYLE_PROMPT §3): контур 24×24 цветом текста,
  // толщина — `appearance.icon_stroke` (--icon-stroke). Иконки собраны из частей, и у выбранного
  // раздела одна деталь двигается (320 мс, cubic-bezier(.22,1,.36,1)): у домика открывается дверь
  // и приподнимается крыша, у плеера растёт треугольник, у лупы линза и ручка расходятся, у
  // медиатеки откидывается передняя стенка, у настроек разъезжаются ручки фейдеров, у профиля
  // поднимается голова. Как отмечен выбранный раздел (точка, капсула, плашка) — app/Rail.svelte.
  // Части названы как в макете (`home-door`, `lib-front`…) — классами, не id: иконка бывает на
  // экране не одна. Прочие имена (сердце «Любимых», «+») — MingCute, как раньше.
  import { navIcons, type NavIconName } from './nav-icons'

  let { name, active = false, size = 24 }: { name: NavIconName; active?: boolean; size?: number } = $props()
  const own = new Set(['home', 'player', 'search', 'library', 'settings', 'user'])
</script>

<span class="ni n-{name}" class:active style:--s="{size}px" aria-hidden="true">
  {#if own.has(name)}
    <svg class="sn" viewBox="0 0 24 24">
      {#if name === 'home'}
        <path class="home-walls" d="M5 10.4V19a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-8.6" />
        <path class="home-roof" d="M3 11.6 12 4.2l9 7.4" />
        <path class="home-door" d="M10 20v-4.4a2 2 0 0 1 4 0V20" />
      {:else if name === 'player'}
        <circle class="player-ring" cx="12" cy="12" r="9" />
        <path class="player-tri" d="M10.3 8.7v6.6a.6.6 0 0 0 .9.5l5.3-3.3a.6.6 0 0 0 0-1l-5.3-3.3a.6.6 0 0 0-.9.5Z" />
      {:else if name === 'search'}
        <circle class="search-lens" cx="10.6" cy="10.6" r="6.2" />
        <path class="search-handle" d="m15.3 15.3 4.7 4.7" />
      {:else if name === 'library'}
        <path class="lib-back" d="M3.5 16.5V6.4A1.4 1.4 0 0 1 4.9 5h3.5c.4 0 .8.2 1.1.5L11 7h8.1a1.4 1.4 0 0 1 1.4 1.4V10" />
        <path class="lib-front" d="M3.5 18.4v-7.6a1.2 1.2 0 0 1 1.2-1.2h14.6a1.2 1.2 0 0 1 1.2 1.2v7.6a1.6 1.6 0 0 1-1.6 1.6H5.1a1.6 1.6 0 0 1-1.6-1.6Z" />
      {:else if name === 'settings'}
        <path class="set-rails" d="M8 4v16M16 4v16" />
        <rect class="set-knob1" x="5.4" y="12.6" width="5.2" height="3" rx="1.5" />
        <rect class="set-knob2" x="13.4" y="8.4" width="5.2" height="3" rx="1.5" />
      {:else}
        <circle class="user-head" cx="12" cy="8.2" r="3.6" />
        <path class="user-body" d="M5 19.6c.7-3.2 3.6-5.4 7-5.4s6.3 2.2 7 5.4" />
      {/if}
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
    overflow: visible;
  }

  /* ---- свои иконки панели: контур, части двигаются у выбранного раздела ---- */
  .sn * {
    fill: none;
    stroke: currentColor;
    stroke-width: var(--icon-stroke, 2);
    stroke-linecap: round;
    stroke-linejoin: round;
    transform-box: fill-box;
    transform-origin: 50% 50%;
    transition:
      transform 0.32s cubic-bezier(0.22, 1, 0.36, 1),
      fill 0.32s cubic-bezier(0.22, 1, 0.36, 1),
      stroke-width 0.32s cubic-bezier(0.22, 1, 0.36, 1);
  }
  /* ручки фейдеров — залитые, рельс под ними не просвечивает */
  .sn .set-knob1,
  .sn .set-knob2 {
    fill: var(--knob-fill, var(--surface-1));
  }
  .active .sn .set-knob1,
  .active .sn .set-knob2 {
    fill: currentColor;
  }
  .sn .home-door,
  .sn .lib-front {
    transform-origin: 0% 100%;
  }
  /* домик: дверь открылась (сжалась к левой петле), крыша приподнялась */
  .active .home-door {
    transform: scaleX(0.28);
  }
  .active .home-roof {
    transform: translateY(-1px);
  }
  .active .player-tri {
    transform: scale(1.18);
  }
  .active .player-ring {
    transform: scale(0.9);
  }
  .active .search-lens {
    transform: translate(-1px, -1px);
  }
  .active .search-handle {
    transform: translate(1.5px, 1.5px);
  }
  /* медиатека: передняя стенка откидывается вперёд на нижней петле */
  .active .lib-front {
    transform: skewX(-16deg) translateX(1.5px);
  }
  .active .set-knob1 {
    transform: translateY(-5px);
  }
  .active .set-knob2 {
    transform: translateY(5px);
  }
  .active .user-head {
    transform: translateY(-1.5px);
  }

  /* ---- MingCute (сердце «Любимых», «+»): контур, у выбранного — заливка цветом темы ---- */
  .line,
  .fill {
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
  @media (prefers-reduced-motion: reduce) {
    .sn * {
      transition: fill 0.2s linear;
    }
    .active .sn * {
      transform: none;
    }
  }
  :global(:root.no-motion) .active .sn * {
    transform: none;
  }
</style>
