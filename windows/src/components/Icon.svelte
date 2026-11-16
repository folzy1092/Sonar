<script lang="ts">
  // Иконка интерфейса. Основной набор — MingCute (как у Dotify: мягкие скруглённые формы, контур и
  // заливка одной формы), `filled` — заливка. Чего в MingCute нет (бренды, «повтор выкл») —
  // контур Tabler из icons.ts. `stroke` — толщина только для Tabler.
  import { icons, type IconName } from './icons'
  import { mingcute } from './mingcute'
  import { sonarFillable, sonarIcons } from './sonar-icons'

  interface Props {
    name: IconName
    size?: number
    stroke?: number
    filled?: boolean
  }

  let { name, size = 20, stroke = 2, filled = false }: Props = $props()
  const mc = $derived(mingcute[name])
  // свои контурные иконки кнопок плеера (sonar-icons.ts) — вместо MingCute с тем же именем
  const sn = $derived(sonarIcons[name])
</script>

{#if sn}
  <svg class="i-{name} sn" class:filled width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
    {#each sn as d, i (i)}
      <path {d} fill={filled && sonarFillable[name]?.includes(i) ? 'currentColor' : 'none'} />
    {/each}
  </svg>
{:else if mc}
  <svg class="i-{name}" width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">{@html filled ? mc.fill : mc.line}</svg>
{:else}
  <svg
    class="i-{name}"
    width={size}
    height={size}
    viewBox="0 0 24 24"
    fill={filled ? 'currentColor' : 'none'}
    stroke="currentColor"
    stroke-width={stroke}
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
  >
    {#each icons[name] as d}
      <path {d} />
    {/each}
  </svg>
{/if}

<style>
  svg {
    display: block;
    flex-shrink: 0;
  }
  .sn {
    stroke: currentColor;
    stroke-width: var(--icon-stroke, 2);
    stroke-linecap: round;
    stroke-linejoin: round;
    overflow: visible;
  }
  .sn path {
    transition: fill 0.24s var(--ease);
  }
</style>
