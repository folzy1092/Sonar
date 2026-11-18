<script lang="ts">
  // Плеер → «Стиль плеера» с живым примером (SETTINGS_NEXT «Плеер» п. 1): уменьшенная страница плеера
  // в выбранном стиле — с обложкой играющего трека, выравниванием заголовка и позицией обложки.
  import Choice from '../../components/settings/Choice.svelte'
  import { player } from '../../player/player.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { t } from '../../lib/i18n.svelte'

  const style = $derived(settings.get('player.style'))
  const align = $derived(settings.get('player.title_align'))
  const flip = $derived(settings.get('player.cover_position') === 'right')
  const cover = $derived(player.current?.cover_url ?? null)
  const title = $derived(player.current?.title ?? t('Название трека'))
  const artist = $derived(player.current?.artist ?? t('Исполнитель'))
</script>

{#snippet demo()}
  <div class="demo st-{style}" class:flip class:playing={player.playing} aria-hidden="true">
    <div class="art">
      {#if style === 'vinyl'}
        <span class="disc"><span class="label" style:background-image={cover ? `url("${cover}")` : null}></span></span>
        <span class="arm"></span>
      {:else}
        <span class="img" style:background-image={cover ? `url("${cover}")` : null}></span>
      {/if}
    </div>
    <div class="meta" style:text-align={align}>
      <b>{title}</b>
      <small>{artist}</small>
      <span class="bar"><i></i></span>
      <span class="dots"><i></i><i></i><i class="big"></i><i></i><i></i></span>
    </div>
  </div>
{/snippet}

<Choice
  title={t('Стиль плеера')}
  hint={t('Выберите визуальный стиль плеера')}
  wide
  fill
  preview={demo}
  value={style}
  options={[
    { id: 'standard' as const, label: t('Обычный'), icon: 'grid' },
    { id: 'vinyl' as const, label: t('Пластинка'), icon: 'vinyl' },
    { id: 'large' as const, label: t('Большой'), icon: 'photo' },
  ]}
  onchange={(v) => settings.set('player.style', v)}
/>

<style>
  .demo {
    display: flex;
    align-items: center;
    gap: 16px;
    height: 132px;
    margin: 10px 0 2px;
    padding: 14px 18px;
    border-radius: 14px;
    background: var(--surface-2);
    overflow: hidden;
    transition: gap var(--normal) var(--ease);
  }
  .demo.flip {
    flex-direction: row-reverse;
  }
  .art {
    position: relative;
    flex-shrink: 0;
    width: 96px;
    height: 96px;
    transition:
      width var(--normal) var(--ease),
      height var(--normal) var(--ease);
  }
  .st-large .art {
    width: 132px;
    height: 132px;
    margin: -14px 0 -14px -18px;
  }
  .st-large.flip .art {
    margin: -14px -18px -14px 0;
  }
  .img,
  .label {
    position: absolute;
    inset: 0;
    border-radius: var(--radius-m, 12px);
    background: linear-gradient(135deg, var(--surface-3), var(--accent-soft)) center / cover;
    transition: border-radius var(--normal) var(--ease);
  }
  .st-large .img {
    border-radius: 0;
  }
  .disc {
    position: absolute;
    inset: 4px;
    border-radius: 50%;
    background: repeating-radial-gradient(circle, #111 0 2px, #1c1c1f 2px 4px);
    box-shadow: 0 0 0 1px var(--surface-3);
    animation: spin 6s linear infinite paused;
  }
  .playing .disc {
    animation-play-state: running;
  }
  .disc .label {
    inset: 32%;
    border-radius: 50%;
  }
  .arm {
    position: absolute;
    top: -6px;
    right: -4px;
    width: 4px;
    height: 54px;
    border-radius: 2px;
    background: var(--text-2);
    transform-origin: top center;
    transform: rotate(24deg);
    transition: transform var(--normal) var(--ease);
  }
  .playing .arm {
    transform: rotate(32deg);
  }
  .meta {
    display: flex;
    flex-direction: column;
    gap: 3px;
    flex: 1;
    min-width: 0;
  }
  .meta b,
  .meta small {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .meta b {
    font-size: calc(14px * var(--fs, 1));
  }
  .st-large .meta b {
    font-size: calc(17px * var(--fs, 1));
  }
  .meta small {
    font-size: calc(12px * var(--fs, 1));
    color: var(--text-3);
  }
  .bar {
    height: 3px;
    margin-top: 10px;
    border-radius: 3px;
    background: var(--surface-3);
  }
  .bar i {
    display: block;
    width: 42%;
    height: 100%;
    border-radius: inherit;
    background: var(--text);
  }
  .dots {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 9px;
    margin-top: 9px;
  }
  .dots i {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--text-3);
  }
  .dots i.big {
    width: 18px;
    height: 18px;
    background: var(--text);
  }
  @keyframes spin {
    to {
      transform: rotate(1turn);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .disc {
      animation: none;
    }
  }
</style>
