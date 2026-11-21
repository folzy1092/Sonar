<script lang="ts">
  // Интерфейс → Плеер (SETTINGS_NEXT «Плеер»): одна страница вместо «Вид» + «Очередь». Карточки: стиль с
  // живым примером и заголовок · визуализатор · ползунок · обложка · очередь. Канвас — не делаем.
  import Card from '../../components/settings/Card.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import PlayerStyle from './PlayerStyle.svelte'
  import PlayerViz from './PlayerViz.svelte'
  import Queue from './Queue.svelte'
  import { settings } from '../../lib/settings.svelte'
  import { t } from '../../lib/i18n.svelte'
</script>

<Card>
  <PlayerStyle />
  <Choice
    title={t('Выравнивание заголовка')}
    hint={t('Выберите выравнивание названия трека')}
    icons
    value={settings.get('player.title_align')}
    options={[
      { id: 'left', label: t('Слева'), icon: 'alignLeft' },
      { id: 'center', label: t('По центру'), icon: 'alignCenter' },
      { id: 'right', label: t('Справа'), icon: 'alignRight' },
    ]}
    onchange={(v) => settings.set('player.title_align', v)}
  />
  <Switch
    title={t('Аватарки артистов')}
    hint={t('Отображать аватарки исполнителей перед их именами в плеере и мини плеере')}
    on={settings.get('player.artist_avatars')}
    onchange={(v) => settings.set('player.artist_avatars', v)}
  />
  <Switch
    title={t('Почему этот трек')}
    hint={t('Под артистом у треков Sonar Mix — откуда трек: похож на твой лайк, разведка, забытый любимый')}
    on={settings.get('player.wave_why')}
    onchange={(v) => settings.set('player.wave_why', v)}
  />
  <Switch
    title={t('Таймер сна в плеере')}
    hint={t('Кнопка с луной рядом со скоростью: выключить музыку через время или в конце трека')}
    on={settings.get('player.sleep_button')}
    onchange={(v) => settings.set('player.sleep_button', v)}
  />
</Card>

<Card title={t('Визуализатор')}>
  <PlayerViz part="viz" />
  <Switch
    title={t('Спектр в полноэкранном плеере')}
    hint={t('Тихая волна звука на дне экрана, за текстом. С «Меньше движения» не рисуется')}
    on={settings.get('player.visualizer_full')}
    onchange={(v) => settings.set('player.visualizer_full', v)}
  />
</Card>

<Card title={t('Ползунок')}>
  <PlayerViz part="slider" />
</Card>

<Card title={t('Обложка')}>
  <Choice
    title={t('Позиция обложки')}
    hint={t('Выберите где отображается обложка')}
    icons
    value={settings.get('player.cover_position')}
    options={[
      { id: 'left', label: t('Слева'), icon: 'layoutLeft' },
      { id: 'right', label: t('Справа'), icon: 'layoutRight' },
    ]}
    onchange={(v) => settings.set('player.cover_position', v)}
  />
  <Switch
    title={t('Обложка в обложке')}
    hint={t('Маленькая чёткая обложка внутри большой размытой')}
    on={settings.get('player.pip_cover')}
    onchange={(v) => settings.set('player.pip_cover', v)}
  />
</Card>

<Card title={t('Очередь')}>
  <Queue />
</Card>
