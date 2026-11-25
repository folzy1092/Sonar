<script lang="ts">
  // «Чаще · Реже · Никогда» для артиста (вкус по артистам, `lib/artist-prefs.svelte.ts`): меню трека,
  // страница исполнителя и «Плеер → Вкус». Нажатое ещё раз — снять. Капсула выбранного переезжает (`use:indicator`).
  import { indicator } from '../lib/indicator'
  import { artistTaste } from '../lib/artist-prefs.svelte'
  import { LEVELS, type ArtistLevel } from '../lib/artist-prefs-core'
  import { t } from '../lib/i18n.svelte'

  let {
    name,
    compact = false,
    quiet = false,
    onpick,
  }: { name: string; compact?: boolean; quiet?: boolean; onpick?: (level: ArtistLevel | null) => void } = $props()

  const LABEL: Record<ArtistLevel, string> = { more: 'вкус::Чаще', less: 'вкус::Реже', never: 'вкус::Никогда' }
  const HINT: Record<ArtistLevel, string> = {
    more: 'Ставить этого артиста в Sonar Mix чаще',
    less: 'Ставить этого артиста в Sonar Mix реже',
    never: 'Не ставить этого артиста в Sonar Mix и похожие',
  }
  const level = $derived(artistTaste.levelOf(name))

  function pick(l: ArtistLevel) {
    artistTaste.set(name, l, quiet)
    onpick?.(artistTaste.levelOf(name))
  }
</script>

<div class="seg" class:compact role="group" aria-label={t('Артист в Sonar Mix')} use:indicator={{ key: level, kind: 'pill' }}>
  {#each LEVELS as l (l)}
    <button type="button" class:on={level === l} class:never={l === 'never'} aria-pressed={level === l} title={t(HINT[l])} onclick={() => pick(l)}>
      {t(LABEL[l])}
    </button>
  {/each}
</div>

<style>
  .seg {
    position: relative;
    display: inline-flex;
    gap: 2px;
    padding: 3px;
    border-radius: 999px;
    border: 1px solid var(--border-strong);
  }
  .seg :global(.tab-ind.pill) {
    border-radius: 999px;
    background: color-mix(in srgb, var(--text) 14%, transparent);
  }
  button {
    position: relative;
    z-index: 1;
    height: 26px;
    padding: 0 12px;
    border-radius: 999px;
    color: var(--text-3);
    font-size: calc(12.5px * var(--fs, 1));
    font-weight: 600;
    white-space: nowrap;
    transition: color var(--fast) var(--ease);
  }
  button:hover {
    color: var(--text);
  }
  button.on {
    color: var(--text);
  }
  button.never.on {
    color: var(--danger, #ff6b6b);
  }
  .compact button {
    height: 24px;
    padding: 0 9px;
    font-size: calc(12px * var(--fs, 1));
  }
</style>
