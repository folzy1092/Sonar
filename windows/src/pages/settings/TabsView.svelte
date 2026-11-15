<script lang="ts">
  // Интерфейс → Вкладки по pc/Screenshot_31: позиция и стиль панели вкладок, подстройка и скрытие.
  // Сейчас панель одна — слева, классическая; остальное — «Скоро».
  import Choice from '../../components/settings/Choice.svelte'
  import Cards from '../../components/settings/Cards.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Divider from '../../components/settings/Divider.svelte'
</script>

<Choice
  title="Позиция вкладок"
  hint="Выберите расположение панели вкладок"
  icons
  value="left"
  options={[
    { id: 'top', label: 'Сверху', icon: 'layoutTop', soon: true },
    { id: 'bottom', label: 'Снизу', icon: 'layoutBottom', soon: true },
    { id: 'left', label: 'Слева', icon: 'layoutLeft' },
    { id: 'right', label: 'Справа', icon: 'layoutRight', soon: true },
  ]}
/>

<Cards
  title="Стиль вкладок"
  hint="Выберите стиль отображения вкладок"
  list
  value="default"
  options={[
    { id: 'default', label: 'По умолчанию', sub: 'Классическая панель', icon: 'layout' },
    { id: 'compact', label: 'Компактный', sub: 'Минимум места', icon: 'compress', soon: true },
    { id: 'full', label: 'Полный', sub: 'Вся высота экрана', icon: 'stack', soon: true },
    { id: 'round', label: 'Круглый', sub: 'Круглые иконки', icon: 'circle', soon: true },
    { id: 'floating', label: 'Плавающий', sub: 'Парящий островок', icon: 'hash', soon: true },
  ]}
/>

<Divider />

<Switch title="Подстраивать вкладки" hint="Контент страницы будет влиять на вкладки" on={false} soon />
<Switch title="Скрытие элементов" hint="Автоскрытие неактивных панелей" on={false} soon />
