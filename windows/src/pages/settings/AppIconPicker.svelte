<script lang="ts">
  // Интерфейс → Вид → «Значок приложения»: плитки с десятью значками, выбранный — в рамке акцента (рамка
  // переезжает, `use:indicator`). Выбор сразу уходит в Rust (`appearance.app_icon` → app_icon.rs): окно,
  // панель задач и трей меняются на лету. Список и названия — `lib/app-icons.ts`.
  import { APP_ICONS, appIconOr, appIconSrc, type AppIconId } from '../../lib/app-icons'
  import { indicator } from '../../lib/indicator'
  import { offline } from '../../lib/offline.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { t } from '../../lib/i18n.svelte'

  const value = $derived(appIconOr(settings.get('appearance.app_icon')))

  function pick(id: AppIconId) {
    if (id !== value) settings.set('appearance.app_icon', id)
  }
</script>

<div class="icons" role="radiogroup" aria-label={t('Значок приложения')} use:indicator={{ key: value, kind: 'pill' }}>
  {#each APP_ICONS as icon (icon.id)}
    <button class="icon" class:on={value === icon.id} role="radio" aria-checked={value === icon.id} onclick={() => pick(icon.id)}>
      <img src={offline.src(appIconSrc(icon.id))} alt="" width="64" height="64" draggable="false" />
      <span>{t(icon.title)}</span>
    </button>
  {/each}
</div>

<style>
  .icons {
    position: relative;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(104px, 1fr));
    gap: 10px;
    padding: 9px 3px;
  }
  .icon {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
    padding: 12px 8px 10px;
    border-radius: 14px;
    background: var(--plate);
    color: var(--text-2);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .icon:hover {
    background: var(--hover);
  }
  .icon:active {
    transform: scale(0.96);
  }
  .icon.on {
    background: var(--surface-3);
    color: var(--text);
  }
  img {
    display: block;
    width: 64px;
    height: 64px;
    transition: transform var(--normal) var(--ease);
  }
  .icon:hover img {
    transform: scale(1.06);
  }
  .icon.on img {
    transform: scale(1.04);
  }
  /* рамка выбранной плитки — тот же переезжающий индикатор, что у плиток «Стиль» и «Вкладки» */
  .icons :global(.tab-ind.pill) {
    z-index: 2;
    border-radius: 14px;
    background: transparent;
    box-shadow: 0 0 0 2px var(--accent);
    transition:
      transform var(--normal) var(--ease),
      top var(--normal) var(--ease),
      width var(--normal) var(--ease),
      height var(--normal) var(--ease),
      opacity var(--fast) var(--ease);
  }
  @media (prefers-reduced-motion: reduce) {
    img,
    .icon:hover img,
    .icon.on img {
      transform: none;
    }
  }
</style>
