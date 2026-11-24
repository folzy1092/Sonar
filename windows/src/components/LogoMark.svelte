<script lang="ts">
  // Знак Sonar с «душой»: заливка — перелив в цвете темы (под обложку) целиком, под ним мягкое
  // свечение того же цвета; при наведении знак делает пол-оборота, как пропеллер на заставке.
  import raw from '../assets/logo-mark.svg?raw'

  let { size = 34, spin = true }: { size?: number; spin?: boolean } = $props()

  const D = /\sd="([^"]+)"/.exec(raw)?.[1] ?? ''
  const VIEW = /viewBox="([^"]+)"/.exec(raw)?.[1] ?? '0 0 24 24'
  const id = `lg${Math.random().toString(36).slice(2, 8)}`
</script>

<span class="mark" class:spin style:--s="{size}px" aria-hidden="true">
  <svg viewBox={VIEW}>
    <defs>
      <linearGradient id={id} x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" class="a" />
        <stop offset="0.55" class="b" />
        <stop offset="1" class="c" />
      </linearGradient>
    </defs>
    <path fill="url(#{id})" fill-rule="evenodd" d={D} />
  </svg>
</span>

<style>
  .mark {
    display: block;
    width: var(--s);
    height: var(--s);
    filter: drop-shadow(0 2px 3px rgba(0, 0, 0, 0.5));
    transition: rotate 0.9s cubic-bezier(0.34, 1.3, 0.5, 1);
  }
  svg {
    display: block;
    width: 100%;
    height: 100%;
    overflow: visible;
  }
  /* весь знак — в цвете темы: сверху чуть светлее (блик), снизу — сам цвет и чуть глубже;
     белого угла больше нет (при монохромной теме цвет темы и есть белый) */
  .a {
    stop-color: color-mix(in srgb, var(--accent) 82%, #ffffff);
  }
  .b {
    stop-color: var(--accent);
  }
  .c {
    stop-color: color-mix(in srgb, var(--accent) 78%, #000000);
  }
  .mark.spin:hover {
    rotate: 180deg;
  }
  @media (prefers-reduced-motion: reduce) {
    .mark {
      transition: none;
    }
    .mark.spin:hover {
      rotate: none;
    }
  }
</style>
