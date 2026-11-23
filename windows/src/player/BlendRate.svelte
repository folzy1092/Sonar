<script lang="ts">
  // «Как прошлый переход?» 👍/👎 (docs/BLEND.md §8.6): 60 с после каждого перехода — в кнопке сведения
  // и в карточке отладки. Состояние общее (`blendRatings`), ответ пишется один раз.
  import Icon from '../components/Icon.svelte'
  import { t } from '../lib/i18n.svelte'
  import { slide } from '../lib/motion'
  import { blendRatings } from './blend/ratings.svelte'
  import { KIND_TEXT } from './blend/view'

  const ask = $derived(blendRatings.ask)
  const answer = $derived(blendRatings.answer)
</script>

{#if ask}
  <div class="rate" transition:slide={{ duration: 220 }}>
    <span class="q">
      {t('Как прошлый переход?')}
      <small>{t(KIND_TEXT[ask.kind].name)}</small>
    </span>
    <button
      class="press"
      class:on={answer === 1}
      disabled={answer !== null}
      title={t('Хороший переход')}
      aria-label={t('Хороший переход')}
      onclick={() => blendRatings.rate(1)}
    >
      <Icon name="like" size={16} filled={answer === 1} />
    </button>
    <button
      class="press"
      class:on={answer === -1}
      disabled={answer !== null}
      title={t('Плохой переход')}
      aria-label={t('Плохой переход')}
      onclick={() => blendRatings.rate(-1)}
    >
      <Icon name="dislike" size={16} filled={answer === -1} />
    </button>
  </div>
{/if}

<style>
  .rate {
    display: grid;
    grid-template-columns: 1fr auto auto;
    align-items: center;
    gap: 6px;
    padding: 6px 6px 6px 10px;
    border-radius: 12px;
    background: var(--plate);
  }
  .q {
    display: flex;
    flex-direction: column;
    min-width: 0;
    font-size: calc(12px * var(--fs, 1));
    font-weight: 600;
    color: var(--text);
  }
  .q small {
    font-weight: 500;
    color: var(--text-2);
  }
  button {
    display: grid;
    place-items: center;
    width: 30px;
    height: 30px;
    border-radius: 9px;
    color: var(--text-2);
    transition:
      color var(--normal) var(--ease),
      background var(--fast) var(--ease),
      opacity var(--normal) var(--ease);
  }
  button:hover:not(:disabled) {
    background: var(--hover);
    color: var(--text);
  }
  button.on {
    color: var(--accent);
  }
  button:disabled:not(.on) {
    opacity: 0.35;
  }
  button:disabled {
    cursor: default;
  }
</style>
