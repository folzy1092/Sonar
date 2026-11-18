<script lang="ts">
  // Конструктор умного плейлиста (NEXT_PROMPT, этап 6): окно по центру с затемнением, как у
  // подтверждения. Шаблоны (только у нового) → источник → условия → сортировка и лимит; внизу —
  // живой счётчик «подходит N треков» (Rust считает те же правила, что и при открытии плейлиста).
  // Открывается и закрывается только кликом (и Esc); черновик правится копией (`smartLists.draft`).
  import { fade } from 'svelte/transition'
  import { flip } from 'svelte/animate'
  import Icon from '../../components/Icon.svelte'
  import Pick from '../../components/Pick.svelte'
  import ConditionRow from './ConditionRow.svelte'
  import { api, type SmartPreview } from '../../lib/api'
  import { durationText, tracksText } from '../../lib/format'
  import { t } from '../../lib/i18n.svelte'
  import { library } from '../../lib/library.svelte'
  import { pop, rise } from '../../lib/motion'
  import { IMPLEMENTED } from '../../lib/services'
  import { MAX_CONDITIONS, TEMPLATES, defaultCondition, normalizeRules, rulesProblem, type SmartCondition, type SmartField, type SortBy } from '../../lib/smart'
  import { smartLists, type SmartDraft } from '../../lib/smart-lists.svelte'
  import { router } from '../router.svelte'

  /** Пауза перед пересчётом предпросмотра, пока правила меняются (печать в поле). */
  const PREVIEW_DELAY_MS = 300

  const draft = $derived(smartLists.draft)
  let saving = $state(false)
  let adding = $state(false)
  let preview = $state<SmartPreview | null>(null)
  let condKeys = $state<number[]>([])
  let keySeq = 0

  const serviceIds = IMPLEMENTED.map((s) => s.id as string)
  const problem = $derived(draft ? rulesProblem(draft.rules, serviceIds) : null)
  const fields: { id: SmartField; label: string }[] = $derived([
    { id: 'plays', label: t('Сколько раз слушал') },
    { id: 'last_played', label: t('Когда слушал последний раз') },
    { id: 'added', label: t('Когда добавлен') },
    { id: 'service', label: t('Сервис') },
    { id: 'artist', label: t('Исполнитель') },
    { id: 'duration', label: t('Длительность') },
  ])
  const sorts: { id: SortBy; label: string }[] = $derived([
    { id: 'added', label: t('По дате добавления') },
    { id: 'plays', label: t('По числу прослушиваний') },
    { id: 'last_played', label: t('По последнему прослушиванию') },
    { id: 'title', label: t('По названию') },
    { id: 'artist', label: t('По исполнителю') },
    { id: 'duration', label: t('По длительности') },
  ])

  // у каждой строки условия — свой ключ: удаление из середины не перерисовывает соседей
  $effect(() => {
    const n = smartLists.draft?.rules.conditions.length ?? 0
    if (condKeys.length !== n) condKeys = Array.from({ length: n }, (_, i) => condKeys[i] ?? ++keySeq)
  })

  // живой предпросмотр: правила поменялись — пересчитать через паузу; ответ на старые правила,
  // пришедший позже нового, не показываем (номер запроса)
  let previewSeq = 0
  $effect(() => {
    const d = smartLists.draft
    const seq = ++previewSeq
    if (!d) {
      preview = null
      return
    }
    const rules = normalizeRules(d.rules)
    if (rulesProblem(rules, serviceIds)) {
      preview = null
      return
    }
    const timer = setTimeout(async () => {
      try {
        const next = await api.smartPreview(rules)
        if (seq === previewSeq) preview = next
      } catch {
        if (seq === previewSeq) preview = null
      }
    }, PREVIEW_DELAY_MS)
    return () => clearTimeout(timer)
  })

  function patch(next: Partial<SmartDraft['rules']>) {
    if (!draft) return
    smartLists.draft = { ...draft, rules: { ...draft.rules, ...next } }
  }

  function setCondition(i: number, c: SmartCondition) {
    if (!draft) return
    patch({ conditions: draft.rules.conditions.map((x, j) => (j === i ? c : x)) })
  }

  function removeCondition(i: number) {
    if (!draft) return
    condKeys = condKeys.filter((_, j) => j !== i)
    patch({ conditions: draft.rules.conditions.filter((_, j) => j !== i) })
  }

  function addCondition(field: SmartField) {
    adding = false
    if (!draft || draft.rules.conditions.length >= MAX_CONDITIONS) return
    condKeys = [...condKeys, ++keySeq]
    patch({ conditions: [...draft.rules.conditions, defaultCondition(field, serviceIds[0])] })
  }

  function useTemplate(id: string) {
    const tpl = TEMPLATES.find((x) => x.id === id)
    if (!tpl || !draft) return
    condKeys = []
    smartLists.edit({ id: null, name: t(tpl.name), rules: tpl.rules })
  }

  async function save() {
    if (!draft || problem || !draft.name.trim()) return
    saving = true
    const isNew = !draft.id
    const id = await smartLists.save(draft)
    saving = false
    if (!id) return
    smartLists.close()
    if (isNew) router.go('playlist', id)
  }

  function onKey(e: KeyboardEvent) {
    if (smartLists.draft && e.key === 'Escape') {
      e.stopPropagation()
      smartLists.close()
    }
  }
</script>

<svelte:window onkeydowncapture={onKey} />

{#if draft}
  <div class="back" transition:fade={{ duration: 200 }} onclick={() => smartLists.close()} role="presentation"></div>
  <div class="wrap" role="dialog" aria-modal="true" aria-labelledby="smart-title">
    <form
      class="card"
      in:pop={{ y: 10, scale: 0.95, duration: 240 }}
      out:pop={{ y: 6 }}
      onsubmit={(e) => (e.preventDefault(), save())}
    >
      <h2 id="smart-title"><Icon name="sparkles" size={20} /> {draft.id ? t('Правила плейлиста') : t('Умный плейлист')}</h2>

      {#if !draft.id}
        <div class="templates">
          {#each TEMPLATES as tpl, i (tpl.id)}
            <button type="button" class="chip" in:rise={{ delay: i * 30, y: 6 }} onclick={() => useTemplate(tpl.id)}>{t(tpl.name)}</button>
          {/each}
        </div>
      {/if}

      <label class="field">
        <span>{t('Название')}</span>
        <input
          value={draft.name}
          maxlength="100"
          spellcheck="false"
          placeholder={t('Например, «Вечерний топ»')}
          oninput={(e) => smartLists.draft && (smartLists.draft = { ...smartLists.draft, name: e.currentTarget.value })}
        />
      </label>

      <div class="field">
        <span>{t('Откуда брать треки')}</span>
        <div class="row">
          <Pick
            value={draft.rules.source.kind}
            label={t('Откуда брать треки')}
            options={[
              { id: 'liked', label: t('Любимые') },
              { id: 'playlist', label: t('Плейлист') },
              { id: 'played', label: t('Всё прослушанное') },
            ]}
            onchange={(kind) => patch({ source: kind === 'playlist' ? { kind, id: library.playlists[0]?.id ?? '' } : { kind } })}
          />
          {#if draft.rules.source.kind === 'playlist'}
            {@const src = draft.rules.source}
            {#if library.playlists.length}
              <Pick value={src.id} label={t('Плейлист')} options={library.playlists.map((p) => ({ id: p.id, label: p.name }))} onchange={(id) => patch({ source: { kind: 'playlist', id } })} />
            {:else}
              <span class="hint">{t('Своих плейлистов пока нет')}</span>
            {/if}
          {/if}
        </div>
      </div>

      <div class="field">
        <span class="head">
          {t('Условия')}
          {#if draft.rules.conditions.length > 1}
            <Pick
              value={draft.rules.match}
              options={[
                { id: 'all', label: t('подходят все') },
                { id: 'any', label: t('подходит любое') },
              ]}
              onchange={(match) => patch({ match })}
            />
          {/if}
        </span>
        <div class="conds">
          {#each draft.rules.conditions as c, i (condKeys[i] ?? i)}
            <div animate:flip={{ duration: 200 }} in:rise={{ y: 6 }}>
              <ConditionRow cond={c} onchange={(next) => setCondition(i, next)} onremove={() => removeCondition(i)} />
            </div>
          {:else}
            <p class="hint">{t('Без условий — все треки источника.')}</p>
          {/each}
        </div>
        <div class="add">
          <button type="button" class="ghost" disabled={draft.rules.conditions.length >= MAX_CONDITIONS} onclick={() => (adding = !adding)}>
            <Icon name="plus" size={15} /> {t('Условие')}
          </button>
          {#if adding}
            <div class="menu" in:pop={{ y: -6 }} out:pop={{ y: -6 }}>
              {#each fields as f (f.id)}
                <button type="button" onclick={() => addCondition(f.id)}>{f.label}</button>
              {/each}
            </div>
          {/if}
        </div>
      </div>

      <div class="field">
        <span>{t('Порядок и лимит')}</span>
        <div class="row">
          <Pick
            value={draft.rules.sort?.by ?? 'added'}
            label={t('Сортировка')}
            options={sorts}
            onchange={(by) => patch({ sort: { by, desc: draft.rules.sort?.desc ?? true, days: draft.rules.sort?.days ?? null } })}
          />
          <Pick
            value={(draft.rules.sort?.desc ?? true) ? 'desc' : 'asc'}
            label={t('Направление')}
            options={[
              { id: 'desc', label: t('сначала больше / новее') },
              { id: 'asc', label: t('сначала меньше / старее') },
            ]}
            onchange={(d) => patch({ sort: { by: draft.rules.sort?.by ?? 'added', days: draft.rules.sort?.days ?? null, desc: d === 'desc' } })}
          />
          {#if draft.rules.sort?.by === 'plays'}
            {@const s = draft.rules.sort}
            <span class="hint">{t('за')}</span>
            <input class="n" type="number" min="0" value={s.days ?? 0} aria-label={t('Дней')} oninput={(e) => patch({ sort: { ...s, days: Number(e.currentTarget.value) || null } })} />
            <span class="hint">{t('дн.')}</span>
          {/if}
          <span class="hint">{t('не больше')}</span>
          <input
            class="n"
            type="number"
            min="0"
            placeholder="∞"
            value={draft.rules.limit ?? ''}
            aria-label={t('Лимит треков')}
            oninput={(e) => patch({ limit: Number(e.currentTarget.value) || null })}
          />
          <span class="hint">{t('треков')}</span>
        </div>
      </div>

      <div class="preview" aria-live="polite">
        {#if problem}
          <span class="warn">{t(problem)}</span>
        {:else if preview?.error === 'source_missing'}
          <span class="warn">{t('Исходного плейлиста больше нет')}</span>
        {:else if preview}
          <span class="covers">{#each preview.covers.slice(0, 3) as c, i (c + i)}<img src={c} alt="" draggable="false" />{/each}</span>
          {#key preview.track_count}
            <span in:fade={{ duration: 160 }}>
              {preview.track_count ? t('Подходит: {tracks}, {time}', { tracks: tracksText(preview.track_count), time: durationText(preview.duration_ms) }) : t('Пока ни один трек не подходит')}
            </span>
          {/key}
        {:else}
          <span class="hint">{t('Считаю…')}</span>
        {/if}
      </div>

      <div class="actions">
        <button type="button" class="btn no" onclick={() => smartLists.close()}>{t('Отмена')}</button>
        <button type="submit" class="btn yes" disabled={saving || !!problem || !draft.name.trim()}>{draft.id ? t('Сохранить') : t('Создать')}</button>
      </div>
    </form>
  </div>
{/if}

<style>
  .back {
    position: fixed;
    inset: 0;
    z-index: 70;
    background: rgba(0, 0, 0, 0.45);
    backdrop-filter: blur(14px) saturate(1.1);
    -webkit-backdrop-filter: blur(14px) saturate(1.1);
  }
  .wrap {
    position: fixed;
    inset: 0;
    z-index: 71;
    display: grid;
    place-items: center;
    pointer-events: none;
  }
  .card {
    pointer-events: auto;
    display: flex;
    flex-direction: column;
    gap: 16px;
    width: min(640px, calc(100vw - 48px));
    max-height: calc(100vh - 80px);
    overflow-y: auto;
    padding: 22px 22px 18px;
    border-radius: var(--radius-l);
    background: color-mix(in srgb, var(--surface-2) 94%, transparent);
    border: 1px solid var(--border-strong);
    box-shadow: 0 24px 60px rgba(0, 0, 0, 0.55);
  }
  h2 {
    display: flex;
    align-items: center;
    gap: 8px;
    margin: 0;
    font-size: calc(18px * var(--fs, 1));
    font-weight: 700;
  }
  h2 :global(svg) {
    color: var(--accent);
  }
  .templates {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .chip {
    height: 30px;
    padding: 0 12px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    font-weight: 600;
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .chip:hover {
    background: var(--hover);
  }
  .chip:active {
    transform: scale(0.96);
  }
  .field {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  .field > span,
  .head {
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--text-3);
  }
  .row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px;
  }
  .conds {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .hint {
    margin: 0;
    color: var(--text-3);
  }
  .field input {
    height: 36px;
    padding: 0 14px;
    border-radius: 999px;
    background: var(--plate);
    border: 1px solid var(--card-line);
    outline: none;
    user-select: text;
  }
  .field input:focus {
    border-color: var(--border-strong);
  }
  .field input.n {
    width: 76px;
    height: 30px;
    padding: 0 10px;
    font-variant-numeric: tabular-nums;
  }
  .add {
    position: relative;
    align-self: flex-start;
  }
  .ghost {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    height: 30px;
    padding: 0 12px;
    border-radius: 999px;
    border: 1px dashed var(--border-strong);
    color: var(--text-2);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .ghost:hover:not(:disabled) {
    background: var(--hover);
    color: var(--text);
  }
  .menu {
    position: absolute;
    top: calc(100% + 6px);
    left: 0;
    z-index: 6;
    display: flex;
    flex-direction: column;
    padding: 6px;
    border-radius: var(--radius-m);
    background: var(--surface-2);
    border: 1px solid var(--border-strong);
    box-shadow: 0 16px 40px rgba(0, 0, 0, 0.45);
  }
  .menu button {
    padding: 7px 10px;
    border-radius: 8px;
    text-align: left;
    white-space: nowrap;
  }
  .menu button:hover {
    background: var(--hover);
  }
  .preview {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 40px;
    padding: 6px 12px;
    border-radius: var(--radius-m);
    background: var(--plate);
    color: var(--text-2);
  }
  .warn {
    color: var(--danger);
  }
  .covers {
    display: inline-flex;
  }
  .covers img {
    width: 28px;
    height: 28px;
    border-radius: 6px;
    object-fit: cover;
    border: 2px solid var(--surface-2);
  }
  .covers img + img {
    margin-left: -10px;
  }
  .actions {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
  }
  .btn {
    height: 40px;
    border-radius: 999px;
    font-weight: 600;
    transition:
      background var(--fast) var(--ease),
      opacity var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .btn:active:not(:disabled) {
    transform: scale(0.96);
  }
  .no {
    background: var(--hover);
    border: 1px solid var(--border-strong);
  }
  .yes {
    background: var(--text);
    color: var(--bg, #000);
  }
  .yes:disabled {
    opacity: 0.5;
    cursor: default;
  }
</style>
