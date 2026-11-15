<script lang="ts">
  // Интеграции → Приложения по pc/Screenshot_14, 15: Discord RPC (работает), Last.fm и OBS Studio —
  // с сервером («Скоро»). ID приложения Discord пользователь не вводит: он вшит в сборку, потом
  // приходит с сервера (`GET /config`).
  import Icon from '../../components/Icon.svelte'
  import Switch from '../../components/settings/Switch.svelte'
  import Choice from '../../components/settings/Choice.svelte'
  import Group from '../../components/settings/Group.svelte'
  import Soon from '../../components/settings/Soon.svelte'
  import { settings } from '../../lib/settings.svelte'
</script>

<Group title="Discord RPC">
  <Switch
    title="Активность в Discord"
    hint="Показывать в Discord, что вы слушаете"
    on={settings.get('integrations.discord.enabled')}
    onchange={(v) => settings.set('integrations.discord.enabled', v)}
  />
  <Switch
    title="Кастомная обложка"
    hint="Отображать оригинальную обложку трека в статусе"
    on={settings.get('integrations.discord.cover')}
    onchange={(v) => settings.set('integrations.discord.cover', v)}
  />
  <Switch
    title="Прогресс воспроизведения"
    hint="Показывать оставшееся время прослушивания трека"
    on={settings.get('integrations.discord.progress')}
    onchange={(v) => settings.set('integrations.discord.progress', v)}
  />
</Group>

<Group title="Last.fm">
  <div class="account">
    <span class="av"><Icon name="brandLastfm" size={26} /></span>
    <b>Подключить Last.fm <Soon /></b>
    <small>Вход появится вместе с сервером Sonar</small>
  </div>
  <Switch title="История прослушиваний" hint="Сохранять прослушанные треки" on={true} soon />
  <Switch title="Сейчас играет" hint="Показывать текущий трек в профиле" on={true} soon />
</Group>

<Group title="OBS Studio">
  <div class="link">https://sonar-api.folzy.ru/obs?token=…</div>
  <div class="tools">
    <button class="copy" disabled><Icon name="copy" size={15} /> Скопировать <Soon /></button>
    <button class="sq" disabled aria-label="Перевыпустить"><Icon name="refresh" size={15} /></button>
    <button class="sq" disabled aria-label="Удалить"><Icon name="trash" size={15} /></button>
  </div>
  <Choice
    title="Размер плашки"
    hint="Габариты на экране стрима"
    wide
    soon
    value="standard"
    options={[
      { id: 'standard', label: 'Стандартный' },
      { id: 'compact', label: 'Компактный' },
    ]}
  />
  <Switch title="Скрывать при паузе" hint="Плавно убирать плашку со стрима, когда трек остановлен" on={true} soon />
</Group>

<Group title="Как подключить в OBS?">
  <ol>
    <li><i>1</i> В OBS добавьте источник «Браузер»</li>
    <li><i>2</i> Вставьте скопированную ссылку в поле «URL»</li>
    <li><i>3</i> Укажите размер: ширина 450, высота 130</li>
  </ol>
</Group>

<style>
  .account {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    padding: 22px 12px 18px;
    margin-bottom: 6px;
    border-radius: 16px;
    background: linear-gradient(180deg, var(--surface-2) 50%, var(--plate) 50%);
    text-align: center;
  }
  .av {
    display: grid;
    place-items: center;
    width: 64px;
    height: 64px;
    margin-bottom: 6px;
    border-radius: 50%;
    background: var(--surface-3);
    color: #d51007;
  }
  .account b {
    font-size: 14px;
  }
  .account small {
    font-size: 12px;
    color: var(--text-3);
  }
  .link {
    padding: 11px 14px;
    border-radius: 10px;
    background: var(--plate);
    font-size: 12px;
    color: var(--text-3);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .tools {
    display: flex;
    gap: 6px;
    margin: 6px 0 4px;
  }
  .copy,
  .sq {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    height: 36px;
    border-radius: 10px;
    border: 1px solid var(--border);
    font-size: 13px;
    color: var(--text-2);
  }
  .copy {
    flex: 1;
  }
  .sq {
    width: 36px;
  }
  button:disabled {
    cursor: default;
    opacity: 0.6;
  }
  ol {
    margin: 4px 0 0;
    padding: 0;
    list-style: none;
    display: flex;
    flex-direction: column;
    gap: 10px;
    font-size: 12px;
    color: var(--text-2);
  }
  li {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  li i {
    display: grid;
    place-items: center;
    width: 20px;
    height: 20px;
    border-radius: 50%;
    background: var(--surface-3);
    font-style: normal;
    font-size: 11px;
    font-weight: 600;
  }
</style>
