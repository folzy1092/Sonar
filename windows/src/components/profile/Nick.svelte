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
    /** Второй цвет переливающегося (hex); null — розоватый по умолчанию. */
    color2?: string | null
    /** Кегль, px (умножается на масштаб текста интерфейса). */
    size?: number
  }
  let { text, font = 'default', effect = 'none', color = null, color2 = null, size = 22 }: Props = $props()
</script>

<span
  class="nick fx-{effect}"
  class:tinted={!!color}
  style:--nick={color ?? 'var(--accent)'}
  style:--nick2={color2 ?? 'color-mix(in srgb, var(--nick) 50%, #ff7ad9)'}
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
    background: linear-gradient(100deg, var(--nick) 20%, #fff 40%, var(--nick) 60%, var(--nick2) 80%, var(--nick) 100%) 0 0 / 250% 100%;
    background-clip: text;
    -webkit-background-clip: text;
    animation: shimmer 3.2s linear infinite;
  }
  /* Свечение и тени шире самих букв, а ник режется по краю (overflow — ради «…» у длинных ников).
     Поэтому у эффектов с ними — поля внутри и такие же отрицательные отступы снаружи: место под
     свечение есть, а текст стоит там же (неон обрывался по краям, у 3D срезалась последняя буква). */
  .fx-neon {
    padding: 0.4em 0.5em;
    margin: -0.4em -0.5em;
    color: color-mix(in srgb, var(--nick) 35%, #fff);
    text-shadow:
      0 0 4px var(--nick),
      0 0 12px var(--nick),
      0 0 24px color-mix(in srgb, var(--nick) 70%, transparent);
  }
  .fx-cartoon {
    padding: 0.06em 0.16em 0.16em 0.06em;
    margin: -0.06em -0.16em -0.16em -0.06em;
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
    padding: 0 0.45em 0.4em 0;
    margin: 0 -0.45em -0.4em 0;
    color: var(--nick);
    text-shadow:
      1px 1px 0 color-mix(in srgb, var(--nick) 70%, #000),
      2px 2px 0 color-mix(in srgb, var(--nick) 60%, #000),
      3px 3px 0 color-mix(in srgb, var(--nick) 50%, #000),
      4px 4px 6px rgba(0, 0, 0, 0.45);
  }
  .fx-retro {
    padding: 0 0.15em 0.15em 0;
    margin: 0 -0.15em -0.15em 0;
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
