<script lang="ts">
  // «Подробнее» из всплывашки обновления: окно по центру со всем, что придёт с новой версией —
  // каждая версия между установленной и найденной (updates/changelog.json: название, дата, все
  // пункты), а если в истории записи нет (авто-патч с CI) — все заметки релиза целиком.
  // Закрывается только кликом: крестик или клик мимо окна.
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import LogoMark from '../components/LogoMark.svelte'
  import { pop } from '../lib/motion'
  import { cascade } from '../lib/cascade'
  import { updater } from '../lib/updater.svelte'
  import { pendingEntries } from '../lib/update-core'
  import { settingsPanel } from '../pages/settings-section.svelte'
  import { t, lang } from '../lib/i18n.svelte'

  let { onclose }: { onclose: () => void } = $props()

  onMount(() => void updater.loadChangelog())

  const p = $derived(updater.phase)
  const entries = $derived(updater.changelog ? pendingEntries(updater.changelog, updater.current, updater.version) : [])

  const LOCALES = { ru: 'ru-RU', en: 'en-GB', uk: 'uk-UA', es: 'es-ES', de: 'de-DE', pl: 'pl-PL' } as const
  const dateText = (d: string) => {
    const ms = Date.parse(d)
    return Number.isNaN(ms) ? '' : new Date(ms).toLocaleDateString(LOCALES[lang()], { day: 'numeric', month: 'long', year: 'numeric' })
  }

  function allVersions() {
    onclose()
    updater.popup = false
    settingsPanel.show('system', 'history')
  }
</script>

<div class="veil" role="presentation" onclick={(e) => e.target === e.currentTarget && onclose()}>
  <div class="box" role="dialog" aria-label={t('Обновление Sonar {version}', { version: updater.version })} in:pop={{ y: 14, scale: 0.95, duration: 300 }} out:pop={{ y: 14, scale: 0.95, duration: 220 }}>
    <header>
      <LogoMark size={40} spin={false} />
      <div class="h">
        <b>Sonar {updater.version}</b>
        <small>
          {t('у тебя {version}', { version: updater.current })}{#if dateText(updater.date)}{` · ${t('вышла {date}', { date: dateText(updater.date) })}`}{/if}
        </small>
      </div>
      <button class="x" aria-label={t('Закрыть')} onclick={onclose}><Icon name="x" size={16} /></button>
    </header>

    <div class="body app-scroll">
      {#if updater.changelog === null}
        <div class="skel ph"></div>
      {:else if entries.length}
        <div use:cascade>
          {#each entries as e (e.version)}
            <article>
              <div class="eh">
                <span class="ver">{e.version}</span>
                {#if e.title}<b>{e.title}</b>{/if}
                {#if dateText(e.date)}<small>{dateText(e.date)}</small>{/if}
              </div>
              <ul>
                {#each e.changes as c, i (i)}<li>{c}</li>{/each}
              </ul>
            </article>
          {/each}
        </div>
        <!-- найденная версия — авто-патч поверх записи истории: его заметки отдельным блоком -->
        {#if updater.notes.length && !entries.some((e) => e.version === updater.version)}
          <article>
            <div class="eh"><span class="ver">{t('мелочи')}</span><b>{t('Исправления и доработки')}</b></div>
            <ul>
              {#each updater.notes as n, i (i)}<li>{n}</li>{/each}
            </ul>
          </article>
        {/if}
      {:else if updater.notes.length}
        <ul use:cascade>
          {#each updater.notes as n, i (i)}<li>{n}</li>{/each}
        </ul>
      {:else}
        <p class="empty">{t('Исправления и небольшие доработки.')}</p>
      {/if}
    </div>

    <footer>
      <button class="btn" onclick={allVersions}>{t('Все версии')}</button>
      {#if p === 'downloading'}
        <button class="btn primary" disabled>{t('Загрузка {percent}%', { percent: Math.round(updater.progress * 100) })}</button>
      {:else if p === 'ready' || p === 'installing'}
        <button class="btn primary" disabled={p === 'installing'} onclick={() => updater.install()}>{t('Установить')}</button>
      {:else if p === 'available' || p === 'error'}
        <button class="btn primary" onclick={() => (p === 'error' ? updater.retry() : updater.download())}>{t('Обновить')}</button>
      {/if}
    </footer>
  </div>
</div>

<style>
  .veil {
    position: fixed;
    inset: 0;
    z-index: 60;
    display: grid;
    place-items: center;
    background: rgba(0, 0, 0, 0.55);
    animation: veil-in var(--normal) var(--ease);
  }
  @keyframes veil-in {
    from {
      opacity: 0;
    }
  }
  .box {
    display: flex;
    flex-direction: column;
    width: min(480px, calc(100vw - 48px));
    max-height: min(560px, calc(100vh - 80px));
    border-radius: 22px;
    background: var(--surface-1);
    border: 1px solid var(--border-strong);
    box-shadow: 0 30px 80px rgba(0, 0, 0, 0.6);
    overflow: hidden;
  }
  header {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 18px 18px 14px 20px;
    background: linear-gradient(180deg, color-mix(in srgb, var(--accent) 12%, transparent), transparent);
  }
  .h {
    flex: 1;
    min-width: 0;
    display: grid;
  }
  .h b {
    font-family: var(--font-display);
    font-size: calc(19px * var(--fs, 1));
    font-weight: 800;
    letter-spacing: -0.01em;
  }
  .h small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  .x {
    align-self: flex-start;
    display: grid;
    place-items: center;
    width: 30px;
    height: 30px;
    border-radius: 10px;
    color: var(--text-3);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .x:hover {
    background: var(--hover);
    color: var(--text);
  }
  .body {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    padding: 4px 16px 8px 20px;
  }
  article + article {
    margin-top: 16px;
    padding-top: 14px;
    border-top: 1px solid var(--border);
  }
  .eh {
    display: flex;
    align-items: baseline;
    flex-wrap: wrap;
    gap: 4px 8px;
    margin-bottom: 6px;
  }
  .ver {
    padding: 1px 7px;
    border-radius: 6px;
    background: var(--accent-soft);
    color: var(--accent);
    font-size: calc(11px * var(--fs, 1));
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
  .eh b {
    font-size: calc(14px * var(--fs, 1));
  }
  .eh small {
    margin-left: auto;
    font-size: calc(11px * var(--fs, 1));
    color: var(--text-3);
  }
  ul {
    margin: 0;
    padding: 0 0 0 14px;
    list-style: none;
  }
  li {
    position: relative;
    padding: 3px 0;
    font-size: calc(13px * var(--fs, 1));
    line-height: 1.5;
    color: var(--text-2);
  }
  li::before {
    content: '';
    position: absolute;
    left: -12px;
    top: 11px;
    width: 4px;
    height: 4px;
    border-radius: 50%;
    background: var(--accent);
    opacity: 0.7;
  }
  .empty {
    margin: 6px 0;
    color: var(--text-3);
  }
  .ph {
    height: 140px;
    border-radius: 14px;
  }
  footer {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    padding: 12px 16px 16px;
    border-top: 1px solid var(--border);
  }
  .btn {
    height: 36px;
    padding: 0 16px;
    border-radius: 12px;
    background: var(--surface-3);
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    transition:
      background var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .btn:hover:not(:disabled) {
    background: var(--hover);
  }
  .btn:active:not(:disabled) {
    transform: scale(0.96);
  }
  .btn.primary {
    background: var(--accent);
    color: var(--accent-ink);
  }
  .btn:disabled {
    opacity: 0.7;
  }
</style>
