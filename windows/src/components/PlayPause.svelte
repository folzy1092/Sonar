<script lang="ts">
  // Значок плей/пауза: плавно сменяются (прозрачность + масштаб), а не прыгают (PLATFORMS.md «Анимации»).
  import Icon from './Icon.svelte'

  let { playing, size = 22 }: { playing: boolean; size?: number } = $props()
</script>

<span class="pp" style:width="{size}px" style:height="{size}px" aria-hidden="true">
  <span class="i" class:show={playing}><Icon name="pause" {size} filled /></span>
  <span class="i play" class:show={!playing}><Icon name="play" {size} filled /></span>
</span>

<style>
  .pp {
    display: grid;
    place-items: center;
  }
  .i {
    grid-area: 1 / 1;
    display: grid;
    place-items: center;
    opacity: 0;
    transform: scale(0.6) rotate(-30deg);
    transition:
      opacity 0.2s var(--ease),
      transform 0.28s var(--ease);
  }
  .i.play {
    transform: scale(0.6) rotate(30deg);
  }
  .i.show {
    opacity: 1;
    transform: none;
  }
</style>
