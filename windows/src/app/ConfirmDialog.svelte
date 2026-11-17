<script lang="ts">
  // Окно подтверждения (lib/confirm.svelte.ts): затемнение с размытием, карточка по центру. «Нет» —
  // в фокусе по умолчанию; «Да» с `delay` — недоступна, на ней отсчёт и полоса, которая тает за это время.
  import { fade } from 'svelte/transition'
  import { confirm } from '../lib/confirm.svelte'
  import { pop } from '../lib/motion'

  const q = $derived(confirm.current)
  let left = $state(0)
  let noBtn: HTMLButtonElement | undefined = $state()

  $effect(() => {
    const cur = q
    if (!cur) return
    left = cur.delay ?? 0
    if (!left) return
    const timer = setInterval(() => {
      left -= 1
      if (left <= 0) clearInterval(timer)
    }, 1000)
    return () => clearInterval(timer)
  })

  $effect(() => {
    if (q) queueMicrotask(() => noBtn?.focus())
  })

  function onKey(e: KeyboardEvent) {
    if (q && e.key === 'Escape') {
      e.stopPropagation()
      confirm.answer(false)
    }
  }
</script>

<svelte:window onkeydowncapture={onKey} />

{#if q}
  <div class="back" transition:fade={{ duration: 200 }} onclick={() => confirm.answer(false)} role="presentation"></div>
  {#key q.id}
    <div class="wrap" role="presentation">
      <div class="card" role="alertdialog" aria-modal="true" aria-labelledby="confirm-title" in:pop={{ y: 10, scale: 0.94, duration: 240 }} out:pop={{ y: 6 }}>
        <h2 id="confirm-title">{q.title}</h2>
        {#if q.text}<p>{q.text}</p>{/if}
        <div class="actions">
          <button class="btn no" bind:this={noBtn} onclick={() => confirm.answer(false)}>{q.no}</button>
          <button
            class="btn yes"
            class:danger={q.danger}
            disabled={left > 0}
            style:--wait="{q.delay ?? 0}s"
            class:waiting={left > 0}
            onclick={() => confirm.answer(true)}
          >
            <span class="drain" aria-hidden="true"></span>
            <span class="label">{q.yes}{#if left > 0}&nbsp;<span class="count">{#key left}<span class="digit" in:pop={{ y: -6, duration: 220 }}>{left}</span>{/key}</span>{/if}</span>
          </button>
        </div>
      </div>
    </div>
  {/key}
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
    width: min(420px, calc(100vw - 48px));
    padding: 24px 24px 20px;
    border-radius: var(--radius-l);
    background: color-mix(in srgb, var(--surface-2) 92%, transparent);
    border: 1px solid var(--border-strong);
    box-shadow: 0 24px 60px rgba(0, 0, 0, 0.55);
    text-align: center;
  }
  h2 {
    margin: 0;
    font-size: calc(18px * var(--fs, 1));
    font-weight: 700;
    line-height: 1.3;
    color: var(--text);
  }
  p {
    margin: 8px 0 0;
    font-size: calc(14px * var(--fs, 1));
    color: var(--text-2);
    line-height: 1.45;
  }
  .actions {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
    margin-top: 22px;
  }
  .btn {
    position: relative;
    overflow: hidden;
    height: 40px;
    border-radius: 999px;
    font-weight: 600;
    transition:
      background var(--fast) var(--ease),
      color var(--fast) var(--ease),
      opacity var(--fast) var(--ease),
      transform var(--fast) var(--ease);
  }
  .btn:active:not(:disabled) {
    transform: scale(0.96);
  }
  .no {
    background: var(--hover);
    color: var(--text);
    border: 1px solid var(--border-strong);
  }
  .no:hover {
    background: color-mix(in srgb, var(--text) 12%, transparent);
  }
  .yes {
    background: var(--text);
    color: var(--bg, #000);
  }
  .yes.danger {
    background: var(--danger);
    color: #fff;
  }
  .yes:disabled {
    cursor: default;
    opacity: 0.55;
  }
  .yes:not(:disabled):hover {
    filter: brightness(1.08);
  }
  /* полоса ожидания тает слева направо за `delay` секунд */
  .drain {
    position: absolute;
    inset: 0;
    background: rgba(255, 255, 255, 0.22);
    transform-origin: right;
    transform: scaleX(0);
  }
  .waiting .drain {
    animation: drain var(--wait) linear both;
  }
  @keyframes drain {
    from {
      transform: scaleX(1);
    }
  }
  .label {
    position: relative;
    display: inline-flex;
    align-items: center;
  }
  .count {
    display: inline-grid;
    min-width: 1ch;
    font-variant-numeric: tabular-nums;
  }
  .digit {
    grid-area: 1 / 1;
  }
  @media (prefers-reduced-motion: reduce) {
    .waiting .drain {
      animation: none;
    }
  }
</style>
