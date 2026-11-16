<script lang="ts">
  // Плашка после сбоя (решение владельца 2026-11-16): прошлый запуск упал или ловил ошибки —
  // при открытии справа внизу «Sonar закрылся с ошибкой» и «Отправить лог». Лог уходит в Telegram
  // ботом отчётов (crashlog.rs); в сборке без бота сохраняется в «Загрузки». Закрывается только кликом.
  import { onMount } from 'svelte'
  import Icon from '../components/Icon.svelte'
  import { pop } from '../lib/motion'
  import { api, errorText, type CrashReport } from '../lib/api'
  import { isTauri } from '../lib/tauri'
  import { updater } from '../lib/updater.svelte'
  import { t } from '../lib/i18n.svelte'

  let report = $state<CrashReport | null>(null)
  let phase = $state<'idle' | 'sending' | 'sent' | 'saved' | 'error'>('idle')
  let error = $state('')

  onMount(() => {
    // превью интерфейса: ?crash в адресе — показать плашку с примером
    if (!isTauri && import.meta.env.DEV && location.search.includes('crash')) {
      report = { crashed: true, errors: 2, last: 'PANIC called `Option::unwrap()` on a `None` value (src/wave.rs:512)' }
    }
    if (!isTauri) return
    // чуть позже заставки — плашка не должна прыгать на загрузке
    const timer = setTimeout(() => {
      void api
        .reportPending()
        .then((r) => (report = r))
        .catch(() => {})
    }, 1600)
    return () => clearTimeout(timer)
  })

  async function send() {
    phase = 'sending'
    try {
      const r = await api.reportSend()
      phase = r.kind === 'telegram' ? 'sent' : 'saved'
      setTimeout(() => (report = null), 2200)
    } catch (e) {
      error = errorText(e)
      phase = 'error'
    }
  }

  function close() {
    report = null
    void api.reportDismiss().catch(() => {})
  }
</script>

{#if report}
  <div class="pop" class:lift={updater.popup} role="dialog" aria-label={t('Отчёт об ошибке')} in:pop={{ y: 16, scale: 0.94, duration: 280 }} out:pop={{ y: 16, scale: 0.94, duration: 240 }}>
    <div class="top">
      <span class="ic" class:ok={phase === 'sent' || phase === 'saved'}>
        {#key phase === 'sent' || phase === 'saved'}
          <span class="glyph"><Icon name={phase === 'sent' || phase === 'saved' ? 'check' : 'bolt'} size={18} /></span>
        {/key}
      </span>
      <div class="txt">
        <b>
          {#if phase === 'sent'}{t('Отправлено, спасибо!')}{:else if phase === 'saved'}{t('Лог сохранён')}{:else if report.crashed}{t('Sonar закрылся с ошибкой')}{:else}{t('В прошлый раз были ошибки')}{/if}
        </b>
        <small>
          {#if phase === 'sent'}{t('Разберёмся и починим')}
          {:else if phase === 'saved'}{t('Файл в «Загрузках» — перешли его Folzy')}
          {:else if phase === 'error'}{error}
          {:else}{t('Отправь лог — так быстрее найдём причину')}{/if}
        </small>
      </div>
      {#if phase !== 'sent' && phase !== 'saved'}
        <button class="x" aria-label={t('Закрыть')} onclick={close}><Icon name="x" size={16} /></button>
      {/if}
    </div>
    {#if report.last && phase !== 'sent' && phase !== 'saved'}
      <p class="last selectable" title={report.last}>{report.last}</p>
    {/if}
    {#if phase !== 'sent' && phase !== 'saved'}
      <div class="btns">
        <button class="btn primary" disabled={phase === 'sending'} onclick={send}>
          {phase === 'sending' ? t('Отправляю…') : phase === 'error' ? t('Ещё раз') : t('Отправить лог')}
        </button>
      </div>
    {/if}
  </div>
{/if}

<style>
  .pop {
    position: fixed;
    right: 18px;
    bottom: calc(var(--player-h) + 22px);
    z-index: 56;
    width: 320px;
    padding: 14px;
    border-radius: 18px;
    background: var(--surface-2);
    border: 1px solid var(--border-strong);
    box-shadow: 0 18px 48px rgba(0, 0, 0, 0.5);
    transform-origin: bottom right;
    transition: bottom var(--normal) var(--ease);
  }
  /* всплывашка обновления на том же месте — встаём над ней */
  .pop.lift {
    bottom: calc(var(--player-h) + 250px);
  }
  .top {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .ic {
    display: grid;
    place-items: center;
    flex: none;
    width: 36px;
    height: 36px;
    border-radius: 12px;
    background: color-mix(in srgb, var(--danger) 18%, transparent);
    color: var(--danger);
    transition:
      background 0.4s var(--ease),
      color 0.4s var(--ease);
  }
  .ic.ok {
    background: color-mix(in srgb, var(--online) 18%, transparent);
    color: var(--online);
  }
  .glyph {
    display: grid;
    animation: glyph-in 0.36s var(--ease);
  }
  @keyframes glyph-in {
    from {
      opacity: 0;
      scale: 0.5;
    }
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
  .last {
    margin: 10px 0 0;
    padding: 8px 10px;
    border-radius: 10px;
    background: var(--plate);
    font: calc(11px * var(--fs, 1))/1.4 'JetBrains Mono Variable', Consolas, monospace;
    color: var(--text-2);
    overflow: hidden;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
  }
  .btns {
    display: flex;
    justify-content: flex-end;
    margin-top: 12px;
  }
  .btn {
    height: 34px;
    padding: 0 16px;
    border-radius: 11px;
    font-size: calc(13px * var(--fs, 1));
    font-weight: 600;
    transition:
      opacity var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .btn.primary {
    background: var(--text);
    color: var(--on-text);
  }
  .btn:active:not(:disabled) {
    transform: scale(0.96);
  }
  .btn:disabled {
    opacity: 0.6;
  }
</style>
