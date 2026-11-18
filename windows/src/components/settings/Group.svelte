<script lang="ts">
  // Заголовок группы с линией (pc/Screenshot_16 «Медиатека», «Запуск»), справа — необязательное действие.
  import type { Snippet } from 'svelte'
  let { title, hint, children, action, icon }: { title: string; hint?: string; children: Snippet; action?: Snippet; icon?: Snippet } =
    $props()
</script>

<section>
  <h4>{#if icon}<span class="ic">{@render icon()}</span>{/if}<span>{title}</span><i></i>{#if action}{@render action()}{/if}</h4>
  <!-- одна строка: что меняет эта группа (NEXT_PROMPT «Этап 0» п. 4) -->
  {#if hint}<p class="lead">{hint}</p>{/if}
  {@render children()}
</section>

<style>
  section {
    margin-top: 22px;
  }
  section:first-child {
    margin-top: 4px;
  }
  h4 {
    display: flex;
    align-items: center;
    gap: 12px;
    margin: 0 0 6px;
    font-size: calc(15px * var(--fs, 1));
    font-weight: 700;
  }
  .ic {
    display: grid;
    place-items: center;
    margin-right: -4px;
  }
  .lead {
    margin: -2px 0 4px;
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.45;
    color: var(--text-3);
  }
  i {
    flex: 1;
    height: 1px;
    background: var(--border);
  }
</style>
