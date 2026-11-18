<script lang="ts">
  // Карточка группы настроек (SETTINGS_NEXT «Общие приёмы вида»): заголовок серым над плашкой, внутри
  // строки без разделителей. Справа от заголовка — необязательное действие.
  import type { Snippet } from 'svelte'
  let { title, hint, children, action }: { title?: string; hint?: string; children: Snippet; action?: Snippet } = $props()
</script>

<section>
  {#if title || action}
    <h4><span>{title ?? ''}</span>{#if action}{@render action()}{/if}</h4>
  {/if}
  {#if hint}<p>{hint}</p>{/if}
  <div class="plate">{@render children()}</div>
</section>

<style>
  section {
    margin-top: 18px;
  }
  section:first-child {
    margin-top: 2px;
  }
  h4 {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    margin: 0 0 7px 4px;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-3);
  }
  p {
    margin: -3px 0 7px 4px;
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.45;
    color: var(--text-3);
  }
  .plate {
    padding: 4px 16px;
    border-radius: var(--radius-xl, 18px);
    background: var(--plate);
    transition: background var(--fast) var(--ease);
  }
</style>
