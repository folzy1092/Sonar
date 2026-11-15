<script lang="ts">
  // Число со «счётом»: при появлении и смене плавно докручивается (PLATFORMS.md «Анимации» — цифры).
  import { countUp } from '../lib/motion'

  let { value, format = (n: number) => Math.round(n).toLocaleString('ru-RU') }: { value: number; format?: (n: number) => string } = $props()
  let shown = $state(0)
  let from = 0

  $effect(() => {
    const to = value
    const stop = countUp(from, to, 900, (v) => (shown = v))
    from = to
    return stop
  })
</script>

{format(shown)}
