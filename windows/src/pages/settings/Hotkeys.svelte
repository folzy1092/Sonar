<script lang="ts">
  // Приложение → Клавиши (SETTINGS_NEXT «Клавиши»): сверху — где действуют (в приложении · поверх окон ·
  // везде), ниже три карточки: Плеер, Навигация (с быстрым окном), Окно и оверлей. Клавиша — кнопка-колпачок:
  // клик — «нажми новое», Esc — отмена, Backspace / Delete — без клавиши. ↻ у строки — как с завода.
  // Навигации можно голую клавишу (`/`): она работает только внутри окна.
  import { slide } from '../../lib/motion'
  import Card from '../../components/settings/Card.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Icon from '../../components/Icon.svelte'
  import { DEFAULTS, settings } from '../../lib/settings.svelte'
  import { cascade } from '../../lib/cascade'
  import {
    comboFrom,
    comboLabel,
    effectiveMap,
    HOTKEY_ACTIONS,
    hotkeys,
    isLocalAction,
    isOutsideAction,
    windowOnly,
    type HotkeyAction,
    type HotkeyScope,
  } from '../../lib/hotkeys.svelte'
  import { t } from '../../lib/i18n.svelte'

  type Target = HotkeyAction | 'quick'

  const SCOPE_HINTS: Record<HotkeyScope, string> = {
    app: 'Сочетания работают, только пока окно Sonar на экране и в фокусе',
    top: 'Ещё и в других программах, пока открыто мини-окно поверх окон',
    global: 'Везде, даже когда Sonar свёрнут или спрятан в трей',
  }

  const GROUPS = [
    { id: 'player', title: 'Плеер' },
    { id: 'nav', title: 'Навигация' },
    { id: 'window', title: 'Окно и оверлей' },
  ] as const

  /** Что ждёт новое сочетание. */
  let listening = $state<Target | null>(null)
  const map = $derived(settings.loaded ? effectiveMap() : DEFAULTS['hotkeys.map'])
  const quickCombo = $derived(settings.get('hotkeys.quick'))
  const scope = $derived(settings.get('hotkeys.scope'))
  const changed = $derived(HOTKEY_ACTIONS.some((a) => map[a.id] !== DEFAULTS['hotkeys.map'][a.id]))

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
      assign(listening, '')
      return
    }
    // одна клавиша (пробел и т. п.) — любому действию, кроме «Показать / скрыть окно»: она работает внутри окна
    const combo = comboFrom(e, listening !== 'quick' && !isOutsideAction(listening))
    if (combo) assign(listening, combo)
  }

  /** Пробел и Enter «нажимают» кнопку-колпачок на отпускании — после записи сочетания это снова включило бы запись. */
  let eatUp: string | null = null
  function release(e: KeyboardEvent) {
    if (e.code !== eatUp) return
    eatUp = null
    e.preventDefault()
    e.stopPropagation()
  }

  function assign(target: Target, combo: string) {
    eatUp = combo.split('+').at(-1) ?? null
    if (target === 'quick') hotkeys.setQuick(combo)
    else hotkeys.set(target, combo)
    listening = null
  }

  /** Подсказка под строкой: не встало, или где действие не сработает при выбранной области. */
  function note(id: HotkeyAction): { text: string; bad?: boolean } | null {
    if (hotkeys.failed.includes(id)) return { text: 'Не встало: сочетание занято другой программой', bad: true }
    if ((isLocalAction(id) || windowOnly(map[id] ?? '')) && scope !== 'app') return { text: 'Только внутри окна Sonar' }
    if (isOutsideAction(id) && scope === 'app') return { text: 'Работает поверх окон или везде' }
    return null
  }
</script>

<svelte:window onkeydowncapture={capture} onkeyupcapture={release} onblur={() => (listening = null)} />

<Card>
  <Choice
    title={t('Где действуют')}
    hint={t(SCOPE_HINTS[scope])}
    wide
    fill
    value={scope}
    options={[
      { id: 'app', label: t('В приложении'), icon: 'layout' },
      { id: 'top', label: t('Поверх окон'), icon: 'stack' },
      { id: 'global', label: t('Везде'), icon: 'monitor' },
    ]}
    onchange={(v) => settings.set('hotkeys.scope', v)}
  />
</Card>

{#each GROUPS as g, gi (g.id)}
  <Card title={t(g.title)}>
    {#snippet action()}
      {#if gi === 0 && changed}
        <button class="reset-all" onclick={() => hotkeys.resetMap()} transition:slide={{ duration: 180, axis: 'x' }}>{t('Вернуть все')}</button>
      {/if}
    {/snippet}
    <div class="list" use:cascade={`hotkeys-${g.id}`}>
      {#each HOTKEY_ACTIONS.filter((a) => a.group === g.id) as a (a.id)}
        {@const combo = map[a.id] ?? ''}
        {@const n = note(a.id)}
        {@render row(a.id, t(a.title), combo, combo !== DEFAULTS['hotkeys.map'][a.id], n, () => hotkeys.reset(a.id))}
      {/each}
      {#if g.id === 'nav'}
        {@render row(
          'quick',
          t('Быстрое окно'),
          quickCombo,
          quickCombo !== DEFAULTS['hotkeys.quick'],
          { text: 'Действия, настройки, плейлисты и поиск треков в одном поле' },
          () => hotkeys.setQuick(DEFAULTS['hotkeys.quick']),
        )}
      {/if}
    </div>
  </Card>
{/each}

<p class="hint">{t('Клик по клавише — нажми новую. Esc — отмена, Backspace — убрать. Одна клавиша (например, пробел) работает только внутри окна Sonar, по всей системе нужен Ctrl, Alt или Win.')}</p>

{#snippet row(id: Target, title: string, combo: string, dirty: boolean, n: { text: string; bad?: boolean } | null, reset: () => void)}
  <div class="row">
    <span class="text">
      <b>{title}</b>
      {#if n}<small class:bad={n.bad} transition:slide={{ duration: 180 }}>{t(n.text)}</small>{/if}
    </span>
    {#if dirty}
      <button class="undo" aria-label={t('Как было')} title={t('Как было')} onclick={reset} transition:slide={{ duration: 180, axis: 'x' }}>
        <Icon name="refresh" size={14} />
      </button>
    {/if}
    <button
      class="combo"
      class:listening={listening === id}
      class:bad={n?.bad}
      aria-label={t('Изменить сочетание: {action}', { action: title })}
      onclick={() => (listening = listening === id ? null : id)}
    >
      {#if listening === id}
        <span class="wait">{t('Нажми клавиши…')}</span>
      {:else if combo}
        {#each comboLabel(combo) as k, i (i)}<kbd>{k}</kbd>{/each}
      {:else}
        <span class="none">—</span>
      {/if}
    </button>
  </div>
{/snippet}

<style>
  .list {
    display: flex;
    flex-direction: column;
    padding: 4px 0;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 44px;
    padding: 4px 0;
  }
  .text {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }
  b {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  small {
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.4;
    color: var(--text-3);
  }
  small.bad {
    color: var(--danger, #e5484d);
  }
  .combo {
    display: inline-flex;
    align-items: center;
    justify-content: flex-end;
    gap: 5px;
    min-width: 120px;
    min-height: 34px;
    padding: 0 4px;
    border-radius: 10px;
    transition:
      background var(--normal) var(--ease),
      box-shadow var(--normal) var(--ease),
      transform var(--fast) var(--ease);
  }
  .combo:hover {
    background: var(--hover);
  }
  .combo:active {
    transform: scale(0.97);
  }
  .combo.listening {
    background: var(--surface-3);
    box-shadow: inset 0 0 0 1px var(--accent);
  }
  .combo.bad {
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--danger, #e5484d) 60%, transparent);
  }
  kbd {
    display: inline-grid;
    place-items: center;
    min-width: 26px;
    height: 26px;
    padding: 0 8px;
    border-radius: 7px;
    background: var(--surface-3);
    box-shadow: inset 0 -2px 0 color-mix(in srgb, var(--text) 10%, transparent);
    font: inherit;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    animation: key-in var(--normal) var(--ease) both;
  }
  kbd:nth-child(2) {
    animation-delay: 30ms;
  }
  kbd:nth-child(3) {
    animation-delay: 60ms;
  }
  .none {
    padding: 0 10px;
    color: var(--text-3);
  }
  .wait {
    padding: 0 8px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-2);
    animation: breathe 1.4s var(--ease) infinite;
  }
  .undo {
    display: grid;
    place-items: center;
    flex: none;
    width: 28px;
    height: 28px;
    border-radius: 50%;
    color: var(--text-3);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      rotate var(--normal) var(--ease);
  }
  .undo:hover {
    background: var(--hover);
    color: var(--text);
    rotate: -90deg;
  }
  .reset-all {
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
    white-space: nowrap;
    transition: color var(--fast) var(--ease);
  }
  .reset-all:hover {
    color: var(--text);
  }
  .hint {
    margin: 12px 4px 0;
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
    .wait {
      animation: none;
    }
    .undo:hover {
      rotate: none;
    }
  }
</style>
