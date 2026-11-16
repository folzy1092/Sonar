<script lang="ts">
  // Плеер → Очередь по pc/Screenshot_7: что вернуть при запуске, показ очереди, её положение и вид,
  // похожие после очереди, «добавлять следующие».
  import Cards from '../../components/settings/Cards.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { t } from '../../lib/i18n.svelte'
</script>

<Choice
  title={t('Продолжить с прошлого раза')}
  hint={t('Что вернуть при открытии приложения')}
  wide
  value={settings.get('general.restore')}
  options={[
    { id: 'none', label: t('Ничего'), icon: 'x' },
    { id: 'track', label: t('Трек'), icon: 'music' },
    { id: 'queue', label: t('Очередь'), icon: 'queue' },
  ]}
  onchange={(v) => settings.set('general.restore', v)}
/>
<Switch title={t('Показывать очередь')} hint={t('Отображать панель очереди')} on={settings.get('queue.show')} onchange={(v) => settings.set('queue.show', v)} />
<Switch
  title={t('Предпросмотр следующего трека')}
  hint={t('За 10 секунд до конца — карточка «Дальше» с названием следующего')}
  on={settings.get('queue.preview')}
  onchange={(v) => settings.set('queue.preview', v)}
/>
<Choice
  title={t('Положение очереди')}
  hint={t('Выберите где отображать очередь воспроизведения')}
  wide
  value={settings.get('queue.position')}
  options={[
    { id: 'bottom' as const, label: t('Снизу'), icon: 'layoutBottom' },
    { id: 'left' as const, label: t('Слева'), icon: 'layoutLeft' },
    { id: 'right' as const, label: t('Справа'), icon: 'layoutRight' },
  ]}
  onchange={(v) => settings.set('queue.position', v)}
/>
<Cards
  title={t('Вид очереди')}
  hint={t('Выберите режим отображения треков в списке очереди')}
  cols={2}
  value={settings.get('queue.view')}
  options={[
    { id: 'normal' as const, label: t('Обычный'), icon: 'textLines' },
    { id: 'extended' as const, label: t('Развернутый'), icon: 'queue' },
  ]}
  onchange={(v) => settings.set('queue.view', v)}
/>
<Switch
  title={t('Авто похожие')}
  hint={t('Как в SoundCloud: после любой очереди — поиска, Любимых, плейлиста — играют похожие треки')}
  on={settings.get('general.similar_autoplay')}
  onchange={(v) => settings.set('general.similar_autoplay', v)}
/>
<Switch
  title={t('Добавлять следующие')}
  hint={t('Нажатый трек ставит в очередь и треки после него')}
  on={settings.get('queue.add_following')}
  onchange={(v) => settings.set('queue.add_following', v)}
/>
