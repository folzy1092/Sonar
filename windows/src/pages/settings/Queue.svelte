<script lang="ts">
  // Плеер → Очередь по pc/Screenshot_7: что вернуть при запуске, показ очереди, её положение и вид,
  // похожие после очереди, «добавлять следующие».
  import Cards from '../../components/settings/Cards.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import { settings } from '../../lib/settings.svelte'
</script>

<Choice
  title="Продолжить с прошлого раза"
  hint="Что вернуть при открытии приложения"
  wide
  value={settings.get('general.restore')}
  options={[
    { id: 'none', label: 'Ничего', icon: 'x' },
    { id: 'track', label: 'Трек', icon: 'music' },
    { id: 'queue', label: 'Очередь', icon: 'queue' },
  ]}
  onchange={(v) => settings.set('general.restore', v)}
/>
<Switch title="Показывать очередь" hint="Отображать панель очереди" on={settings.get('queue.show')} onchange={(v) => settings.set('queue.show', v)} />
<Switch title="Предпросмотр следующего трека" hint="Показывать информацию о следующем треке" on={true} soon />
<Choice
  title="Положение очереди"
  hint="Выберите где отображать очередь воспроизведения"
  wide
  value="bottom"
  options={[
    { id: 'bottom', label: 'Снизу', icon: 'layoutBottom' },
    { id: 'left', label: 'Слева', icon: 'layoutLeft', soon: true },
    { id: 'right', label: 'Справа', icon: 'layoutRight', soon: true },
  ]}
/>
<Cards
  title="Вид очереди"
  hint="Выберите режим отображения треков в списке очереди"
  cols={2}
  value="extended"
  options={[
    { id: 'normal', label: 'Обычный', icon: 'textLines', soon: true },
    { id: 'extended', label: 'Развернутый', icon: 'queue' },
  ]}
/>
<Switch
  title="Авто похожие"
  hint="Автоматически догружать похожие треки, когда следующего нет"
  on={settings.get('general.similar_autoplay')}
  onchange={(v) => settings.set('general.similar_autoplay', v)}
/>
<Switch
  title="Добавлять следующие"
  hint="Нажатый трек ставит в очередь и треки после него"
  on={settings.get('queue.add_following')}
  onchange={(v) => settings.set('queue.add_following', v)}
/>
