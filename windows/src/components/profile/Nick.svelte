<script lang="ts">
  // Ник профиля в выбранном шрифте и эффекте (lib/profile-look.ts). Цвет профиля красит ник; без цвета —
  // цвет текста (эффектам нужен оттенок — берут акцент темы). Один и тот же рисунок — в превью профиля и
  // в карточках выбора шрифта и эффекта. «Меньше движения» — перелив стоит на месте.
  import { nickFontStack, type NickEffect } from '../../lib/profile-look'

  interface Props {
    text: string
    font?: string
    effect?: NickEffect
    /** Hex цвета профиля; null — цвет темы. */
    color?: string | null
    /** Кегль, px (умножается на масштаб текста интерфейса). */
    size?: number
  }
  let { text, font = 'default', effect = 'none', color = null, size = 22 }: Props = $props()
</script>

<span
  class="nick fx-{effect}"
  class:tinted={!!color}
  style:--nick={color ?? 'var(--accent)'}
  style:--nick-size="{size}px"
  style:font-family={nickFontStack(font)}
  data-text={text}>{text}</span
>

<style>
  .nick {
    position: relative;
    display: inline-block;
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: calc(var(--nick-size) * var(--fs, 1));
    font-weight: 700;
    line-height: 1.25;
    color: var(--text);
    transition:
      color var(--normal) var(--ease),
      text-shadow var(--normal) var(--ease);
  }
  .tinted {
    color: var(--nick);
  }
  .fx-shimmer {
    color: transparent;
    background: linear-gradient(100deg, var(--nick) 20%, #fff 40%, var(--nick) 60%, color-mix(in srgb, var(--nick) 50%, #ff7ad9) 80%) 0 0 / 250% 100%;
    background-clip: text;
    -webkit-background-clip: text;
    animation: shimmer 3.2s linear infinite;
  }
  .fx-neon {
    color: color-mix(in srgb, var(--nick) 35%, #fff);
    text-shadow:
      0 0 4px var(--nick),
      0 0 12px var(--nick),
      0 0 24px color-mix(in srgb, var(--nick) 70%, transparent);
  }
  .fx-cartoon {
    color: var(--nick);
    -webkit-text-stroke: 0.08em #111;
    paint-order: stroke fill;
    text-shadow: 0.07em 0.08em 0 #111;
  }
  .fx-highlight {
    padding: 0 0.18em;
    border-radius: 0.2em;
    color: var(--text);
    background: linear-gradient(transparent 52%, color-mix(in srgb, var(--nick) 55%, transparent) 52%, color-mix(in srgb, var(--nick) 55%, transparent) 92%, transparent 92%);
  }
  .fx-3d {
    color: var(--nick);
    text-shadow:
      1px 1px 0 color-mix(in srgb, var(--nick) 70%, #000),
      2px 2px 0 color-mix(in srgb, var(--nick) 60%, #000),
      3px 3px 0 color-mix(in srgb, var(--nick) 50%, #000),
      4px 4px 6px rgba(0, 0, 0, 0.45);
  }
  .fx-retro {
    color: transparent;
    background: linear-gradient(180deg, #ffe66d 0%, #ff8a3d 45%, #ff3d7f 55%, var(--nick) 100%);
    background-clip: text;
    -webkit-background-clip: text;
    filter: drop-shadow(2px 2px 0 color-mix(in srgb, var(--nick) 45%, #000));
  }
  @keyframes shimmer {
    to {
      background-position: -250% 0;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .fx-shimmer {
      animation: none;
    }
  }
</style>
