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
<Switch
  title="Предпросмотр следующего трека"
  hint="За 10 секунд до конца — карточка «Дальше» с названием следующего"
  on={settings.get('queue.preview')}
  onchange={(v) => settings.set('queue.preview', v)}
/>
<Choice
  title="Положение очереди"
  hint="Выберите где отображать очередь воспроизведения"
  wide
  value={settings.get('queue.position')}
  options={[
    { id: 'bottom' as const, label: 'Снизу', icon: 'layoutBottom' },
    { id: 'left' as const, label: 'Слева', icon: 'layoutLeft' },
    { id: 'right' as const, label: 'Справа', icon: 'layoutRight' },
  ]}
  onchange={(v) => settings.set('queue.position', v)}
/>
<Cards
  title="Вид очереди"
  hint="Выберите режим отображения треков в списке очереди"
  cols={2}
  value={settings.get('queue.view')}
  options={[
    { id: 'normal' as const, label: 'Обычный', icon: 'textLines' },
    { id: 'extended' as const, label: 'Развернутый', icon: 'queue' },
  ]}
  onchange={(v) => settings.set('queue.view', v)}
/>
<Switch
  title="Авто похожие"
  hint="Как в SoundCloud: после любой очереди — поиска, Любимых, плейлиста — играют похожие треки"
  on={settings.get('general.similar_autoplay')}
  onchange={(v) => settings.set('general.similar_autoplay', v)}
/>
<Switch
  title="Добавлять следующие"
  hint="Нажатый трек ставит в очередь и треки после него"
  on={settings.get('queue.add_following')}
  onchange={(v) => settings.set('queue.add_following', v)}
/>
