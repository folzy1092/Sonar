<script lang="ts">
  // Интерфейс → Вид → «Вкладки» по pc/Screenshot_31: где панель вкладок (слева / справа / сверху / снизу), её
  // стиль, подстройка цвета под страницу и автоскрытие. Сетка окна — App.svelte, вид панели — Rail.svelte.
  // С 2026-11-18 — карточка внутри «Вида» (SETTINGS_NEXT): отдельного пункта «Вкладки» нет. Стиль «Полный»
  // убран (от «По умолчанию» не отличался), старое значение переводит settings-migrate. С 2026-11-25 основной —
  // «Sonar» (подписи, плейлисты, раскрытие в полку), прежняя колонка — «Значки».
  import Tiles from '../../components/settings/Tiles.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { t } from '../../lib/i18n.svelte'

  const position = $derived(settings.get('tabs.position'))
  const style = $derived(settings.get('tabs.style'))
  const mini = $derived(settings.get('mini.style') === 'off' ? 'none' : settings.get('mini.position'))
  // на схемах позиции плавающая панель не видна бы была — рисуем обычную
  const shapeStyle = $derived(style === 'floating' ? 'default' : style)
</script>

<Tiles
  title={t('Позиция вкладок')}
  hint={t('Где стоит панель разделов')}
  value={position}
  options={[
    { id: 'top' as const, label: t('Сверху') },
    { id: 'bottom' as const, label: t('Снизу') },
    { id: 'left' as const, label: t('Слева') },
    { id: 'right' as const, label: t('Справа') },
  ].map((o) => ({ ...o, diagram: { tabs: o.id, style: shapeStyle, mini } }))}
  onchange={(v) => settings.set('tabs.position', v)}
/>

<Tiles
  title={t('Стиль вкладок')}
  hint={t('Как выглядит панель разделов')}
  value={style}
  options={[
    { id: 'sonar' as const, label: 'Sonar', sub: t('Подписи и плейлисты') },
    { id: 'default' as const, label: t('Значки'), sub: t('Классическая панель') },
    { id: 'compact' as const, label: t('Компактный'), sub: t('Минимум места') },
    { id: 'round' as const, label: t('Круглый'), sub: t('Круглые иконки') },
    { id: 'floating' as const, label: t('Плавающий'), sub: t('Парящий островок') },
  ].map((o) => ({ ...o, diagram: { tabs: position, style: o.id, mini } }))}
  onchange={(v) => settings.set('tabs.style', v)}
/>

  <Switch
    title={t('Подстраивать вкладки')}
    hint={t('Панель берёт цвет подкраски страницы')}
    on={settings.get('tabs.adapt')}
    onchange={(v) => settings.set('tabs.adapt', v)}
  />
  <Switch
    title={t('Скрытие элементов')}
    hint={t('Мышь замерла на 3 секунды — панель и мини плеер гаснут')}
    on={settings.get('tabs.autohide')}
    onchange={(v) => settings.set('tabs.autohide', v)}
  />

