<script lang="ts">
  // Строка поиска по настройкам сверху панели (NEXT_PROMPT «Этап 0» п. 4). Ищет по каталогу
  // `lib/settings-catalog.ts`; результаты показывает SearchResults.svelte вместо страницы.
  // Esc в непустой строке — только очищает её (панель не закрывается).
  import Icon from '../Icon.svelte'
  import { t } from '../../lib/i18n.svelte'

  let { query = $bindable('') }: { query?: string } = $props()
  let input: HTMLInputElement | undefined = $state()

  function onKey(e: KeyboardEvent) {
    if (e.key !== 'Escape' || !query) return
    e.stopPropagation()
    query = ''
  }

  function clear() {
    query = ''
    input?.focus()
  }
</script>

<label class="find" class:filled={!!query}>
  <span class="ic"><Icon name="search" size={16} /></span>
  <input bind:this={input} bind:value={query} type="search" spellcheck="false" autocomplete="off" placeholder={t('Найти настройку')} aria-label={t('Поиск по настройкам')} onkeydown={onKey} />
  <button class="clear" tabindex={query ? 0 : -1} aria-label={t('Очистить поиск')} onclick={clear}>
    <Icon name="x" size={14} />
  </button>
</label>

<style>
  .find {
    position: relative;
    display: flex;
    align-items: center;
    width: min(560px, 100%);
    height: 38px;
    padding: 0 6px 0 12px;
    gap: 8px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    color: var(--text-3);
    transition:
      border-color var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .find:focus-within {
    border-color: color-mix(in srgb, var(--accent) 60%, var(--card-line));
    color: var(--text-2);
  }
  .ic {
    display: grid;
    place-items: center;
  }
  input {
    flex: 1;
    min-width: 0;
    height: 100%;
    background: none;
    border: 0;
    outline: none;
    color: var(--text);
    font: inherit;
    font-size: calc(13px * var(--fs, 1));
  }
  input::placeholder {
    color: var(--text-3);
  }
  input::-webkit-search-cancel-button {
    display: none;
  }
  .clear {
    display: grid;
    place-items: center;
    width: 26px;
    height: 26px;
    border-radius: 50%;
    color: var(--text-3);
    opacity: 0;
    scale: 0.6;
    pointer-events: none;
    transition:
      opacity var(--fast) var(--ease),
      scale var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .filled .clear {
    opacity: 1;
    scale: 1;
    pointer-events: auto;
  }
  .clear:hover {
    background: var(--hover);
    color: var(--text);
  }
</style>
