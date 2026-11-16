<script lang="ts">
  // Интерфейс → Вкладки по pc/Screenshot_31: где панель вкладок (слева / справа / сверху / снизу), её
  // стиль, подстройка цвета под страницу и автоскрытие. Сетка окна — App.svelte, вид панели — Rail.svelte.
  import Choice from '../../components/settings/Choice.svelte'
  import Cards from '../../components/settings/Cards.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Divider from '../../components/settings/Divider.svelte'
  import { settings } from '../../lib/settings.svelte'
</script>

<Choice
  title="Позиция вкладок"
  hint="Выберите расположение панели вкладок"
  icons
  value={settings.get('tabs.position')}
  options={[
    { id: 'top' as const, label: 'Сверху', icon: 'layoutTop' },
    { id: 'bottom' as const, label: 'Снизу', icon: 'layoutBottom' },
    { id: 'left' as const, label: 'Слева', icon: 'layoutLeft' },
    { id: 'right' as const, label: 'Справа', icon: 'layoutRight' },
  ]}
  onchange={(v) => settings.set('tabs.position', v)}
/>

<Cards
  title="Стиль вкладок"
  hint="Выберите стиль отображения вкладок"
  list
  value={settings.get('tabs.style')}
  options={[
    { id: 'default' as const, label: 'По умолчанию', sub: 'Классическая панель', icon: 'layout' },
    { id: 'compact' as const, label: 'Компактный', sub: 'Минимум места', icon: 'compress' },
    { id: 'full' as const, label: 'Полный', sub: 'Вся высота экрана', icon: 'stack' },
    { id: 'round' as const, label: 'Круглый', sub: 'Круглые иконки', icon: 'circle' },
    { id: 'floating' as const, label: 'Плавающий', sub: 'Парящий островок', icon: 'hash' },
  ]}
  onchange={(v) => settings.set('tabs.style', v)}
/>

<Divider />

<Switch
  title="Подстраивать вкладки"
  hint="Контент страницы будет влиять на вкладки"
  on={settings.get('tabs.adapt')}
  onchange={(v) => settings.set('tabs.adapt', v)}
/>
<Switch
  title="Скрытие элементов"
  hint="Автоскрытие неактивных панелей"
  on={settings.get('tabs.autohide')}
  onchange={(v) => settings.set('tabs.autohide', v)}
/>
