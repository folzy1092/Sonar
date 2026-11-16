<script lang="ts">
  // Кнопка эквалайзера в плеере и всплывашка (референс владельца 2026-11-16): сверху переключатель
  // «Эквалайзер», вкладки Улучшение / Жанры / Акценты / Мои с сеткой пресетов, ниже 12 вертикальных
  // ползунков со значением в дБ сверху и частотой снизу (тянуть мышью, колесо — ±0.5 дБ, двойной клик —
  // 0). Правки звучат сразу, «Сохранить» делает кривую общей для всех треков; закрыл без сохранения —
  // вернулась сохранённая. Включён и не ровный — кнопка подсвечена. Открывается и закрывается только кликом.
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import { pop } from '../lib/motion'
  import { indicator } from '../lib/indicator'
  import { cascade } from '../lib/cascade'
  import { EQ_FREQS, EQ_GROUPS, EQ_MAX_DB, PRESET_GROUPS, eq, freqLabel, type EqGroup } from './eq.svelte'

  let open = $state(false)
  let down = $state(false)
  /** Сколько места до края окна со стороны, куда открываемся, — всплывашка не вылезает за окно. */
  let room = $state(600)

  /** Открываемся туда, где места больше (страница плеера — кнопка высоко, нижний плеер — низко). */
  function place() {
    if (!root) return
    const r = root.getBoundingClientRect()
    const above = r.top - 16
    const below = window.innerHeight - r.bottom - 16
    down = below > above
    room = Math.max(220, down ? below : above)
  }
  let root: HTMLDivElement | undefined = $state()
  let group = $state<EqGroup>('enhance')
  let naming = $state(false)
  let newName = $state('')
  let justSaved = $state(false)
  let savedTimer: ReturnType<typeof setTimeout> | undefined
  let drag = $state<number | null>(null)

  /** Подсветка кнопки: эквалайзер включён и кривая не ровная. */
  const active = $derived(eq.enabled && eq.gains.some((g) => Math.abs(g) >= 0.05))
  const list = $derived(group === 'mine' ? eq.userPresets : PRESET_GROUPS[group])
  const fmt = (v: number) => (v > 0 ? `+${v}` : String(v))

  function toggle() {
    if (open) return close()
    place()
    open = true
  }

  function close() {
    open = false
    naming = false
    eq.discard()
  }

  function save() {
    eq.save()
    justSaved = true
    clearTimeout(savedTimer)
    savedTimer = setTimeout(() => (justSaved = false), 1600)
  }

  function savePreset(e: SubmitEvent) {
    e.preventDefault()
    eq.addPreset(newName)
    newName = ''
    naming = false
  }

  /** Значение полосы по вертикали курсора над её дорожкой. */
  function dbAt(track: HTMLElement, clientY: number) {
    const r = track.getBoundingClientRect()
    const t = 1 - (clientY - r.top) / r.height
    return Math.round((t * 2 - 1) * EQ_MAX_DB * 2) / 2
  }

  function down_(e: PointerEvent, i: number) {
    const track = e.currentTarget as HTMLElement
    track.setPointerCapture(e.pointerId)
    drag = i
    eq.setBand(i, dbAt(track, e.clientY))
  }

  function move(e: PointerEvent, i: number) {
    if (drag === i) eq.setBand(i, dbAt(e.currentTarget as HTMLElement, e.clientY))
  }

  onMount(() => {
    const outside = (e: MouseEvent) => {
      if (open && root && !root.contains(e.target as Node)) close()
    }
    window.addEventListener('mousedown', outside, true)
    return () => window.removeEventListener('mousedown', outside, true)
  })
</script>

<div class="eq" bind:this={root}>
  <button class="icon-btn" class:active class:open aria-label="Эквалайзер" title="Эквалайзер" aria-expanded={open} onclick={toggle}>
    <Icon name="adjustments" size={18} />
  </button>

  {#if open}
    <div class="pop" class:down style:max-height="{room}px" role="dialog" aria-label="Эквалайзер" in:pop={{ y: down ? -8 : 8 }} out:pop={{ y: down ? -8 : 8 }}>
      <button class="head" role="switch" aria-checked={eq.enabled} onclick={() => eq.setEnabled(!eq.enabled)}>
        <span class="ht"><b>Эквалайзер</b><small>Настройка звука по частотам</small></span>
        <i class="switch" class:on={eq.enabled} aria-hidden="true"></i>
      </button>

      <div class="body" class:off={!eq.enabled}>
        <div class="tabs" use:indicator={{ key: group, kind: 'pill' }}>
          {#each EQ_GROUPS as g (g.id)}
            <button class:on={group === g.id} onclick={() => (group = g.id)}>{g.label}</button>
          {/each}
        </div>

        {#key group}
          <div class="grid" use:cascade>
            {#each list as p (p.name)}
              <span class="chip" class:on={eq.activePreset === p.name}>
                <button class="pick" onclick={() => eq.set(p.gains)}>{p.name}</button>
                {#if group === 'mine'}
                  <button class="del" aria-label="Удалить пресет «{p.name}»" title="Удалить" onclick={() => eq.removePreset(p.name)}><Icon name="x" size={11} /></button>
                {/if}
              </span>
            {/each}
            {#if group === 'mine'}
              {#if naming}
                <form class="name" onsubmit={savePreset}>
                  <!-- svelte-ignore a11y_autofocus -->
                  <input bind:value={newName} placeholder="Название" maxlength="24" autofocus />
                  <button type="submit" aria-label="Сохранить пресет" disabled={!newName.trim()}><Icon name="check" size={14} /></button>
                </form>
              {:else}
                <button class="chip add" onclick={() => (naming = true)}><Icon name="plus" size={14} /> Сохранить текущий</button>
              {/if}
              {#if !eq.userPresets.length && !naming}
                <p class="mine-hint">Подвигай полосы и сохрани кривую — она появится здесь</p>
              {/if}
            {/if}
          </div>
        {/key}

        <div class="bands">
          {#each EQ_FREQS as f, i (f)}
            {@const g = eq.gains[i]}
            <div class="band">
              <span class="db" class:zero={Math.abs(g) < 0.05}>{fmt(g)}</span>
              <div
                class="track"
                class:drag={drag === i}
                role="slider"
                tabindex="-1"
                aria-label="{freqLabel(f)} Гц"
                aria-valuenow={g}
                aria-valuemin={-EQ_MAX_DB}
                aria-valuemax={EQ_MAX_DB}
                onpointerdown={(e) => down_(e, i)}
                onpointermove={(e) => move(e, i)}
                onpointerup={() => (drag = null)}
                ondblclick={() => eq.setBand(i, 0)}
                onwheel={(e) => {
                  e.preventDefault()
                  eq.setBand(i, g + (e.deltaY < 0 ? 0.5 : -0.5))
                }}
              >
                <i class="mid"></i>
                <i class="fill" style:--from="{50}%" style:--to="{50 - (g / EQ_MAX_DB) * 50}%"></i>
                <span class="thumb" style:top="{50 - (g / EQ_MAX_DB) * 50}%"></span>
              </div>
              <span class="hz">{freqLabel(f)}</span>
            </div>
          {/each}
        </div>

        <button class="save" class:on={justSaved && !eq.dirty} disabled={!eq.dirty && !justSaved} onclick={save}>
          {#key justSaved && !eq.dirty}
            <span class="lbl">{#if justSaved && !eq.dirty}<Icon name="check" size={15} /> Сохранено{:else}Сохранить для всех треков{/if}</span>
          {/key}
        </button>
      </div>
    </div>
  {/if}
</div>

<style>
  .eq {
    position: relative;
  }
  .icon-btn {
    display: grid;
    place-items: center;
    width: 32px;
    height: 32px;
    border-radius: 10px;
    color: var(--text-2);
    transition:
      color var(--normal) var(--ease),
      background var(--normal) var(--ease),
      box-shadow var(--normal) var(--ease);
  }
  .icon-btn:hover,
  .icon-btn.open {
    color: var(--text);
  }
  /* что-то настроено — кнопка мягко подсвечена (как у Liner) */
  .icon-btn.active {
    color: var(--text);
    background: color-mix(in srgb, var(--text) 14%, transparent);
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--text) 10%, transparent);
  }
  .pop {
    position: absolute;
    right: -8px;
    bottom: calc(100% + 10px);
    z-index: 20;
    width: 340px;
    padding: 14px;
    border-radius: 20px;
    background: color-mix(in srgb, var(--surface-1) 92%, var(--tint));
    border: 1px solid var(--border-strong);
    box-shadow: 0 22px 50px -12px rgba(0, 0, 0, 0.7);
    transform-origin: bottom right;
    overflow-y: auto;
    scrollbar-width: thin;
  }
  .pop.down {
    top: calc(100% + 10px);
    bottom: auto;
    transform-origin: top right;
  }
  .head {
    display: flex;
    align-items: center;
    gap: 12px;
    width: 100%;
    text-align: left;
  }
  .ht {
    flex: 1;
    display: grid;
  }
  .ht b {
    font-size: calc(15px * var(--fs, 1));
  }
  .ht small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .switch {
    position: relative;
    flex: none;
    width: 40px;
    height: 24px;
    border-radius: 999px;
    background: var(--surface-3);
    transition: background var(--normal) var(--ease);
  }
  .switch::after {
    content: '';
    position: absolute;
    top: 3px;
    left: 3px;
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background: var(--text-2);
    transition:
      transform var(--normal) var(--ease),
      background var(--normal) var(--ease);
  }
  .switch.on {
    background: color-mix(in srgb, var(--text) 45%, transparent);
  }
  .switch.on::after {
    transform: translateX(16px);
    background: var(--text);
  }
  .body {
    transition:
      opacity var(--normal) var(--ease),
      filter var(--normal) var(--ease);
  }
  .body.off {
    opacity: 0.4;
    filter: saturate(0.4);
  }
  .tabs {
    display: flex;
    margin-top: 12px;
    padding: 3px;
    border-radius: 12px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  .tabs :global(.tab-ind.pill) {
    border-radius: 9px;
    background: var(--surface-3);
  }
  .tabs button {
    flex: 1;
    height: 28px;
    border-radius: 9px;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-3);
    transition: color var(--fast) var(--ease);
  }
  .tabs button.on {
    color: var(--text);
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 6px;
    margin-top: 10px;
  }
  .chip {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: center;
    min-width: 0;
    height: 32px;
    border-radius: 10px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
    transition:
      background var(--normal) var(--ease),
      color var(--normal) var(--ease),
      border-color var(--normal) var(--ease);
  }
  .chip:hover {
    color: var(--text);
    background: var(--hover);
  }
  .chip.on {
    background: var(--text);
    border-color: var(--text);
    color: var(--on-text);
  }
  .pick {
    width: 100%;
    height: 100%;
    padding: 0 6px;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .del {
    position: absolute;
    top: -5px;
    right: -5px;
    display: grid;
    place-items: center;
    width: 17px;
    height: 17px;
    border-radius: 50%;
    background: var(--surface-3);
    color: var(--text-2);
    opacity: 0;
    transition: opacity var(--fast) var(--ease);
  }
  .chip:hover .del {
    opacity: 1;
  }
  .chip.add {
    grid-column: 1 / -1;
    gap: 6px;
    border-style: dashed;
  }
  .mine-hint {
    grid-column: 1 / -1;
    margin: 2px 2px 0;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .name {
    display: flex;
    grid-column: 1 / -1;
    gap: 4px;
  }
  .name input {
    flex: 1;
    min-width: 0;
    height: 32px;
    padding: 0 10px;
    border-radius: 10px;
    border: 1px solid var(--border-strong);
    background: var(--surface-2);
    font-size: calc(12px * var(--fs, 1));
    outline: none;
  }
  .name button {
    display: grid;
    place-items: center;
    width: 32px;
    border-radius: 10px;
    background: var(--text);
    color: var(--on-text);
  }
  .name button:disabled {
    opacity: 0.4;
  }
  .bands {
    display: grid;
    grid-template-columns: repeat(12, 1fr);
    margin-top: 14px;
  }
  .band {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
  }
  .db {
    font-size: calc(10px * var(--fs, 1));
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    color: var(--text);
    transition: color var(--normal) var(--ease);
  }
  .db.zero {
    color: var(--text-3);
  }
  .track {
    position: relative;
    width: 20px;
    height: 120px;
    cursor: ns-resize;
    touch-action: none;
  }
  .track::before {
    content: '';
    position: absolute;
    left: 50%;
    top: 0;
    bottom: 0;
    width: 3px;
    translate: -50% 0;
    border-radius: 3px;
    background: var(--surface-3);
  }
  .mid {
    position: absolute;
    left: 50%;
    top: 50%;
    width: 9px;
    height: 1px;
    translate: -50% 0;
    background: var(--text-3);
  }
  .fill {
    position: absolute;
    left: 50%;
    width: 3px;
    translate: -50% 0;
    top: min(var(--from), var(--to));
    bottom: calc(100% - max(var(--from), var(--to)));
    border-radius: 3px;
    background: color-mix(in srgb, var(--text) 70%, transparent);
    transition:
      top 0.18s var(--ease),
      bottom 0.18s var(--ease);
  }
  .thumb {
    position: absolute;
    left: 50%;
    width: 16px;
    height: 10px;
    translate: -50% -50%;
    border-radius: 4px;
    background: var(--text);
    box-shadow: 0 2px 6px rgba(0, 0, 0, 0.45);
    transition:
      top 0.18s var(--ease),
      scale var(--fast) var(--ease);
  }
  .track:hover .thumb,
  .track.drag .thumb {
    scale: 1.15;
  }
  .track.drag .thumb,
  .track.drag .fill {
    transition: none;
  }
  .hz {
    font-size: calc(10px * var(--fs, 1));
    color: var(--text-3);
  }
  .save {
    display: grid;
    place-items: center;
    width: 100%;
    height: 36px;
    margin-top: 14px;
    border-radius: 12px;
    background: var(--text);
    color: var(--on-text);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    transition:
      background var(--normal) var(--ease),
      color var(--normal) var(--ease),
      opacity var(--normal) var(--ease),
      transform var(--fast) var(--ease);
  }
  .save:active:not(:disabled) {
    transform: scale(0.97);
  }
  .save.on {
    background: var(--surface-3);
    color: var(--text);
    opacity: 1;
  }
  .save:disabled {
    opacity: 0.4;
    cursor: default;
  }
  .lbl {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    animation: tab-in var(--normal) var(--ease);
  }
</style>
