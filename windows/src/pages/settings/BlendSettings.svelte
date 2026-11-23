<script lang="ts">
  // Настройки сведения в Аудио (docs/BLEND.md §10.2): то же, что во всплывашке кнопки, плюс допуск темпа и,
  // только для Dev, отладочная панель. Значения читаются через blendSettings — с теми же границами, что у плеера.
  import Choice from '../../components/settings/Choice.svelte'
  import Slider from '../../components/settings/Slider.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import { t } from '../../lib/i18n.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { subscriptionOf } from '../../lib/subscription'
  import { BLEND_LENGTHS, BLEND_TYPES, blendSettings, CUT_MAX_SEC, TEMPO_TOL_MAX_PCT } from '../../player/blend/settings'
  import { KIND_TEXT, LENGTH_TEXT } from '../../player/blend/view'

  const opts = $derived(
    blendSettings({
      type: settings.get('audio.blend_type'),
      length: settings.get('audio.blend_length'),
      cut: settings.get('audio.blend_cut'),
      tempo: settings.get('audio.blend_tempo'),
      key: settings.get('audio.blend_key'),
    }),
  )
  const dev = $derived(subscriptionOf({ username: settings.get('profile.username') }).tier === 'dev')
</script>

<Choice
  title={t('Вид сведения')}
  hint={t(KIND_TEXT[opts.type].about)}
  value={opts.type}
  options={BLEND_TYPES.map((k) => ({ id: k, label: t(KIND_TEXT[k].name) }))}
  onchange={(v) => settings.set('audio.blend_type', v)}
  wide
  fill
/>
<Choice
  title={t('Длина сведения')}
  hint={t('Сколько треки звучат вместе: около 6, 10 или 16 секунд, точно — по тактам')}
  value={opts.lengthSec}
  options={BLEND_LENGTHS.map((l) => ({ id: l, label: t(LENGTH_TEXT[l]) }))}
  onchange={(v) => settings.set('audio.blend_length', v)}
/>
<Slider
  title={t('Можно срезать')}
  hint={t('Сколько секунд конца трека можно пропустить ради лучшего момента; рекомендуется 16')}
  value={opts.cutSec}
  min={0}
  max={CUT_MAX_SEC}
  unit=" {t('с')}"
  onchange={(v) => settings.set('audio.blend_cut', v)}
/>
<Slider
  title={t('Допуск темпа')}
  hint={t('Насколько можно ускорить или замедлить следующий трек, чтобы попасть в долю; дальше — без бита')}
  value={opts.tempoTolPct}
  min={0}
  max={TEMPO_TOL_MAX_PCT}
  unit=" %"
  onchange={(v) => settings.set('audio.blend_tempo', v)}
/>
<Switch
  title={t('Подгонять тональность')}
  hint={t('Сдвигает тон следующего трека на время перехода, если тональности не дружат')}
  on={opts.keyShift}
  onchange={(v) => settings.set('audio.blend_key', v)}
/>
{#if dev}
  <Switch
    title={t('Отладочная панель')}
    hint={t('Карточка у плеера: анализ треков, план перехода и его фазы — только для Dev')}
    on={settings.get('audio.blend_debug')}
    onchange={(v) => settings.set('audio.blend_debug', v)}
  />
{/if}
