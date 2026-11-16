<script lang="ts">
  // Заголовок группы с линией (pc/Screenshot_16 «Медиатека», «Запуск»), справа — необязательное действие.
  import type { Snippet } from 'svelte'
  let { title, children, action }: { title: string; children: Snippet; action?: Snippet } = $props()
</script>

<section>
  <h4><span>{title}</span><i></i>{#if action}{@render action()}{/if}</h4>
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
  i {
    flex: 1;
    height: 1px;
    background: var(--border);
  }
</style>
