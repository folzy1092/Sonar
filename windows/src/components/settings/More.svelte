<script lang="ts">
  // «Ещё настройки» (NEXT_PROMPT «Этап 0» п. 4): редкие пункты раздела свёрнуты под одной строкой,
  // главные 3–5 остаются сверху. Открывается и закрывается только кликом; поиск по настройкам
  // раскрывает блок сам — событием `reveal` на элементе (SettingsPanel.svelte).
  import type { Snippet } from 'svelte'
  import Icon from '../Icon.svelte'
  import { t } from '../../lib/i18n.svelte'

  let { children }: { children: Snippet } = $props()
  let open = $state(false)
  /** Доехало до конца — тогда содержимому можно выходить за край (выпадающие списки). */
  let settled = $state(false)
  let root: HTMLDivElement | undefined = $state()

  function toggle(next: boolean) {
    if (next === open) return
    open = next
    settled = false
  }

  $effect(() => {
    const el = root
    if (!el) return
    const reveal = () => toggle(true)
    el.addEventListener('reveal', reveal)
    return () => el.removeEventListener('reveal', reveal)
  })
</script>

<div class="more" class:open class:settled data-more bind:this={root}>
  <button class="head" aria-expanded={open} onclick={() => toggle(!open)}>
    <span>{t('Ещё настройки')}</span>
    <i></i>
    <span class="chev"><Icon name="chevronDown" size={16} /></span>
  </button>
  <div class="body" ontransitionend={(e) => e.target === e.currentTarget && (settled = open)}>
    <div class="inner" inert={!open}>
      {@render children()}
    </div>
  </div>
</div>

<style>
  .more {
    column-span: all;
    margin-top: 14px;
  }
  .head {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    padding: 8px 0;
    color: var(--text-2);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    transition: color var(--fast) var(--ease);
  }
  .head:hover {
    color: var(--text);
  }
  i {
    flex: 1;
    height: 1px;
    background: var(--border);
  }
  .chev {
    display: grid;
    place-items: center;
    transition: transform var(--normal) var(--ease);
  }
  .open .chev {
    transform: rotate(180deg);
  }
  /* высота «0 → по содержимому» — через строку сетки 0fr → 1fr */
  .body {
    display: grid;
    grid-template-rows: 0fr;
    opacity: 0;
    transition:
      grid-template-rows var(--normal) var(--ease),
      opacity var(--normal) var(--ease);
  }
  .open .body {
    grid-template-rows: 1fr;
    opacity: 1;
  }
  .inner {
    min-height: 0;
    overflow: hidden;
  }
  .open.settled .inner {
    overflow: visible;
  }
</style>
