<script lang="ts">
  // Интерфейс → Вкладки по pc/Screenshot_31: где панель вкладок (слева / справа / сверху / снизу), её
  // стиль, подстройка цвета под страницу и автоскрытие. Сетка окна — App.svelte, вид панели — Rail.svelte.
  import Choice from '../../components/settings/Choice.svelte'
  import Cards from '../../components/settings/Cards.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Divider from '../../components/settings/Divider.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { t } from '../../lib/i18n.svelte'
</script>

<Choice
  title={t('Позиция вкладок')}
  hint={t('Выберите расположение панели вкладок')}
  icons
  value={settings.get('tabs.position')}
  options={[
    { id: 'top' as const, label: t('Сверху'), icon: 'layoutTop' },
    { id: 'bottom' as const, label: t('Снизу'), icon: 'layoutBottom' },
    { id: 'left' as const, label: t('Слева'), icon: 'layoutLeft' },
    { id: 'right' as const, label: t('Справа'), icon: 'layoutRight' },
  ]}
  onchange={(v) => settings.set('tabs.position', v)}
/>

<Cards
  title={t('Стиль вкладок')}
  hint={t('Выберите стиль отображения вкладок')}
  list
  value={settings.get('tabs.style')}
  options={[
    { id: 'default' as const, label: t('По умолчанию'), sub: t('Классическая панель'), icon: 'layout' },
    { id: 'compact' as const, label: t('Компактный'), sub: t('Минимум места'), icon: 'compress' },
    { id: 'full' as const, label: t('Полный'), sub: t('Вся высота экрана'), icon: 'stack' },
    { id: 'round' as const, label: t('Круглый'), sub: t('Круглые иконки'), icon: 'circle' },
    { id: 'floating' as const, label: t('Плавающий'), sub: t('Парящий островок'), icon: 'hash' },
  ]}
  onchange={(v) => settings.set('tabs.style', v)}
/>

<Divider />

<Switch
  title={t('Подстраивать вкладки')}
  hint={t('Контент страницы будет влиять на вкладки')}
  on={settings.get('tabs.adapt')}
  onchange={(v) => settings.set('tabs.adapt', v)}
/>
<Switch
  title={t('Скрытие элементов')}
  hint={t('Автоскрытие неактивных панелей')}
  on={settings.get('tabs.autohide')}
  onchange={(v) => settings.set('tabs.autohide', v)}
/>
