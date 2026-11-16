<script lang="ts">
  // Всплывашка «Доступно обновление» (как у Dotify): выезжает справа над мини-плеером, когда фоновая
  // проверка нашла новую версию. Закрывается только кликом — «Позже» или после установки.
  // «Подробнее» — окно UpdateDetails со всеми изменениями.
  import Icon from '../components/Icon.svelte'
  import { pop } from '../lib/motion'
  import { updater } from '../lib/updater.svelte'
  import UpdateDetails from './UpdateDetails.svelte'

  const p = $derived(updater.phase)
  /** «Подробнее» — окно со всеми изменениями до найденной версии. */
  let more = $state(false)
</script>

{#if more && updater.popup}
  <UpdateDetails onclose={() => (more = false)} />
{/if}

{#if updater.popup}
  <div class="pop" role="dialog" aria-label="Доступно обновление" in:pop={{ y: 16, scale: 0.94, duration: 280 }} out:pop={{ y: 16, scale: 0.94, duration: 280 }}>
    <div class="top">
      <span class="ic"><Icon name="download" size={18} /></span>
      <div class="txt">
        <b>Доступно обновление</b>
        <small>
          Sonar {updater.version}
          {#if p === 'downloading'}· загрузка {Math.round(updater.progress * 100)}%{:else if p === 'ready'}· скачано{/if}
        </small>
      </div>
      <button class="x" aria-label="Позже" onclick={() => updater.later()}><Icon name="x" size={16} /></button>
    </div>

    {#if updater.notes.length}
      <ul>
        {#each updater.notes.slice(0, 3) as n, i (i)}<li>{n}</li>{/each}
      </ul>
    {/if}

    {#if p === 'downloading'}
      <div class="bar"><i style:transform="scaleX({updater.progress})"></i></div>
    {/if}

    <div class="btns">
      <button class="btn" onclick={() => (more = true)}>Подробнее</button>
      {#if p === 'ready' || p === 'installing'}
        <button class="btn primary" disabled={p === 'installing'} onclick={() => updater.install()}>Установить</button>
      {:else if p === 'available' || p === 'error'}
        <button class="btn primary" onclick={() => (p === 'error' ? updater.retry() : updater.download())}>Обновить</button>
      {/if}
    </div>
  </div>
{/if}

<style>
  .pop {
    position: fixed;
    right: 18px;
    bottom: calc(var(--player-h) + 22px);
    z-index: 55;
    width: 320px;
    padding: 14px;
    border-radius: 18px;
    background: var(--surface-2);
    border: 1px solid var(--border-strong);
    box-shadow: 0 18px 48px rgba(0, 0, 0, 0.5);
    transform-origin: bottom right;
  }
  .top {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .ic {
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    flex: none;
    border-radius: 12px;
    background: var(--accent);
    color: var(--accent-ink);
  }
  .txt {
    flex: 1;
    min-width: 0;
    display: grid;
  }
  .txt b {
    font-size: calc(14px * var(--fs, 1));
    font-weight: 700;
  }
  .txt small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
    font-variant-numeric: tabular-nums;
  }
  .x {
    display: grid;
    place-items: center;
    width: 28px;
    height: 28px;
    border-radius: 9px;
    color: var(--text-3);
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease);
  }
  .x:hover {
    background: var(--hover);
    color: var(--text);
  }
  ul {
    margin: 10px 0 0;
    padding: 0 0 0 48px;
    list-style: none;
  }
  li {
    position: relative;
    font-size: calc(12px * var(--fs, 1));
    line-height: 1.5;
    color: var(--text-2);
  }
  li::before {
    content: '';
    position: absolute;
    left: -10px;
    top: 8px;
    width: 3px;
    height: 3px;
    border-radius: 50%;
    background: var(--text-3);
  }
  .bar {
    height: 3px;
    margin: 12px 0 0;
    border-radius: 2px;
    background: color-mix(in srgb, var(--accent) 18%, transparent);
    overflow: hidden;
  }
  .bar i {
    display: block;
    height: 100%;
    background: var(--accent);
    transform-origin: left;
    transition: transform 0.25s var(--ease);
  }
  .btns {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    margin-top: 12px;
  }
  .btn {
    height: 34px;
    padding: 0 14px;
    border-radius: 11px;
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
    opacity: 0.6;
  }
</style>
