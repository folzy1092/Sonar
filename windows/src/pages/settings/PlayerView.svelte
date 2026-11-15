<script lang="ts">
  // Плеер → Вид (pc/Screenshot_6): выравнивание заголовка, аватары артистов, визуализатор.
  import Switch from '../../components/settings/Switch.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Group from '../../components/settings/Group.svelte'
  import { settings } from '../../lib/settings.svelte'
</script>

<Group title="Страница плеера">
  <Choice
    title="Выравнивание заголовка"
    hint="Название трека и исполнитель"
    value={settings.get('player.title_align')}
    options={[
      { id: 'left', label: 'Слева' },
      { id: 'center', label: 'По центру' },
      { id: 'right', label: 'Справа' },
    ]}
    onchange={(v) => settings.set('player.title_align', v)}
  />
  <Switch
    title="Аватарки артистов"
    hint="Аватар исполнителя перед его именем в плеере"
    on={settings.get('player.artist_avatars')}
    onchange={(v) => settings.set('player.artist_avatars', v)}
  />
  <Choice
    title="Визуализатор"
    hint="Волна по звуку под ползунком"
    value={settings.get('player.visualizer')}
    options={[
      { id: 'off', label: 'Выкл', icon: 'x' },
      { id: 'bar', label: 'Полоса', icon: 'equalizer' },
    ]}
    onchange={(v) => settings.set('player.visualizer', v)}
  />
</Group>
