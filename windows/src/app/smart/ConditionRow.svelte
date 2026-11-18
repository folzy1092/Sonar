<script lang="ts">
  // Одна строка условия в конструкторе умного плейлиста: поле, сравнение и значение.
  // Условие не правится на месте — наверх уходит новая копия (`onchange`).
  import Icon from '../../components/Icon.svelte'
  import Pick from '../../components/Pick.svelte'
  import { t } from '../../lib/i18n.svelte'
  import { IMPLEMENTED } from '../../lib/services'
  import type { SmartCondition } from '../../lib/smart'

  interface Props {
    cond: SmartCondition
    onchange: (c: SmartCondition) => void
    onremove: () => void
  }
  let { cond, onchange, onremove }: Props = $props()

  const cmp = $derived([
    { id: 'gte' as const, label: t('не меньше') },
    { id: 'lte' as const, label: t('не больше') },
  ])
  const isNot = $derived([
    { id: 'is' as const, label: t('условие::это') },
    { id: 'not' as const, label: t('условие::не') },
  ])
  const services = $derived(IMPLEMENTED.map((s) => ({ id: s.id as string, label: t(s.name) })))

  const num = (e: Event) => Math.max(0, Math.round(Number((e.currentTarget as HTMLInputElement).value) || 0))
</script>

<div class="cond">
  {#if cond.field === 'plays'}
    {@const c = cond}
    <span class="lbl">{t('Прослушиваний')}</span>
    <Pick value={c.op} options={cmp} onchange={(op) => onchange({ ...c, op })} />
    <input class="n" type="number" min="0" value={c.value} oninput={(e) => onchange({ ...c, value: num(e) })} aria-label={t('Сколько раз')} />
    <span class="lbl">{t('за')}</span>
    <input class="n" type="number" min="0" value={c.days ?? 0} oninput={(e) => onchange({ ...c, days: num(e) || null })} aria-label={t('Дней')} />
    <span class="lbl">{c.days ? t('дн.') : t('дн. (0 — за всё время)')}</span>
  {:else if cond.field === 'last_played'}
    {@const c = cond}
    <span class="lbl">{t('Последний раз слушал')}</span>
    <Pick
      value={c.op}
      options={[
        { id: 'before', label: t('раньше, чем') },
        { id: 'after', label: t('позже, чем') },
      ]}
      onchange={(op) => onchange({ ...c, op })}
    />
    <input class="n" type="number" min="1" value={c.days} oninput={(e) => onchange({ ...c, days: num(e) })} aria-label={t('Дней')} />
    <span class="lbl">{t('дн. назад')}</span>
  {:else if cond.field === 'added'}
    {@const c = cond}
    <span class="lbl">{t('Добавлен за последние')}</span>
    <input class="n" type="number" min="1" value={c.days} oninput={(e) => onchange({ ...c, days: num(e) })} aria-label={t('Дней')} />
    <span class="lbl">{t('дн.')}</span>
  {:else if cond.field === 'service'}
    {@const c = cond}
    <span class="lbl">{t('Сервис')}</span>
    <Pick value={c.op} options={isNot} onchange={(op) => onchange({ ...c, op })} />
    <Pick value={c.value} options={services} onchange={(value) => onchange({ ...c, value })} />
  {:else if cond.field === 'artist'}
    {@const c = cond}
    <span class="lbl">{t('Исполнитель')}</span>
    <Pick value={c.op} options={isNot} onchange={(op) => onchange({ ...c, op })} />
    <input class="txt" value={c.value} spellcheck="false" placeholder={t('Имя или часть имени')} oninput={(e) => onchange({ ...c, value: e.currentTarget.value })} />
  {:else if cond.field === 'duration'}
    {@const c = cond}
    <span class="lbl">{t('Длительность')}</span>
    <Pick value={c.op} options={cmp} onchange={(op) => onchange({ ...c, op })} />
    <input class="n" type="number" min="0" value={Math.round(c.value / 60)} oninput={(e) => onchange({ ...c, value: num(e) * 60 })} aria-label={t('Минут')} />
    <span class="lbl">{t('мин')}</span>
  {/if}
  <span class="spacer"></span>
  <button type="button" class="x" aria-label={t('Убрать условие')} title={t('Убрать условие')} onclick={onremove}><Icon name="x" size={15} /></button>
</div>

<style>
  .cond {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px;
    padding: 8px 8px 8px 12px;
    border-radius: var(--radius-m);
    background: var(--plate);
    border: 1px solid var(--card-line);
  }
  .lbl {
    color: var(--text-2);
    white-space: nowrap;
  }
  .spacer {
    flex: 1;
  }
  input {
    height: 30px;
    padding: 0 10px;
    border-radius: 999px;
    background: var(--surface-2);
    border: 1px solid var(--card-line);
    outline: none;
    user-select: text;
  }
  input:focus {
    border-color: var(--border-strong);
  }
  .n {
    width: 72px;
    font-variant-numeric: tabular-nums;
  }
  .txt {
    flex: 1;
    min-width: 140px;
  }
  .x {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    border-radius: 50%;
    color: var(--text-3);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .x:hover {
    background: var(--hover);
    color: var(--text);
  }
  .x:active {
    transform: scale(0.92);
  }
</style>
