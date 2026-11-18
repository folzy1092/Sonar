<script lang="ts">
  // Значок «Dev» у ника — у разработчика Sonar (`lib/subscription.ts` `subscriptionOf`, до сервера —
  // по нику). Маленькая капсула цвета профиля с точкой-«пингом»: появляется из масштаба, точка мягко
  // пульсирует один раз. «Меньше движения» — только прозрачность.
  import { t } from '../../lib/i18n.svelte'

  interface Props {
    /** Hex цвета профиля; null — акцент темы. */
    color?: string | null
    /** Кегль, px (умножается на масштаб текста интерфейса). */
    size?: number
  }
  let { color = null, size = 10.5 }: Props = $props()
</script>

<span class="dev" style:--dev={color ?? 'var(--accent)'} style:--dev-size="{size}px" title={t('Разработчик Sonar: открыто всё Sonar Deep')}>
  <i aria-hidden="true"></i>Dev
</span>

<style>
  .dev {
    flex: none;
    display: inline-flex;
    align-items: center;
    gap: 0.45em;
    height: calc(var(--dev-size) * 1.85 * var(--fs, 1));
    padding: 0 0.75em 0 0.6em;
    border-radius: 999px;
    border: 1px solid color-mix(in srgb, var(--dev) 45%, transparent);
    background: color-mix(in srgb, var(--dev) 16%, transparent);
    color: color-mix(in srgb, var(--dev) 70%, var(--text));
    font-size: calc(var(--dev-size) * var(--fs, 1));
    font-weight: 700;
    letter-spacing: 0.04em;
    line-height: 1;
    white-space: nowrap;
    vertical-align: middle;
    animation: dev-in var(--normal, 0.26s) var(--ease) both;
    user-select: none;
  }
  i {
    position: relative;
    width: 0.5em;
    height: 0.5em;
    border-radius: 50%;
    background: var(--dev);
  }
  /* один «пинг» сонара после появления */
  i::after {
    content: '';
    position: absolute;
    inset: 0;
    border-radius: 50%;
    border: 1px solid var(--dev);
    opacity: 0;
    animation: dev-ping 1.1s var(--ease) 0.25s 1;
  }
  @keyframes dev-in {
    from {
      opacity: 0;
      transform: scale(0.6);
    }
  }
  @keyframes dev-ping {
    from {
      opacity: 0.9;
      transform: scale(1);
    }
    to {
      opacity: 0;
      transform: scale(3.2);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .dev {
      animation-name: dev-fade;
    }
    i::after {
      animation: none;
    }
  }
  @keyframes dev-fade {
    from {
      opacity: 0;
    }
  }
</style>
