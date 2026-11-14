<script lang="ts">
  import { icons, type IconName } from './icons'

  interface Props {
    name: IconName
    size?: number
    stroke?: number
    filled?: boolean
  }

  let { name, size = 20, stroke = 2, filled = false }: Props = $props()
</script>

<svg
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

<style>
  svg {
    display: block;
    flex-shrink: 0;
  }
</style>
