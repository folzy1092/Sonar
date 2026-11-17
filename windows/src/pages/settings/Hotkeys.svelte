<script lang="ts">
  // Система → Горячие клавиши (решение владельца 2026-11-17): сочетания работают по всей системе,
  // даже когда Sonar свёрнут в трей. По умолчанию выключены. Клик по сочетанию — «нажми новое»:
  // Esc — отмена, Backspace / Delete — без клавиши. Нужен хотя бы один модификатор.
  import { slide } from 'svelte/transition'
  import Switch from '../../components/settings/Switch.svelte'
  import Group from '../../components/settings/Group.svelte'
  import { DEFAULTS, settings } from '../../lib/settings.svelte'
  import { cascade } from '../../lib/cascade'
  import { comboFrom, comboLabel, HOTKEY_ACTIONS, hotkeys, type HotkeyAction } from '../../lib/hotkeys.svelte'
  import { t } from '../../lib/i18n.svelte'

  let listening = $state<HotkeyAction | null>(null)
  const map = $derived(settings.get('hotkeys.map'))
  const enabled = $derived(settings.get('hotkeys.enabled'))

  // пока ждём новое сочетание, свои сняты — иначе нажатие сработает как команда
  $effect(() => {
    hotkeys.suspended = listening !== null
    return () => (hotkeys.suspended = false)
  })

  function capture(e: KeyboardEvent) {
    if (!listening) return
    e.preventDefault()
    e.stopPropagation()
    if (e.key === 'Escape') {
      listening = null
      return
    }
    if ((e.key === 'Backspace' || e.key === 'Delete') && !e.ctrlKey && !e.altKey && !e.shiftKey && !e.metaKey) {
      hotkeys.set(listening, '')
      listening = null
      return
    }
    const combo = comboFrom(e)
    if (!combo) return
    hotkeys.set(listening, combo)
    listening = null
  }

  function reset() {
    settings.set('hotkeys.map', { ...DEFAULTS['hotkeys.map'] })
  }
</script>

<svelte:window onkeydown={capture} onblur={() => (listening = null)} />

<Group title={t('Горячие клавиши')}>
  <Switch
    title={t('Горячие клавиши по всей системе')}
    hint={t('Управлять музыкой, даже когда Sonar свёрнут или спрятан в трей')}
    on={enabled}
    onchange={(v) => settings.set('hotkeys.enabled', v)}
  />
</Group>

{#if enabled}
  <div transition:slide={{ duration: 240 }}>
    <Group title={t('Сочетания')}>
      {#snippet action()}
        <button class="reset" onclick={reset}>{t('Вернуть по умолчанию')}</button>
      {/snippet}
      <div class="list" use:cascade={'hotkeys'}>
        {#each HOTKEY_ACTIONS as a (a.id)}
          {@const combo = map[a.id] ?? ''}
          {@const bad = hotkeys.failed.includes(a.id)}
          <div class="row">
            <span class="text">
              <b>{t(a.title)}</b>
              {#if bad}<small class="bad" transition:slide={{ duration: 180 }}>{t('Не встало: сочетание занято другой программой')}</small>{/if}
            </span>
            <button
              class="combo"
              class:listening={listening === a.id}
              class:empty={!combo}
              class:bad
              aria-label={t('Изменить сочетание: {action}', { action: t(a.title) })}
              onclick={() => (listening = listening === a.id ? null : a.id)}
            >
              {#if listening === a.id}
                <span class="wait">{t('Нажми сочетание…')}</span>
              {:else if combo}
                {#each comboLabel(combo) as k, i (i)}<kbd>{k}</kbd>{/each}
              {:else}
                <span class="wait">{t('Без клавиши')}</span>
              {/if}
            </button>
          </div>
        {/each}
      </div>
      <p class="hint">{t('Клик по сочетанию — нажми новое. Esc — отмена, Backspace — убрать клавишу. Нужен Ctrl, Alt, Shift или Win.')}</p>
    </Group>
  </div>
{/if}

<style>
  .list {
    display: flex;
    flex-direction: column;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 7px 0;
  }
  .text {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 3px;
  }
  b {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  small.bad {
    font-size: calc(12px * var(--fs, 1));
    color: var(--danger, #e5484d);
  }
  .combo {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    min-width: 132px;
    height: 32px;
    justify-content: flex-end;
    padding: 0 8px;
    border-radius: 10px;
    background: var(--plate);
    transition:
      background var(--normal) var(--ease),
      box-shadow var(--normal) var(--ease);
  }
  .combo:hover {
    background: var(--hover);
  }
  .combo.listening {
    box-shadow: inset 0 0 0 1px var(--accent);
  }
  .combo.bad {
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--danger, #e5484d) 60%, transparent);
  }
  kbd {
    min-width: 22px;
    padding: 2px 6px;
    border-radius: 6px;
    background: var(--surface-3);
    font: inherit;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    text-align: center;
    animation: key-in var(--normal) var(--ease);
  }
  .wait {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .combo.listening .wait {
    color: var(--text-2);
    animation: breathe 1.4s var(--ease) infinite;
  }
  .reset {
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
    transition: color var(--fast) var(--ease);
  }
  .reset:hover {
    color: var(--text);
  }
  .hint {
    margin: 10px 0 0;
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.45;
    color: var(--text-3);
  }
  @keyframes key-in {
    from {
      opacity: 0;
      translate: 0 3px;
    }
  }
  @keyframes breathe {
    50% {
      opacity: 0.5;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    kbd,
    .combo.listening .wait {
      animation: none;
    }
  }
</style>
