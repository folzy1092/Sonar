<script lang="ts">
  // Интерфейс → Вид → «Текст» (SETTINGS_NEXT «Вид»): группы шрифтов капсулами, под ними сетка карточек
  // «Aa + название» в 4 колонки — без прокрутки вбок. Длинная группа показывает первые 16 и «Ещё N».
  // «Свой» — файл шрифта с компьютера (theme/custom-font.ts). Ниже — размер и жирность.
  import Icon from '../../components/Icon.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import { indicator } from '../../lib/indicator'
  import { cascade } from '../../lib/cascade'
  import { settings } from '../../lib/settings.svelte'
  import { CUSTOM_PREFIX, FONT_CATEGORIES, FONTS, fontCategory, fontLabel, fontStack, type FontCategory } from '../../theme/look'
  import { saveCustomFont } from '../../theme/custom-font'
  import { toast } from '../../lib/toast.svelte'
  import { t, tn } from '../../lib/i18n.svelte'

  /** Сколько карточек видно в группе до «Ещё»: сетка 4×4. */
  const VISIBLE = 16

  const font = $derived(settings.get('appearance.font'))
  const custom = $derived(font.startsWith(CUSTOM_PREFIX))
  let category = $state<FontCategory>(fontCategory(settings.get('appearance.font')))
  let expanded = $state(false)
  let filePick: HTMLInputElement | undefined = $state()

  const all = $derived(FONTS[category])
  // выбранный шрифт из хвоста группы не прячем под «Ещё»
  const shown = $derived(expanded || all.indexOf(font) >= VISIBLE ? all : all.slice(0, VISIBLE))
  const hidden = $derived(all.length - shown.length)

  function pickCategory(c: FontCategory) {
    category = c
    expanded = false
  }

  /** «Свой» — выбирается сразу, файл хранится в IndexedDB. */
  async function pickFont(e: Event) {
    const input = e.currentTarget as HTMLInputElement
    const file = input.files?.[0]
    input.value = ''
    if (!file) return
    try {
      const name = await saveCustomFont(file)
      settings.set('appearance.font', CUSTOM_PREFIX + name)
      toast.show(t('Шрифт «{name}» подключён', { name }))
    } catch {
      toast.show(t('Не получилось прочитать шрифт — нужен файл .ttf, .otf, .woff или .woff2'))
    }
  }
</script>

<div class="block">
  <b>{t('Шрифт')}</b>
  <small>{t('Семейство шрифта')}</small>
  <div class="cats" use:indicator={{ key: category, kind: 'pill' }}>
    {#each FONT_CATEGORIES as c (c.id)}
      <button class:on={category === c.id} onclick={() => pickCategory(c.id)}>{t(c.label)}</button>
    {/each}
  </div>
  {#key category}
    <div class="fonts" use:cascade>
      {#each shown as f (f)}
        <button class="font" class:on={font === f} title={t(fontLabel(f))} onclick={() => settings.set('appearance.font', f)}>
          <span class="aa" style:font-family={fontStack(f) ?? 'var(--font)'}>Aa</span>
          <span class="name">{t(fontLabel(f))}</span>
        </button>
      {/each}
      {#if custom && category === fontCategory(font)}
        <button class="font on" title={fontLabel(font)}>
          <span class="aa" style:font-family={fontStack(font)}>Aa</span>
          <span class="name">{fontLabel(font)}</span>
        </button>
      {/if}
      {#if hidden > 0}
        <button class="font more" onclick={() => (expanded = true)}>
          <span class="aa"><Icon name="plus" size={18} /></span>
          <span class="name">{tn(hidden, ['Ещё {n} шрифт', 'Ещё {n} шрифта', 'Ещё {n} шрифтов']).replace('{n}', String(hidden))}</span>
        </button>
      {/if}
      <button class="font more" title={t('Свой шрифт с компьютера (.ttf, .otf, .woff, .woff2)')} onclick={() => filePick?.click()}>
        <span class="aa"><Icon name="cloudUp" size={18} /></span>
        <span class="name">{t('Свой')}</span>
      </button>
    </div>
  {/key}
  <input bind:this={filePick} type="file" accept=".ttf,.otf,.woff,.woff2" hidden onchange={pickFont} />
</div>

<Choice
  title={t('Размер шрифта')}
  hint={t('Базовый размер шрифта интерфейса')}
  wide
  fill
  value={settings.get('appearance.font_size')}
  options={[12, 14, 16, 18, 20].map((n) => ({ id: n, label: String(n), sub: n === 16 ? t('Авто') : undefined }))}
  onchange={(v) => settings.set('appearance.font_size', v)}
/>
<Choice
  title={t('Жирность шрифта')}
  hint={t('Плотность начертания обычного текста')}
  wide
  fill
  value={settings.get('appearance.font_weight')}
  options={[{ id: 'auto' as const, label: t('Авто') }, ...(['400', '500', '600', '700'] as const).map((n) => ({ id: n, label: n }))]}
  onchange={(v) => settings.set('appearance.font_weight', v)}
/>

<style>
  .block {
    display: flex;
    flex-direction: column;
    gap: 3px;
    padding: 11px 0 9px;
  }
  .block b {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 600;
  }
  .block small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .cats {
    display: flex;
    margin-top: 10px;
    padding: 3px;
    border-radius: 10px;
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
  }
  .cats :global(.tab-ind.pill) {
    border-radius: 7px;
    background: var(--surface-3);
  }
  .cats button {
    flex: 1;
    height: 30px;
    border-radius: 7px;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    transition: color var(--fast) var(--ease);
  }
  .cats button.on {
    color: var(--text);
    font-weight: 600;
  }
  .fonts {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 8px;
    margin-top: 12px;
  }
  .font {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    min-width: 0;
    padding: 12px 6px 9px;
    border-radius: var(--radius-m);
    background: var(--surface-2);
    color: var(--text-2);
    box-shadow: inset 0 0 0 1.5px transparent;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      box-shadow var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .font:hover {
    background: var(--hover);
    color: var(--text);
  }
  .font:active {
    transform: scale(0.95);
  }
  .font.on {
    background: var(--surface-3);
    color: var(--text);
    box-shadow: inset 0 0 0 1.5px var(--accent);
  }
  .aa {
    display: grid;
    place-items: center;
    height: 30px;
    font-size: 24px;
    line-height: 1;
  }
  .more .aa {
    color: var(--text-3);
  }
  .name {
    max-width: 100%;
    font-size: calc(11px * var(--fs, 1));
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .font.on .name {
    font-weight: 700;
  }
  @media (prefers-reduced-motion: reduce) {
    .font:active {
      transform: none;
    }
  }
</style>
