<script lang="ts">
  import Icon from '../components/Icon.svelte'
  import { router } from './router.svelte'
  import { search, type Source } from './search.svelte'

  const sources: { id: Source; label: string; title: string }[] = [
    { id: 'sc', label: 'SC', title: 'SoundCloud' },
    { id: 'ym', label: 'Я', title: 'Яндекс Музыка' },
  ]

  function onInput() {
    if (search.query.trim() && router.page !== 'search') router.go('search')
  }
</script>

<div class="bar">
  <label class="field">
    <Icon name="search" size={18} />
    <input
      type="text"
      placeholder="Что включить?"
      spellcheck="false"
      bind:value={search.query}
      oninput={onInput}
    />
  </label>

  <div class="sources" role="radiogroup" aria-label="Источник поиска">
    {#each sources as s (s.id)}
      <button
        class="src"
        class:on={search.source === s.id}
        role="radio"
        aria-checked={search.source === s.id}
        title={s.title}
        onclick={() => (search.source = s.id)}
      >
        {s.label}
      </button>
    {/each}
  </div>

  <button class="paste" aria-label="Вставить ссылку" title="Вставить ссылку на трек или плейлист">
    <Icon name="link" size={18} />
  </button>
</div>

<style>
  .bar {
    display: flex;
    align-items: center;
    gap: 8px;
    width: min(560px, 100%);
  }
  .field {
    flex: 1;
    display: flex;
    align-items: center;
    gap: 10px;
    height: 40px;
    padding: 0 14px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--border);
    color: var(--text-3);
    transition:
      border-color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .field:focus-within {
    border-color: var(--border-strong);
    background: var(--surface-2);
    color: var(--text-2);
  }
  input {
    flex: 1;
    min-width: 0;
    background: none;
    border: 0;
    outline: none;
    color: var(--text);
    user-select: text;
  }
  input::placeholder {
    color: var(--text-3);
  }
  .sources {
    display: flex;
    padding: 3px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--border);
  }
  .src {
    min-width: 38px;
    height: 32px;
    padding: 0 10px;
    border-radius: 999px;
    font-size: 12px;
    font-weight: 700;
    color: var(--text-3);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .src:hover {
    color: var(--text);
  }
  .src.on {
    background: var(--accent);
    color: var(--accent-ink);
  }
  .paste {
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    border-radius: 50%;
    background: var(--plate);
    border: 1px solid var(--border);
    color: var(--text-2);
    transition:
      color var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .paste:hover {
    color: var(--text);
    background: var(--hover);
  }
</style>
