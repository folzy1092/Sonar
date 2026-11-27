<script lang="ts">
  // Быстрое окно (Ctrl+K, Система → Горячие клавиши → «Быстрое окно»): по центру поверх всего — поле
  // и список. Ищет действия, настройки, медиатеку и историю сразу, треки и артистов сервисов — чуть
  // позже (lib/quick.svelte.ts). Клавиши: ↑↓ — строка, Enter / Shift+Enter, Tab — следующая группа,
  // Esc или клик мимо — закрыть. Появляется 0.98 → 1 с прозрачностью, список — каскадом.
  import { tick } from 'svelte'
  import { fade } from 'svelte/transition'
  import Icon from '../components/Icon.svelte'
  import SourceIcon from '../components/SourceIcon.svelte'
  import { pop } from '../lib/motion'
  import { cascade } from '../lib/cascade'
  import { t } from '../lib/i18n.svelte'
  import { settings } from '../lib/settings.svelte'
  import { comboFrom, comboLabel, hotkeys } from '../lib/hotkeys.svelte'
  import { jumpGroup, step } from '../lib/quick-core'
  import { QUICK_HINTS } from '../lib/quick-catalog'
  import { quick, type QuickItem } from '../lib/quick.svelte'
  import { offline } from '../lib/offline.svelte'

  let input: HTMLInputElement | undefined = $state()
  let list: HTMLElement | undefined = $state()
  let active = $state(0)
  /** Куда вернуть фокус после закрытия. */
  let before: HTMLElement | null = null

  const sections = $derived(quick.sections)
  const local = $derived(sections.filter((s) => s.id !== 'tracks' && s.id !== 'artists'))
  const remote = $derived(sections.filter((s) => s.id === 'tracks' || s.id === 'artists'))
  const flat = $derived(sections.flatMap((s) => s.items))
  const starts = $derived(sections.reduce<number[]>((acc, s, i) => [...acc, i ? acc[i - 1] + sections[i - 1].items.length : 0], []))
  const indexOf = $derived(new Map(flat.map((item, i) => [item.key, i])))
  /** Каскад у результатов сервисов — заново, когда приходят новые. */
  const remoteKey = $derived(remote.flatMap((s) => s.items.map((i) => i.key)).join('|'))
  const shortcut = $derived(comboLabel(settings.get('hotkeys.quick')).join('+'))

  // новый запрос — снова с первой строки; список сократился — не выходим за край
  $effect(() => {
    quick.query
    active = 0
  })
  $effect(() => {
    if (active >= flat.length) active = Math.max(0, flat.length - 1)
  })

  $effect(() => {
    if (!quick.open) return
    before = document.activeElement instanceof HTMLElement ? document.activeElement : null
    void tick().then(() => input?.focus())
    return () => before?.focus?.()
  })

  // выбранная строка всегда видна (стрелки и Tab)
  $effect(() => {
    const key = flat[active]?.key
    if (!key || !list) return
    list.querySelector<HTMLElement>(`[data-key="${CSS.escape(key)}"]`)?.scrollIntoView({ block: 'nearest' })
  })

  /** Сочетание быстрого окна — открыть / закрыть. Пока в настройках записывают сочетание — молчим. */
  function onWindowKey(e: KeyboardEvent) {
    const combo = settings.get('hotkeys.quick')
    if (combo && !hotkeys.suspended && comboFrom(e) === combo) {
      e.preventDefault()
      e.stopPropagation()
      // зажатое сочетание повторяется — окно не должно мигать
      if (!e.repeat) quick.toggle()
      return
    }
    if (quick.open && e.key === 'Escape') {
      e.preventDefault()
      e.stopPropagation()
      quick.hide()
    }
  }

  function onInputKey(e: KeyboardEvent) {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault()
      active = Math.max(0, step(active, e.key === 'ArrowDown' ? 1 : -1, flat.length))
    } else if (e.key === 'Tab') {
      e.preventDefault()
      active = Math.max(0, jumpGroup(active, starts, e.shiftKey))
    } else if (e.key === 'Enter' && !e.isComposing) {
      e.preventDefault()
      const item = flat[active]
      if (item) quick.run(item, e.shiftKey)
    }
  }

  function choose(item: QuickItem, e: MouseEvent) {
    quick.run(item, e.shiftKey)
  }
</script>

<svelte:window onkeydowncapture={onWindowKey} />

{#snippet row(item: QuickItem)}
  {@const i = indexOf.get(item.key) ?? -1}
  <button
    class="row"
    class:on={i === active}
    data-key={item.key}
    role="option"
    aria-selected={i === active}
    tabindex="-1"
    onmousemove={() => (active = i)}
    onclick={(e) => choose(item, e)}
  >
    <span class="art" class:round={item.group === 'artists'}>
      {#if item.cover}
        <img src={offline.src(item.cover, 34)} alt="" loading="lazy" draggable="false" />
      {:else}
        <Icon name={item.icon} size={18} />
      {/if}
      {#if item.service}<span class="src"><SourceIcon service={item.service} size={12} /></span>{/if}
    </span>
    <span class="text">
      <span class="title">{item.title}</span>
      {#if item.sub}<span class="sub">{item.sub}</span>{/if}
    </span>
    {#if i === active}
      <span class="hints" in:fade={{ duration: 120 }}>
        {#each QUICK_HINTS[item.hint] as [key, label] (key)}
          <span class="hint"><kbd>{key}</kbd> {t(label)}</span>
        {/each}
      </span>
    {/if}
  </button>
{/snippet}

<!-- заголовок и строки — прямые потомки .part, чтобы каскад шёл по строкам, а не группами -->
{#snippet group(section: (typeof sections)[number])}
  <h3 role="presentation">{section.title}</h3>
  {#each section.items as item (item.key)}
    {@render row(item)}
  {/each}
{/snippet}

{#if quick.open}
  <div class="back" transition:fade={{ duration: 160 }} onclick={() => quick.hide()} role="presentation"></div>
  <div class="wrap" role="presentation">
    <div class="box" role="dialog" aria-modal="true" aria-label={t('Быстрое окно')} in:pop={{ y: 0, scale: 0.98, duration: 220 }} out:pop={{ y: 0, scale: 0.98 }}>
      <label class="field">
        <Icon name="search" size={18} />
        <input
          bind:this={input}
          value={quick.query}
          oninput={(e) => quick.setQuery(e.currentTarget.value)}
          onkeydown={onInputKey}
          placeholder={t('Действие, настройка, плейлист или трек…')}
          spellcheck="false"
          autocomplete="off"
          role="combobox"
          aria-expanded="true"
          aria-controls="quick-list"
        />
        {#if shortcut}<kbd class="combo">{shortcut}</kbd>{/if}
      </label>

      <div class="list" id="quick-list" role="listbox" bind:this={list}>
        <div class="part" use:cascade={quick.opened}>
          {#each local as section (section.id)}
            {@render group(section)}
          {/each}
        </div>
        <div class="part" use:cascade={remoteKey}>
          {#each remote as section (section.id)}
            {@render group(section)}
          {/each}
        </div>
        {#if quick.searching}
          <p class="note" in:fade={{ duration: 120 }}>{t('Ищу в сервисах…')}</p>
        {:else if quick.remoteError}
          <p class="note err" in:fade={{ duration: 120 }}>{quick.remoteError}</p>
        {:else if !flat.length && quick.query.trim()}
          <p class="note" in:fade={{ duration: 120 }}>{t('Ничего не нашлось')}</p>
        {/if}
      </div>

      <footer>
        <span><kbd>↑</kbd><kbd>↓</kbd> {t('выбрать')}</span>
        <span><kbd>Tab</kbd> {t('следующий раздел')}</span>
        <span><kbd>Esc</kbd> {t('закрыть')}</span>
      </footer>
    </div>
  </div>
{/if}

<style>
  .back {
    position: fixed;
    inset: 0;
    z-index: 66;
    background: rgba(0, 0, 0, 0.4);
    backdrop-filter: blur(10px) saturate(1.1);
    -webkit-backdrop-filter: blur(10px) saturate(1.1);
  }
  .wrap {
    position: fixed;
    inset: 0;
    z-index: 67;
    display: flex;
    justify-content: center;
    align-items: flex-start;
    padding-top: 14vh;
    pointer-events: none;
  }
  .box {
    pointer-events: auto;
    width: min(620px, calc(100vw - 48px));
    max-height: min(560px, 76vh);
    display: flex;
    flex-direction: column;
    border-radius: var(--radius-l);
    background: color-mix(in srgb, var(--surface-2) 94%, transparent);
    border: 1px solid var(--border-strong);
    box-shadow: 0 28px 70px rgba(0, 0, 0, 0.55);
    overflow: hidden;
  }
  .field {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 0 16px;
    height: 54px;
    flex: none;
    color: var(--text-3);
    border-bottom: 1px solid var(--border);
  }
  input {
    flex: 1;
    min-width: 0;
    height: 100%;
    background: none;
    border: 0;
    outline: none;
    color: var(--text);
    font-size: calc(16px * var(--fs, 1));
  }
  input::placeholder {
    color: var(--text-3);
  }
  .list {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    padding: 6px;
    overscroll-behavior: contain;
  }
  h3:not(:first-child),
  .part:not(:empty) + .part:not(:empty) {
    margin-top: 4px;
  }
  h3 {
    margin: 0;
    padding: 8px 10px 4px;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-3);
  }
  .row {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 7px 10px;
    border-radius: var(--radius-s);
    text-align: left;
    color: var(--text);
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .row.on {
    background: var(--hover);
  }
  .row:active {
    transform: scale(0.99);
  }
  .art {
    position: relative;
    flex: none;
    width: 34px;
    height: 34px;
    display: grid;
    place-items: center;
    border-radius: 8px;
    background: var(--surface-3);
    color: var(--text-2);
  }
  .art.round,
  .art.round img {
    border-radius: 50%;
  }
  .art img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    border-radius: 8px;
  }
  .row.on .art {
    color: var(--accent);
  }
  .src {
    position: absolute;
    right: -3px;
    bottom: -3px;
    display: flex;
  }
  .text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }
  .title,
  .sub {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .title {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 500;
  }
  .sub {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .hints {
    flex: none;
    display: flex;
    gap: 10px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .hint {
    white-space: nowrap;
  }
  kbd {
    display: inline-block;
    padding: 1px 6px;
    border-radius: 6px;
    border: 1px solid var(--border-strong);
    background: var(--surface-1);
    font: inherit;
    font-size: calc(11px * var(--fs, 1));
    color: var(--text-2);
  }
  kbd + kbd {
    margin-left: 3px;
  }
  .combo {
    flex: none;
  }
  .note {
    margin: 0;
    padding: 12px 10px;
    font-size: calc(13px * var(--fs, 1));
    color: var(--text-3);
  }
  .note.err {
    color: var(--danger);
  }
  footer {
    flex: none;
    display: flex;
    gap: 16px;
    padding: 9px 16px;
    border-top: 1px solid var(--border);
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
</style>
