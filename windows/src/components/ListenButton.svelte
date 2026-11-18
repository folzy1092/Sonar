<script lang="ts">
  // «Слушать» ⇄ «Пауза» в шапке подборки (плейлист, Любимые, альбом, исполнитель). Играет эта же
  // подборка — «Пауза»; после паузы — «Слушать» продолжает с того же места (lib/listen.ts). Значок
  // перетекает (PlayPause), подпись сменяется прозрачностью, ширина кнопки плавно подстраивается.
  import PlayPause from './PlayPause.svelte'
  import { listenAction } from '../lib/listen'
  import { xfade } from '../lib/motion'
  import { t } from '../lib/i18n.svelte'
  import { player } from '../player/player.svelte'

  interface Props {
    /** Контекст очереди этой подборки (`playlist:<id>`, `favorites`, `album:<ref>`, `artist:<ref>`). */
    context?: string | null
    /** Начинать нечего (нет треков или фильтр всё спрятал) — блокирует только «Слушать» с начала:
     *  пауза и продолжение играющей подборки работают и так. */
    disabled?: boolean
    /** Начать подборку с начала. */
    onplay: () => void
  }

  let { context = null, disabled = false, onplay }: Props = $props()

  const action = $derived(listenAction(context, { context: player.context, playing: player.playing, hasCurrent: !!player.current, ended: player.ended }))
  const playing = $derived(action === 'pause')
  const label = $derived(playing ? t('Пауза') : t('Слушать'))
  const blocked = $derived(disabled && action === 'start')
  // ширина содержимого: кнопка тянется к ней через transition (при «меньше движения» — сразу)
  let innerWidth = $state(0)

  function onclick() {
    if (action === 'pause') player.pause()
    else if (action === 'resume') void player.play()
    else onplay()
  }
</script>

<button class="listen" disabled={blocked} {onclick} style:width={innerWidth ? `${innerWidth}px` : null}>
  <span class="inner" bind:offsetWidth={innerWidth}>
    <PlayPause {playing} size={16} />
    {#key label}<span class="label" in:xfade={{ duration: 180 }}>{label}</span>{/key}
  </span>
</button>

<style>
  /* белая, как у Dotify (не в цвет темы) */
  .listen {
    display: inline-flex;
    align-items: center;
    flex-shrink: 0;
    height: 34px;
    overflow: hidden;
    border-radius: 10px;
    background: var(--text);
    color: var(--on-text);
    font-weight: 600;
    transition:
      width 0.28s var(--ease),
      transform var(--fast) var(--ease),
      background var(--fast) var(--ease);
  }
  .inner {
    display: inline-flex;
    align-items: center;
    flex-shrink: 0;
    gap: 8px;
    padding: 0 20px;
    white-space: nowrap;
  }
  .listen:active:not(:disabled) {
    transform: scale(0.95);
  }
  .listen:disabled {
    opacity: 0.4;
    cursor: default;
  }
</style>
