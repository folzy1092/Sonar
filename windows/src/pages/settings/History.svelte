<script lang="ts">
  // Sonar → История версий: что менялось в каждой версии, новые сверху, «У вас» — у установленной.
  // Записи — `changelog.json` + заметки релизов `windows-v*` без служебных коммитов (update-core `mergeReleases`).
  import { onMount } from 'svelte'
  import { updater } from '../../lib/updater.svelte'
  import { cascade } from '../../lib/cascade'
  import { lang, t } from '../../lib/i18n.svelte'

  onMount(() => void updater.loadChangelog())

  const LOCALES = { ru: 'ru-RU', en: 'en-US', uk: 'uk-UA', es: 'es-ES', de: 'de-DE', pl: 'pl-PL' } as const
  const dateText = (d: string) => {
    const ms = Date.parse(d)
    return Number.isNaN(ms) ? d : new Date(ms).toLocaleDateString(LOCALES[lang()], { day: 'numeric', month: 'long', year: 'numeric' })
  }
</script>

  {#if updater.changelog === null}
    <div class="skel ph"></div>
  {:else if updater.changelog.length === 0}
    <p class="empty">{t('Здесь появятся изменения каждой версии — вместе с первым обновлением.')}</p>
  {:else}
    <div class="history" use:cascade>
      {#each updater.changelog as e (e.version)}
        <article class:current={e.version === updater.current}>
          <header>
            <b>{e.version}</b>
            {#if e.version === updater.current}<span class="tag">{t('У вас')}</span>{/if}
            {#if e.title}<span class="title">{e.title}</span>{/if}
            <small>{dateText(e.date)}</small>
          </header>
          <ul>
            {#each e.changes as c, i (i)}<li>{c}</li>{/each}
          </ul>
        </article>
      {/each}
    </div>
  {/if}

<style>
  article ul {
    margin: 0;
    padding: 0;
    list-style: none;
  }
  .empty {
    margin: 4px 0;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .history {
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  article {
    padding: 12px 14px;
    border-radius: 14px;
    border: 1px solid var(--card-line);
    box-shadow: var(--sheen);
    transition: border-color var(--fast) var(--ease);
  }
  article:hover {
    border-color: var(--border-strong);
  }
  article header {
    display: flex;
    align-items: baseline;
    gap: 8px;
    margin-bottom: 6px;
  }
  article header b {
    font-family: var(--font-display);
    font-size: calc(15px * var(--fs, 1));
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
  .tag {
    padding: 2px 8px;
    border-radius: 999px;
    background: var(--accent);
    color: var(--accent-ink);
    font-size: calc(11px * var(--fs, 1));
    font-weight: 700;
  }
  .title {
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    color: var(--text-2);
  }
  article header small {
    margin-left: auto;
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  article li {
    position: relative;
    padding: 3px 0 3px 14px;
    font-size: calc(13px * var(--fs, 1));
    line-height: 1.45;
    color: var(--text-2);
  }
  article li::before {
    content: '';
    position: absolute;
    left: 2px;
    top: 11px;
    width: 4px;
    height: 4px;
    border-radius: 50%;
    background: var(--text-3);
  }
  .ph {
    height: 90px;
    border-radius: 14px;
  }
</style>
