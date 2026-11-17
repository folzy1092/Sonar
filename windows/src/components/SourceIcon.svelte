<script module lang="ts">
  /** Счётчик экземпляров: id внутри svg (маски, градиенты) уникальны на странице. */
  let instances = 0
</script>

<script lang="ts">
  // Значок сервиса (как у Dotify — маленький знак в углу обложки, без плашки с буквами).
  // Разметка — lib/service-icons (копии brand/icon; Яндекс Музыка — прежний значок в тёмном круге).
  // Содержимое {@html} — свои файлы из сборки, не ввод пользователя.
  /** `mono` — знак одним цветом (currentColor), без круга: плитки «Лайки SoundCloud» / «Мне нравится» в цвете темы. */
  import { t } from '../lib/i18n.svelte'
  import { byId, type ServiceId } from '../lib/services'
  import { ICONS, uniquifyIds } from '../lib/service-icons'

  let { service, size = 16, plain = false, mono = false }: { service: ServiceId; size?: number; plain?: boolean; mono?: boolean } = $props()

  const uid = String(++instances)
  const info = $derived(byId(service))
  const title = $derived(info ? t(info.name) : '')
  const svg = $derived.by(() => {
    const icon = ICONS[service]
    if (!icon) return null
    return uniquifyIds(mono ? icon.mono : plain ? icon.plain : icon.badge, uid)
  })
</script>

<span class="si {service}" class:plain={plain || mono} class:mono style:--s="{size}px" {title} aria-label={title} role="img">
  {#if svg}{@html svg}{/if}
</span>

<style>
  .si {
    display: inline-grid;
    place-items: center;
    width: var(--s);
    height: var(--s);
    flex: none;
  }
  .si :global(svg) {
    width: 100%;
    height: 100%;
    overflow: visible;
  }
  .mono {
    color: inherit;
  }
  /* на обложке — лёгкая тень, чтобы знак читался на любой картинке */
  .si:not(.plain) :global(svg) {
    filter: drop-shadow(0 1px 2px rgba(0, 0, 0, 0.55));
  }
</style>
